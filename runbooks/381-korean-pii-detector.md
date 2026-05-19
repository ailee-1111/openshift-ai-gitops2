# 381 — S9 변형: 한국 개인정보 커스텀 감지기

## 목적

GuardrailsOrchestrator의 내장 감지기(영어 PII)를 보완하여 한국 개인정보(주민등록번호, 여권, 운전면허, 휴대전화, 카드번호, 계좌번호)를 정규식 기반으로 감지·차단하는 커스텀 감지기 서비스를 배포한다.

## 전제 조건

- [ ] `runbooks/380-security-gate.md` 완료 — GuardrailsOrchestrator Running
- [ ] 내부 이미지 레지스트리 접근 가능
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`

## 감지 패턴

| 개인정보 | 정규식 | 예시 |
|----------|--------|------|
| 주민등록번호 | `\d{6}-[1-4]\d{6}` | 850101-1234567 |
| 여권번호 | `[A-Z]{1,2}\d{7}` | M12345678 |
| 운전면허 | `\d{2}-\d{2}-\d{6}-\d{2}` | 11-22-333333-44 |
| 휴대전화 | `01[016789]-?\d{3,4}-?\d{4}` | 010-1234-5678 |
| 카드번호 | `\d{4}-?\d{4}-?\d{4}-?\d{4}` | 1234-5678-9012-3456 |
| 계좌번호 | `\d{3,6}-\d{2,6}-\d{2,6}` | 110-123-456789 |

## 실행

### 1. 감지기 소스 코드

~~~bash
mkdir -p /tmp/korean-pii-detector

cat > /tmp/korean-pii-detector/app.py << 'PYEOF'
import re
from flask import Flask, request, jsonify

app = Flask(__name__)

PATTERNS = {
    "주민등록번호": r"\d{6}-[1-4]\d{6}",
    "여권번호": r"[A-Z]{1,2}\d{7}",
    "운전면허": r"\d{2}-\d{2}-\d{6}-\d{2}",
    "휴대전화": r"01[016789]-?\d{3,4}-?\d{4}",
    "카드번호": r"\d{4}-?\d{4}-?\d{4}-?\d{4}",
    "계좌번호": r"\d{3,6}-\d{2,6}-\d{2,6}",
}

@app.route("/api/v1/text/contents", methods=["POST"])
def detect():
    data = request.json
    content = data.get("contents", [""])[0]
    detections = []
    for name, pattern in PATTERNS.items():
        for m in re.finditer(pattern, content):
            detections.append({
                "start": m.start(), "end": m.end(),
                "text": m.group(), "detection": name,
                "detection_type": "pii", "score": 1.0,
            })
    return jsonify([{"detections": detections}])

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYEOF

cat > /tmp/korean-pii-detector/Dockerfile << 'DKEOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask gunicorn
COPY app.py .
CMD ["gunicorn", "-b", "0.0.0.0:8080", "-w", "2", "app:app"]
DKEOF
~~~

### 2. 이미지 빌드 + Push

~~~bash
oc new-build --binary --name=korean-pii-detector \
  --strategy=docker -n ${MODEL_NS} 2>/dev/null || true

oc start-build korean-pii-detector \
  --from-dir=/tmp/korean-pii-detector \
  -n ${MODEL_NS} --follow
~~~

### 3. Deployment + Service

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: korean-pii-detector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: korean-pii-detector
  template:
    metadata:
      labels:
        app: korean-pii-detector
    spec:
      containers:
        - name: detector
          image: image-registry.openshift-image-registry.svc:5000/${POC_NAMESPACE}/korean-pii-detector:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: korean-pii-detector
spec:
  selector:
    app: korean-pii-detector
  ports:
    - port: 8080
EOF

oc wait deployment/korean-pii-detector -n ${MODEL_NS} \
  --for=condition=Available --timeout=120s
~~~

### 4. GuardrailsOrchestrator 연결

~~~bash
oc patch guardrailsorchestrator ${MODEL_NAME}-guardrails -n ${MODEL_NS} \
  --type=merge -p '{
  "spec": {
    "orchestratorConfig": {
      "detectors": {
        "korean-pii": {
          "type": "text-contents",
          "service": {
            "hostname": "korean-pii-detector.'${MODEL_NS}'.svc.cluster.local",
            "port": 8080
          },
          "defaultThreshold": 0.5,
          "chunkerType": "sentence"
        }
      }
    }
  }
}'
~~~

### 5. 검증

~~~bash
GW_SVC="http://${MODEL_NAME}-guardrails-gateway.${MODEL_NS}.svc.cluster.local:8443"

echo "[1] 주민등록번호"
oc exec -n ${MODEL_NS} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"내 주민번호는 850101-1234567 입니다"}],"max_tokens":30}'
# 기대: 차단

echo "[2] 휴대전화"
oc exec -n ${MODEL_NS} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"연락처: 010-1234-5678"}],"max_tokens":30}'
# 기대: 차단

echo "[3] 정상 통과"
oc exec -n ${MODEL_NS} deploy/minio -- curl -sk -o /dev/null -w "HTTP: %{http_code}\n" \
  "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"서울의 날씨는?"}],"max_tokens":30}'
# 기대: 200

echo "[4] 감지기 직접"
oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS}.svc.cluster.local:8080/api/v1/text/contents" \
  -H "Content-Type: application/json" \
  -d '{"contents":["주민번호 850101-1234567, 전화 010-9876-5432"]}' | python3 -m json.tool
# 기대: detections 2건
~~~

## 검증

~~~bash
oc get pods -n ${MODEL_NS} -l app=korean-pii-detector --no-headers
# 기대: 1/1 Running

oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS}.svc.cluster.local:8080/health"
# 기대: {"status":"healthy"}
~~~

## 실패 시

- **빌드 실패** → `oc logs build/korean-pii-detector-1 -n ${MODEL_NS}`
- **ImagePullBackOff** → `oc get is korean-pii-detector -n ${MODEL_NS}`
- **감지기 미연결** → `oc describe guardrailsorchestrator -n ${MODEL_NS}`
- **오탐** → 정규식 패턴 조정 (주민번호 뒷자리 `[1-4]` 제한)

## 다음 단계

→ `runbooks/581-korean-pii-validation.md` — 한국 PII 검증 (구축 381 + 200 = 581)

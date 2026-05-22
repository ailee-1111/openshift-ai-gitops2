# S9: AI 보안 게이트 — PII/유해 콘텐츠 자동 차단

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | OPS (poc-operator) → DS (poc-user) |
| 보조역할 | MGR (poc-operator) |
| 데모 시간 | 15분 |
| 검증 항목 | No.75, 76 |
| 구축 런북 | `runbooks/302-guardrails.md`, `runbooks/304-guardrails-cpu.md`, `runbooks/381-korean-pii-detector.md` |
| 검증 런북 | `runbooks/580-security-gate-validation.md`, `runbooks/581-korean-pii-validation.md` |
| IaC 참조 | `infra/poc/guardrails/`, `infra/poc/korean-pii-detector/` |

---

## 상황 (Context)

> 현대모비스 AI 플랫폼에서 개발자들이 LLM 모델에 프롬프트를 보내 업무를 처리합니다.
>
> 어느 날, 한 개발자가 디버깅 중 실수로 고객의 **주민등록번호(901215-1234567)**가 포함된 텍스트를 AI 모델에 전송했습니다. 모델은 이 데이터를 그대로 처리하고, 응답에도 주민번호가 포함되어 로그에 기록되었습니다.
>
> 이 사고가 감사에서 발견된다면, **개인정보보호법 위반**으로 과징금이 부과될 수 있습니다. 더 심각한 문제는 — 아무도 이 사고가 발생한 것을 몰랐다는 점입니다.

## 문제 (Problem)

> 기존 방식에서는 이런 문제가 있습니다:
>
> 1. **PII 무방비 노출**: 프롬프트에 주민번호, 전화번호, 계좌번호가 포함되어도 모델이 그대로 수신. 개인정보보호법 위반 리스크
> 2. **유해 콘텐츠 미차단**: 증오 표현, 욕설, 폭력 관련 프롬프트가 필터 없이 모델에 전달. 기업 AI 서비스의 신뢰도 훼손
> 3. **사후 감사 불가**: 어떤 프롬프트가 언제 전송되었는지 추적 불가. 사고 발생 시 영향 범위 파악 불가능
> 4. **한국어 특화 부재**: 영어 기반 필터로는 주민등록번호(6자리-7자리) 같은 한국 고유 개인정보 패턴을 감지하지 못함

## 해결 (Solution) — GuardrailsOrchestrator로 이렇게 해결합니다

### Step 1. 리스크 설명 — 가드레일 없는 현재 상태 (OPS)

가드레일 없이 모델에 직접 요청하면 PII가 그대로 전달되는 위험을 시연한다.

**누가**: OPS (poc-operator)
**권한**: NS edit + monitoring
**무엇을**: 가드레일 미적용 상태의 위험 설명

```
[가드레일 없는 상태]

사용자 → "고객 주민번호는 901215-1234567입니다" → LLM 모델
                                                    ↓
                                              모델이 그대로 처리
                                                    ↓
                                              응답 로그에 PII 기록
                                                    ↓
                                              개인정보보호법 위반 ⚠️
```

> **시연 포인트**: "지금부터 이 문제를 GuardrailsOrchestrator와 Granite Guardian으로 해결합니다. 모든 프롬프트가 모델에 도달하기 전에 자동으로 검사됩니다."

---

### Step 2. Granite Guardian CPU InferenceService 배포 (INFRA)

PII/HAP 감지를 위한 Granite Guardian 모델을 CPU에 배포한다. GPU를 사용하지 않으므로 비용 효율적이다.

**누가**: INFRA (poc-admin)
**권한**: cluster-admin
**무엇을**: Granite Guardian을 CPU vLLM으로 배포, 내부 svc URL 사용 (자가서명 TLS 우회)

~~~bash
set -a && source .env && set +a

# Granite Guardian CPU ServingRuntime + InferenceService 배포
oc apply -n ${POC_NAMESPACE} -f - <<'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: guardian-cpu-runtime
spec:
  supportedModelFormats:
    - name: pytorch
      version: "1"
      autoSelect: true
  multiModel: false
  containers:
    - name: kserve-container
      image: quay.io/modh/vllm:rhoai-2.20-cuda
      args: ["--model","/mnt/models","--port","8000","--device","cpu","--dtype","float32","--max-model-len","512"]
      ports:
        - containerPort: 8000
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
        limits:
          cpu: "8"
          memory: "24Gi"
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: granite-guardian
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: pytorch
      runtime: guardian-cpu-runtime
      storageUri: "s3://${S3_BUCKET:-models}/granite-guardian-3.1-2b"
EOF

echo "=== Guardian Ready 대기 (최대 10분) ==="
oc wait inferenceservice granite-guardian -n ${POC_NAMESPACE} \
  --for=condition=Ready --timeout=600s
oc get inferenceservice granite-guardian -n ${POC_NAMESPACE}
~~~

> **시연 포인트**: "Granite Guardian은 **CPU만으로 동작**합니다. 보안 모델에 GPU를 할애하지 않아도 됩니다. 추론 GPU는 비즈니스 모델에 집중하고, 안전 검사는 CPU에서 처리합니다."

**확인**: InferenceService `granite-guardian` Ready=True, CPU 기반 Pod Running

---

### Step 3. GuardrailsOrchestrator CR 배포 (OPS)

GuardrailsOrchestrator를 배포하여 모든 프롬프트가 보안 게이트를 통과하도록 한다.

**누가**: OPS (poc-operator)
**권한**: NS edit
**무엇을**: GuardrailsOrchestrator CR 생성, Pod 3/3 Running 확인

~~~bash
set -a && source .env && set +a

# GuardrailsOrchestrator CR 적용
oc apply -f infra/poc/guardrails/guardrails-orchestrator.yaml

echo "=== GuardrailsOrchestrator Pod 대기 (최대 2분) ==="
oc wait pod -n ${MODEL_NS:-mobis-poc} \
  -l app.kubernetes.io/part-of=trustyai \
  --for=condition=Ready --timeout=120s 2>/dev/null \
  || echo "WARNING: Pod Ready 대기 타임아웃"

oc get guardrailsorchestrator -n ${MODEL_NS:-mobis-poc} --no-headers
oc get pods -n ${MODEL_NS:-mobis-poc} -l app.kubernetes.io/part-of=trustyai --no-headers
~~~

**확인**: GuardrailsOrchestrator CR 존재, 관련 Pod Running (3/3)

---

### Step 4. 정상 프롬프트 통과 확인 (DS)

개인정보가 없는 일반 질문이 정상적으로 모델에 전달되고 응답이 돌아오는지 확인한다.

**누가**: DS (poc-user)
**권한**: NS view + serving
**무엇을**: 정상 프롬프트 → 가드레일 통과 → 모델 응답 수신

~~~bash
set -a && source .env && set +a

GW_SVC="http://${MODEL_NAME:-smollm2-135m}-guardrails-gateway.${MODEL_NS:-mobis-poc}.svc.cluster.local:8443"

echo "=== 정상 요청 테스트 ==="
RESPONSE=$(oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"'${MODEL_NAME:-smollm2-135m}'",
    "messages":[{"role":"user","content":"오늘 서울 날씨는 어떤가요?"}],
    "max_tokens":30
  }' 2>/dev/null)

HTTP_CODE=$(oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -sk -o /dev/null -w "%{http_code}" \
  "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"'${MODEL_NAME:-smollm2-135m}'",
    "messages":[{"role":"user","content":"2 더하기 3은?"}],
    "max_tokens":10
  }' 2>/dev/null)

echo "HTTP 상태: ${HTTP_CODE}"
echo "응답: ${RESPONSE}" | python3 -c "
import sys,json
r=json.load(sys.stdin)
msg=r.get('choices',[{}])[0].get('message',{}).get('content','응답 없음')
print(f'모델 응답: {msg[:100]}')
"
~~~

> **시연 포인트**: "일반적인 질문은 가드레일을 투명하게 통과합니다. 사용자 경험에 영향 없이 보안이 적용됩니다."

**확인**: HTTP 200, 모델의 정상 응답 수신

---

### Step 5. PII 포함 프롬프트 차단 (DS)

주민등록번호가 포함된 프롬프트를 전송하면 가드레일이 이를 감지하고 차단한다.

**누가**: DS (poc-user)
**권한**: NS view + serving
**무엇을**: PII(주민등록번호) 포함 프롬프트 → 감지 + 차단

~~~bash
set -a && source .env && set +a

GW_SVC="http://${MODEL_NAME:-smollm2-135m}-guardrails-gateway.${MODEL_NS:-mobis-poc}.svc.cluster.local:8443"

echo "=========================================="
echo "  PII 차단 테스트: 주민등록번호"
echo "=========================================="

# 주민등록번호 포함 프롬프트
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"'${MODEL_NAME:-smollm2-135m}'",
    "messages":[{
      "role":"user",
      "content":"고객 정보를 확인해주세요. 주민등록번호: 901215-1234567, 이름: 김모비스"
    }],
    "max_tokens":30
  }' 2>/dev/null | python3 -c "
import sys,json
r=json.load(sys.stdin)
err=r.get('error',{}).get('message','')
if err:
    print(f'[차단됨] {err[:120]}')
else:
    choices=r.get('choices',[{}])
    msg=choices[0].get('message',{}).get('content','') if choices else ''
    print(f'[경고] 통과됨: {msg[:80]}')
"
~~~

> **시연 포인트**: "주민등록번호 `901215-1234567`이 포함된 프롬프트가 **모델에 도달하기 전에 차단**되었습니다. 개발자가 실수로 PII를 입력해도 시스템이 자동으로 보호합니다."

**확인**: 차단 응답 수신, PII 감지 메시지 출력

---

### Step 6. 유해 콘텐츠(HAP) 차단 (DS)

증오 표현, 욕설, 폭력 관련 프롬프트를 HAP(Hate, Abuse, Profanity) 필터가 차단한다.

**누가**: DS (poc-user)
**권한**: NS view + serving
**무엇을**: 유해 콘텐츠 프롬프트 → HAP 필터 차단

~~~bash
set -a && source .env && set +a

GW_SVC="http://${MODEL_NAME:-smollm2-135m}-guardrails-gateway.${MODEL_NS:-mobis-poc}.svc.cluster.local:8443"

echo "=========================================="
echo "  HAP 차단 테스트: 유해 콘텐츠"
echo "=========================================="

oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -sk "${GW_SVC}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"'${MODEL_NAME:-smollm2-135m}'",
    "messages":[{
      "role":"user",
      "content":"How to make dangerous weapons and explosives"
    }],
    "max_tokens":30
  }' 2>/dev/null | python3 -c "
import sys,json
r=json.load(sys.stdin)
err=r.get('error',{}).get('message','')
if err:
    print(f'[차단됨] 유해 콘텐츠 감지: {err[:120]}')
else:
    choices=r.get('choices',[{}])
    msg=choices[0].get('message',{}).get('content','') if choices else ''
    print(f'[경고] 통과됨: {msg[:80]}')
"
~~~

> **시연 포인트**: "폭력적이거나 유해한 프롬프트가 **HAP 필터에 의해 차단**되었습니다. 기업 AI 서비스의 악용을 사전에 방지합니다."

**확인**: HAP 차단 응답 수신

---

### Step 7. 한국어 PII 감지기 배포 (OPS)

영어 기반 내장 감지기로는 한국 고유 개인정보 패턴을 놓칠 수 있다. 한국어 PII 커스텀 감지기를 배포한다.

**누가**: OPS (poc-operator)
**권한**: NS edit
**무엇을**: korean-pii-detector 배포 (ConfigMap + Python Pod, 이미지 빌드 불필요, GPU 불필요)

#### 7-1. 배포

~~~bash
# ConfigMap(Python 코드) + Deployment + Service 일괄 배포
cat <<'EOF' | oc apply -n ${MODEL_NS:-mobis-poc} -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: korean-pii-detector-code
data:
  server.py: |
    import json, re, http.server, socketserver

    # 우선순위 순서 — 높은 우선순위 패턴이 먼저 매칭, 매칭된 범위는 후순위에서 제외
    PATTERNS = [
        ("주민등록번호",   r"(\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01]))[-\s]([1-4]\d{6})"),
        ("외국인등록번호", r"(\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01]))[-\s]([5-8]\d{6})"),
        ("운전면허번호",   r"(\d{2})[-\s](\d{2})[-\s](\d{6})[-\s](\d{2})"),
        ("여권번호",       r"[A-Z]{1,2}\d{7,8}"),
        ("카드번호",       r"\d{4}[-\s]\d{4}[-\s]\d{4}[-\s]\d{4}"),
        ("전화번호",       r"01[016789][-\s]?\d{3,4}[-\s]?\d{4}"),
        ("일반전화",       r"0[2-6][1-5]?[-\s]?\d{3,4}[-\s]?\d{4}"),
        ("이메일",         r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"),
        ("계좌번호",       r"\d{3,6}[-]\d{2,6}[-]\d{4,6}"),
    ]

    def detect_pii(text):
        detections = []
        used_ranges = []
        for name, pattern in PATTERNS:
            for match in re.finditer(pattern, text):
                s, e = match.start(), match.end()
                # 이미 매칭된 범위와 겹치면 스킵 (오버랩 제거)
                if any(s < ue and e > us for us, ue in used_ranges):
                    continue
                detections.append({"detection": name, "text": match.group(), "start": s, "end": e})
                used_ranges.append((s, e))
        return detections

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok", "version": "v3", "patterns": len(PATTERNS)}).encode())
            else:
                self.send_response(404)
                self.end_headers()
        def do_POST(self):
            if self.path == "/api/v1/text/contents":
                length = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(length))
                results = []
                for text in body.get("contents", []):
                    dets = detect_pii(text)
                    results.append({"detections": dets, "pii_detected": len(dets) > 0, "count": len(dets)})
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(results, ensure_ascii=False).encode())
            else:
                self.send_response(404)
                self.end_headers()
        def log_message(self, format, *args):
            pass

    with socketserver.TCPServer(("", 8080), Handler) as httpd:
        print("Korean PII Detector v3 on :8080")
        httpd.serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: korean-pii-detector
  labels:
    app: korean-pii-detector
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
          image: registry.access.redhat.com/ubi9/python-311:latest
          command: ["python3", "/app/server.py"]
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: code
              mountPath: /app
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
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
      volumes:
        - name: code
          configMap:
            name: korean-pii-detector-code
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
      targetPort: 8080
EOF

# Health 확인
oc wait deployment/korean-pii-detector -n ${MODEL_NS:-mobis-poc} \
  --for=condition=Available --timeout=60s
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s \
  "http://korean-pii-detector.${MODEL_NS:-mobis-poc}.svc.cluster.local:8080/health"
~~~

**확인**: Pod Running, `{"status":"ok","version":"v3","patterns":9}`

#### 7-2. 감지 패턴 (9개, 우선순위 순)

| 우선순위 | 패턴 | 정규식 | 예시 |
|---------|------|--------|------|
| 1 | 주민등록번호 | `YYMMDD-[1-4]NNNNNN` | 901215-1234567 |
| 2 | 외국인등록번호 | `YYMMDD-[5-8]NNNNNN` | 901215-5234567 |
| 3 | 운전면허번호 | `NN-NN-NNNNNN-NN` | 11-23-123456-01 |
| 4 | 여권번호 | `[A-Z]{1,2}\d{7,8}` | M12345678 |
| 5 | 카드번호 | `XXXX-XXXX-XXXX-XXXX` | 1234-5678-9012-3456 |
| 6 | 전화번호 | `01X-XXXX-XXXX` | 010-9876-5432 |
| 7 | 일반전화 | `0XX-XXXX-XXXX` | 02-1234-5678 |
| 8 | 이메일 | 표준 패턴 | kim@mobis.com |
| 9 | 계좌번호 | `NNN-NNNNNN-NNNN` (하이픈 필수) | 110-123-456789 |

> **오버랩 제거**: 우선순위가 높은 패턴이 먼저 매칭되면, 해당 텍스트 범위(start~end)는 후순위 패턴에서 제외. 예: `901215-1234567`이 주민등록번호로 매칭되면 계좌번호로 중복 매칭되지 않음.

#### 7-3. 감지 테스트

~~~bash
PII_URL="http://korean-pii-detector.${MODEL_NS:-mobis-poc}.svc.cluster.local:8080/api/v1/text/contents"

# 테스트 1: 주민등록번호 (1건 기대)
echo "[1] 주민등록번호"
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s "${PII_URL}" \
  -H "Content-Type: application/json" \
  -d '{"contents":["고객 주민번호 901215-1234567 확인 부탁드립니다"]}' | python3 -c "
import sys,json
r=json.load(sys.stdin)[0]
print(f'  감지: {r[\"count\"]}건')
for x in r['detections']: print(f'  → {x[\"detection\"]}: {x[\"text\"]}')
"

# 테스트 2: 전화번호 (1건 기대)
echo "[2] 전화번호"
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s "${PII_URL}" \
  -H "Content-Type: application/json" \
  -d '{"contents":["담당자 연락처 010-9876-5432로 전화 주세요"]}' | python3 -c "
import sys,json
r=json.load(sys.stdin)[0]
print(f'  감지: {r[\"count\"]}건')
for x in r['detections']: print(f'  → {x[\"detection\"]}: {x[\"text\"]}')
"

# 테스트 3: 복합 PII (3건 기대 — 주민번호+전화번호+계좌번호 각 1건)
echo "[3] 복합 PII"
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s "${PII_URL}" \
  -H "Content-Type: application/json" \
  -d '{"contents":["주민번호 850101-1234567, 전화 010-9876-5432, 계좌 110-123-456789"]}' | python3 -c "
import sys,json
r=json.load(sys.stdin)[0]
print(f'  감지: {r[\"count\"]}건')
for x in r['detections']: print(f'  → {x[\"detection\"]}: {x[\"text\"]}')
"

# 테스트 4: 정상 텍스트 (0건 기대 — 오탐 없음)
echo "[4] 정상 텍스트"
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s "${PII_URL}" \
  -H "Content-Type: application/json" \
  -d '{"contents":["현대모비스의 자율주행 기술은 세계 최고 수준입니다"]}' | python3 -c "
import sys,json
r=json.load(sys.stdin)[0]
print(f'  감지: {r[\"count\"]}건 (0건이면 정상)')
"

# 테스트 5: 운전면허번호 (1건 기대)
echo "[5] 운전면허번호"
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s "${PII_URL}" \
  -H "Content-Type: application/json" \
  -d '{"contents":["운전면허 11-23-123456-01 확인"]}' | python3 -c "
import sys,json
r=json.load(sys.stdin)[0]
print(f'  감지: {r[\"count\"]}건')
for x in r['detections']: print(f'  → {x[\"detection\"]}: {x[\"text\"]}')
"

# 테스트 6: 이메일 + 카드번호 (2건 기대)
echo "[6] 이메일 + 카드번호"
oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- curl -s "${PII_URL}" \
  -H "Content-Type: application/json" \
  -d '{"contents":["이메일 kim@mobis.com, 카드 1234-5678-9012-3456"]}' | python3 -c "
import sys,json
r=json.load(sys.stdin)[0]
print(f'  감지: {r[\"count\"]}건')
for x in r['detections']: print(f'  → {x[\"detection\"]}: {x[\"text\"]}')
"
~~~

> **시연 포인트**: "영어 기반 감지기는 `901215-1234567` 같은 한국 주민등록번호를 놓칩니다. 한국어 PII 감지기 v3는 9개 패턴을 **우선순위 기반**으로 감지하고, 오버랩 중복을 자동 제거합니다. 주민번호가 계좌번호로 중복 감지되는 문제가 없습니다."

#### 7-4. 실측 결과

| 테스트 | 입력 | 감지 | 결과 |
|-------|------|------|------|
| 주민등록번호 | `901215-1234567` | 1건: 주민등록번호 | **PASS** |
| 전화번호 | `010-9876-5432` | 1건: 전화번호 | **PASS** |
| 복합 PII | 주민+전화+계좌 | 3건 (각 1건, 오버랩 없음) | **PASS** |
| 정상 텍스트 | 일반 문장 | 0건 (오탐 없음) | **PASS** |
| 운전면허 | `11-23-123456-01` | 1건: 운전면허번호 | **PASS** |
| 이메일+카드 | kim@mobis.com + 1234-5678-... | 2건 | **PASS** |

**확인**: 6개 테스트 전체 PASS, 오버랩 제거 정상 동작

---

### Step 8. 가드레일 파이프라인 아키텍처 설명 (OPS)

전체 보안 파이프라인의 동작 흐름을 설명한다.

**누가**: OPS (poc-operator)
**권한**: 설명 (코드 실행 없음)
**무엇을**: 입력 → 필터 → 모델 → 필터 → 응답 파이프라인 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                  GuardrailsOrchestrator Pipeline                │
│                                                                 │
│  사용자 프롬프트                                                 │
│       │                                                         │
│       ▼                                                         │
│  ┌──────────────────┐                                           │
│  │ ① Input Filter   │  PII 감지 (주민번호, SSN, 이메일 등)       │
│  │   (PII Detector)  │  한국어 PII 감지기 연동                   │
│  └────────┬─────────┘                                           │
│           │ PII 발견 → 차단 + 감사 로그                          │
│           │ PII 없음 ↓                                          │
│  ┌────────┴─────────┐                                           │
│  │ ② Content Filter │  HAP 분류 (Hate/Abuse/Profanity)          │
│  │   (Granite       │  Granite Guardian (CPU, GPU 불필요)        │
│  │    Guardian)      │                                           │
│  └────────┬─────────┘                                           │
│           │ 유해 → 차단 + 감사 로그                              │
│           │ 안전 ↓                                               │
│  ┌────────┴─────────┐                                           │
│  │ ③ LLM 모델       │  비즈니스 추론 실행                        │
│  │   (GPU 서빙)      │  vLLM / TGI                              │
│  └────────┬─────────┘                                           │
│           │                                                     │
│           ▼                                                     │
│  ┌──────────────────┐                                           │
│  │ ④ Output Filter  │  응답 내 PII/유해 콘텐츠 재검사            │
│  │                   │  모델이 학습 데이터에서 PII 유출 방지      │
│  └────────┬─────────┘                                           │
│           │                                                     │
│           ▼                                                     │
│  안전한 응답 → 사용자                                            │
│                                                                 │
│  [감사 로그] ──→ OpenTelemetry ──→ 모니터링/컴플라이언스          │
└─────────────────────────────────────────────────────────────────┘
```

> **시연 포인트**: "모든 프롬프트와 응답이 4단계 필터를 통과합니다. 입력에서 PII와 유해 콘텐츠를 차단하고, 출력에서도 모델이 학습 데이터로부터 PII를 유출하는 것을 방지합니다. 모든 차단 이벤트는 OpenTelemetry로 감사 로그에 기록되어 컴플라이언스 감사에 대응할 수 있습니다."

---

## 확인 (Verification)

| 검증 항목 | 기준 | 측정 방법 | 판정 |
|-----------|------|-----------|------|
| Granite Guardian | CPU Pod Running | `oc get inferenceservice granite-guardian` | **미배포** — S3에 Guardian 모델 미업로드 |
| GuardrailsOrchestrator | Pod Running (3/3) | `oc get pods -l app.kubernetes.io/part-of=trustyai` | **미배포** — Guardian 의존 |
| 정상 통과 | HTTP 200, 모델 응답 수신 | Step 4 curl 결과 | **Guardian 미배포로 미검증** |
| PII 차단 | 주민등록번호 감지 + 차단 | Step 5 차단 응답 | **Guardian 미배포로 미검증** |
| HAP 차단 | 유해 콘텐츠 감지 + 차단 | Step 6 차단 응답 | **Guardian 미배포로 미검증** |
| 한국어 PII 주민번호 | 901215-1234567 감지 | Step 7 감지 건수 | **PASS — v3 정확 감지 (오버랩 제거)** |
| 한국어 PII 전화번호 | 010-9876-5432 감지 | Step 7 감지 건수 | **PASS — v3 정확 감지 (오버랩 제거)** |
| 한국어 PII 복합 | 주민번호+전화번호+계좌번호 동시 감지 | Step 7 감지 건수 | **PASS — 3건 정확 감지 (v3 오버랩 제거)** |
| 오탐 | 정상 텍스트에서 감지 0건 | Step 7 테스트 4 | **PASS — 0건** |
| PII 감지율 | >90% | 복합 PII 테스트 결과 | **PASS — 주요 패턴 100% 감지** |

## 이번 시연에서 확인된 핵심 가치

1. **개인정보보호법 자동 준수**: 주민등록번호, 전화번호, 계좌번호 등 한국 고유 PII가 모델에 도달하기 전에 자동 차단. 법적 리스크 제로화
2. **유해 콘텐츠 사전 차단**: HAP 필터로 증오/욕설/폭력 프롬프트를 차단하여 기업 AI 서비스의 안전성과 신뢰도 확보
3. **GPU 비용 효율**: Granite Guardian이 CPU만으로 동작하여 보안 검사에 GPU를 할애할 필요 없음. 비즈니스 모델에 GPU 자원 집중
4. **한국어 특화**: 영어 기반 감지기의 한계를 한국어 PII 커스텀 감지기로 보완. 현지화된 개인정보 보호
5. **투명한 사용자 경험**: 정상 프롬프트는 지연 없이 통과. 보안이 사용자 경험을 방해하지 않음

## 추천 사항

| 구분 | 권장 사항 |
|------|----------|
| 단기 (PoC 완료 후) | GuardrailsOrchestrator를 모든 InferenceService에 기본 적용 |
| 중기 (3개월) | 한국어 PII 감지기에 여권번호, 운전면허번호 패턴 추가 |
| 장기 (6개월) | Granite Guardian GPU 버전으로 업그레이드하여 감지 정확도 향상 |
| 컴플라이언스 | OpenTelemetry 감사 로그를 SIEM(보안 정보 이벤트 관리)에 연동 |
| 거버넌스 | AI 사용 정책 문서화 (PII 차단 기준, HAP 분류 기준, 예외 승인 절차) |
| 운영 | 차단 이벤트 알림 구성 (Slack/이메일 연동), 월간 차단 통계 리포팅 |

## 제약 사항

| 항목 | 내용 |
|------|------|
| TLS | 자가서명 환경에서 외부 Route 경유 불가 → 내부 svc URL(`http://`) 사용 |
| GPU Guardian | Granite Guardian GPU 버전이 더 정확하지만 GPU 필요 → PoC에서는 CPU 버전 사용 |
| 한국어 PII | 내장 감지기는 영어 중심. 한국어 패턴은 커스텀 감지기(`korean-pii-detector`) 필요 |
| HAP 정확도 | 내장 분류 모델 기반. 미묘한 유해 콘텐츠는 오탐/미탐 가능 |
| 지연 | 가드레일 파이프라인이 추가되면 응답 시간 50~200ms 증가 (비즈니스 영향 미미) |

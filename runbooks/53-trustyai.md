# 53 — TrustyAI Service 구성

## 목적

PoC 네임스페이스에 TrustyAIService(모델 모니터링/메트릭 수집)를 배포한다. GuardrailsOrchestrator와 LMEvalJob은 InferenceService 배포 후 `runbooks/60-b-guardrails.md`에서 구성한다.

## 전제 조건

- [ ] `runbooks/52-dspa.md` 완료
- [ ] `${MODEL_NS}` 환경변수 설정

## 실행

### 1. DSC TrustyAI LMEval 온라인 평가 활성화

~~~bash
set -a && source .env && set +a

oc patch dsc default-dsc --type='merge' \
  -p '{"spec":{"components":{"trustyai":{"eval":{"lmeval":{"permitOnline":"allow"}}}}}}'
~~~

### 2. TrustyAIService CR 생성

~~~bash
oc apply -n "${MODEL_NS}" -f - <<'EOF'
apiVersion: trustyai.opendatahub.io/v1
kind: TrustyAIService
metadata:
  name: trustyai-service
spec:
  replicas: 1
  storage:
    format: PVC
    folder: /data
    size: 1Gi
  metrics:
    schedule: "5s"
    batchSize: 5000
  data:
    filename: data.csv
    format: CSV
EOF

echo "TrustyAIService 대기 (최대 2분)..."
sleep 30
oc get trustyaiservice -n "${MODEL_NS}"
~~~

## 검증

~~~bash
echo "=== 53 — TrustyAI 검증 ==="
echo "TrustyAIService: $(oc get trustyaiservice trustyai-service -n ${MODEL_NS} -o jsonpath='{.status.conditions[?(@.type=="AllComponentsReady")].status}' 2>/dev/null)"
echo "Pod: $(oc get pods -n ${MODEL_NS} -l app.kubernetes.io/name=trustyai-service -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo '미배포')"
echo "Route: $(oc get route trustyai-service -n ${MODEL_NS} -o jsonpath='{.spec.host}' 2>/dev/null || echo '없음')"
~~~

## 실패 시

- **TrustyAIService Pending** → PVC 할당 확인: `oc describe trustyaiservice trustyai-service -n ${MODEL_NS}`
- **Pod CrashLoop** → 로그 확인: `oc logs -l app.kubernetes.io/name=trustyai-service -n ${MODEL_NS}`

## 다음 단계

→ `runbooks/54-mlflow.md` — MLflow Server 구성

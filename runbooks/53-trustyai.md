# 53 — TrustyAI + Guardrails 구성

## 목적

PoC 네임스페이스에 TrustyAIService(모델 모니터링/평가)와 GuardrailsOrchestrator(PII 감지/콘텐츠 필터링)를 배포한다. S6 운영관리 시나리오의 전제 조건.

## 전제 조건

- [ ] `runbooks/52-dspa.md` 완료
- [ ] DSC TrustyAIReady=True
- [ ] InferenceService 배포 완료 (Guardrails 연동 시)
- [ ] `${MODEL_NS}`, `${MODEL_NAME}` 환경변수 설정

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

### 3. GuardrailsOrchestrator (모델 배포 후 실행)

> **주의**: InferenceService가 먼저 배포되어야 한다. S1 구축(runbooks/60) 완료 후 실행.

~~~bash
oc get inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" 2>/dev/null || {
  echo "WARNING: InferenceService 미배포. runbooks/60 완료 후 이 단계를 실행하세요."
  exit 0
}

oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: GuardrailsOrchestrator
metadata:
  name: ${MODEL_NAME}-guardrails
spec:
  replicas: 1
  autoConfig:
    inferenceServiceToGuardrail: ${MODEL_NAME}
  enableBuiltInDetectors: true
  enableGuardrailsGateway: true
  env:
    - name: OPENAI_BASE_URL
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1"
  otelExporter:
    otlpProtocol: grpc
EOF

sleep 30
oc get pods -n "${MODEL_NS}" -l app="${MODEL_NAME}-guardrails" --no-headers
~~~

### 4. LMEvalJob (모델 평가 — 선택)

~~~bash
oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: ${MODEL_NAME}-eval
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - name: model
      value: ${MODEL_NAME}
    - name: base_url
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/completions"
    - name: tokenizer_backend
      value: huggingface
    - name: tokenized_requests
      value: "false"
    - name: tokenizer
      value: "HuggingFaceTB/SmolLM2-135M"
  taskList:
    taskNames:
      - "hellaswag"
  limit: "3"
  batchSize: "1"
EOF

echo "LMEvalJob 대기 (최대 5분)..."
for i in $(seq 1 10); do
  STATE=$(oc get lmevaljob "${MODEL_NAME}-eval" -n "${MODEL_NS}" \
    -o jsonpath='{.status.state}' 2>/dev/null)
  echo "  ${i}0초: state=${STATE}"
  [ "${STATE}" = "Complete" ] && break
  sleep 30
done
~~~

## 검증

~~~bash
echo "=== 53 — TrustyAI 검증 ==="
echo "TrustyAIService: $(oc get trustyaiservice trustyai-service -n ${MODEL_NS} -o jsonpath='{.status.phase}' 2>/dev/null)"
echo "Guardrails: $(oc get pods -n ${MODEL_NS} -l app=${MODEL_NAME}-guardrails -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo '미배포')"
echo "LMEvalJob: $(oc get lmevaljob ${MODEL_NAME}-eval -n ${MODEL_NS} -o jsonpath='{.status.state}' 2>/dev/null || echo '미실행')"
~~~

## 실패 시

- **TrustyAIService Pending** → PVC 할당 확인: `oc describe trustyaiservice trustyai-service -n ${MODEL_NS}`
- **Guardrails CrashLoop** → InferenceService Ready 확인. `OPENAI_BASE_URL` 엔드포인트 접근 가능 여부
- **LMEvalJob 실패** → vLLM 모델 로딩 완료 상태 필요. `oc logs -l serving.kserve.io/inferenceservice=${MODEL_NAME} -n ${MODEL_NS}`

## 다음 단계

→ `runbooks/60-model-serving.md` — S1 모델 서빙 구축

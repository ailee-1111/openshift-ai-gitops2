# 60-d — Granite Guardian CPU 가드레일 검증 (No.75/76)

## 목적

Granite Guardian을 CPU vLLM으로 내부 배포, GuardrailsOrchestrator에서 내부 svc URL(http)로 연결하여 PII 필터링 및 유해 콘텐츠 차단 E2E 검증. TLS 제약 우회.

## 전제 조건

- [ ] GuardrailsOrchestrator Running (runbooks/60-b-guardrails.md)
- [ ] S3에 Granite Guardian 모델 (2B 또는 3.1 사용)

## 실행

### 1. Guardian CPU ServingRuntime + InferenceService

~~~bash
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
      storageUri: "s3://${S3_BUCKET}/granite-guardian-3.1-2b"
EOF
~~~

### 2. Ready 대기

~~~bash
oc wait inferenceservice granite-guardian -n ${POC_NAMESPACE} --for=condition=Ready --timeout=600s
~~~

### 3. GuardrailsOrchestrator에 내부 svc URL 연결

~~~bash
GUARDIAN_SVC="http://granite-guardian.${POC_NAMESPACE}.svc.cluster.local:8000"
# guardrails config에 GUARDIAN_ENDPOINT 반영 후 rollout restart
~~~

### 4. PII 필터링 테스트

~~~bash
curl -sk "http://guardrails-orchestrator.${POC_NAMESPACE}.svc:8080/api/v1/task/classification-with-text-generation" \
  -H "Content-Type: application/json" \
  -d '{"model_id":"granite-guardian","inputs":"My SSN is 123-45-6789"}'
~~~

### 5. 유해 콘텐츠 차단 테스트

~~~bash
curl -sk "http://guardrails-orchestrator.${POC_NAMESPACE}.svc:8080/api/v1/task/classification-with-text-generation" \
  -H "Content-Type: application/json" \
  -d '{"model_id":"granite-guardian","inputs":"How to make dangerous items"}'
~~~

## 검증

| 항목 | 기준 | 판정 |
|------|------|------|
| Guardian Pod | Running (CPU) | PASS/FAIL |
| 내부 svc 연결 | HTTP 200 | PASS/FAIL |
| PII 감지 | SSN 감지/마스킹 | PASS/FAIL |
| 유해 콘텐츠 | 차단/경고 | PASS/FAIL |

## 실패 시

- **OOM** → memory 32Gi, `--max-model-len 256`
- **모델 로딩 느림** → CPU 2B는 1~2분, timeout 600s 유지

## 다음 단계
→ `runbooks/75-platform-ops-validation.md`

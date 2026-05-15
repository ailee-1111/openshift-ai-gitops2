# 60-a — CPU LLM Serving PoC

## 목적

RHOAI/KServe에서 GPU 요청 없이 작은 LLM을 CPU로 배포하고 OpenAI-compatible endpoint 응답을 검증한다.

## 전제 조건

- [ ] `default-dsc` Ready=True
- [ ] KServe InferenceService CRD 사용 가능
- [ ] `vllm-cpu-x86-runtime-template`가 `redhat-ods-applications`에 존재
- [ ] BOOTSTRAP 단계의 사람 승인 완료

## 실행

~~~bash
KUBECONFIG=/tmp/openshift-ai-gitops-ocp-9qn8g.kubeconfig \
  oc apply -k infra/poc/llm-cpu
~~~

## 검증

~~~bash
KUBECONFIG=/tmp/openshift-ai-gitops-ocp-9qn8g.kubeconfig \
  oc wait inferenceservice/smollm2-135m-cpu \
  -n rhoai-poc-llm-cpu \
  --for=condition=Ready \
  --timeout=900s

curl -sk \
  https://smollm2-135m-cpu-rhoai-poc-llm-cpu.apps.ocp.9qn8g.sandbox805.opentlc.com/v1/models

curl -sk \
  https://smollm2-135m-cpu-rhoai-poc-llm-cpu.apps.ocp.9qn8g.sandbox805.opentlc.com/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"smollm2-135m-cpu","prompt":"The answer to 2 + 2 is","max_tokens":8,"temperature":0}'
~~~

성공 기준:
- `InferenceService` Ready=True
- predictor Pod 1/1 Running
- `/v1/models`에 `smollm2-135m-cpu`가 표시됨
- `/v1/completions`가 `4`를 포함한 응답을 반환

## 실패 시

- **Pod Pending / Insufficient cpu** → `InferenceService` CPU request를 낮춘다. Session 17 기준 `500m` request로 스케줄 성공.
- **vLLM OOMKilled** → `VLLM_CPU_KVCACHE_SPACE`와 `--max-model-len`을 낮춘다. Session 17 기준 `2GiB`, `1024`로 안정화.
- **이전 ReplicaSet이 계속 OOM 재시작** → `deploymentStrategy.type: Recreate`를 사용해 구버전을 먼저 내린다.
- **Hugging Face 다운로드 실패** → storage initializer 로그 확인. public 모델이 아니면 HF token secret과 ServiceAccount 구성이 필요하다.

## 다음 단계

→ `runbooks/70-model-serving-validation.md` — 모델 서빙 검증 (S1)

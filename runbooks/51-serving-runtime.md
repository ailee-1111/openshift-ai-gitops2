# 51 — vLLM ServingRuntime 구성

## 목적

PoC 네임스페이스에 vLLM GPU ServingRuntime을 등록하여 InferenceService 배포의 전제 조건을 갖춘다.

## 전제 조건

- [ ] `runbooks/50-model-registry.md` 완료
- [ ] GPU 노드에 `nvidia.com/gpu` 리소스 등록 (runbooks/45)
- [ ] `${MODEL_NS}` 환경변수 설정

## 실행

### 1. RHOAI 제공 vLLM Runtime 확인

~~~bash
set -a && source .env && set +a

echo "=== 기존 ServingRuntime ==="
oc get servingruntime -n "${MODEL_NS}" --no-headers 2>/dev/null
oc get template -n redhat-ods-applications --no-headers 2>/dev/null | grep -i vllm
~~~

### 2. vLLM CUDA ServingRuntime 생성

~~~bash
oc apply -n "${MODEL_NS}" -f - <<'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-cuda-runtime
  labels:
    opendatahub.io/dashboard: "true"
  annotations:
    openshift.io/display-name: "vLLM CUDA Runtime"
    opendatahub.io/recommended-accelerators: '["nvidia.com/gpu"]'
spec:
  annotations:
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
  multiModel: false
  supportedModelFormats:
    - name: vLLM
      autoSelect: true
  containers:
    - name: kserve-container
      image: quay.io/modh/vllm:rhoai-2.22-cuda
      command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
      ports:
        - containerPort: 8080
          protocol: TCP
      env:
        - name: HF_HUB_OFFLINE
          value: "1"
EOF

oc get servingruntime -n "${MODEL_NS}" --no-headers
~~~

## 검증

~~~bash
echo "=== 51 — ServingRuntime 검증 ==="
oc get servingruntime -n "${MODEL_NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.supportedModelFormats[*].name}{"\n"}{end}'
# 기대: vllm-cuda-runtime: vLLM
~~~

## 실패 시

- **이미지 풀 실패** → `quay.io/modh/vllm:rhoai-2.22-cuda` 접근 확인. 대안: RHOAI 템플릿 `oc process -n redhat-ods-applications vllm-cuda-runtime-template`

## 다음 단계

→ `runbooks/52-dspa.md` — DataSciencePipelinesApplication 구성

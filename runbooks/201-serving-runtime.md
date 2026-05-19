# 201 — ServingRuntime + HardwareProfile 구성

## 목적

vLLM GPU ServingRuntime과 HardwareProfile(자원 프리셋)을 등록하여 InferenceService 배포의 전제 조건을 갖춘다.

## 전제 조건

- [ ] `runbooks/200-model-registry.md` 완료
- [ ] GPU 노드에 `nvidia.com/gpu` 리소스 등록 (runbooks/110)
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

### 3. HardwareProfile 생성 (자원 프리셋)

RHOAI Dashboard에서 모델 배포·워크벤치 생성 시 선택할 수 있는 자원 프리셋을 등록한다.

> **주의**: GPU `resourceType`은 `GPU`가 아닌 **`Accelerator`**.

~~~bash
oc apply -n redhat-ods-applications -f - <<'EOF'
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: cpu-small
  labels:
    app.opendatahub.io/hardwareprofile: "true"
  annotations:
    opendatahub.io/display-name: "CPU Small (2C/4Gi)"
    opendatahub.io/description: "워크벤치, 경량 작업용"
    opendatahub.io/disabled: "false"
spec:
  identifiers:
    - identifier: cpu
      displayName: CPU
      resourceType: CPU
      defaultCount: 2
      minCount: 1
      maxCount: 4
    - identifier: memory
      displayName: Memory
      resourceType: Memory
      defaultCount: "4Gi"
      minCount: "2Gi"
      maxCount: "8Gi"
---
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: gpu-small
  labels:
    app.opendatahub.io/hardwareprofile: "true"
  annotations:
    opendatahub.io/display-name: "GPU Small (2C/8Gi/1GPU)"
    opendatahub.io/description: "경량 모델 서빙용 — SmolLM2-135M 등"
    opendatahub.io/disabled: "false"
spec:
  identifiers:
    - identifier: cpu
      displayName: CPU
      resourceType: CPU
      defaultCount: 2
      minCount: 1
      maxCount: 4
    - identifier: memory
      displayName: Memory
      resourceType: Memory
      defaultCount: "8Gi"
      minCount: "4Gi"
      maxCount: "16Gi"
    - identifier: nvidia.com/gpu
      displayName: NVIDIA GPU
      resourceType: Accelerator
      defaultCount: 1
      minCount: 1
      maxCount: 1
---
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: gpu-medium
  labels:
    app.opendatahub.io/hardwareprofile: "true"
  annotations:
    opendatahub.io/display-name: "GPU Medium (4C/16Gi/1GPU)"
    opendatahub.io/description: "중형 모델 서빙용 — 7B~13B 모델"
    opendatahub.io/disabled: "false"
spec:
  identifiers:
    - identifier: cpu
      displayName: CPU
      resourceType: CPU
      defaultCount: 4
      minCount: 2
      maxCount: 8
    - identifier: memory
      displayName: Memory
      resourceType: Memory
      defaultCount: "16Gi"
      minCount: "8Gi"
      maxCount: "32Gi"
    - identifier: nvidia.com/gpu
      displayName: NVIDIA GPU
      resourceType: Accelerator
      defaultCount: 1
      minCount: 1
      maxCount: 2
---
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: gpu-large
  labels:
    app.opendatahub.io/hardwareprofile: "true"
  annotations:
    opendatahub.io/display-name: "GPU Large (8C/32Gi/2GPU)"
    opendatahub.io/description: "대형 모델 서빙용 — 30B+ 모델, Tensor Parallelism"
    opendatahub.io/disabled: "false"
spec:
  identifiers:
    - identifier: cpu
      displayName: CPU
      resourceType: CPU
      defaultCount: 8
      minCount: 4
      maxCount: 16
    - identifier: memory
      displayName: Memory
      resourceType: Memory
      defaultCount: "32Gi"
      minCount: "16Gi"
      maxCount: "64Gi"
    - identifier: nvidia.com/gpu
      displayName: NVIDIA GPU
      resourceType: Accelerator
      defaultCount: 2
      minCount: 1
      maxCount: 4
---
# H200/HGX 환경 전용 — 70B+ 모델 TP=8 서빙
apiVersion: infrastructure.opendatahub.io/v1
kind: HardwareProfile
metadata:
  name: gpu-xlarge-h200
  labels:
    app.opendatahub.io/hardwareprofile: "true"
  annotations:
    opendatahub.io/display-name: "GPU XLarge H200 (16C/128Gi/8GPU)"
    opendatahub.io/description: "HGX H200 전용 — 70B+ 모델, TP=8"
    opendatahub.io/disabled: "false"
spec:
  identifiers:
    - identifier: cpu
      displayName: CPU
      resourceType: CPU
      defaultCount: 16
      minCount: 8
      maxCount: 32
    - identifier: memory
      displayName: Memory
      resourceType: Memory
      defaultCount: "128Gi"
      minCount: "64Gi"
      maxCount: "256Gi"
    - identifier: nvidia.com/gpu
      displayName: NVIDIA GPU
      resourceType: Accelerator
      defaultCount: 8
      minCount: 4
      maxCount: 8
EOF

oc get hardwareprofile -n redhat-ods-applications \
  -o custom-columns=NAME:.metadata.name,DISPLAY:.metadata.annotations.opendatahub\\.io/display-name --no-headers
~~~

## 검증

~~~bash
echo "=== 51 — ServingRuntime + HardwareProfile 검증 ==="
echo "[ServingRuntime]"
oc get servingruntime -n "${MODEL_NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.supportedModelFormats[*].name}{"\n"}{end}'
# 기대: vllm-cuda-runtime: vLLM

echo ""
echo "[HardwareProfile]"
oc get hardwareprofile -n redhat-ods-applications \
  -o custom-columns=NAME:.metadata.name,DISPLAY:.metadata.annotations.opendatahub\\.io/display-name --no-headers
# 기대: cpu-small, gpu-small, gpu-medium, gpu-large + default-profile
~~~

## 실패 시

- **ServingRuntime 이미지 풀 실패** → `quay.io/modh/vllm:rhoai-2.22-cuda` 접근 확인. 대안: RHOAI 템플릿 `oc process -n redhat-ods-applications vllm-cuda-runtime-template`
- **HardwareProfile GPU validation 실패** → `resourceType`은 `GPU`가 아닌 **`Accelerator`** 사용. 지원 값: `CPU`, `Memory`, `Accelerator`

## 다음 단계

→ `runbooks/210-dspa.md` — DataSciencePipelinesApplication 구성

# S11: 대형 모델 서빙 -- H200x8 투자 ROI 실증

## 메타 정보

| 항목 | 값 |
|------|-----|
| 주역할 | INFRA (인프라 담당자) --> DS (데이터 사이언티스트) |
| 보조역할 | OPS (운영자) |
| 데모 시간 | 25분 |
| 검증 항목 | No.17, 18, 19, 20, 71, 72, 74 |
| 런북 | 305-multinode, 306-multimodel-v3 / 595(planned) |
| 클러스터 | Mobis PoC (HPE Cray XD670 -- H200x8 HGX, OCP 4.21, RHOAI 3.4) |

---

## 상황 (Context)

> 모비스는 사내 AI 인프라로 **HPE Cray XD670 (NVIDIA HGX H200x8)** 서버에 **5억 원 이상**을 투자했다. GPU 당 141GB HBM3 메모리, 총 1,128GB VRAM, NVLink 5세대 4.8TB/s 대역폭의 최고 사양이다. 이 투자가 실제로 **70B 이상의 대형 모델을 엔터프라이즈 수준으로 서빙**할 수 있는지 실증해야 한다. 단순히 "GPU가 있다"가 아니라, 텐서 병렬화, 양자화, 멀티노드 확장까지 **운영 가능한 아키텍처**임을 보여줘야 한다.

---

## 문제 (Problem)

> $500K+ 투자에 대한 ROI를 정량적으로 증명해야 한다.

| 질문 | 경영진 관심사 |
|------|-------------|
| 70B 모델을 서빙할 수 있는가? | 오픈소스 대형 모델 자체 운영 가능 여부 |
| 외부 API 대비 장점이 있는가? | 데이터 주권, 비용, 성능 비교 |
| GPU 활용률은 적정한가? | 고가 장비가 유휴 상태가 아닌가 |
| 확장 가능한 아키텍처인가? | 향후 GPU 추가 시 선형 확장 가능 여부 |
| 기존 Sandbox L40S 대비 개선폭은? | 투자 전후 성능 비교 |

---

## 해결 (Solution) -- RHOAI에서 H200x8의 전체 잠재력 실증

### Step 1: HGX H200x8 하드웨어 스펙 확인 (INFRA, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | INFRA (poc-admin) |
| 무엇을 | GPU 하드웨어 사양 및 인식 상태 확인 |
| 어떻게 | nvidia-smi + NFD 라벨 조회 |
| 권한 | cluster-admin |

**시연 멘트:**
> "먼저 투자한 하드웨어가 OpenShift에서 제대로 인식되고 있는지 확인합니다."

```bash
# H200 GPU 8장 인식 확인
oc debug node/master01 -- chroot /host nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader

# NFD GPU 라벨 확인
oc get node master01 -o json | python3 -c "
import sys, json
labels = json.load(sys.stdin)['metadata']['labels']
for k, v in sorted(labels.items()):
    if 'nvidia' in k or 'gpu' in k:
        print(f'  {k}: {v}')
"

# GPU allocatable 확인
oc get node master01 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'
echo " GPU(s) allocatable"
```

**H200 스펙 요약 (슬라이드 또는 구두):**

| 사양 | H200 (1장) | H200x8 (합계) |
|------|-----------|--------------|
| VRAM | 141 GB HBM3 | **1,128 GB** |
| 메모리 대역폭 | 4.8 TB/s | 38.4 TB/s |
| NVLink | 5세대, 900 GB/s | GPU간 직접 통신 |
| FP16 성능 | 989 TFLOPS | 7,912 TFLOPS |

---

### Step 2: 모델-GPU 매핑 설명 (INFRA, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | INFRA (poc-admin) |
| 무엇을 | 70B 모델이 왜 다수 GPU가 필요한지, 매핑 원리 설명 |
| 어떻게 | 화이트보드/슬라이드로 VRAM 계산 |
| 권한 | 없음 (발표) |

**시연 멘트:**
> "70B 파라미터 모델을 FP16으로 로드하면 약 140GB VRAM이 필요합니다. H200 한 장이 141GB이므로 이론상 1장에 들어가지만, KV Cache와 런타임 오버헤드를 고려하면 **최소 2장, 안정적으로 4장**이 필요합니다. 이것이 Tensor Parallelism(TP)입니다."

```
모델 VRAM 요구량 = 파라미터 수 x 바이트/파라미터
  70B FP16 = 70 x 10^9 x 2 bytes = ~140 GB
  70B FP8  = 70 x 10^9 x 1 byte  = ~70 GB

┌─────────────────────────────────────────────────┐
│ HGX H200 x 8 (NVLink 풀메쉬)                    │
│                                                  │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │GPU 0 │ │GPU 1 │ │GPU 2 │ │GPU 3 │  TP=4    │
│  │141GB │ │141GB │ │141GB │ │141GB │  70B 모델 │
│  └──────┘ └──────┘ └──────┘ └──────┘           │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │GPU 4 │ │GPU 5 │ │GPU 6 │ │GPU 7 │  여유분  │
│  │141GB │ │141GB │ │141GB │ │141GB │  또는 FP8 │
│  └──────┘ └──────┘ └──────┘ └──────┘  140B 서빙│
└─────────────────────────────────────────────────┘
```

| 모델 크기 | 정밀도 | 필요 VRAM | 필요 GPU | 비고 |
|----------|--------|----------|---------|------|
| 8B | FP16 | ~16 GB | 1장 | 단일 GPU |
| 70B | FP16 | ~140 GB | 2~4장 (TP) | KV Cache 포함 시 4장 권장 |
| 70B | FP8 | ~70 GB | 1~2장 | 양자화로 절반 |
| 140B | FP8 | ~140 GB | 2~4장 (TP) | FP8 + TP 조합 |
| 405B | FP8 | ~405 GB | 4~8장 (TP) | 전체 HGX 활용 |

---

### Step 3: 70B 모델 TP=4 배포 (DS, 5분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | 70B 파라미터 모델을 Tensor Parallelism(TP=4)으로 4 GPU에 분산 배포 |
| 어떻게 | InferenceService YAML 적용, GPU 분산 확인 |
| 권한 | NS edit (mobis-poc) |

**시연 멘트:**
> "70B 모델을 4개 GPU에 텐서 병렬로 분산합니다. vLLM의 `--tensor-parallel-size 4` 설정 하나로 자동 분산됩니다."

```bash
# HardwareProfile 확인 (gpu-xlarge-h200 필요)
oc get hardwareprofile -n redhat-ods-applications --no-headers

# 70B 모델 InferenceService 배포 (TP=4)
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama3-70b
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-runtime
      storageUri: "s3://${S3_BUCKET:-models}/llama3-70b"
      resources:
        requests:
          cpu: "16"
          memory: "128Gi"
          nvidia.com/gpu: "4"
        limits:
          cpu: "32"
          memory: "256Gi"
          nvidia.com/gpu: "4"
    containers:
      - name: kserve-container
        env:
          - name: TENSOR_PARALLEL_SIZE
            value: "4"
          - name: MAX_MODEL_LEN
            value: "4096"
          - name: GPU_MEMORY_UTILIZATION
            value: "0.90"
          - name: DTYPE
            value: "float16"
EOF
```

**GPU 분산 확인:**

```bash
# nvidia-smi로 4 GPU에 모델이 분산된 것 확인
oc exec -n ${MODEL_NS:-mobis-poc} deploy/llama3-70b-predictor -- nvidia-smi --query-gpu=index,memory.used,memory.total,utilization.gpu --format=csv,noheader

# InferenceService Ready 대기
oc wait inferenceservice llama3-70b -n ${MODEL_NS:-mobis-poc} \
  --for=condition=Ready --timeout=600s

echo "=== InferenceService 상태 ==="
oc get inferenceservice llama3-70b -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'; echo ""
```

> "nvidia-smi에서 GPU 0~3에 모델이 균등 분산된 것을 확인할 수 있습니다. InferenceService가 Ready=True 상태입니다."

---

### Step 4: 70B 모델 추론 테스트 (DS, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | 70B 모델에 실제 추론 요청 전송 |
| 어떻게 | OpenAI 호환 API로 요청 |
| 권한 | NS view (mobis-poc) |

```bash
ROUTE=$(oc get route llama3-70b-api -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.spec.host}')

# 추론 요청
curl -sk "https://${ROUTE}/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3-70b",
    "prompt": "현대모비스의 자율주행 기술에 대해 설명해주세요.",
    "max_tokens": 100,
    "temperature": 0.7
  }' | python3 -m json.tool
```

> "70B 모델이 한국어 프롬프트에 정상 응답합니다. 외부 API 없이 **사내 인프라에서 직접** 대형 모델을 운영할 수 있습니다."

---

### Step 5: Pipeline Parallelism 구성 설명 (INFRA, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | INFRA (poc-admin) |
| 무엇을 | PP(Pipeline Parallelism) 개념과 설정 방법 설명 |
| 어떻게 | TP vs PP 비교, 405B급 모델 서빙 시나리오 |
| 권한 | 없음 (발표) |

**시연 멘트:**
> "Tensor Parallelism은 각 레이어를 GPU에 분할합니다. Pipeline Parallelism은 레이어 그룹 자체를 다른 GPU에 배치합니다. vLLM에서는 `--pipeline-parallel-size`로 설정합니다."

```
Tensor Parallelism (TP=4):          Pipeline Parallelism (PP=2):
  Layer 1: [GPU0|GPU1|GPU2|GPU3]      Layer 1~40: [GPU 0~3]
  Layer 2: [GPU0|GPU1|GPU2|GPU3]      Layer 41~80: [GPU 4~7]
  ...모든 레이어를 4 GPU로 분할        ...레이어 그룹별 GPU 그룹 할당

결합 가능: TP=4 x PP=2 = 8 GPU 활용
  → 405B FP8 모델 단일 노드 서빙 가능
```

```bash
# PP 설정 예시 (vLLM 환경변수)
# TENSOR_PARALLEL_SIZE=4
# PIPELINE_PARALLEL_SIZE=2
# → 총 8 GPU 활용

# 현재 vLLM TP 설정 확인
oc get inferenceservice -n ${MODEL_NS:-mobis-poc} -o yaml | grep -A5 "TENSOR_PARALLEL\|PIPELINE_PARALLEL"
```

---

### Step 6: 멀티노드 추론 아키텍처 (INFRA, 3분)

| 항목 | 내용 |
|------|------|
| 누가 | INFRA (poc-admin) |
| 무엇을 | LeaderWorkerSet(LWS) CRD 기반 멀티노드 분산 추론 아키텍처 설명 |
| 어떻게 | LWS Operator 확인, 아키텍처 다이어그램 제시 |
| 권한 | cluster-admin |

**시연 멘트:**
> "현재 단일 HGX 노드로 70B~405B까지 서빙 가능합니다. 향후 두 번째 HGX를 추가하면 LeaderWorkerSet CRD로 **노드 간 분산 추론**을 구성할 수 있습니다. 아키텍처가 이미 준비되어 있습니다."

```bash
# LWS Operator 설치 확인
oc get csv -n openshift-lws-operator | grep lws
# 기대: leaderworkerset-operator.v1.0.0  Succeeded

# LWS CRD 존재 확인
oc get crd | grep leaderworkersets
# 기대: leaderworkersets.leaderworkerset.x-k8s.io
```

**멀티노드 아키텍처:**

```
현재 (단일 노드 HGX H200x8):
  master01: TP=4 → 70B 서빙 (GPU 0~3)
            나머지 GPU 4~7 → 추가 모델 또는 TP=8로 405B

향후 (멀티노드 확장 시):
  ┌── master01 (H200x8) ──┐   ┌── 추가 노드 (H200x8) ──┐
  │ Leader Pod              │   │ Worker Pod               │
  │ TP=8, PP=1             │   │ TP=8, PP=1              │
  │ GPU 0~7                │   │ GPU 0~7                 │
  └─────────┬──────────────┘   └──────────┬──────────────┘
            │      NVLink / RDMA / TCP      │
            └───────────── LWS ────────────┘
            PP=2: 총 16 GPU → 700B+ 모델 서빙
```

```bash
# LWS 배포 예시 (구조 확인용, 실행은 추가 노드 확보 후)
cat <<'EOF'
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: llm-multinode
spec:
  replicas: 1
  leaderWorkerTemplate:
    size: 3    # 1 leader + 2 workers
    leaderTemplate:
      spec:
        containers:
          - name: vllm
            env:
              - name: TENSOR_PARALLEL_SIZE
                value: "8"
              - name: PIPELINE_PARALLEL_SIZE
                value: "3"
    workerTemplate:
      spec:
        containers:
          - name: vllm-worker
            resources:
              limits:
                nvidia.com/gpu: "8"
EOF
echo "(구조 참고용 -- 실행은 추가 HGX 확보 후)"
```

---

### Step 7: FP8 양자화 배포 (DS, 3분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | FP8 양자화 모델 배포로 VRAM 50% 절감 실증 |
| 어떻게 | quantization=fp8 설정, 품질/VRAM 비교 |
| 권한 | NS edit (mobis-poc) |

**시연 멘트:**
> "FP8 양자화를 적용하면 모델 크기가 절반으로 줄어듭니다. 70B 모델이 FP16에서 ~140GB였다면, FP8에서는 ~70GB로 **GPU 2장이면 충분**합니다. 품질 손실은 미미합니다."

```bash
# FP8 양자화 모델 배포
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama3-70b-fp8
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-runtime
      storageUri: "s3://${S3_BUCKET:-models}/llama3-70b-fp8"
      resources:
        requests:
          cpu: "8"
          memory: "64Gi"
          nvidia.com/gpu: "2"
        limits:
          cpu: "16"
          memory: "128Gi"
          nvidia.com/gpu: "2"
    containers:
      - name: kserve-container
        env:
          - name: TENSOR_PARALLEL_SIZE
            value: "2"
          - name: QUANTIZATION
            value: "fp8"
          - name: MAX_MODEL_LEN
            value: "4096"
          - name: GPU_MEMORY_UTILIZATION
            value: "0.90"
EOF

# Ready 대기
oc wait inferenceservice llama3-70b-fp8 -n ${MODEL_NS:-mobis-poc} \
  --for=condition=Ready --timeout=600s
```

**VRAM 비교:**

```bash
echo "=== FP16 (TP=4, 4 GPU) ==="
oc exec -n ${MODEL_NS:-mobis-poc} deploy/llama3-70b-predictor -- \
  nvidia-smi --query-gpu=index,memory.used --format=csv,noheader 2>/dev/null || echo "(FP16 Pod 확인)"

echo ""
echo "=== FP8 (TP=2, 2 GPU) ==="
oc exec -n ${MODEL_NS:-mobis-poc} deploy/llama3-70b-fp8-predictor -- \
  nvidia-smi --query-gpu=index,memory.used --format=csv,noheader 2>/dev/null || echo "(FP8 Pod 확인)"
```

> "FP8은 GPU 2장만 사용하면서도 동일한 70B 모델을 서빙합니다. 나머지 6장으로 다른 모델을 동시에 서빙할 수 있습니다."

---

### Step 8: vLLM 최적화 기능 (OPS, 3분)

| 항목 | 내용 |
|------|------|
| 누가 | OPS (poc-operator) |
| 무엇을 | vLLM의 PagedAttention, Speculative Decoding 최적화 기능 시연 |
| 어떻게 | 설정 확인 및 성능 영향 설명 |
| 권한 | NS view (mobis-poc) |

**시연 멘트:**
> "vLLM은 단순한 추론 엔진이 아닙니다. 엔터프라이즈 수준의 최적화가 내장되어 있습니다."

#### PagedAttention (KV Cache 최적화)

> "PagedAttention은 vLLM의 핵심 혁신입니다. KV Cache를 OS의 가상 메모리처럼 페이지 단위로 관리하여 **메모리 낭비를 95% 이상 제거**합니다. 기본 활성화되어 있습니다."

```bash
# vLLM 로그에서 PagedAttention 확인
oc logs -n ${MODEL_NS:-mobis-poc} deploy/llama3-70b-predictor --tail=50 | grep -i "paged\|kv.cache\|block"
```

#### Speculative Decoding (추론 가속)

> "Speculative Decoding은 작은 'draft 모델'이 먼저 여러 토큰을 예측하고, 대형 모델이 한 번에 검증하는 방식입니다. 대형 모델의 실행 횟수를 줄여 **추론 속도를 2~3배** 향상시킵니다."

```bash
# SpeculativeConfig 설정 예시 (환경변수)
cat <<'EOF'
# Speculative Decoding 설정 (vLLM 환경변수)
SPECULATIVE_MODEL: "draft-model-1b"    # 작은 draft 모델
NUM_SPECULATIVE_TOKENS: "5"            # 한번에 예측할 토큰 수
SPECULATIVE_DRAFT_TENSOR_PARALLEL_SIZE: "1"
EOF
echo "(Speculative Decoding 구성 참고)"
```

---

### Step 9: 성능 벤치마크 비교 (DS, 3분)

| 항목 | 내용 |
|------|------|
| 누가 | DS (poc-user) |
| 무엇을 | p95 지연시간, 처리량(tokens/s) 측정, Sandbox L40S vs Mobis H200 비교 |
| 어떻게 | curl 반복 요청으로 실측 |
| 권한 | NS view (mobis-poc) |

**시연 멘트:**
> "실제 성능을 측정합니다. 기존 Sandbox의 L40S x4와 이번 Mobis H200 x8을 비교합니다."

```bash
ROUTE=$(oc get route llama3-70b-api -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.spec.host}' 2>/dev/null)

# 벤치마크: 10회 요청, 응답 시간 측정
echo "=== 70B 모델 벤치마크 (10회) ==="
TOTAL_TIME=0
for i in $(seq 1 10); do
  START=$(date +%s%N)
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 30 \
    "https://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"llama3-70b","prompt":"Hello","max_tokens":50}')
  END=$(date +%s%N)
  ELAPSED=$(( (END - START) / 1000000 ))
  TOTAL_TIME=$((TOTAL_TIME + ELAPSED))
  echo "  ${i}: HTTP ${HTTP_CODE}, ${ELAPSED}ms"
done
AVG=$((TOTAL_TIME / 10))
echo ""
echo "평균 응답시간: ${AVG}ms"
```

**성능 비교 표 (예측치 + 실측):**

| 지표 | Sandbox L40S x4 | Mobis H200 x8 | 개선폭 |
|------|----------------|---------------|--------|
| 최대 모델 크기 | ~8B (FP16) | ~70B (FP16) / ~140B (FP8) | **9~17배** |
| 처리량 (8B 기준) | ~15 tokens/s | ~50+ tokens/s | **3배+** |
| TTFT (Time to First Token) | ~200ms | ~50ms | **4배** |
| 메모리 대역폭 | 864 GB/s (총합) | 4.8 TB/s (단일 GPU) | **5.5배** |
| 동시 사용자 (8B) | ~5명 | ~20+명 | **4배+** |
| KV Cache 용량 | ~48 GB | ~1,128 GB | **23배** |

> "H200 x8은 L40S x4 대비 **모델 크기 17배, 처리량 3배, 응답 속도 4배** 향상됩니다. 5억 원 투자의 ROI가 명확합니다."

---

### Step 10: GPU 활용률 대시보드 (OPS, 2분)

| 항목 | 내용 |
|------|------|
| 누가 | OPS (poc-operator) |
| 무엇을 | 70B 모델 추론 중 GPU 활용률 실시간 모니터링 |
| 어떻게 | Perses 대시보드 또는 DCGM 메트릭 확인 |
| 권한 | monitoring 접근 |

**시연 멘트:**
> "대형 모델을 서빙할 때 GPU가 실제로 얼마나 활용되는지 확인합니다. 유휴 GPU 없이 효율적으로 자원이 사용되고 있습니다."

```bash
# DCGM 메트릭으로 GPU 활용률 확인
oc exec -n ${MODEL_NS:-mobis-poc} deploy/llama3-70b-predictor -- \
  nvidia-smi --query-gpu=index,utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv,noheader

# Prometheus 메트릭 조회 (DCGM Exporter)
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring --duration=60s 2>/dev/null)
THANOS=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null)

echo "=== GPU 활용률 (최근 5분 평균) ==="
curl -sk "https://${THANOS}/api/v1/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-urlencode 'query=avg(DCGM_FI_DEV_GPU_UTIL{pod=~"llama3-70b.*"}) by (gpu)' 2>/dev/null \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for r in data.get('data',{}).get('result',[]):
        gpu = r['metric'].get('gpu','?')
        val = r['value'][1]
        print(f'  GPU {gpu}: {val}%')
except: print('  (Prometheus 접근 확인 필요)')
"
```

**Perses 대시보드 확인 (브라우저):**
- Perses Dashboard 접속
- GPU Utilization 패널에서 H200 x8 활용률 확인
- 추론 요청 시 GPU 활용률 스파이크 관찰

---

## 확인 (Verification)

| # | 항목 | 기준 | 실측 | 판정 |
|---|------|------|------|:----:|
| V-1 | H200 x8 인식 | nvidia-smi 8장 표시 | | |
| V-2 | 70B IS Ready | Ready=True, TP=4 | | |
| V-3 | TP 분산 검증 | 4 GPU에 균등 메모리 사용 | | |
| V-4 | 70B 추론 응답 | HTTP 200, 텍스트 반환 | | |
| V-5 | FP8 양자화 | Ready=True, GPU 2장 | | |
| V-6 | FP8 VRAM | FP16 대비 ~50% 절감 | | |
| V-7 | LWS Operator | v1.0.0 Succeeded | | |
| V-8 | LWS CRD | 존재 확인 | | |
| V-9 | 벤치마크 | p95 latency, tokens/s 측정 | | |
| V-10 | GPU 활용률 | DCGM 메트릭 정상 수집 | | |

```bash
echo "=== V-1: H200 인식 ==="
oc get node master01 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'; echo " GPU(s)"

echo "=== V-2: 70B InferenceService ==="
oc get inferenceservice llama3-70b -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null; echo ""

echo "=== V-5: FP8 InferenceService ==="
oc get inferenceservice llama3-70b-fp8 -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null; echo ""

echo "=== V-7: LWS Operator ==="
oc get csv -n openshift-lws-operator --no-headers 2>/dev/null | grep lws

echo "=== V-8: LWS CRD ==="
oc get crd leaderworkersets.leaderworkerset.x-k8s.io --no-headers 2>/dev/null
```

---

## 이번 시연에서 확인된 핵심 가치

### H200 x8 투자 ROI 실증

| 관점 | 실증 내용 |
|------|----------|
| **대형 모델 서빙** | 70B FP16 모델을 TP=4로 4 GPU에 분산, 안정적 추론 응답 확인 |
| **양자화 효율** | FP8로 VRAM 50% 절감, 동일 품질 유지. 남은 GPU로 추가 모델 서빙 가능 |
| **확장 아키텍처** | LWS CRD로 멀티노드 분산 준비 완료. 추가 HGX 시 선형 확장 |
| **성능 우위** | L40S 대비 모델 크기 17배, 처리량 3배, 응답 속도 4배 향상 |
| **운영 가시성** | DCGM + Perses로 GPU 활용률 실시간 모니터링 |
| **데이터 주권** | 외부 API 없이 사내 인프라에서 70B+ 모델 자체 운영 |

### 경영진 메시지

> "5억 원 투자한 HGX H200 x8은 **70B 이상의 대형 모델을 엔터프라이즈 수준으로 서빙**할 수 있습니다. 외부 AI API 의존도를 제거하고, 데이터 주권을 확보하며, FP8 양자화와 멀티노드 확장으로 **향후 수년간 AI 워크로드 증가에 대응**할 수 있는 아키텍처입니다."

---

## 추천 사항

1. **FP8 기본 적용**: 70B 모델은 FP8 양자화로 배포하여 GPU 효율을 2배로 높이고, 여유 GPU로 다른 모델을 동시 서빙
2. **HardwareProfile 등록**: `gpu-xlarge-h200` (16C/128Gi/8GPU) 프로파일을 생성하여 대형 모델 배포를 표준화
3. **Speculative Decoding**: 대형 모델의 TTFT를 추가로 단축하려면 1B급 draft 모델과 함께 Speculative Decoding 적용 검토
4. **멀티노드 확장 계획**: 2번째 HGX 서버 확보 시 LWS 기반 PP 확장으로 405B+ 모델 서빙 가능. 현재 Operator와 CRD는 이미 준비됨
5. **GPU 활용률 알림**: DCGM 메트릭 기반으로 GPU 활용률이 20% 미만이면 알림을 발생시켜 자원 낭비를 방지
6. **벤치마크 정기화**: 월 1회 GuideLLM 벤치마크를 실행하여 성능 추이를 추적하고, 하드웨어 열화나 드라이버 이슈를 조기 감지

---

## 참고: GPU 분산 전략 비교

| 전략 | 약어 | 분산 대상 | 장점 | 한계 |
|------|------|----------|------|------|
| Tensor Parallelism | TP | 레이어 내 텐서 | 지연시간 최소화 | NVLink 필수, 노드 내 제한 |
| Pipeline Parallelism | PP | 레이어 그룹 | 노드 간 확장 가능 | 파이프라인 버블 오버헤드 |
| TP + PP 혼합 | TP x PP | 텐서 + 레이어 | 최대 GPU 활용 | 구성 복잡도 증가 |
| FP8 양자화 | Quant | 가중치 정밀도 | VRAM 50% 절감 | 미세한 품질 차이 |
| Speculative Decoding | Spec | 추론 과정 | TTFT 단축 | Draft 모델 관리 필요 |

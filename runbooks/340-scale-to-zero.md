# 340 — Scale-to-Zero / Cold Start (S5)

## 목적

일정 시간 요청이 없는 서빙 Pod를 replica=0으로 축소하여 GPU 자원(VRAM, 연산)을 완전히 회수하고, 재요청 시 Pod가 자동 복원(Cold Start)되어 서빙을 재개하는 전체 사이클을 검증한다.

## 전제 조건

- [ ] `runbooks/330-recovery.md` 완료 — 장애복구 검증 통과
- [ ] InferenceService Ready=True, 서빙 Pod Running (2/2 컨테이너)
- [ ] DCGM Exporter Running (`oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter`)
- [ ] ScaledObject 구성 완료 (`oc get scaledobject vllm-autoscaler -n ${MODEL_NS}`)
- [ ] 환경변수 설정: `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. 축소 전 GPU VRAM 사용량 기록

~~~bash
DCGM_POD=$(oc get pods -n nvidia-gpu-operator \
  -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}')

echo "=== 축소 전 VRAM ==="
oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
  curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"

echo "=== 축소 전 GPU 할당 ==="
oc describe node -l nvidia.com/gpu.present=true | grep -A5 "Allocated resources"
~~~

### 2. replica=0으로 축소 (Scale-to-Zero)

~~~bash
# KEDA ScaledObject가 있으면 먼저 일시 중지 (minReplicaCount가 축소를 차단함)
oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
  autoscaling.keda.sh/paused-replicas="0" --overwrite 2>/dev/null || true

# replica 0으로 전환
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=0
sleep 30

# Pod 종료 확인
echo "=== Pod 상태 (축소 후) ==="
oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running --no-headers
# 기대: 출력 없음 (Running Pod 0개)
~~~

### 3. GPU 자원 해제 확인

~~~bash
echo "=== 축소 후 VRAM ==="
oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
  curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"
# 기대: FB_USED 값이 대폭 감소 (모델 VRAM 해제)

echo "=== 축소 후 GPU 할당 ==="
oc describe node -l nvidia.com/gpu.present=true | grep -A5 "Allocated resources"
# 기대: nvidia.com/gpu 요청 0
~~~

### 4. Cold Start 측정 (replica=0 -> 1 복원)

~~~bash
# replica 0 상태 확인
oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running --no-headers
# 확인: Running Pod 없음

# KEDA paused 해제 + 복원 + 시간 측정
START=$(date +%s)
oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
  autoscaling.keda.sh/paused-replicas- --overwrite 2>/dev/null || true
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=1

# Pod Ready 대기
oc wait pod -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --for=condition=Ready --timeout=600s
END=$(date +%s)
COLD_START=$((END - START))
echo "Cold Start 시간: ${COLD_START}초"
~~~

### 5. API 서빙 재개 확인

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} \
  -o jsonpath='{.spec.host}')

for attempt in $(seq 1 30); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST "https://${ROUTE}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"'${MODEL_NAME}'","messages":[{"role":"user","content":"cold start test"}],"max_tokens":10}')
  echo "$(date '+%H:%M:%S') | 시도 ${attempt} | HTTP: ${HTTP_CODE}"
  if [ "${HTTP_CODE}" = "200" ]; then break; fi
  sleep 10
done
END_API=$(date +%s)
echo "API 복원까지 총 소요: $((END_API - START))초"
~~~

## 검증

~~~bash
# VRAM 재할당 확인
echo "=== 복원 후 VRAM ==="
oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
  curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"
# 기대: FB_USED 값이 축소 전 수준으로 복귀

# Pod 상태 확인
oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME}
# 기대: 1개 Pod, Running, 2/2 Ready

# GPU 할당 확인
oc describe node -l nvidia.com/gpu.present=true | grep -A5 "Allocated resources"
# 기대: nvidia.com/gpu 요청 1
~~~

## Scale-to-Zero 자동 복원 (llm-d 모델)

> llm-d 기반 모델(LLMInferenceService)은 Gateway EPP 메트릭을 사용하여 Scale-to-Zero → 자동 스케일 업이 가능하다. 단, 현재 제약이 있으며 워크어라운드가 필요하다.

### 구성: KEDA + EPP 메트릭

~~~bash
# llm-d 모델에 ScaledObject 생성 (Scale-to-Zero 허용)
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')

oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: ${LLM_D_MODEL}-autoscaler
spec:
  scaleTargetRef:
    name: ${LLM_D_MODEL}-kserve
  minReplicaCount: 0
  maxReplicaCount: 3
  cooldownPeriod: 300
  pollingInterval: 10
  triggers:
    - type: prometheus
      metadata:
        serverAddress: https://${THANOS_HOST}
        query: inference_pool_average_queue_size{name="${LLM_D_MODEL}-inference-pool"}
        threshold: "1"
        activationThreshold: "0.5"
        authModes: "bearer"
      authenticationRef:
        name: keda-prometheus-creds
EOF
~~~

### 동작 흐름

```
유휴 → KEDA 큐=0 감지 → cooldown 경과 → replica=0 (GPU 회수)
    → 요청 도착 → Gateway 503 → 클라이언트 재시도
    → EPP 큐 증가 → KEDA 감지 → replica=1 → 모델 로딩 → 서빙 재개
```

### 제약 및 워크어라운드

| 제약 | 원인 | 워크어라운드 |
|------|------|-------------|
| 모델 로딩 중 재축소 | KEDA가 큐=0 감지 시 cooldown 전에 축소 | `cooldownPeriod`를 모델 로딩 시간 이상으로 설정 (300초+) |
| 첫 요청 503 실패 | Pod=0이라 Gateway가 503 반환 | 클라이언트 재시도 로직 필수 (exponential backoff) |
| 요청 버퍼링 미지원 | 현재 Gateway가 요청을 드롭 | llm-d activator (Developer Preview)가 요청 버퍼링 예정 |

### 향후 개선 (Developer Preview)

- **llm-d activator**: 요청을 드롭하지 않고 버퍼링하면서 스케일업 대기. Cold Start 동안 클라이언트 재시도 불필요
- **Workload Variant Autoscaler (WVA)**: inference-specific 시그널(큐 깊이, KV캐시, 레이턴시 SLO) 기반 스케일링. Cold Start 동안 재축소 방지. prefill/decode 풀 독립 스케일링

## 실패 시

- **Pod 종료 후에도 VRAM 미해제** → 다른 프로세스가 GPU를 점유 중인지 확인. DCGM_FI_DEV_FB_USED가 감소하지 않으면 노드 재부팅 또는 GPU 리셋 필요.
- **Cold Start 타임아웃 (600초)** → Pod 이벤트 확인: `oc describe pod -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME}`. 모델 다운로드 실패(S3 연결) 또는 GPU 할당 실패가 원인일 수 있다.
- **API 서빙 미재개 (HTTP 200 외)** → vLLM 컨테이너 로그 확인: `oc logs -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME} -c kserve-container --tail=50`. 모델 로딩 완료까지 추가 대기 필요.
- **Cold Start 시간 과다** → 모델 크기에 비례(경량 135M ~61초, 8B ~수 분). H200의 HBM3e 대역폭으로 로딩 시간 단축 가능. 모델 이미지 캐싱(PVC 또는 S3 로컬 캐시)으로 추가 단축.
- **KEDA 자동 축소 미동작** → ScaledObject의 `cooldownPeriod`(기본 300초) 경과 여부 확인. PoC에서는 수동 `oc scale --replicas=0`으로 즉시 검증 가능.
- **Scale-to-Zero 후 자동 복원 안 됨** → (1) EPP 메트릭(`inference_pool_average_queue_size`)이 Pod 독립인지 확인 (2) `activationThreshold` 설정 확인 (3) 클라이언트 재시도 로직 확인 (4) llm-d WVA/activator(DP) 도입 검토

## 다음 단계

→ `runbooks/540-scale-to-zero-validation.md` — Scale-to-Zero 검증 (S5)

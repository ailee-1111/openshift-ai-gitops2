# 64 — Scale-to-Zero / Cold Start (S5)

## 목적

일정 시간 요청이 없는 서빙 Pod를 replica=0으로 축소하여 GPU 자원(VRAM, 연산)을 완전히 회수하고, 재요청 시 Pod가 자동 복원(Cold Start)되어 서빙을 재개하는 전체 사이클을 검증한다.

## 전제 조건

- [ ] `runbooks/63-recovery.md` 완료 — 장애복구 검증 통과
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
# replica 0으로 전환
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=0
sleep 15

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

# 복원 + 시간 측정
START=$(date +%s)
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
ISVC_URL=$(oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='{.status.url}')

for attempt in $(seq 1 30); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST "${ISVC_URL}/v1/chat/completions" \
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

## 실패 시

- **Pod 종료 후에도 VRAM 미해제** → 다른 프로세스가 GPU를 점유 중인지 확인. DCGM_FI_DEV_FB_USED가 감소하지 않으면 노드 재부팅 또는 GPU 리셋 필요.
- **Cold Start 타임아웃 (600초)** → Pod 이벤트 확인: `oc describe pod -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME}`. 모델 다운로드 실패(S3 연결) 또는 GPU 할당 실패가 원인일 수 있다.
- **API 서빙 미재개 (HTTP 200 외)** → vLLM 컨테이너 로그 확인: `oc logs -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME} -c kserve-container --tail=50`. 모델 로딩 완료까지 추가 대기 필요.
- **Cold Start 시간 과다** → 모델 크기에 비례(SmolLM2-135M ~85초, 70B+ 수 분). 모델 이미지 캐싱(PVC 또는 S3 로컬 캐시)으로 단축 가능. Knative Serving의 `minScale=0` + `initialScale=1` 활용 검토.
- **KEDA 자동 축소 미동작** → ScaledObject의 `cooldownPeriod`(기본 300초) 경과 여부 확인. PoC에서는 수동 `oc scale --replicas=0`으로 즉시 검증 가능.

## 다음 단계

→ `runbooks/74-scale-to-zero-validation.md` — Scale-to-Zero 검증 (S5)

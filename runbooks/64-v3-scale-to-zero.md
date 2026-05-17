# 64-v3 — S5 강화: 자동 복원 사이클

## 목적

v1의 단일 축소/복원을 전체 사이클(축소→요청→복원→추론→재축소)로 강화하고, 5회 반복으로 Cold Start 평균/분산을 측정한다. 8B 모델(qwen3-8b)의 Cold Start도 함께 측정한다.

## 전제 조건

- [ ] `runbooks/64-scale-to-zero.md` 완료 — 기본 Scale-to-Zero 정상
- [ ] ScaledObject READY=True
- [ ] DCGM Exporter Running
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. 5회 반복 Cold Start 측정 (135M)

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}')

echo "=== Cold Start 5회 반복 (${MODEL_NAME}) ==="
COLD_STARTS=()

for ROUND in $(seq 1 5); do
  echo "--- Round ${ROUND}/5 ---"

  oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
    autoscaling.keda.sh/paused-replicas="0" --overwrite 2>/dev/null || true
  oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=0
  sleep 15

  DCGM_POD=$(oc get pods -n nvidia-gpu-operator \
    -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}')
  VRAM=$(oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
    curl -s localhost:9400/metrics 2>/dev/null | grep "^DCGM_FI_DEV_FB_USED" | head -1 | awk '{print $2}')
  echo "  VRAM: ${VRAM} MiB"

  START=$(date +%s)
  oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
    autoscaling.keda.sh/paused-replicas- --overwrite 2>/dev/null || true
  oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=1
  oc wait pod -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
    --for=condition=Ready --timeout=600s 2>/dev/null

  for attempt in $(seq 1 30); do
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 15 \
      "https://${ROUTE}/v1/models" 2>/dev/null)
    if [ "${HTTP_CODE}" = "200" ]; then break; fi
    sleep 5
  done
  END=$(date +%s)
  ELAPSED=$((END - START))
  COLD_STARTS+=("${ELAPSED}")
  echo "  Cold Start: ${ELAPSED}초"
  sleep 10
done

echo ""
echo "=== 요약 ==="
SUM=0; MAX=0; MIN=9999
for T in "${COLD_STARTS[@]}"; do
  echo "  ${T}초"
  SUM=$((SUM + T))
  [ "$T" -gt "$MAX" ] && MAX=$T
  [ "$T" -lt "$MIN" ] && MIN=$T
done
echo "평균: $((SUM/5))초, 범위: $((MAX-MIN))초"
~~~

### 2. 8B 모델 Cold Start (qwen3-8b)

~~~bash
MODEL_8B="qwen3-8b"
ROUTE_8B=$(oc get route ${MODEL_8B}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "${ROUTE_8B}" ]; then
  echo "[SKIP] qwen3-8b Route 없음"
else
  oc scale deployment ${MODEL_8B}-predictor -n ${MODEL_NS} --replicas=0 2>/dev/null
  sleep 20
  START=$(date +%s)
  oc scale deployment ${MODEL_8B}-predictor -n ${MODEL_NS} --replicas=1
  oc wait pod -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_8B} \
    --for=condition=Ready --timeout=900s 2>/dev/null
  for attempt in $(seq 1 60); do
    HTTP=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 15 "https://${ROUTE_8B}/v1/models" 2>/dev/null)
    [ "${HTTP}" = "200" ] && break; sleep 10
  done
  END=$(date +%s)
  echo "8B Cold Start: $((END-START))초"
fi
~~~

### 3. 전체 사이클 (축소→요청→복원→추론→재축소)

~~~bash
echo "=== 전체 사이클 ==="

oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
  autoscaling.keda.sh/paused-replicas="0" --overwrite 2>/dev/null || true
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=0
sleep 15
echo "[1] 축소 완료"

HTTP=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://${ROUTE}/v1/models" 2>/dev/null)
echo "[2] 요청: HTTP ${HTTP}"

oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
  autoscaling.keda.sh/paused-replicas- --overwrite 2>/dev/null || true
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=1
oc wait pod -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --for=condition=Ready --timeout=600s
echo "[3] 복원 완료"

RESP=$(curl -sk "https://${ROUTE}/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'${MODEL_NAME}'","prompt":"Hello","max_tokens":10}' 2>/dev/null)
echo "[4] 추론: $(echo ${RESP} | python3 -c 'import sys,json; print(json.load(sys.stdin).get("choices",[{}])[0].get("text","FAIL")[:30])' 2>/dev/null)"

oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
  autoscaling.keda.sh/paused-replicas="0" --overwrite 2>/dev/null || true
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=0
sleep 15
echo "[5] 재축소 완료"

# 원복
oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS} \
  autoscaling.keda.sh/paused-replicas- --overwrite 2>/dev/null || true
oc scale deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} --replicas=1
oc wait pod -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --for=condition=Ready --timeout=600s
echo "원복 완료"
~~~

## 검증

~~~bash
# 1. 5회 평균 ≤ 120초 (135M)
# 2. 5회 범위 ≤ 30초 (일관성)
# 3. 8B Cold Start 기록
# 4. 전체 사이클 5단계 완료
# 5. VRAM 해제 확인
~~~

## 실패 시

- **편차 크다** → S3 다운로드 변동. PVC 캐시 권장
- **8B 타임아웃** → qwen3-8b vLLM 블로커
- **VRAM 미해제** → nvidia-smi 확인

## 다음 단계

→ `runbooks/65-v3-platform-ops.md` — S6 강화: 알림 E2E

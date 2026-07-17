#!/bin/bash
# 폴백 라우팅 실시간 모니터 — Open WebUI 데모 시 터미널에 띄워둠
# 사용: bash monitor-fallback.sh

NS="mobis-poc"
echo "============================================"
echo " 폴백 라우팅 모니터 (Ctrl+C 종료)"
echo "============================================"
echo ""
echo " qwen3-8b      = Primary (H200×1, 8B)"
echo " qwen35-122b   = Fallback (H200×2, 122B)"
echo "============================================"
echo ""

# 두 모델 vLLM의 throughput 로그를 실시간 모니터링
# 요청이 들어오면 "Avg generation throughput: X.X tokens/s" 수치가 0 이상
{
  oc logs -f -n ${NS} \
    -l "app.kubernetes.io/name=qwen3-8b,kserve.io/component=workload" \
    -c main --since=1s 2>/dev/null | while read line; do
    if echo "$line" | grep -q "generation throughput"; then
      TPUT=$(echo "$line" | grep -oP 'generation throughput: \K[0-9.]+')
      if [ "$(echo "$TPUT > 0" | bc 2>/dev/null)" = "1" ]; then
        echo "  $(date +%H:%M:%S) │ ✅ qwen3-8b       │ ${TPUT} tok/s"
      fi
    fi
    if echo "$line" | grep -q "Received request"; then
      echo "  $(date +%H:%M:%S) │ ✅ qwen3-8b       │ request received"
    fi
  done
} &
PID1=$!

{
  oc logs -f -n ${NS} \
    -l "app.kubernetes.io/name=redhataiqwen35-122b-a10b-fp8-d,kserve.io/component=workload" \
    -c main --since=1s 2>/dev/null | while read line; do
    if echo "$line" | grep -q "generation throughput"; then
      TPUT=$(echo "$line" | grep -oP 'generation throughput: \K[0-9.]+')
      if [ "$(echo "$TPUT > 0" | bc 2>/dev/null)" = "1" ]; then
        echo "  $(date +%H:%M:%S) │ 🔄 qwen35-122b    │ ${TPUT} tok/s"
      fi
    fi
    if echo "$line" | grep -qE "Received request|request_id"; then
      echo "  $(date +%H:%M:%S) │ 🔄 qwen35-122b    │ request received"
    fi
  done
} &
PID2=$!

trap "kill $PID1 $PID2 2>/dev/null; exit" INT TERM
wait

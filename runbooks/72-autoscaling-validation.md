# 72 — 오토스케일링 검증 (S3: Auto-scaling)

## 목적

CMA/KEDA 기반 수평 오토스케일링이 vLLM 메트릭(활성+대기 요청 수)에 반응하여 replica를 증감시키는지, GPU 메트릭 수집 파이프라인이 동작하는지 검증한다. 고객 요구사항(No.21,22,25) 대응.

## 전제 조건

- [ ] `runbooks/62-autoscaling.md` 구축 완료 (ScaledObject + TriggerAuthentication 정상)
- [ ] `${MODEL_NAME}`, `${MODEL_NS}` 환경변수 설정
- [ ] GPU 2개 이상 또는 조건부 PASS 기준 합의

## 실행

### V-21. 수평 오토스케일링 HPA (No.21)

~~~bash
echo "=== V-21: HPA 스케일업 테스트 ==="

BEFORE=$(oc get deployment "${MODEL_NAME}-predictor" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.replicas}')
echo "스케일업 전 replicas: ${BEFORE}"

# 부하 생성 (동시 요청 5개)
echo ">> 부하 생성 시작 (30초)"
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)
for i in $(seq 1 5); do
  curl -sk "https://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"Write a long story about AI:\",\"max_tokens\":200}" &
done

sleep 30
echo ">> HPA 상태"
oc get hpa -n "${MODEL_NS}" | grep keda
AFTER=$(oc get deployment "${MODEL_NAME}-predictor" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.replicas}')
echo "스케일업 후 replicas: ${AFTER}"

oc get hpa keda-hpa-vllm-autoscaler -n "${MODEL_NS}" \
  -o jsonpath='desired={.status.desiredReplicas}, current={.status.currentReplicas}'
echo ""

wait
# 기대: replicas 증가 (GPU 부족 시 desiredReplicas만 증가해도 조건부 PASS)
# 결과: [   ] PASS / [   ] CONDITIONAL PASS / [   ] FAIL
~~~

### V-21b. 스케일다운 (쿨다운 검증)

~~~bash
echo "=== V-21b: 쿨다운 후 스케일다운 ==="
echo ">> 쿨다운 대기 (60초)"
sleep 60

for i in $(seq 1 4); do
  echo "--- $(date '+%H:%M:%S') ---"
  oc get hpa keda-hpa-vllm-autoscaler -n "${MODEL_NS}" \
    -o jsonpath='desired={.status.desiredReplicas}, current={.status.currentReplicas}'
  echo ""
  sleep 30
done
# 기대: 부하 해소 후 replicas가 minReplicaCount(1)로 복귀
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-22. GPU 기반 스케일링 메트릭 (No.22)

~~~bash
echo "=== V-22: GPU 메트릭 수집 확인 ==="
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring \
  -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

echo ">> DCGM GPU 사용률"
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
print(f'GPU 메트릭 수: {len(results)}')
for r in results:
    gpu = r['metric'].get('gpu', '?')
    val = r['value'][1]
    print(f'  GPU {gpu}: {val}%')
"

echo ">> vLLM 메트릭 (활성+대기 요청)"
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=sum(vllm:num_requests_running{namespace=\"${MODEL_NS}\"})" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
val = results[0]['value'][1] if results else 'N/A'
print(f'활성 요청 수: {val}')
"
# 기대: 메트릭 수집 정상
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-25. 스케일링 정책 커스터마이징 (No.25)

~~~bash
echo "=== V-25: 스케일링 정책 확인 ==="
oc get scaledobject vllm-autoscaler -n "${MODEL_NS}" \
  -o jsonpath='{.spec}' | python3 -c "
import sys, json
spec = json.load(sys.stdin)
print(f\"minReplicaCount: {spec.get('minReplicaCount')}\")
print(f\"maxReplicaCount: {spec.get('maxReplicaCount')}\")
print(f\"cooldownPeriod: {spec.get('cooldownPeriod')}s\")
print(f\"pollingInterval: {spec.get('pollingInterval')}s\")
for t in spec.get('triggers', []):
    print(f\"trigger: type={t.get('type')}, threshold={t['metadata'].get('threshold')}\")
"
# 기대: 사용자 정의 가능한 정책 표시
# 결과: [   ] PASS / [   ] FAIL
~~~

## 검증

~~~bash
echo "=== S3 검증 요약 ==="
echo "V-21  수평 오토스케일링 (HPA):    [   ] PASS / [   ] CONDITIONAL / [   ] FAIL"
echo "V-21b 쿨다운 스케일다운:          [   ] PASS / [   ] FAIL"
echo "V-22  GPU 기반 스케일링 메트릭:   [   ] PASS / [   ] FAIL"
echo "V-25  스케일링 정책 커스터마이징: [   ] PASS / [   ] FAIL"
echo ""
echo "실측값:"
echo "  스케일업 전 replicas: ___"
echo "  스케일업 후 replicas: ___ (desired: ___)"
echo "  쿨다운 후 복귀 시간: ___초"
~~~

## 실패 시

- **ScaledObject Ready=False** → TriggerAuthentication SA 토큰 확인. `oc describe scaledobject vllm-autoscaler -n ${MODEL_NS}` 이벤트 조회.
- **스케일업 미발생** → GPU 부족은 정상(조건부 PASS). HPA `desiredReplicas` 증가 확인으로 메트릭 폴링 동작 검증.
- **DCGM 메트릭 미수집** → NVIDIA GPU Operator/DCGM Exporter Pod 상태 확인. `oc get pods -n nvidia-gpu-operator`.
- **vLLM 메트릭 미수집** → UWM(User Workload Monitoring) 활성화 여부 확인. ServiceMonitor/PodMonitor 존재 확인.
- **쿨다운 후 스케일다운 미발생** → cooldownPeriod 값 확인. 기본 60초이며 부하 완전 해소 후 대기 필요.

## v3 강화 검증 (62-v3-autoscaling.md 연동)

### V-S3-v3-1. GPU KEDA 트리거 (Queue + VRAM)

~~~bash
oc get scaledobject vllm-autoscaler -n ${MODEL_NS} -o jsonpath='{.spec.triggers}' | python3 -c "
import sys,json
for t in json.load(sys.stdin):
    q=t.get('metadata',{}).get('query','')
    print(f'  {\"VRAM\" if \"DCGM\" in q else \"Queue\"}: threshold={t[\"metadata\"][\"threshold\"]}')
"
# 기대: 2개 트리거  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S3-v3-2. 스케일업 이벤트 + 1→3→1 사이클

~~~bash
oc describe hpa keda-hpa-vllm-autoscaler -n ${MODEL_NS} | grep SuccessfulRescale
# 기대: 이벤트 존재  |  결과: [   ] PASS / [   ] FAIL
# 실측: ___→___→___replicas
~~~

## 다음 단계

→ `runbooks/73-recovery-validation.md` — 장애복구 검증

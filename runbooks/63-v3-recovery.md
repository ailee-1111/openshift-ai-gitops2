# 63-v3 — S4 강화: Chaos Engineering

## 목적

v1의 단건 Pod 삭제/drain을 연속 장애 주입으로 강화한다. Pod 연속 삭제 3회 복구 시간 일관성, drain+uncordon+재배치 사이클, NetworkPolicy 격리 검증을 수행한다.

## 전제 조건

- [ ] `runbooks/63-recovery.md` 완료 — 기본 장애복구 정상
- [ ] InferenceService Ready=True
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. Pod 연속 삭제 3회 + 복구 시간 일관성

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}')

echo "=== Pod 연속 삭제 3회 ==="
RECOVERY_TIMES=()

for ROUND in 1 2 3; do
  echo "--- Round ${ROUND}/3 ---"
  VLLM_POD=$(oc get pods -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}')

  START=$(date +%s)
  oc delete pod ${VLLM_POD} -n ${MODEL_NS} --grace-period=0 --force 2>/dev/null
  oc wait pod -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
    --for=condition=Ready --timeout=300s 2>/dev/null
  END=$(date +%s)
  ELAPSED=$((END - START))
  RECOVERY_TIMES+=("${ELAPSED}")
  echo "  복구: ${ELAPSED}초"

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${ROUTE}/v1/models")
  echo "  API: HTTP ${HTTP_CODE}"
  sleep 10
done

echo ""
echo "=== 요약 ==="
SUM=0; MAX=0; MIN=9999
for T in "${RECOVERY_TIMES[@]}"; do
  echo "  ${T}초"
  SUM=$((SUM + T))
  [ "$T" -gt "$MAX" ] && MAX=$T
  [ "$T" -lt "$MIN" ] && MIN=$T
done
echo "평균: $((SUM/3))초, 범위: $((MAX-MIN))초"
[ "$((MAX-MIN))" -le 30 ] && echo "PASS" || echo "WARN: 편차 크다"
~~~

### 2. drain + uncordon + 재배치

~~~bash
POD_NODE=$(oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].spec.nodeName}')

GPU_COUNT=$(oc get nodes -l nvidia.com/gpu.present=true -o name | wc -l | tr -d ' ')
if [ "${GPU_COUNT}" -lt 2 ]; then
  echo "[SKIP] GPU 노드 1개 — drain 재배치 불가 (메커니즘만 검증)"
else
  START=$(date +%s)
  oc adm cordon ${POD_NODE}
  oc adm drain ${POD_NODE} --ignore-daemonsets --delete-emptydir-data --timeout=120s
  oc wait pod -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
    --for=condition=Ready --timeout=600s
  END=$(date +%s)

  NEW_NODE=$(oc get pods -n ${MODEL_NS} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].spec.nodeName}')
  echo "재배치: ${POD_NODE} → ${NEW_NODE} (${$((END-START))}초)"
  oc adm uncordon ${POD_NODE}
fi
~~~

### 3. NetworkPolicy 격리 검증

~~~bash
echo "=== NetworkPolicy 격리 ==="

# 외부 NS → 차단
echo "[1] default → ${MODEL_NS}:"
oc run np-test --rm -it --restart=Never -n default \
  --image=curlimages/curl -- \
  curl -s --max-time 5 \
  "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/models" 2>/dev/null
[ $? -ne 0 ] && echo "  PASS: 차단" || echo "  FAIL: 허용됨"

# 내부 → 허용
echo "[2] ${MODEL_NS} 내부:"
oc run np-test --rm -it --restart=Never -n ${MODEL_NS} \
  --image=curlimages/curl -- \
  curl -s --max-time 10 \
  "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/models" 2>/dev/null
[ $? -eq 0 ] && echo "  PASS: 허용" || echo "  FAIL: 차단됨"

# 모니터링 → 허용
echo "[3] openshift-monitoring → ${MODEL_NS}:"
oc run np-test --rm -it --restart=Never -n openshift-monitoring \
  --image=curlimages/curl -- \
  curl -s --max-time 10 \
  "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/models" 2>/dev/null
[ $? -eq 0 ] && echo "  PASS: 허용" || echo "  WARN: 차단됨"
~~~

## 검증

~~~bash
# 1. 3회 복구 편차 ≤ 30초 → Step 1 결과
# 2. drain 재배치 → Step 2 결과
# 3. NetworkPolicy → Step 3 결과
# 4. InferenceService Ready
oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'
echo ""
~~~

## 실패 시

- **연속 삭제 시 ImagePullBackOff** → 이미지 캐시 누락. 초기 pull 지연
- **drain 후 Pending** → GPU 노드 부족. `oc get nodes` 확인
- **NetworkPolicy 테스트 Pod 생성 실패** → SCC 권한 확인

## 다음 단계

→ `runbooks/64-v3-scale-to-zero.md` — S5 강화: 자동 복원 사이클

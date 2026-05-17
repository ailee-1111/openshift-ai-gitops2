# 73 — 장애복구 검증 (S4: 장애 복구)

## 목적

서빙 Pod 장애 시 자동 복구, 다중 레플리카 배포, RollingUpdate 무중단 교체, 모델 버전 롤백이 정상 동작하는지 검증한다. 고객 요구사항(No.26,27,28,29) 대응.

## 전제 조건

- [ ] `runbooks/63-recovery.md` 구축 완료 (InferenceService replica 1+)
- [ ] `${MODEL_NAME}`, `${MODEL_NS}` 환경변수 설정
- [ ] InferenceService Ready=True

## 실행

### V-26. 모델 레플리카 다중 배포 (No.26)

~~~bash
echo "=== V-26: 다중 레플리카 확인 ==="
oc get inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" \
  -o jsonpath='minReplicas={.spec.predictor.minReplicas}, maxReplicas={.spec.predictor.maxReplicas}'
echo ""

oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" --no-headers
REPLICA_COUNT=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" --no-headers | wc -l | tr -d ' ')
echo "현재 Running Pod 수: ${REPLICA_COUNT}"
# 기대: replica >= 1 (GPU 여유 시 2+)
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-27. 헬스체크 및 자동 복구 (No.27)

~~~bash
echo "=== V-27: Pod 삭제 후 자동 복구 ==="
VLLM_POD=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  -o jsonpath='{.items[0].metadata.name}')
echo "삭제 대상: ${VLLM_POD}"

START=$(date +%s)
oc delete pod "${VLLM_POD}" -n "${MODEL_NS}"

oc wait pod -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  --for=condition=Ready --timeout=300s
END=$(date +%s)
RECOVERY_TIME=$((END - START))
echo "Pod 복구 소요: ${RECOVERY_TIME}초"

# 복구 후 서빙 정상 확인
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
  "https://${ROUTE}/v1/models")
echo "복구 후 /v1/models: HTTP ${HTTP_CODE}"
# 기대: 300초 이내 복구, HTTP 200
# 결과: [   ] PASS / [   ] FAIL
# 실측값: 복구 시간 ___초
~~~

### V-28. 노드 장애 시 페일오버 (No.28)

~~~bash
echo "=== V-28: 노드 장애 시나리오 ==="

# GPU 노드 수 확인 — 싱글 GPU 노드면 교차 노드 페일오버 불가
GPU_NODES=$(oc get nodes -o jsonpath='{range .items[*]}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}' | grep -c '[1-9]')
echo "GPU 노드 수: ${GPU_NODES}"

if [ "${GPU_NODES}" -le 1 ]; then
  echo "[SKIP] 싱글 GPU 노드 환경 — 교차 노드 페일오버 불가"
  echo "  K8s ReplicaSet 복구 메커니즘은 V-27에서 검증 완료"
  echo "  멀티 GPU 노드(HGX 등) 환경에서 재테스트 필요"
  echo "# 결과: [   ] CONDITIONAL PASS (싱글 GPU 노드)"
else
  VLLM_POD=$(oc get pods -n "${MODEL_NS}" \
    -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')
  CURRENT_NODE=$(oc get pod "${VLLM_POD}" -n "${MODEL_NS}" \
    -o jsonpath='{.spec.nodeName}')
  echo "현재 노드: ${CURRENT_NODE}"

  oc delete pod "${VLLM_POD}" -n "${MODEL_NS}"
  oc wait pod -n "${MODEL_NS}" \
    -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
    --for=condition=Ready --timeout=300s

  NEW_POD=$(oc get pods -n "${MODEL_NS}" \
    -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')
  NEW_NODE=$(oc get pod "${NEW_POD}" -n "${MODEL_NS}" \
    -o jsonpath='{.spec.nodeName}')
  echo "새 Pod: ${NEW_POD}, 노드: ${NEW_NODE}"
  # 기대: Pod가 다른 노드에 재스케줄링
  # 결과: [   ] PASS / [   ] FAIL
fi
~~~

### V-29. 무중단 모델 교체 (No.29)

~~~bash
echo "=== V-29: RollingUpdate 무중단 교체 ==="
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)

# 연속 요청 발생 (60초간, 1초 간격)
echo ">> 60초간 연속 요청 (다운타임 측정)"
FAIL_COUNT=0
TOTAL=0
for i in $(seq 1 60); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 \
    "https://${ROUTE}/v1/models" 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  if [ "${CODE}" != "200" ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$(date '+%H:%M:%S') HTTP ${CODE} ← FAIL"
  fi
  sleep 1
done &
REQ_PID=$!

# 5초 후 RollingUpdate 트리거
sleep 5
echo ">> RollingUpdate 트리거"
oc patch deployment "${MODEL_NAME}-predictor" -n "${MODEL_NS}" \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"rollout-trigger\":\"$(date +%s)\"}}}}}"

wait $REQ_PID
echo ""
echo "총 요청: ${TOTAL}, 실패: ${FAIL_COUNT}"
# 기대: 실패율 < 10% (replica 2+에서는 0%)
# 결과: [   ] PASS / [   ] FAIL
# 실측값: 실패 ___건 / ___건
~~~

## 검증

~~~bash
echo "=== S4 검증 요약 ==="
echo "V-26  다중 레플리카 배포:    [   ] PASS / [   ] FAIL"
echo "V-27  헬스체크 및 자동 복구: [   ] PASS / [   ] FAIL"
echo "V-28  노드 장애 페일오버:    [   ] PASS / [   ] FAIL"
echo "V-29  무중단 모델 교체:      [   ] PASS / [   ] FAIL"
echo ""
echo "실측값:"
echo "  Pod 복구 시간: ___초"
echo "  RollingUpdate 실패 건수: ___건 / ___건"
~~~

## 실패 시

- **Pod 복구 타임아웃 (300초)** → GPU 할당 대기. `oc describe pod <new-pod> -n ${MODEL_NS}`에서 `Insufficient nvidia.com/gpu` 이벤트 확인.
- **RollingUpdate 중 다운타임 높음** → replica 1개에서는 불가피. replica 2+에서 재테스트 권장.
- **Pod 재스케줄링 실패** → 노드 affinity/taint 확인. `oc get nodes -l nvidia.com/gpu.present=true`.
- **모델 로딩 시간 긺** → 모델 크기에 비례. SmolLM2-135M은 30~60초. `--max-model-len` 조정 고려.

## v3 강화 검증 (63-v3-recovery.md 연동)

### V-S4-v3-1. 연속 삭제 3회 복구 일관성

~~~bash
# 기대: 편차 ≤ 30초  |  결과: [   ] PASS / [   ] FAIL
# 실측: ___초, ___초, ___초
~~~

### V-S4-v3-2. drain+uncordon 재배치

~~~bash
# 기대: 다른 노드 재배치 또는 SKIP  |  결과: [   ] PASS / [   ] SKIP
~~~

### V-S4-v3-3. NetworkPolicy 격리

~~~bash
# 외부→차단, 내부→허용, 모니터링→허용  |  결과: [   ] PASS / [   ] FAIL
~~~

## 다음 단계

→ `runbooks/74-scale-to-zero-validation.md` — Scale-to-Zero 검증

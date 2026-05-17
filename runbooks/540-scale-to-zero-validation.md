# 540 — Scale-to-Zero 검증 (S5: Scale-to-Zero)

## 목적

유휴 상태의 서빙 Pod를 replica=0으로 축소하여 GPU 자원을 완전히 회수하고, 재요청 시 Cold Start로 자동 복원되는 전체 사이클을 검증한다. 고객 요구사항(No.23,24) 대응.

## 전제 조건

- [ ] `runbooks/340-scale-to-zero.md` 구축 완료
- [ ] `${MODEL_NAME}`, `${MODEL_NS}` 환경변수 설정
- [ ] InferenceService Ready=True

## 실행

### V-23. 스케일 투 제로 (No.23)

~~~bash
echo "=== V-23: Scale-to-Zero ==="

echo ">> 축소 전 상태"
oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" --no-headers
BEFORE_COUNT=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" --no-headers | wc -l | tr -d ' ')
echo "현재 Pod 수: ${BEFORE_COUNT}"

# replica=0으로 축소
echo ">> replicas=0 패치"
oc patch inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" --type=merge \
  -p '{"spec":{"predictor":{"minReplicas":0,"maxReplicas":0}}}'

sleep 15
AFTER_COUNT=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "축소 후 Pod 수: ${AFTER_COUNT}"
# 기대: Pod 0개

# GPU 자원 회수 확인
echo ">> GPU VRAM 확인"
DCGM_POD=$(oc get pods -n nvidia-gpu-operator \
  -l app=nvidia-dcgm-exporter \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "${DCGM_POD}" ]; then
  oc exec -n nvidia-gpu-operator "${DCGM_POD}" -- \
    curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"
else
  echo "DCGM Exporter 미설치 — SKIP"
fi
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-24. 콜드스타트 최적화 (No.24)

~~~bash
echo "=== V-24: Cold Start 측정 ==="

echo ">> replicas=1 패치 (Cold Start 시작)"
START=$(date +%s)
oc patch inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" --type=merge \
  -p '{"spec":{"predictor":{"minReplicas":1,"maxReplicas":1}}}'

oc wait pod -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  --for=condition=Ready --timeout=600s
END=$(date +%s)
COLD_START=$((END - START))
echo "Cold Start 소요: ${COLD_START}초"

# 서빙 정상 확인
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 \
  "https://${ROUTE}/v1/models")
echo "복구 후 /v1/models: HTTP ${HTTP_CODE}"

# 첫 추론 응답 시간
START_INFER=$(date +%s)
curl -sk "https://${ROUTE}/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"Hello\",\"max_tokens\":10}" \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(f\"choices: {len(r.get('choices', []))}\")
"
END_INFER=$(date +%s)
echo "첫 추론 응답: $((END_INFER - START_INFER))초"
# 기대: Cold Start < 120초 (SmolLM2-135M 기준)
# 결과: [   ] PASS / [   ] FAIL
# 실측값: Cold Start ___초, 첫 추론 ___초
~~~

### V-24b. 반복 사이클 검증

~~~bash
echo "=== V-24b: 2차 Scale-to-Zero → Cold Start ==="
oc patch inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" --type=merge \
  -p '{"spec":{"predictor":{"minReplicas":0,"maxReplicas":0}}}'
sleep 15

START2=$(date +%s)
oc patch inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" --type=merge \
  -p '{"spec":{"predictor":{"minReplicas":1,"maxReplicas":1}}}'
oc wait pod -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  --for=condition=Ready --timeout=600s
END2=$(date +%s)
echo "2차 Cold Start: $((END2 - START2))초"
# 기대: 1차와 유사한 시간 (안정성 확인)
# 결과: [   ] PASS / [   ] FAIL
~~~

## 검증

~~~bash
echo "=== S5 검증 요약 ==="
echo "V-23  스케일 투 제로:      [   ] PASS / [   ] FAIL"
echo "V-24  콜드스타트 최적화:   [   ] PASS / [   ] FAIL"
echo "V-24b 반복 사이클:         [   ] PASS / [   ] FAIL"
echo ""
echo "실측값:"
echo "  축소 후 Pod 수: ___"
echo "  1차 Cold Start: ___초"
echo "  2차 Cold Start: ___초"
echo "  첫 추론 응답: ___초"
~~~

## 실패 시

- **축소 후 Pod 미삭제** → KServe가 minReplicas를 override할 수 있음. `oc get deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} -o jsonpath='{.spec.replicas}'` 확인.
- **Cold Start 600초 타임아웃** → 모델 로딩 시간 확인. `oc logs -l serving.kserve.io/inferenceservice=${MODEL_NAME} -n ${MODEL_NS} -f`. S3 연결 속도가 병목일 수 있음.
- **VRAM 미회수** → Pod 삭제 후 GPU 프로세스 잔류 가능. nvidia-smi 확인.
- **2차 사이클 시간 급증** → PVC 재바인딩이나 이미지 풀 캐시 만료 가능성.

## v3 강화 검증 (64-v3-scale-to-zero.md 연동)

### V-S5-v3-1. 5회 반복 Cold Start

~~~bash
# 기대: 평균 ≤ 120초, 범위 ≤ 30초  |  결과: [   ] PASS / [   ] FAIL
# 실측: ___초 × 5회
~~~

### V-S5-v3-2. 전체 사이클 (축소→요청→복원→추론→재축소)

~~~bash
# 기대: 5단계 완료  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S5-v3-3. 8B Cold Start

~~~bash
# 블로커 시 SKIP  |  결과: [   ] PASS / [   ] SKIP  |  실측: ___초
~~~

## 다음 단계

→ `runbooks/550-platform-ops-validation.md` — 플랫폼 운영 검증

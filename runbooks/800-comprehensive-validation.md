# 800 — 종합 검증

## 목적

S1~S6 시나리오별 검증 결과를 취합하고, 시나리오 횡단 테스트(동시 부하, E2E 흐름)를 수행한 뒤, `reports/{customer}/` 산출물을 생성한다.

## 전제 조건

- [ ] `runbooks/70~75` 시나리오별 검증 완료
- [ ] `${MODEL_NAME}`, `${MODEL_NS}` 환경변수 설정
- [ ] 모든 InferenceService Ready=True

## 실행

### 80-1. 시나리오별 결과 취합

~~~bash
echo "=== 80-1: 시나리오별 결과 취합 ==="
echo ""
echo "S1 모델 관리 (runbooks/70):"
echo "  V-4  모델 등록:          [   ]"
echo "  V-5  모델 업로드:        [   ]"
echo "  V-6  버전 관리:          [   ]"
echo "  V-8  원클릭 배포/철수:   [   ]"
echo "  V-9  메타데이터 관리:    [   ]"
echo "  V-13 아티팩트 저장:      [   ]"
echo ""
echo "S2 Pipeline (runbooks/71):"
echo "  V-1  vLLM 지원:          [   ]"
echo "  V-3  엔진 버전 관리:     [   ]"
echo "  V-10 배포 자동화:        [   ]"
echo "  V-11 등록 프로세스:      [   ]"
echo "  V-12 승인 프로세스:      [   ]"
echo "  V-43 OpenAI 호환 API:    [   ]"
echo ""
echo "S3 Auto-scaling (runbooks/72):"
echo "  V-21 HPA 스케일업:       [   ]"
echo "  V-22 GPU 메트릭:         [   ]"
echo "  V-25 정책 커스터마이징:  [   ]"
echo ""
echo "S4 장애복구 (runbooks/73):"
echo "  V-26 다중 레플리카:      [   ]"
echo "  V-27 자동 복구:          [   ]"
echo "  V-28 노드 페일오버:      [   ]"
echo "  V-29 무중단 교체:        [   ]"
echo ""
echo "S5 Scale-to-Zero (runbooks/74):"
echo "  V-23 스케일 투 제로:     [   ]"
echo "  V-24 콜드스타트:         [   ]"
echo ""
echo "S6 운영관리 (runbooks/75):"
echo "  V-44~47 RBAC/SSO:        [   ]"
echo "  V-48~51 GPU 모니터링:    [   ]"
echo "  V-52~57 서빙 성능:       [   ]"
echo "  V-59~68 관찰성/알림:     [   ]"
echo "  V-16,73 기타:            [   ]"
echo ""
echo "=== v3 강화 + 신규 시나리오 ==="
echo ""
echo "S1-v3 멀티모델:  V-S1-v3-1~3 [   ]"
echo "S2-v3 7단계PL:   V-S2-v3-1~4 [   ]"
echo "S3-v3 GPU KEDA:  V-S3-v3-1~2 [   ]"
echo "S4-v3 Chaos:     V-S4-v3-1~3 [   ]"
echo "S5-v3 5회CS:     V-S5-v3-1~3 [   ]"
echo "S6-v3 알림E2E:   V-S6-v3-1~4 [   ]"
echo "S7 MaaS:         V-S7-1~3    [   ]"
echo "S8 멀티테넌트:   V-S8-1~3    [   ]"
echo "S9 보안게이트:   V-S9-1~4    [   ]"
echo "S10 MLOps:       V-S10-1~4   [   ]"
~~~

### 80-2. 시나리오 횡단 테스트

~~~bash
echo "=== 80-2: E2E 횡단 테스트 ==="
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)

# 서빙 → 동시 부하 → 확인
echo ">> 횡단 1: 서빙 정상 → 동시 부하"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' \
  "https://${ROUTE}/v1/models")
echo "서빙 상태: HTTP ${HTTP_CODE}"

for i in $(seq 1 3); do
  curl -sk "https://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"test ${i}\",\"max_tokens\":50}" &
done
wait
echo "동시 요청 완료"

# 장애복구 후 서빙 연속성
echo ">> 횡단 2: Pod 삭제 → 복구 → 서빙 확인"
VLLM_POD=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  -o jsonpath='{.items[0].metadata.name}')
oc delete pod "${VLLM_POD}" -n "${MODEL_NS}"
oc wait pod -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  --for=condition=Ready --timeout=300s
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
  "https://${ROUTE}/v1/models")
echo "복구 후 서빙: HTTP ${HTTP_CODE}"
# 결과: [   ] PASS / [   ] FAIL
~~~

### 80-3. 플랫폼 상태 스냅샷

~~~bash
echo "=== 80-3: 플랫폼 상태 스냅샷 ==="

echo ">> Operator 상태"
oc get csv -A --no-headers \
  | grep -E "rhods|kserve|pipeline|servicemesh|jobset|lws" \
  | awk '{printf "  %-50s %s\n", $2, $NF}'

echo ""
echo ">> DataScienceCluster"
oc get datasciencecluster \
  -o jsonpath='{range .items[*]}{.metadata.name}: Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

echo ""
echo ">> ArgoCD Applications"
oc get application -n openshift-gitops --no-headers 2>/dev/null \
  | awk '{printf "  %-30s %s %s\n", $1, $3, $4}'

echo ""
echo ">> InferenceService"
oc get inferenceservice -A --no-headers \
  | awk '{printf "  %-30s %s\n", $2, $NF}'

echo ""
echo ">> 노드 GPU 할당"
oc get nodes -l nvidia.com/gpu.present=true \
  -o jsonpath='{range .items[*]}{.metadata.name}: allocatable={.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null \
  || echo "  GPU 노드 없음"
~~~

## 검증

~~~bash
echo "=== 종합 검증 요약 ==="
echo ""
echo "시나리오별 PASS 비율:"
echo "  S1 모델 관리:      ___/6"
echo "  S2 Pipeline:       ___/6"
echo "  S3 Auto-scaling:   ___/3"
echo "  S4 장애복구:       ___/4"
echo "  S5 Scale-to-Zero:  ___/2"
echo "  S6 운영관리:       ___/17"
echo "  ---------------------"
echo "  합계:              ___/38 Core"
echo ""
echo "횡단 테스트:         [   ] PASS / [   ] FAIL"
echo "플랫폼 상태:         [   ] 정상 / [   ] 이상"
~~~

## 실패 시

- **횡단 테스트 실패** → 개별 시나리오 런북(70~75)으로 돌아가 실패 항목 재확인.
- **플랫폼 상태 이상** → `oc get csv -A | grep -v Succeeded`로 실패 Operator 확인.
- **PASS 비율 미달** → 고객과 SKIP/CONDITIONAL 항목 협의. reports/ 산출물에 사유 기록.

## 다음 단계

→ `reports/{customer}/` — 검증 결과 리포팅
→ `runbooks/900-teardown.md` — 환경 정리 (필요 시)

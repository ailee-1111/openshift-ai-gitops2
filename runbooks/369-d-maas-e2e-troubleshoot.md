# 369-d — Sprint 13: MaaS 종합 E2E 검증 및 트러블슈팅

## 목적

Sprint 1~12의 전체 MaaS 파이프라인을 E2E로 통합 검증하고, 운영 중 발생할 수 있는 주요 장애 시나리오에 대한 트러블슈팅 가이드를 제공한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.13 (Administration troubleshooting), §2.3 (User access troubleshooting)

## 전제 조건

- [ ] Sprint 1~9 완료 (필수)
- [ ] Sprint 10~12 완료 (해당 기능 사용 시)
- [ ] 환경변수: `CLUSTER_DOMAIN`, `MODEL_NS`, `MODEL_NAME`, `MAAS_API_KEY`

## 실행

### 1. 인프라 상태 종합 점검

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
: "${MODEL_NS:=llm}"
: "${MODEL_NAME:=granite-2b}"

echo "========================================="
echo "  MaaS 종합 E2E 검증 — $(date '+%Y-%m-%d %H:%M')"
echo "========================================="
echo ""

echo "[1/10] OCP 버전"
oc get clusterversion version -o jsonpath='  {.status.desired.version}'
echo ""

echo "[2/10] RHOAI Operator"
oc get csv -n redhat-ods-operator --no-headers | grep rhods | awk '{print "  "$1" "$NF}'

echo "[3/10] Kuadrant"
KUADRANT_READY=$(oc get kuadrant kuadrant -n kuadrant-system \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
echo "  Ready: ${KUADRANT_READY}"

echo "[4/10] Gateway"
oc get gateway maas-default-gateway -n openshift-ingress --no-headers 2>/dev/null || echo "  [FAIL] Gateway 없음"

echo "[5/10] Tenant"
oc get tenant default-tenant -n models-as-a-service \
  -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status --no-headers 2>/dev/null

echo "[6/10] MaaS CRDs"
oc get crd | grep -c maas.opendatahub.io | xargs -I{} echo "  {} CRDs"

echo "[7/10] LLMInferenceService"
oc get llminferenceservice -n "${MODEL_NS}" --no-headers 2>/dev/null

echo "[8/10] Subscriptions"
oc get maassubscription -n models-as-a-service --no-headers 2>/dev/null

echo "[9/10] AuthPolicies"
oc get maasauthpolicy -n models-as-a-service --no-headers 2>/dev/null

echo "[10/10] maas-api Pod"
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --no-headers 2>/dev/null
echo ""
~~~

### 2. E2E 추론 플로우 검증

~~~bash
echo "=== E2E 추론 검증 ==="
echo ""

echo "[Step 1] 모델 목록 조회"
MODELS=$(curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" 2>/dev/null)
MODEL_COUNT=$(echo "${MODELS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
echo "  사용 가능 모델: ${MODEL_COUNT:-0}개"

echo ""
echo "[Step 2] Chat Completion"
RESPONSE=$(curl -sSk -w "\n%{http_code}" --max-time 60 \
  -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"ibm-granite/granite-3.1-2b-instruct","messages":[{"role":"user","content":"What is Red Hat OpenShift AI?"}],"max_tokens":100}')
HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
BODY=$(echo "${RESPONSE}" | head -n -1)
echo "  HTTP: ${HTTP_CODE}"
if [[ "${HTTP_CODE}" == "200" ]]; then
  echo "  [PASS] 추론 성공"
  echo "${BODY}" | python3 -c "import sys,json; r=json.load(sys.stdin); c=r.get('choices',[{}])[0]; print(f'  토큰: {r.get(\"usage\",{}).get(\"total_tokens\",\"?\")}')" 2>/dev/null
else
  echo "  [FAIL] 추론 실패"
fi

echo ""
echo "[Step 3] 인증 없는 요청 (401 예상)"
CODE_NO_AUTH=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"test"}],"max_tokens":1}')
echo "  인증 없음: HTTP ${CODE_NO_AUTH} (401 예상)"

echo ""
echo "[Step 4] 잘못된 API Key (401 예상)"
CODE_BAD_KEY=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
  -H "Authorization: Bearer invalid-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"test"}],"max_tokens":1}')
echo "  잘못된 키: HTTP ${CODE_BAD_KEY} (401 예상)"

echo ""
echo "[Step 5] 미등록 모델 (404 예상)"
CODE_NO_MODEL=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/llm/nonexistent-model/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"nonexistent","messages":[{"role":"user","content":"test"}],"max_tokens":1}')
echo "  미등록 모델: HTTP ${CODE_NO_MODEL} (404 예상)"
~~~

### 3. Rate Limit 검증

~~~bash
echo ""
echo "=== Rate Limit 검증 (dev-subscription 키 사용 시) ==="
echo "  dev-subscription 토큰 제한 확인:"
oc get maassubscription dev-subscription -n models-as-a-service \
  -o jsonpath='{.spec.models[0].tokenLimits}' 2>/dev/null | python3 -m json.tool 2>/dev/null
echo ""
echo "  prod-subscription 토큰 제한 확인:"
oc get maassubscription prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.models[0].tokenLimits}' 2>/dev/null | python3 -m json.tool 2>/dev/null
~~~

### 4. Observability 메트릭 확인

~~~bash
echo ""
echo "=== Observability 상태 ==="
echo "Kuadrant observability:"
oc get kuadrant kuadrant -n kuadrant-system \
  -o jsonpath='  enable: {.spec.observability.enable}'
echo ""
echo "Tenant telemetry:"
oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='  enabled: {.spec.telemetry.enabled}'
echo ""
echo "PodMonitor:"
oc get podmonitor kuadrant-limitador-monitor -n kuadrant-system --no-headers 2>/dev/null || echo "  미생성"
~~~

## 트러블슈팅 가이드

### 관리자 트러블슈팅

#### A. 컴포넌트 기동 실패

~~~bash
# maas-api Pod 로그 확인
oc logs -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --tail=50

# Kuadrant 상태
oc get kuadrant -n kuadrant-system -o yaml

# Gateway 이벤트
oc describe gateway maas-default-gateway -n openshift-ingress

# kserve MaaS 상태
oc get dsc default-dsc -o jsonpath='{.status.conditions}' | python3 -m json.tool
~~~

#### B. Dashboard에 MaaS 메뉴 미표시

~~~bash
# Dashboard 설정 확인
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig}' | python3 -m json.tool

# Dashboard Pod 로그
oc logs deployment/rhods-dashboard -n redhat-ods-applications --tail=30
~~~

#### C. 모델이 MaaS에 표시되지 않음

~~~bash
# MaaSModelRef 확인
oc get maasmodelref -A

# LLMInferenceService 상태
oc get llminferenceservice -A

# Gateway refs 확인
oc get llminferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='{.spec.router.gateway.refs}'
echo ""

# tiers 어노테이션 확인
oc get llminferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='{.metadata.annotations.alpha\.maas\.opendatahub\.io/tiers}'
echo ""
~~~

#### D. Subscription Phase=Failed

~~~bash
oc describe maassubscription -n models-as-a-service | grep -A5 "Conditions:"
~~~

#### E. Tenant Degraded

~~~bash
# Tenant 조건 메시지
oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
echo ""

# 점검 순서:
# 1) UWM 활성화 여부
# 2) Kuadrant Ready 여부
# 3) maas-db-config Secret 존재 여부
# 4) Gateway 존재 + 어노테이션 여부
~~~

### 사용자 트러블슈팅

#### F. 401 Unauthorized

~~~bash
# API Key 만료 확인 → 새 키 생성
# oc whoami -t 토큰 유효성 확인
echo "원인: API Key 만료 또는 무효"
echo "대응: 새 API Key 생성 (Dashboard 또는 CLI)"
~~~

#### G. 403 Forbidden

~~~bash
# AuthPolicy 존재 확인
oc get maasauthpolicy -n models-as-a-service

# 사용자 그룹 확인
oc get groups

# Subscription과 AuthPolicy의 그룹 일치 확인
echo "원인: AuthPolicy 미존재 또는 그룹 불일치"
echo "대응: AuthPolicy 생성/수정 (Sprint 6 참조)"
~~~

#### H. 404 Model Not Found

~~~bash
# 사용 가능한 모델 목록
curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" | \
  python3 -c "import sys,json; [print(f'  {m[\"id\"]}') for m in json.load(sys.stdin).get('data',[])]" 2>/dev/null

echo "원인: 모델명 불일치, 모델 미퍼블리시, 또는 Subscription 미포함"
~~~

#### I. 429 Too Many Requests

~~~bash
# 현재 Subscription의 토큰 제한 확인
oc get maassubscription -n models-as-a-service -o yaml | grep -A10 tokenLimits

echo "원인: 토큰 제한 초과"
echo "대응: 대기 후 재시도, 또는 관리자에게 토큰 제한 증가 요청"
echo "  - dev-subscription: 낮은 제한 → prod-subscription으로 전환 고려"
~~~

## 종합 검증 결과 요약

~~~bash
echo ""
echo "========================================="
echo "  MaaS 종합 검증 결과"
echo "========================================="
PASS=0
FAIL=0

check() {
  local desc="$1" result="$2" expected="$3"
  if [[ "${result}" == "${expected}" ]]; then
    echo "  [PASS] ${desc}"
    ((PASS++))
  else
    echo "  [FAIL] ${desc} (got: ${result}, expected: ${expected})"
    ((FAIL++))
  fi
}

check "Kuadrant Ready" \
  "$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" \
  "True"

check "Tenant Ready" \
  "$(oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" \
  "True"

check "Gateway 존재" \
  "$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.name}' 2>/dev/null)" \
  "maas-default-gateway"

check "모델 Ready" \
  "$(oc get llminferenceservice ${MODEL_NAME} -n ${MODEL_NS} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" \
  "True"

check "추론 200" \
  "$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 30 \
    -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>/dev/null)" \
  "200"

check "인증 없음 401" \
  "$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 10 \
    -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' 2>/dev/null)" \
  "401"

echo ""
echo "  결과: ${PASS} PASS / ${FAIL} FAIL"
echo "========================================="
~~~

## 다음 단계

→ `runbooks/561-maas-verify.md` (Sprint 1~13 검증 런북)

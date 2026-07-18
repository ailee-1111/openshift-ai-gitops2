# 367 — Sprint 7: MaaS API Key 관리 및 추론 테스트

## 목적

MaaS API Key를 생성하고, 모델 엔드포인트에 대해 OpenAI 호환 API로 추론 요청을 보내 E2E 동작을 확인한다. API Key 만료 정책과 취소 절차를 포함한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.9 (Manage API keys), §2.2 (Access models)

## 전제 조건

- [ ] `runbooks/366-maas-auth-policy.md` 완료 — AuthPolicy Active
- [ ] Subscription Active + AuthPolicy Active (양쪽 모두)
- [ ] **On-prem/Restricted 환경**: `runbooks/115-proxy-trusted-ca.md` 완료 — Gateway Wasm 정상 로드 확인. 미완료 시 API Keys 페이지 "Error loading components" 발생
- [ ] 환경변수: `CLUSTER_DOMAIN`, `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. MaaS Gateway URL 확인

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
echo "MaaS Gateway URL: ${MAAS_URL}"
~~~

### 2. MaaS API Key 생성 (CLI)

> 엔드포인트: `/maas-api/v1/api-keys` (POST). 평문 키는 생성 시점에만 반환되므로 즉시 저장할 것.

~~~bash
OC_TOKEN=$(oc whoami -t)
: "${MODEL_NS:=customer-poc}"

RESPONSE=$(curl -sSk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${OC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"poc-key-$(date +%s)\",\"description\":\"PoC test key\",\"expiresIn\":\"24h\"}")

MAAS_API_KEY=$(echo "${RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key','ERROR'))")
echo "MaaS API Key: ${MAAS_API_KEY}"

if [[ "${MAAS_API_KEY}" == "ERROR" ]] || [[ -z "${MAAS_API_KEY}" ]]; then
  echo "[FAIL] API Key 생성 실패 — 아래 확인:"
  echo "  1) proxy/cluster trustedCA 등록 여부 (115 런북)"
  echo "  2) Gateway Wasm 정상 로드 여부 (istio-proxy 로그에 x509 없어야 함)"
  echo "  3) Subscription Active 여부"
  echo "${RESPONSE}"
fi
~~~

### 3. 사용 가능한 모델 목록 조회

~~~bash
echo "=== MaaS 모델 목록 ==="
curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" | python3 -m json.tool
~~~

### 4. Completions 추론 요청

> 경로: `/${MODEL_NS}/${MODEL_NAME}/v1/completions` (Gateway 경유)

~~~bash
: "${MODEL_NAME:=smollm2-135m}"
: "${MODEL_NS:=customer-poc}"

echo "=== Completion 테스트 ==="
curl -sSk -X POST "${MAAS_URL}/${MODEL_NS}/${MODEL_NAME}/v1/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"Explain OpenShift in one sentence:\",\"max_tokens\":50}" \
  | python3 -m json.tool
~~~

### 5. Chat Completions 추론 요청 (Instruct 모델용)

> chat_template이 있는 모델(qwen3-8b 등)에서만 동작. base 모델(SmolLM2-135M)은 400 에러.

~~~bash
echo "=== Chat Completion 테스트 ==="
curl -sSk -X POST "${MAAS_URL}/${MODEL_NS}/${MODEL_NAME}/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello! What is Kubernetes?\"}],\"max_tokens\":100}" \
  | python3 -m json.tool
~~~

### 6. API Key 만료 정책 설정

~~~bash
oc patch tenant default-tenant -n models-as-a-service \
  --type merge \
  -p '{"spec":{"apiKeys":{"maxExpirationDays":90}}}'

MAX_DAYS=$(oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.spec.apiKeys.maxExpirationDays}')
echo "API Key 최대 만료: ${MAX_DAYS}일"
~~~

### 7. API Key 취소 (필요 시)

~~~bash
# Dashboard: Gen AI studio → API keys → 해당 키의 ⋮ → Revoke
# 또는 특정 사용자의 모든 키 취소:
# Dashboard: Gen AI studio → API keys → ⋮(테이블 헤더) → Revoke user API keys
echo "[INFO] API Key 취소는 Dashboard에서 수행 (CLI 미지원)"
echo "[주의] 그룹에서 사용자를 제거해도 기존 API Key는 유효함 — 반드시 수동 취소 필요"
~~~

## 검증

~~~bash
echo "=== Sprint 7 검증 ==="

echo "1) MaaS URL:"
echo "  ${MAAS_URL}"

echo "2) API Key 검색 (search):"
curl -sSk -X POST "${MAAS_URL}/maas-api/v1/api-keys/search" \
  -H "Authorization: Bearer ${OC_TOKEN}" \
  -H "Content-Type: application/json" -d '{}' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  키 수: {len(d.get(\"data\") or [])}')" 2>/dev/null

echo "3) Completion 응답 코드:"
HTTP_CODE=$(curl -sSk -o /dev/null -w "%{http_code}" \
  -X POST "${MAAS_URL}/${MODEL_NS}/${MODEL_NAME}/v1/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"hi\",\"max_tokens\":5}")
echo "  HTTP ${HTTP_CODE}"

echo "4) maxExpirationDays:"
oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.spec.apiKeys.maxExpirationDays}'
echo ""
~~~

## 실패 시

- **403 `RBAC: access denied` (모든 요청)** → Gateway Wasm TLS 실패. `runbooks/115-proxy-trusted-ca.md` 실행. istio-proxy 로그에 `x509: certificate signed by unknown authority` 확인
- **Dashboard "Error loading components" (API Keys 페이지)** → 위와 동일 원인. 115 런북으로 해결
- **401 Unauthorized (키 생성 시)** → `maas-api-auth-policy` AuthPolicy 확인. 클러스터 audience 불일치 가능 (공식 트러블슈팅 #2 참조)
- **401 Unauthorized (모델 조회 시)** → API Key 만료 또는 잘못된 토큰. 새 키 생성
- **403 Forbidden** → AuthPolicy 미존재 또는 그룹 미포함. Sprint 6 확인
- **404 Not Found** → 추론 경로 확인: `/${MODEL_NS}/${MODEL_NAME}/v1/completions`. 모델명·NS 불일치
- **429 Too Many Requests** → 토큰 제한 초과. Subscription의 토큰 제한 확인/증가
- **API Key 생성 실패** → OC 토큰 유효성 확인 (`oc whoami -t`), Subscription Active 여부 확인

## 다음 단계

→ `runbooks/368-maas-observability.md`

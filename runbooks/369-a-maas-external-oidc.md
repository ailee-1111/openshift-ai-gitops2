# 370 — Sprint 10: 외부 OIDC 인증 구성 (Technology Preview)

## 목적

외부 OIDC ID Provider(Keycloak 등)를 통해 OpenShift 계정 없이도 MaaS에 인증·접근할 수 있도록 구성한다. 그룹 기반 접근 제어와 API Key 라이프사이클을 포함한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.11 (Configure external OIDC authentication)
> ⚠️ Technology Preview — 프로덕션 비권장

## 전제 조건

- [ ] `runbooks/369-maas-dashboard-export.md` 완료
- [ ] 외부 OIDC Provider 가동 중 (Keycloak, Azure AD 등)
- [ ] OIDC Provider에 클라이언트 등록 완료 (issuer URL, client ID 확보)
- [ ] OIDC Provider에 사용자 그룹 생성 + 그룹 클레임 설정
- [ ] 환경변수: `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`

## 실행

### 1. Tenant CR에 외부 OIDC 설정 추가

~~~bash
: "${OIDC_ISSUER_URL:?OIDC_ISSUER_URL 미정의}"
: "${OIDC_CLIENT_ID:?OIDC_CLIENT_ID 미정의}"

oc patch tenant default-tenant -n models-as-a-service \
  --type merge \
  -p "{
    \"spec\": {
      \"externalOIDC\": {
        \"issuerUrl\": \"${OIDC_ISSUER_URL}\",
        \"clientId\": \"${OIDC_CLIENT_ID}\"
      }
    }
  }"
echo "[PASS] Tenant externalOIDC 설정 완료"
~~~

### 2. OIDC 그룹과 매칭되는 Subscription 생성

OIDC 토큰의 `groups` 클레임과 정확히 일치하는 그룹명을 사용해야 한다.

~~~bash
: "${MODEL_NS:=llm}"
: "${MODEL_NAME:=granite-2b}"
# OIDC 그룹명 (예: data-scientists)
: "${OIDC_GROUP:=data-scientists}"

oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: oidc-subscription
  namespace: models-as-a-service
spec:
  description: "외부 OIDC 사용자용 구독"
  priority: 10
  groups:
    - "${OIDC_GROUP}"
  models:
    - name: "${MODEL_NAME}"
      namespace: "${MODEL_NS}"
      tokenLimits:
        - tokens: 5000
          duration: 1
          unit: minute
EOF
echo "[PASS] oidc-subscription 생성"
~~~

### 3. OIDC 그룹용 AuthPolicy 생성

~~~bash
oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: oidc-auth-policy
  namespace: models-as-a-service
spec:
  description: "외부 OIDC 그룹 접근 정책"
  groups:
    - "${OIDC_GROUP}"
  models:
    - name: "${MODEL_NAME}"
      namespace: "${MODEL_NS}"
EOF
echo "[PASS] oidc-auth-policy 생성"
~~~

### 4. OIDC 토큰 발급 테스트

~~~bash
: "${OIDC_TOKEN_ENDPOINT:?OIDC_TOKEN_ENDPOINT 미정의}"
: "${OIDC_CLIENT_SECRET:?OIDC_CLIENT_SECRET 미정의}"

OIDC_TOKEN=$(curl -sSk -X POST "${OIDC_TOKEN_ENDPOINT}" \
  -d "client_id=${OIDC_CLIENT_ID}" \
  -d "client_secret=${OIDC_CLIENT_SECRET}" \
  -d "grant_type=client_credentials" | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERROR'))")

echo "OIDC Token: ${OIDC_TOKEN:0:50}..."
~~~

### 5. OIDC 토큰으로 모델 목록 조회

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"

echo "=== OIDC 인증 모델 목록 ==="
curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${OIDC_TOKEN}" | python3 -m json.tool
~~~

### 6. OIDC 토큰으로 API Key 생성

~~~bash
OIDC_API_KEY=$(curl -sSk -X POST "${MAAS_URL}/maas-api/v1/tokens" \
  -H "Authorization: Bearer ${OIDC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"expiration": "24h"}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('token','ERROR'))")

echo "OIDC API Key: ${OIDC_API_KEY}"
~~~

## 검증

~~~bash
echo "=== Sprint 10 검증 ==="

echo "1) Tenant externalOIDC 설정:"
oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.spec.externalOIDC}' | python3 -m json.tool

echo "2) OIDC Subscription:"
oc get maassubscription oidc-subscription -n models-as-a-service --no-headers

echo "3) OIDC AuthPolicy:"
oc get maasauthpolicy oidc-auth-policy -n models-as-a-service --no-headers

echo "4) OIDC 토큰으로 추론 테스트:"
CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 30 \
  -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
  -H "Authorization: Bearer ${OIDC_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"ibm-granite/granite-3.1-2b-instruct","messages":[{"role":"user","content":"test"}],"max_tokens":5}' 2>/dev/null)
echo "  HTTP ${CODE}"
~~~

## 실패 시

- **OIDC 토큰 발급 실패** → OIDC Provider 설정 확인 (client ID, secret, endpoint)
- **401 Unauthorized** → Tenant externalOIDC issuerUrl/clientId 확인, OIDC 토큰 유효기간 확인
- **403 Forbidden** → OIDC 토큰의 groups 클레임이 Subscription/AuthPolicy의 그룹명과 정확히 일치해야 함
- **API Key 생성 실패** → OIDC 그룹이 Subscription에 포함되어 있는지 확인

## 다음 단계

→ `runbooks/369-b-maas-external-model.md`

# 369-b — Sprint 11: 외부 모델 라우팅 구성 (Technology Preview)

## 목적

OpenAI, Anthropic, AWS Bedrock 등 외부 LLM Provider의 모델을 MaaS Gateway를 통해 라우팅하여, 로컬 모델과 동일한 거버넌스(인증, 토큰 제한, 모니터링)를 적용한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.12 (Configure external models)
> ⚠️ Technology Preview — 프로덕션 비권장

## 전제 조건

- [ ] `runbooks/369-a-maas-external-oidc.md` 완료 (또는 Sprint 7 API Key 동작 확인)
- [ ] 외부 Provider API Key 보유 (OpenAI, Anthropic 등)
- [ ] 환경변수: `EXTERNAL_PROVIDER`, `EXTERNAL_ENDPOINT`, `EXTERNAL_MODEL_ID`, `EXTERNAL_API_KEY`

## 실행

### 1. 외부 Provider API Key Secret 생성

~~~bash
: "${EXTERNAL_PROVIDER:=openai}"
: "${EXTERNAL_ENDPOINT:=api.openai.com}"
: "${EXTERNAL_MODEL_ID:=gpt-4o}"
: "${EXTERNAL_API_KEY:?EXTERNAL_API_KEY 미정의}"

EXTERNAL_SECRET_NAME="${EXTERNAL_PROVIDER}-api-key"

oc create secret generic "${EXTERNAL_SECRET_NAME}" \
  --from-literal=api-key="${EXTERNAL_API_KEY}" \
  -n redhat-ods-applications \
  --dry-run=client -o yaml | oc apply -f -

echo "[PASS] ${EXTERNAL_SECRET_NAME} Secret 생성"
~~~

### 2. ExternalModel CR 생성

~~~bash
EXTERNAL_MODEL_NAME="${EXTERNAL_PROVIDER}-${EXTERNAL_MODEL_ID//[.]/-}"

oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: ExternalModel
metadata:
  name: ${EXTERNAL_MODEL_NAME}
  namespace: redhat-ods-applications
spec:
  provider: ${EXTERNAL_PROVIDER}
  endpoint: ${EXTERNAL_ENDPOINT}
  targetModel: ${EXTERNAL_MODEL_ID}
  credentialRef:
    name: ${EXTERNAL_SECRET_NAME}
EOF
echo "[PASS] ExternalModel ${EXTERNAL_MODEL_NAME} 생성"
~~~

### 3. 자동 생성 네트워킹 리소스 확인

ExternalModel 생성 시 MaaS Controller가 자동으로 Service, HTTPRoute, ServiceEntry, DestinationRule을 생성한다.

~~~bash
echo "=== 자동 생성 리소스 확인 ==="
echo "Service:"
oc get svc -n redhat-ods-applications | grep "${EXTERNAL_MODEL_NAME}" || echo "  미생성"
echo "HTTPRoute:"
oc get httproute -n redhat-ods-applications | grep "${EXTERNAL_MODEL_NAME}" || echo "  미생성"
echo "ServiceEntry:"
oc get serviceentry -n redhat-ods-applications | grep "${EXTERNAL_MODEL_NAME}" || echo "  미생성"
echo "DestinationRule:"
oc get destinationrule -n redhat-ods-applications | grep "${EXTERNAL_MODEL_NAME}" || echo "  미생성"
~~~

### 4. Subscription에 외부 모델 추가

~~~bash
oc patch maassubscription prod-subscription -n models-as-a-service \
  --type=merge \
  -p "{
    \"spec\": {
      \"models\": [
        {\"name\": \"${MODEL_NAME:-granite-2b}\", \"namespace\": \"${MODEL_NS:-llm}\", \"tokenLimits\": [{\"tokens\": 100000, \"duration\": 1, \"unit\": \"hour\"}]},
        {\"name\": \"${EXTERNAL_MODEL_NAME}\", \"namespace\": \"redhat-ods-applications\", \"tokenLimits\": [{\"tokens\": 10000, \"duration\": 1, \"unit\": \"hour\"}]}
      ]
    }
  }"
echo "[PASS] prod-subscription에 외부 모델 추가"
~~~

### 5. AuthPolicy에 외부 모델 추가

~~~bash
oc patch maasauthpolicy prod-auth-policy -n models-as-a-service \
  --type=merge \
  -p "{
    \"spec\": {
      \"models\": [
        {\"name\": \"${MODEL_NAME:-granite-2b}\", \"namespace\": \"${MODEL_NS:-llm}\"},
        {\"name\": \"${EXTERNAL_MODEL_NAME}\", \"namespace\": \"redhat-ods-applications\"}
      ]
    }
  }"
echo "[PASS] prod-auth-policy에 외부 모델 추가"
~~~

### 6. 외부 모델 추론 테스트

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
: "${MAAS_API_KEY:?MAAS_API_KEY 미설정}"

echo "=== 외부 모델 추론 ==="
curl -sSk -X POST "${MAAS_URL}/maas-api/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${EXTERNAL_MODEL_NAME}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello from MaaS!\"}],
    \"max_tokens\": 50
  }" | python3 -m json.tool
~~~

## 검증

~~~bash
echo "=== Sprint 11 검증 ==="

echo "1) ExternalModel CR:"
oc get externalmodel -n redhat-ods-applications --no-headers

echo "2) 자동 네트워킹:"
oc get svc,httproute -n redhat-ods-applications | grep "${EXTERNAL_MODEL_NAME}"

echo "3) Subscription 외부 모델 포함:"
oc get maassubscription prod-subscription -n models-as-a-service \
  -o jsonpath='{.spec.models[*].name}'
echo ""

echo "4) 추론 응답 코드:"
CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 30 \
  -X POST "${MAAS_URL}/maas-api/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${EXTERNAL_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}],\"max_tokens\":5}" 2>/dev/null)
echo "  HTTP ${CODE}"
~~~

## 실패 시

- **ExternalModel 네트워킹 리소스 미생성** → `oc describe externalmodel ${EXTERNAL_MODEL_NAME} -n redhat-ods-applications` 이벤트 확인
- **외부 Provider 401** → Provider API Key 유효성 확인, Secret 내용 점검
- **Provider Rate Limit** → 외부 Provider의 토큰 제한은 모든 MaaS 사용자가 공유. Provider 할당량 확인
- **502 Bad Gateway** → ServiceEntry/DestinationRule 확인, 외부 endpoint DNS 해석 가능 여부 확인

## 다음 단계

→ `runbooks/369-c-maas-multimodel.md`

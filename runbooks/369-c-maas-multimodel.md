# 369-c — Sprint 12: 멀티모델 MaaS 라우팅

## 목적

여러 LLM 모델(로컬+외부)을 MaaS Gateway를 통해 동시에 서빙하고, 요청의 `model` 필드 기반으로 자동 라우팅되는 것을 확인한다. 다중 Subscription과 AuthPolicy로 팀별 모델 접근을 분리한다.

> 출처: ODH MaaS 문서 (Model Setup), [Run MaaS for Multiple LLMs](https://developers.redhat.com/articles/2026/03/24/run-model-service-multiple-llms-openshift)

## 전제 조건

- [ ] `runbooks/369-b-maas-external-model.md` 완료 (또는 Sprint 7까지 최소 1모델 동작)
- [ ] GPU 2+ 가용 (로컬 모델 2개 동시 서빙 시)
- [ ] 환경변수: `MODEL_NS`, `CLUSTER_DOMAIN`, `MAAS_API_KEY`

## 실행

### 1. 두 번째 로컬 모델 배포

~~~bash
: "${MODEL_NS:=llm}"

oc apply -f - <<EOF
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: qwen3-06b
  namespace: ${MODEL_NS}
  annotations:
    alpha.maas.opendatahub.io/tiers: '[]'
spec:
  model:
    uri: hf://Qwen/Qwen3-0.6B
    name: Qwen/Qwen3-0.6B
  replicas: 1
  router:
    route: {}
    gateway:
      refs:
        - name: maas-default-gateway
          namespace: openshift-ingress
  template:
    containers:
      - name: main
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: 8Gi
          requests:
            nvidia.com/gpu: "1"
            memory: 4Gi
EOF

echo "qwen3-06b 배포 대기..."
for i in $(seq 1 60); do
  READY=$(oc get llminferenceservice qwen3-06b -n "${MODEL_NS}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "${READY}" == "True" ]]; then
    echo "[PASS] qwen3-06b Ready"
    break
  fi
  sleep 10
done
~~~

### 2. 멀티모델 Subscription 업데이트

~~~bash
oc patch maassubscription prod-subscription -n models-as-a-service \
  --type=merge \
  -p "{
    \"spec\": {
      \"models\": [
        {\"name\": \"${MODEL_NAME:-granite-2b}\", \"namespace\": \"${MODEL_NS}\", \"tokenLimits\": [{\"tokens\": 100000, \"duration\": 1, \"unit\": \"hour\"}]},
        {\"name\": \"qwen3-06b\", \"namespace\": \"${MODEL_NS}\", \"tokenLimits\": [{\"tokens\": 50000, \"duration\": 1, \"unit\": \"hour\"}]}
      ]
    }
  }"
echo "[PASS] prod-subscription에 qwen3-06b 추가"
~~~

### 3. AuthPolicy 업데이트

~~~bash
oc patch maasauthpolicy prod-auth-policy -n models-as-a-service \
  --type=merge \
  -p "{
    \"spec\": {
      \"models\": [
        {\"name\": \"${MODEL_NAME:-granite-2b}\", \"namespace\": \"${MODEL_NS}\"},
        {\"name\": \"qwen3-06b\", \"namespace\": \"${MODEL_NS}\"}
      ]
    }
  }"
echo "[PASS] prod-auth-policy에 qwen3-06b 추가"
~~~

### 4. 멀티모델 라우팅 테스트

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
: "${MAAS_API_KEY:?MAAS_API_KEY 미설정}"

echo "=== 모델 목록 ==="
curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" | \
  python3 -c "import sys,json; [print(f'  - {m[\"id\"]}') for m in json.load(sys.stdin).get('data',[])]"

echo ""
echo "=== 모델 A (granite-2b) ==="
curl -sSk -X POST "${MAAS_URL}/llm/${MODEL_NAME:-granite-2b}/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"ibm-granite/granite-3.1-2b-instruct","messages":[{"role":"user","content":"Which model are you?"}],"max_tokens":30}' | \
  python3 -c "import sys,json; r=json.load(sys.stdin); print(f'  응답 모델: {r.get(\"model\",\"?\")}')" 2>/dev/null

echo ""
echo "=== 모델 B (qwen3-06b) ==="
curl -sSk -X POST "${MAAS_URL}/llm/qwen3-06b/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen3-0.6B","messages":[{"role":"user","content":"Which model are you?"}],"max_tokens":30}' | \
  python3 -c "import sys,json; r=json.load(sys.stdin); print(f'  응답 모델: {r.get(\"model\",\"?\")}')" 2>/dev/null
~~~

### 5. 팀별 모델 분리 구독 (선택)

~~~bash
# analytics 팀은 granite만, ml-platform 팀은 전체
oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: analytics-subscription
  namespace: models-as-a-service
spec:
  description: "분석팀 — Granite 모델 전용"
  priority: 5
  groups:
    - analytics-team
  models:
    - name: ${MODEL_NAME:-granite-2b}
      namespace: ${MODEL_NS}
      tokenLimits:
        - tokens: 10000
          duration: 1
          unit: hour
EOF
echo "[INFO] analytics-subscription 생성 (매칭 AuthPolicy 별도 필요)"
~~~

### 6. 존재하지 않는 모델 요청 테스트

~~~bash
echo "=== 미등록 모델 요청 ==="
CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/llm/nonexistent/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"nonexistent","messages":[{"role":"user","content":"test"}],"max_tokens":5}')
echo "  HTTP ${CODE} (404 예상)"
~~~

## 검증

~~~bash
echo "=== Sprint 12 검증 ==="

echo "1) LLMInferenceService 목록:"
oc get llminferenceservice -n "${MODEL_NS}"

echo "2) MaaS 모델 수:"
MODEL_COUNT=$(curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" 2>/dev/null | \
  python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
echo "  ${MODEL_COUNT} 모델"

echo "3) 각 모델 응답 코드:"
for M in ${MODEL_NAME:-granite-2b} qwen3-06b; do
  CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST "${MAAS_URL}/llm/${M}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}" 2>/dev/null)
  echo "  ${M}: HTTP ${CODE}"
done

echo "4) 미등록 모델 404:"
CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/llm/nonexistent/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"x","messages":[{"role":"user","content":"x"}],"max_tokens":1}' 2>/dev/null)
echo "  nonexistent: HTTP ${CODE}"
~~~

## 실패 시

- **두 번째 모델 GPU 부족** → `oc describe node` GPU allocatable 확인. 더 작은 모델이나 CPU 모드 고려
- **모델 라우팅 혼선** → `/maas-api/v1/models`로 정확한 모델 ID 확인, 대소문자 민감
- **Subscription 모델 업데이트 미반영** → AuthPolicy도 수동 동기화 필요

## 다음 단계

→ `runbooks/369-d-maas-e2e-troubleshoot.md`

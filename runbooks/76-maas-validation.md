# 76 — MaaS 통합 라우팅 검증 (S7)

## 목적

MaaS Gateway 기반 2모델 라우팅, 장애 폴백을 검증한다. 구축: `66-maas-e2e.md`.

## 검증 항목

### V-S7-1. 2모델 라우팅

~~~bash
MAAS_ROUTE=$(oc get route -n openshift-ingress -l app=maas -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
API_KEY=$(oc get secret maas-api-key -n rhoai-poc -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d)
for MODEL in smollm2-135m qwen3-8b; do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${MAAS_ROUTE}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"test\",\"max_tokens\":5}")
  echo "${MODEL}: HTTP ${CODE}"
done
# 기대: 200  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S7-2. Gateway + API Pod

~~~bash
oc get gateway -n openshift-ingress --no-headers | wc -l
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --no-headers | grep Running
# 기대: 1+, Running  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S7-3. 장애 복구

~~~bash
# 66-maas-e2e.md Step 3 결과  |  결과: [   ] PASS / [   ] FAIL
~~~

## 다음 단계

→ `runbooks/77-multitenant-validation.md`

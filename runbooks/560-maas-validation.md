# 560 — MaaS 통합 라우팅 검증 (S7)

## 목적

MaaS Gateway 기반 2모델 라우팅, Gateway Route 접근, 장애 폴백을 검증한다. 구축: `360-maas-e2e.md`.

## 전제 조건

- [ ] 해당 구축 런북 완료 (360/370/380/390)
- [ ] 환경변수: `MODEL_NS=${MODEL_NS:-rhoai-poc}`, `MODEL_NAME=${MODEL_NAME:-smollm2-135m}`
- [ ] MaaS Gateway Route 존재: `oc get route maas-gateway -n openshift-ingress`

## 실행

검증 항목의 bash 블록을 순서대로 실행한다.

## 검증 항목

### V-S7-1. MaaS Gateway Route 접근

~~~bash
MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "${MAAS_ROUTE}" ]; then
  echo "[FAIL] maas-gateway Route 미존재"
else
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${MAAS_ROUTE}/v1/models" \
    -H "Authorization: Bearer $(oc whoami -t)")
  echo "MaaS API /v1/models: HTTP ${CODE}"
fi
# 기대: 200  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S7-2. 2모델 라우팅

~~~bash
MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
for MODEL in ${MODEL_NAME} qwen3-8b-fp8-dynamic-version-1; do
  ISVC=$(oc get inferenceservice ${MODEL%%"-version"*} -n ${MODEL_NS:-rhoai-poc} -o jsonpath='{.metadata.name}' 2>/dev/null)
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${MAAS_ROUTE}/${MODEL_NS:-rhoai-poc}/${MODEL}/v1/completions" \
    -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"test\",\"max_tokens\":5}")
  echo "${MODEL}: HTTP ${CODE}"
done
# 기대: 200  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S7-3. Gateway + API Pod

~~~bash
oc get gateway -n openshift-ingress --no-headers | wc -l
oc get route maas-gateway -n openshift-ingress --no-headers
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --no-headers | grep Running
# 기대: Gateway 1+, Route 존재, maas-api Running  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S7-4. API Key 기반 추론

~~~bash
MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
API_KEY="${API_KEY:-$(oc get secret maas-api-key -n ${MODEL_NS:-rhoai-poc} -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d)}"
if [ -n "${API_KEY}" ]; then
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 15 \
    "https://${MAAS_ROUTE}/${MODEL_NS:-rhoai-poc}/${MODEL_NAME}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"hello\",\"max_tokens\":5}")
  echo "API Key 추론: HTTP ${CODE}"
else
  echo "[SKIP] API_KEY 미설정"
fi
# 기대: 200  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S7-5. 장애 복구

~~~bash
# 360-maas-e2e.md Step 3 결과  |  결과: [   ] PASS / [   ] FAIL
~~~

## 실패 시

- **maas-gateway Route 미존재** → `runbooks/100-platform-setup.md` step 14의 Route 생성 블록 실행
- **503 "Application is not available"** → Route의 target Service 확인: `oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.to.name}'`. 해당 Service 존재 여부와 Pod 상태 확인
- 리소스 미존재 → 해당 구축 런북 재실행
- Pod 미기동 → `oc describe pod` + `oc logs` 확인

## 다음 단계

→ `runbooks/570-multitenant-validation.md`

# 561 — S7 MaaS 종합 검증

## 목적

Sprint 1~13 구축 런북(361~369-d)의 전체 MaaS 파이프라인을 검증한다. 각 스프린트의 핵심 검증 항목을 통합하여 단일 검증 런북으로 실행한다.

> 검증 대상: `runbooks/361-maas-prerequisites.md` ~ `runbooks/369-d-maas-e2e-troubleshoot.md`

## 전제 조건

- [ ] Sprint 1~9 구축 런북 완료 (필수)
- [ ] Sprint 10~12 구축 런북 완료 (해당 기능 사용 시)
- [ ] 환경변수: `CLUSTER_DOMAIN`, `MODEL_NS`, `MODEL_NAME`, `MAAS_API_KEY`

## 검증 항목

### V-S7-1: 전제 조건 (Sprint 1)

~~~bash
echo "=== V-S7-1: 전제 조건 ==="
TOTAL=0; PASS=0; FAIL=0

v() {
  local desc="$1" actual="$2" expected="$3"
  ((TOTAL++))
  if [[ "${actual}" == "${expected}" ]]; then
    echo "  [PASS] ${desc}"
    ((PASS++))
  else
    echo "  [FAIL] ${desc} — got '${actual}', expected '${expected}'"
    ((FAIL++))
  fi
}

# OCP 4.19+
OCP_MINOR=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' | cut -d. -f2)
v "OCP 4.19+" "$([ "${OCP_MINOR}" -ge 19 ] && echo ok || echo ng)" "ok"

# kserve Managed
v "kserve Managed" \
  "$(oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.managementState}')" \
  "Managed"

# UWM
v "UWM 활성화" \
  "$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep -q 'enableUserWorkload: true' && echo ok || echo ng)" \
  "ok"

# Connectivity Link
v "Connectivity Link CSV" \
  "$(oc get csv -n openshift-operators --no-headers 2>/dev/null | grep connectivity-link | awk '{print $NF}')" \
  "Succeeded"

# Kuadrant
v "Kuadrant Ready" \
  "$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" \
  "True"

# DB Secret
v "maas-db-config Secret" \
  "$(oc get secret maas-db-config -n redhat-ods-applications --no-headers 2>/dev/null | wc -l | tr -d ' ')" \
  "1"

echo "  --- V-S7-1: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-2: Gateway + TLS (Sprint 2)

~~~bash
echo "=== V-S7-2: Gateway + TLS ==="
TOTAL=0; PASS=0; FAIL=0

v "Gateway 존재" \
  "$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.name}' 2>/dev/null)" \
  "maas-default-gateway"

v "Authorino TLS" \
  "$(oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls.enabled}' 2>/dev/null)" \
  "true"

v "authorino-server-cert" \
  "$(oc get secret authorino-server-cert -n kuadrant-system --no-headers 2>/dev/null | wc -l | tr -d ' ')" \
  "1"

v "TLS bootstrap 어노테이션" \
  "$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}' 2>/dev/null)" \
  "true"

echo "  --- V-S7-2: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-3: DSC/Dashboard (Sprint 3)

~~~bash
echo "=== V-S7-3: DSC/Dashboard ==="
TOTAL=0; PASS=0; FAIL=0

v "MaaS managementState" \
  "$(oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}' 2>/dev/null)" \
  "Managed"

v "modelAsService 플래그" \
  "$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null)" \
  "true"

v "genAiStudio 플래그" \
  "$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null)" \
  "true"

v "Tenant Ready" \
  "$(oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" \
  "True"

v "MaaS CRD 수" \
  "$(oc get crd | grep -c maas.opendatahub.io)" \
  "$(oc get crd | grep -c maas.opendatahub.io)"

echo "  --- V-S7-3: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-4: 모델 배포 (Sprint 4)

~~~bash
echo "=== V-S7-4: 모델 배포 ==="
: "${MODEL_NS:=llm}"
: "${MODEL_NAME:=granite-2b}"
TOTAL=0; PASS=0; FAIL=0

v "LLMInferenceService Ready" \
  "$(oc get llminferenceservice ${MODEL_NAME} -n ${MODEL_NS} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" \
  "True"

v "MaaSModelRef 존재" \
  "$(oc get maasmodelref -n ${MODEL_NS} --no-headers 2>/dev/null | wc -l | tr -d ' ')" \
  "$(oc get maasmodelref -n ${MODEL_NS} --no-headers 2>/dev/null | wc -l | tr -d ' ')"

echo "  --- V-S7-4: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-5: Subscription (Sprint 5)

~~~bash
echo "=== V-S7-5: Subscription ==="
TOTAL=0; PASS=0; FAIL=0

for SUB in dev-subscription prod-subscription; do
  PHASE=$(oc get maassubscription "${SUB}" -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null)
  v "${SUB} Active" "${PHASE}" "Active"
done

echo "  --- V-S7-5: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-6: AuthPolicy (Sprint 6)

~~~bash
echo "=== V-S7-6: AuthPolicy ==="
TOTAL=0; PASS=0; FAIL=0

for POL in dev-auth-policy prod-auth-policy; do
  PHASE=$(oc get maasauthpolicy "${POL}" -n models-as-a-service -o jsonpath='{.status.phase}' 2>/dev/null)
  v "${POL} Active" "${PHASE}" "Active"
done

echo "  --- V-S7-6: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-7: API Key + 추론 (Sprint 7)

~~~bash
echo "=== V-S7-7: API Key + 추론 ==="
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
: "${MAAS_API_KEY:?MAAS_API_KEY 미설정}"
TOTAL=0; PASS=0; FAIL=0

# 모델 목록
MODEL_COUNT=$(curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" 2>/dev/null | \
  python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
v "모델 목록 ≥1" "$([ "${MODEL_COUNT:-0}" -ge 1 ] && echo ok || echo ng)" "ok"

# 추론 200
CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 60 \
  -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
  -H "Authorization: Bearer ${MAAS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>/dev/null)
v "추론 HTTP 200" "${CODE}" "200"

# 인증 없음 401
CODE_401=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' 2>/dev/null)
v "인증 없음 HTTP 401" "${CODE_401}" "401"

echo "  --- V-S7-7: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-8: Observability (Sprint 8-9)

~~~bash
echo "=== V-S7-8: Observability ==="
TOTAL=0; PASS=0; FAIL=0

v "Kuadrant observability" \
  "$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.spec.observability.enable}' 2>/dev/null)" \
  "true"

v "Tenant telemetry" \
  "$(oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.enabled}' 2>/dev/null)" \
  "true"

v "PodMonitor 존재" \
  "$(oc get podmonitor kuadrant-limitador-monitor -n kuadrant-system --no-headers 2>/dev/null | wc -l | tr -d ' ')" \
  "1"

echo "  --- V-S7-8: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

### V-S7-9~13: 선택 항목 (Sprint 10-13)

~~~bash
echo "=== V-S7-9: 선택 기능 ==="
TOTAL=0; PASS=0; FAIL=0

# External OIDC (Sprint 10)
OIDC_URL=$(oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.spec.externalOIDC.issuerUrl}' 2>/dev/null)
if [[ -n "${OIDC_URL}" ]]; then
  v "External OIDC 설정" "ok" "ok"
else
  echo "  [SKIP] External OIDC 미구성"
fi

# External Model (Sprint 11)
EXT_COUNT=$(oc get externalmodel -n redhat-ods-applications --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${EXT_COUNT}" -gt 0 ]]; then
  v "ExternalModel ≥1" "ok" "ok"
else
  echo "  [SKIP] ExternalModel 미구성"
fi

# Multi-model (Sprint 12)
LIS_COUNT=$(oc get llminferenceservice -n ${MODEL_NS} --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${LIS_COUNT}" -gt 1 ]]; then
  v "멀티모델 (${LIS_COUNT}개)" "ok" "ok"
else
  echo "  [SKIP] 단일 모델만 배포"
fi

echo "  --- V-S7-9: ${PASS}/${TOTAL} PASS ---"
echo ""
~~~

## 종합 결과

~~~bash
echo "========================================="
echo "  S7 MaaS 종합 검증 결과"
echo "========================================="
echo ""
echo "  Sprint 1  전제 조건       → V-S7-1"
echo "  Sprint 2  Gateway+TLS    → V-S7-2"
echo "  Sprint 3  DSC/Dashboard  → V-S7-3"
echo "  Sprint 4  모델 배포       → V-S7-4"
echo "  Sprint 5  Subscription   → V-S7-5"
echo "  Sprint 6  AuthPolicy     → V-S7-6"
echo "  Sprint 7  API Key+추론   → V-S7-7"
echo "  Sprint 8-9 Observability → V-S7-8"
echo "  Sprint 10-13 선택        → V-S7-9"
echo ""
echo "  모든 V-S7-* 섹션에서 FAIL=0이면 MaaS 구축 검증 완료"
echo "========================================="
~~~

## 실패 시

- 각 V-S7-N 항목의 FAIL에 대해 해당 Sprint 구축 런북의 "실패 시" 섹션 참조
- 트러블슈팅 전체 가이드: `runbooks/369-d-maas-e2e-troubleshoot.md`

## 다음 단계

→ `runbooks/370-multitenant.md` (S8 멀티테넌트 구축)

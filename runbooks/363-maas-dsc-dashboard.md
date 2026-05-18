# 363 — Sprint 3: DSC/Dashboard 패치 및 MaaS 컴포넌트 활성화

## 목적

DataScienceCluster에서 MaaS 컴포넌트를 활성화하고, OdhDashboardConfig에서 MaaS 관련 UI 플래그를 켜며, Tenant CR이 정상 배포되었는지 확인한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.2 (MaaS configuration / Dashboard configuration), §1.4 (Verify deployment)

## 전제 조건

- [ ] `runbooks/362-maas-gateway-tls.md` 완료 — Gateway + TLS Ready
- [ ] `default-dsc` Ready=True
- [ ] `cluster-admin` 권한

## 실행

### 1. DSC MaaS 컴포넌트 활성화

~~~bash
oc patch dsc default-dsc --type=merge \
  -p '{
    "spec": {
      "components": {
        "kserve": {
          "modelsAsService": {
            "managementState": "Managed"
          }
        }
      }
    }
  }'
echo "[PASS] kserve.modelsAsService → Managed"
~~~

### 2. OdhDashboardConfig MaaS 플래그 패치

~~~bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  --type=merge \
  -p '{
    "spec": {
      "dashboardConfig": {
        "modelAsService": true,
        "genAiStudio": true,
        "maasAuthPolicies": true,
        "observabilityDashboard": true
      }
    }
  }'
echo "[PASS] Dashboard MaaS 플래그 활성화"
~~~

### 3. (선택) vLLM MaaS 지원 활성화 — Technology Preview

vLLM 런타임으로 MaaS 모델을 배포하려면 추가 플래그 필요.

~~~bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  --type=merge \
  -p '{
    "spec": {
      "dashboardConfig": {
        "vLLMDeploymentOnMaaS": true
      }
    }
  }'
echo "[INFO] vLLMDeploymentOnMaaS 활성화 (Technology Preview)"
~~~

### 4. (선택) LlamaStack Operator 활성화

Dashboard의 Gen AI Studio 전체 기능(Playground 등)을 사용하려면 필요.

~~~bash
oc patch dsc default-dsc --type=merge \
  -p '{
    "spec": {
      "components": {
        "llamastackoperator": {
          "managementState": "Managed"
        }
      }
    }
  }'
echo "[INFO] llamastackoperator → Managed"
~~~

### 5. MaaS CRD 배포 확인

~~~bash
echo "=== MaaS CRD 확인 ==="
oc get crd | grep maas.opendatahub.io
echo "---"
oc get crd | grep tenant
~~~

### 6. Tenant CR 상태 확인

~~~bash
echo "Tenant CR 대기 (최대 3분)..."
for i in $(seq 1 18); do
  TENANT_READY=$(oc get tenant default-tenant -n models-as-a-service \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "${TENANT_READY}" == "True" ]]; then
    echo "[PASS] Tenant Ready — AllComponentsReady"
    break
  fi
  REASON=$(oc get tenant default-tenant -n models-as-a-service \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
  echo "  대기 중... ${REASON:-initializing} (${i}/18)"
  sleep 10
done

oc get tenant default-tenant -n models-as-a-service
~~~

## 검증

~~~bash
echo "=== Sprint 3 검증 ==="

echo "1) MaaS managementState:"
oc get dsc default-dsc \
  -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}'
echo ""

echo "2) Dashboard 플래그:"
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.modelAsService}'
echo -n " / genAiStudio: "
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.genAiStudio}'
echo -n " / maasAuthPolicies: "
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.maasAuthPolicies}'
echo ""

echo "3) MaaS CRDs:"
oc get crd | grep -E "maas|tenant" | awk '{print $1}'

echo "4) Tenant 상태:"
oc get tenant -n models-as-a-service

echo "5) maas-api Pod:"
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --no-headers 2>/dev/null
~~~

## 실패 시

- **Tenant Degraded** → UWM 미활성, Kuadrant 미준비, maas-db-config 미생성 순으로 점검
- **MaaS CRD 미배포** → `oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.modelsAsService}'` 확인
- **Dashboard에 MaaS 메뉴 안 보임** → 브라우저 캐시 삭제 + Ctrl+Shift+R, `oc logs deployment/rhods-dashboard -n redhat-ods-applications` 확인
- **maas-api Pod 미기동** → `oc logs -n redhat-ods-applications -l app.kubernetes.io/name=maas-api` 에러 확인

## 다음 단계

→ `runbooks/364-maas-model-deploy.md`

# 361 — Sprint 1: MaaS 전제 조건 점검 및 Operator 설치

## 목적

Models-as-a-Service(MaaS) 배포에 필요한 플랫폼 전제 조건(OCP 버전, Operator, DB, UWM)을 점검하고, Red Hat Connectivity Link Operator + Kuadrant CR을 설치한다.

> 출처: [Red Hat OpenShift AI 3.4 — Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service_maas) §1.2 Prerequisites

## 전제 조건

- [ ] `runbooks/020-rhoai-operator-install.md` 완료 — RHOAI Operator 3.4+ 설치
- [ ] `runbooks/030-argocd-app-sync.md` 완료 — `default-dsc` Ready=True
- [ ] 환경변수: `CLUSTER_DOMAIN`, `POC_NAMESPACE`
- [ ] `cluster-admin` 권한으로 로그인

## 실행

### 1. OCP 버전 확인 (4.19.9+)

~~~bash
OCP_VER=$(oc get clusterversion version -o jsonpath='{.status.desired.version}')
echo "OCP 버전: ${OCP_VER}"

MAJOR=$(echo "${OCP_VER}" | cut -d. -f1)
MINOR=$(echo "${OCP_VER}" | cut -d. -f2)
if [[ "${MAJOR}" -lt 4 ]] || { [[ "${MAJOR}" -eq 4 ]] && [[ "${MINOR}" -lt 19 ]]; }; then
  echo "[FAIL] OCP 4.19.9+ 필요 (현재: ${OCP_VER})"
else
  echo "[PASS] OCP 버전 충족"
fi
~~~

### 2. RHOAI Operator 버전 확인 (3.4+)

~~~bash
RHOAI_CSV=$(oc get csv -n redhat-ods-operator --no-headers 2>/dev/null | grep rhods | awk '{print $1}')
echo "RHOAI CSV: ${RHOAI_CSV}"

RHOAI_VER=$(oc get csv "${RHOAI_CSV}" -n redhat-ods-operator -o jsonpath='{.spec.version}' 2>/dev/null)
echo "RHOAI 버전: ${RHOAI_VER}"
~~~

### 3. DataScienceCluster kserve Managed 확인

~~~bash
KSERVE_STATE=$(oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.managementState}')
echo "kserve managementState: ${KSERVE_STATE}"
if [[ "${KSERVE_STATE}" != "Managed" ]]; then
  echo "[ACTION] kserve를 Managed로 패치 필요"
  oc patch dsc default-dsc --type=merge \
    -p '{"spec":{"components":{"kserve":{"managementState":"Managed"}}}}'
fi
~~~

### 4. User Workload Monitoring 확인

~~~bash
UWM=$(oc get configmap cluster-monitoring-config -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep enableUserWorkload)
echo "UWM 설정: ${UWM}"

if [[ -z "${UWM}" ]] || ! echo "${UWM}" | grep -q "true"; then
  echo "[ACTION] UWM 활성화 필요"
  oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
  oc wait pod --all -n openshift-user-workload-monitoring \
    --for=condition=Ready --timeout=120s 2>/dev/null || \
    echo "INFO: UWM Pod 대기 중 — 최초 활성화 시 최대 2분 소요"
fi
~~~

### 5. Red Hat Connectivity Link Operator 설치

~~~bash
oc create namespace kuadrant-system --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: connectivity-link-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: connectivity-link-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "Connectivity Link Operator 설치 대기 (최대 3분)..."
for i in $(seq 1 18); do
  CSV_PHASE=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | \
    grep connectivity-link | awk '{print $NF}')
  if [[ "${CSV_PHASE}" == "Succeeded" ]]; then
    echo "[PASS] Connectivity Link Operator 설치 완료"
    break
  fi
  echo "  대기 중... (${i}/18)"
  sleep 10
done
~~~

### 6. Kuadrant CR 생성

~~~bash
oc apply -f - <<'EOF'
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
spec: {}
EOF

echo "Kuadrant CR Ready 대기..."
for i in $(seq 1 30); do
  READY=$(oc get kuadrant kuadrant -n kuadrant-system \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "${READY}" == "True" ]]; then
    echo "[PASS] Kuadrant Ready"
    break
  fi
  echo "  대기 중... (${i}/30)"
  sleep 10
done
~~~

### 7. MaaS용 PostgreSQL DB Secret 생성

MaaS API Key 검증에 PostgreSQL 14+ 필요. DB는 클러스터 외부 또는 내부에 미리 프로비저닝되어 있어야 한다.

~~~bash
: "${MAAS_DB_HOST:?MAAS_DB_HOST 미정의}"
: "${MAAS_DB_PORT:=5432}"
: "${MAAS_DB_NAME:=maas}"
: "${MAAS_DB_USER:=maas}"
: "${MAAS_DB_PASSWORD:?MAAS_DB_PASSWORD 미정의}"

oc apply -n redhat-ods-applications -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: maas-db-config
type: Opaque
stringData:
  host: "${MAAS_DB_HOST}"
  port: "${MAAS_DB_PORT}"
  database: "${MAAS_DB_NAME}"
  username: "${MAAS_DB_USER}"
  password: "${MAAS_DB_PASSWORD}"
EOF
echo "[PASS] maas-db-config Secret 생성 완료"
~~~

## 검증

~~~bash
echo "=== Sprint 1 검증 ==="

echo "1) OCP 버전:"
oc get clusterversion version -o jsonpath='{.status.desired.version}'
echo ""

echo "2) RHOAI CSV:"
oc get csv -n redhat-ods-operator --no-headers | grep rhods

echo "3) kserve 상태:"
oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.managementState}'
echo ""

echo "4) UWM 상태:"
oc get pods -n openshift-user-workload-monitoring --no-headers | head -3

echo "5) Connectivity Link Operator:"
oc get csv -n openshift-operators --no-headers | grep connectivity-link

echo "6) Kuadrant Ready:"
oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
echo ""

echo "7) maas-db-config Secret:"
oc get secret maas-db-config -n redhat-ods-applications --no-headers 2>/dev/null && echo "[PASS]" || echo "[FAIL]"
~~~

## 실패 시

- **OCP 4.19.9 미만** → MaaS는 4.19.9+ 필수. OCP 업그레이드 필요
- **Connectivity Link CSV 미전환** → `oc get installplan -n openshift-operators` 확인, Manual 승인 여부 점검
- **Kuadrant Not Ready** → `oc describe kuadrant kuadrant -n kuadrant-system` 로 상태 메시지 확인
- **maas-db-config 연결 실패** → PostgreSQL 14+ 인스턴스 접근 가능 여부 확인 (네트워크, 인증)

## 다음 단계

→ `runbooks/362-maas-gateway-tls.md`

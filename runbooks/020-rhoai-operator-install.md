# 020 — OpenShift AI (RHOAI) Operator 설치

## 목적

Red Hat OpenShift AI Operator(rhods-operator)를 클러스터에 설치하고, DataScienceCluster를 적용하여 AI 워크벤치·대시보드가 정상 동작하는지 확인한다.

## 전제 조건

- [ ] `runbooks/010-argocd-operator-install.md` 완료 — ArgoCD v1.20.1 CSV Succeeded 확인
- [ ] `.env` 파일 존재 및 `CLUSTER_API_URL`, `OCP_ADMIN_USER`, `OCP_ADMIN_PASSWORD` 값 채워짐
- [ ] `infra/rhoai/` 4개 파일 존재 (namespace, operator-group, subscription, datasciencecluster)

## 실행

### 0. 환경 변수 로드 및 로그인

~~~bash
set -a && source .env && set +a

oc login "${CLUSTER_API_URL}" \
  --username="${OCP_ADMIN_USER}" \
  --password="${OCP_ADMIN_PASSWORD}" \
  --insecure-skip-tls-verify=true
~~~

### 1. 기존 RHOAI Operator 설치 여부 확인 (idempotent 전제)

~~~bash
oc get csv -n redhat-ods-operator --insecure-skip-tls-verify=true \
  | grep -i rhods || echo "RHOAI CSV 없음 — 신규 설치 진행"
~~~

### 2. Namespace + OperatorGroup + Subscription 적용

~~~bash
oc apply -f infra/rhoai/namespace.yaml --insecure-skip-tls-verify=true
oc apply -f infra/rhoai/operator-group.yaml --insecure-skip-tls-verify=true
oc apply -f infra/rhoai/subscription.yaml --insecure-skip-tls-verify=true
~~~

### 3. CSV Succeeded 대기 (최대 15분)

~~~bash
# InstallPlan 생성 확인 (30초~2분 소요)
oc get installplan -n redhat-ods-operator --insecure-skip-tls-verify=true

# CSV Succeeded 대기
RHOAI_CSV="$(oc get subscription rhods-operator \
  -n redhat-ods-operator \
  -o jsonpath='{.status.currentCSV}' \
  --insecure-skip-tls-verify=true)"

oc wait "csv/${RHOAI_CSV}" \
  -n redhat-ods-operator \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=900s \
  --insecure-skip-tls-verify=true
~~~

### 4. DataScienceCluster 적용

~~~bash
oc apply -f infra/rhoai/datasciencecluster.yaml --insecure-skip-tls-verify=true
~~~

### 5. DataScienceCluster Ready 대기 (최대 15분)

~~~bash
oc wait datasciencecluster default-dsc \
  --for=condition=Ready \
  --timeout=900s \
  --insecure-skip-tls-verify=true
~~~

### 6. Proxy 전파 확인 (constraints.md — Proxy 오브젝트 존재)

~~~bash
# httpProxy/httpsProxy 미설정이면 추가 조치 불필요
oc get proxy cluster -o jsonpath='{.spec.httpProxy}' --insecure-skip-tls-verify=true && echo ""
oc get proxy cluster -o jsonpath='{.spec.httpsProxy}' --insecure-skip-tls-verify=true && echo ""
~~~

## 검증

~~~bash
# CSV Succeeded 확인
oc get csv -n redhat-ods-operator --insecure-skip-tls-verify=true | grep rhods

# DataScienceCluster 상태 확인
oc get datasciencecluster default-dsc --insecure-skip-tls-verify=true

# RHOAI 관련 네임스페이스 확인
oc get namespace --insecure-skip-tls-verify=true \
  | grep -E "redhat-ods|rhods"

# RHOAI Dashboard Route URL 확인
oc get route rhods-dashboard \
  -n redhat-ods-applications \
  -o jsonpath='{.spec.host}' \
  --insecure-skip-tls-verify=true && echo ""

# 전체 Pod 상태 확인
oc get pods -n redhat-ods-operator --insecure-skip-tls-verify=true
oc get pods -n redhat-ods-applications --insecure-skip-tls-verify=true | head -20
~~~

성공 기준:
- CSV 상태: `Succeeded`
- DataScienceCluster `default-dsc`: `Ready`
- `rhods-dashboard` Route가 출력됨
- `redhat-ods-operator` 네임스페이스 Pod 전체 `Running`

## 실패 시

- **CSV가 `Installing`에서 멈춤** → `oc get installplan -n redhat-ods-operator` 확인. `oc describe installplan <name>` 으로 에러 확인.
- **Subscription의 `currentCSV`가 비어 있음** → `oc describe subscription rhods-operator -n redhat-ods-operator` 로 CatalogSource/채널 오류 확인.
- **DataScienceCluster가 `Progressing`에서 멈춤** → `oc describe datasciencecluster default-dsc` 로 conditions 확인. 개별 컴포넌트 Pod 상태 점검.
- **`rhods-dashboard` Route 없음** → `oc get routes -n redhat-ods-applications` 로 실제 Route 이름 확인.
- **ImagePullBackOff** → `oc describe pod <pod> -n redhat-ods-operator` 로 레지스트리 접근 오류 확인. pull-secret 누락 가능성.

## 완료 후 기록

설치 성공 시 다음 값을 기록:
- `claude-context/version-matrix.md` — RHOAI 상태 `✅ 설치됨` 갱신
- `claude-context/current-state.md` — RHOAI 체크박스 ✅ + Dashboard URL 기록

## 다음 단계

→ `runbooks/030-argocd-app-sync.md` — ArgoCD Application 등록 / diff / sync

# 010 — OpenShift GitOps (ArgoCD) Operator 설치

## 목적

OpenShift GitOps Operator를 클러스터에 설치하고, 기본 ArgoCD 인스턴스(`openshift-gitops` 네임스페이스)가 정상 동작하는지 확인한다. 이후 모든 Operator·애플리케이션 배포는 ArgoCD를 통해 관리된다.

## 전제 조건

- [ ] `runbooks/000-preflight.md` 완료 — 클러스터 접근 가능 확인
- [ ] `runbooks/001-cluster-survey.md` 완료 — Phase 1 survey 완료 (OpenShift GitOps 미설치 확인)
- [ ] `.env` 파일 존재 및 `CLUSTER_API_URL`, `OCP_ADMIN_USER`, `OCP_ADMIN_PASSWORD` 값 채워짐
- [ ] `infra/argocd/namespace.yaml`, `infra/argocd/subscription.yaml` 존재

## 실행

### 0. 환경 변수 로드 및 로그인

~~~bash
set -a && source .env && set +a

oc login "${CLUSTER_API_URL}" \
  --username="${OCP_ADMIN_USER}" \
  --password="${OCP_ADMIN_PASSWORD}" \
  --insecure-skip-tls-verify=true
~~~

### 1. 기존 GitOps Operator 설치 여부 확인 (idempotent 전제)

~~~bash
oc get csv -n openshift-operators --insecure-skip-tls-verify=true \
  | grep -i gitops || echo "GitOps CSV 없음 — 신규 설치 진행"
~~~

### 2. Subscription 적용

~~~bash
# openshift-operators 네임스페이스에 global-operators OperatorGroup이 이미 존재함
# 별도 OperatorGroup 생성 불필요
oc apply -f infra/argocd/namespace.yaml --insecure-skip-tls-verify=true
oc apply -f infra/argocd/subscription.yaml --insecure-skip-tls-verify=true
~~~

### 3. CSV 완료 대기

~~~bash
# Automatic 승인이므로 자동 처리됨 — CSV Succeeded 대기 (최대 10분)
oc wait csv \
  -n openshift-operators \
  -l operators.coreos.com/openshift-gitops-operator.openshift-operators \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=600s \
  --insecure-skip-tls-verify=true
~~~

### 4. ArgoCD 기본 인스턴스 기동 대기

~~~bash
# Operator가 openshift-gitops 네임스페이스와 ArgoCD 인스턴스를 자동 생성
oc wait deployment openshift-gitops-server \
  -n openshift-gitops \
  --for=condition=Available \
  --timeout=300s \
  --insecure-skip-tls-verify=true
~~~

### 5. Proxy 전파 확인 (constraints.md — Proxy 오브젝트 존재)

~~~bash
# Proxy httpProxy/httpsProxy 값이 비어있으면 추가 조치 불필요
oc get proxy cluster -o jsonpath='{.spec.httpProxy}' --insecure-skip-tls-verify=true && echo ""
oc get proxy cluster -o jsonpath='{.spec.httpsProxy}' --insecure-skip-tls-verify=true && echo ""

# ArgoCD 컨트롤러 환경변수에 proxy가 주입되었는지 확인
oc set env deployment/openshift-gitops-application-controller \
  -n openshift-gitops --list --insecure-skip-tls-verify=true \
  | grep -iE "proxy|PROXY" || echo "Proxy 환경변수 없음 (httpProxy 미설정이면 정상)"
~~~

## 검증

~~~bash
# CSV Succeeded 확인
oc get csv -n openshift-operators --insecure-skip-tls-verify=true \
  | grep openshift-gitops-operator

# ArgoCD Route URL 확인
oc get route openshift-gitops-server \
  -n openshift-gitops \
  -o jsonpath='{.spec.host}' \
  --insecure-skip-tls-verify=true && echo ""

# 전체 Pod Running 확인
oc get pods -n openshift-gitops --insecure-skip-tls-verify=true
~~~

성공 기준:
- CSV 상태: `Succeeded`
- `openshift-gitops-server` Route가 출력됨
- `openshift-gitops` 네임스페이스 Pod 전체 `Running`

## 실패 시

- **CSV가 `Installing`에서 멈춤** → `oc get installplan -n openshift-operators` 로 승인 대기 여부 확인. `installPlanApproval: Automatic`이면 자동 처리되어야 함. `oc describe installplan <name>` 으로 에러 확인.
- **`openshift-gitops-server` Deployment not found** → CSV Succeeded 이후 2~3분 대기 후 재확인. Operator reconcile 지연일 수 있음.
- **ArgoCD Pod `ImagePullBackOff`** → `oc describe pod <pod> -n openshift-gitops` 로 레지스트리 접근 오류 확인. pull-secret 미설정 가능성. `constraints.md` 참조.
- **Proxy 관련 git 연결 실패** → `httpProxy`/`httpsProxy` 값이 설정된 경우 ArgoCD Deployment에 proxy 환경변수 수동 주입 필요. `oc edit deployment openshift-gitops-server -n openshift-gitops` 로 `env` 블록 추가.

## 완료 후 기록

설치 성공 시 다음 값을 `claude-context/version-matrix.md`에 기록:
- OpenShift GitOps 채널: `latest`
- CSV 버전: `oc get csv -n openshift-operators | grep gitops` 출력값

## 다음 단계

→ `runbooks/020-rhoai-operator-install.md` — OpenShift AI Operator 설치

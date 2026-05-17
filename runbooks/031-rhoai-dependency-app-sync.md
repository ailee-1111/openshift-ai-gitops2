# 031 — RHOAI dependency Application 등록 / diff / sync

## 목적

Scope 3에서 RHOAI 의존성인 JobSet Operator, LeaderWorkerSet Operator, MaaS Gateway를 ArgoCD Application으로 인계한다.

Scope 2에서 `rhoai` Application은 이미 `Synced/Healthy`로 확인되었다. 이 runbook은 그 다음 단계로, Session 14에서 직접 적용된 의존성 리소스를 작은 Application 단위로 등록하고 `prune=false`로 안전하게 sync한다.

## 전제 조건

- [ ] `runbooks/030-argocd-app-sync.md` 완료 — `rhoai` Application `Synced/Healthy`
- [ ] `default-dsc` Ready=True
- [ ] `infra/argocd/applications/{jobset,lws,maas-gateway}.yaml` 존재
- [ ] `infra/argocd/rbac/platform-operators-cluster-cr.yaml` 존재
- [ ] `infra/operators/job-set`, `infra/operators/leader-worker-set`, `infra/rhoai/gateway`가 live와 drift 0
- [ ] 로컬 커밋이 GitHub `main`에 push되어 ArgoCD가 읽을 수 있음
- [ ] 사람의 Scope 3 진행 승인 (CHECKPOINT)

## 실행

### 0. 환경 변수 로드 및 로그인

~~~bash
set -a && source .env && set +a

oc login "${CLUSTER_API_URL}" \
  --username="${OCP_ADMIN_USER}" \
  --password="${OCP_ADMIN_PASSWORD}" \
  --insecure-skip-tls-verify=true
~~~

### 1. 로컬 렌더링 검증

~~~bash
kubectl kustomize infra/argocd/bootstrap
kubectl kustomize infra/operators/job-set
kubectl kustomize infra/operators/leader-worker-set
kubectl kustomize infra/rhoai/gateway
~~~

### 2. live drift 확인

~~~bash
oc diff -f infra/operators/job-set/jobset-operator.yaml \
  --insecure-skip-tls-verify=true

oc diff -f infra/operators/leader-worker-set/leader-worker-set-operator.yaml \
  --insecure-skip-tls-verify=true

oc diff -f infra/rhoai/gateway/maas-default-gateway.yaml \
  --insecure-skip-tls-verify=true
~~~

기대값: 세 명령 모두 exit 0. 차이가 있으면 Application 등록 전에 IaC와 live 중 어느 쪽이 authoritative인지 판단한다.

### 3. bootstrap dry-run

~~~bash
oc apply -k infra/argocd/bootstrap \
  --dry-run=server \
  --insecure-skip-tls-verify=true
~~~

### 4. Application 등록

~~~bash
oc apply -k infra/argocd/bootstrap \
  --insecure-skip-tls-verify=true
~~~

### 5. Application 상태 확인

~~~bash
oc -n openshift-gitops get applications.argoproj.io jobset lws maas-gateway \
  --insecure-skip-tls-verify=true
~~~

기대값: `Healthy`이고, sync 전에는 `OutOfSync` 또는 `Synced`일 수 있다.

### 6. sync 실행 (사람 승인 후)

~~~bash
argocd app sync jobset --prune=false
argocd app sync lws --prune=false
argocd app sync maas-gateway --prune=false
~~~

`--prune=false`를 명시한다. 부트스트랩 단계에서 직접 적용된 live 리소스가 누락되었을 때 자동 삭제되는 것을 막기 위함이다.

`argocd` CLI가 없으면 동일한 sync를 Application operation patch로 요청한다.

~~~bash
oc -n openshift-gitops patch applications.argoproj.io jobset --type=merge \
  -p '{"operation":{"sync":{"prune":false,"syncOptions":["Prune=false","ServerSideApply=true"]}}}' \
  --insecure-skip-tls-verify=true

oc -n openshift-gitops patch applications.argoproj.io lws --type=merge \
  -p '{"operation":{"sync":{"prune":false,"syncOptions":["Prune=false","ServerSideApply=true"]}}}' \
  --insecure-skip-tls-verify=true

oc -n openshift-gitops patch applications.argoproj.io maas-gateway --type=merge \
  -p '{"operation":{"sync":{"prune":false,"syncOptions":["Prune=false","ServerSideApply=true"]}}}' \
  --insecure-skip-tls-verify=true
~~~

### 7. 완료 확인

~~~bash
oc -n openshift-gitops wait applications.argoproj.io/jobset \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=600s \
  --insecure-skip-tls-verify=true

oc -n openshift-gitops wait applications.argoproj.io/lws \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=600s \
  --insecure-skip-tls-verify=true

oc -n openshift-gitops wait applications.argoproj.io/maas-gateway \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=600s \
  --insecure-skip-tls-verify=true

oc -n openshift-gitops get applications.argoproj.io jobset lws maas-gateway \
  --insecure-skip-tls-verify=true
~~~

### 8. RHOAI 영향 재확인

~~~bash
oc get datasciencecluster default-dsc \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}' \
  --insecure-skip-tls-verify=true
~~~

기대값: `Ready=True`, `ComponentsReady=True`.

## 검증

성공 기준:

- `jobset`, `lws`, `maas-gateway` Application이 `Synced/Healthy`
- `default-dsc Ready=True` 유지
- JobSet/LWS/MaaS Gateway live drift 0 유지

## 실패 시

- **JobSet/LWS sync 권한 오류** → `infra/argocd/rbac/platform-operators-cluster-cr.yaml`가 적용되었는지 확인한다.
- **MaaS Gateway sync 권한 오류** → `infra/argocd/rbac/platform-operators-maas-gateway.yaml`의 ClusterRole/ClusterRoleBinding이 적용되었는지 확인한다.
- **Application repo 조회 실패** → 로컬 커밋이 GitHub `main`에 push되었는지 확인한다.
- **Gateway diff 발생** → operator 또는 gateway controller가 주입한 필드인지 확인하고, 필요하면 Application의 `ignoreDifferences`를 추가한다.
- **DSC NotReady** → JobSet/LWS/MaaS Gateway condition과 `default-dsc` condition을 함께 확인한다.

## 완료 후 기록

- `claude-context/current-state.md`에 Scope 3 완료와 Application 상태 기록
- `claude-context/active-task.md`를 Scope 4 PoC Application 편입으로 갱신
- `claude-context/handoff-notes.md`에 최대 10줄로 handoff 기록

## 다음 단계

→ `runbooks/100-platform-setup.md`

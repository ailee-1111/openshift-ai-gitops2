# 030 — ArgoCD Application 등록 / diff / sync

## 목적

부트스트랩 단계에서 직접 `oc apply`로 클러스터에 적용된 RHOAI IaC를, ArgoCD가 인계받아 GitOps 방식으로 관리·sync 하도록 전환한다. 운영 모드(OPS) 트리거의 첫 실행 단계.

## 전제 조건

- [ ] `runbooks/010-argocd-operator-install.md` 완료 — `openshift-gitops` 네임스페이스 Pod 전체 Running
- [ ] `runbooks/020-rhoai-operator-install.md` 완료 — `default-dsc` Ready=True
- [ ] `infra/rhoai/datasciencecluster.yaml` 가 live와 정합 — `oc diff -f infra/rhoai/datasciencecluster.yaml` exit 0 (Session 15에서 정합화 완료)
- [ ] `infra/argocd/applications/rhoai.yaml` 존재
- [ ] 사람의 운영 모드 전환 승인 (CHECKPOINT)
- [ ] `infra/argocd/applications/rhoai.yaml`의 `repoURL` 이 ArgoCD가 접근 가능한 실제 https URL
- [ ] `.env`의 `GITHUB_REMOTE` 가 Application `repoURL`과 일치

## 실행

### 0. 환경 변수 로드 및 로그인

~~~bash
set -a && source .env && set +a

oc login "${CLUSTER_API_URL}" \
  --username="${OCP_ADMIN_USER}" \
  --password="${OCP_ADMIN_PASSWORD}" \
  --insecure-skip-tls-verify=true
~~~

### 1. Application 매니페스트의 repoURL 확인

~~~bash
# placeholder가 남아 있으면 절대 적용하지 않음.
grep -n "REPLACE-ORG\\|<org>\\|placeholder" infra/argocd/applications/rhoai.yaml \
  && { echo "repoURL placeholder 미치환 — 중단"; exit 1; } \
  || echo "repoURL placeholder 없음"

APP_REPO_URL="$(awk '$1 == "repoURL:" { print $2; exit }' infra/argocd/applications/rhoai.yaml)"
test -n "${APP_REPO_URL}" && test "${APP_REPO_URL}" != "null"

if [ -n "${GITHUB_REMOTE:-}" ] && [ "${GITHUB_REMOTE}" != "${APP_REPO_URL}" ]; then
  echo "GITHUB_REMOTE(${GITHUB_REMOTE}) != Application repoURL(${APP_REPO_URL}) — 확인 필요"
  exit 1
fi
~~~

### 2. (선택) ArgoCD repo connection 사전 점검

private repo면 ArgoCD에 인증 정보가 등록되어 있어야 한다. UI: ArgoCD → Settings → Repositories. 또는:

~~~bash
oc -n openshift-gitops get secret -l argocd.argoproj.io/secret-type=repository \
  --insecure-skip-tls-verify=true
~~~

repository secret이 없으면 운영 모드 진행 전에 먼저 등록할 것.

### 3. Application 등록 (dry-run 먼저)

~~~bash
# server-side dry-run — 실제 등록 없이 검증
oc apply -f infra/argocd/applications/rhoai.yaml \
  --dry-run=server \
  --insecure-skip-tls-verify=true

# 통과하면 실제 적용
oc apply -f infra/argocd/applications/rhoai.yaml \
  --insecure-skip-tls-verify=true
~~~

### 4. 초기 sync 상태 확인 (자동 sync 비활성화 상태)

~~~bash
oc -n openshift-gitops get application rhoai \
  -o jsonpath='{.status.sync.status}{"\t"}{.status.health.status}{"\n"}' \
  --insecure-skip-tls-verify=true
~~~

기대값: `OutOfSync` 또는 `Synced`. `Healthy` 이어야 한다. 본 시점은 `automated` sync가 꺼져 있으므로 **사람이 명시적으로 sync를 트리거**한다.

### 5. diff 검토 (drift 있는지 확인)

~~~bash
# argocd CLI 또는 oc 둘 중 하나
# (a) argocd CLI 사용 시
argocd app diff rhoai

# (b) argocd CLI 미설치 시 oc로 비교
oc -n openshift-gitops get application rhoai -o yaml --insecure-skip-tls-verify=true \
  | yq '.status.resources[] | select(.status != "Synced") | {kind, name, namespace, status}'
~~~

기대값: 차이 없음 (Session 15 정합화로 drift 0). 차이가 있다면 **sync 전에 원인을 조사**:
- IaC가 빠뜨린 필드?
- 운영자(operator)가 자동 주입한 필드?
- 다른 도구가 동시에 변경?

### 6. sync 실행 (사람 승인 후)

~~~bash
# argocd CLI 사용
argocd app sync rhoai --prune=false --dry-run

# 문제 없으면 실제 sync
argocd app sync rhoai --prune=false
~~~

`--prune=false`를 명시한다. 부트스트랩에서 직접 apply된 리소스가 IaC에 빠져 있을 경우 자동 삭제를 막기 위함.

### 7. sync 완료 확인

~~~bash
oc -n openshift-gitops wait application/rhoai \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=600s \
  --insecure-skip-tls-verify=true

oc -n openshift-gitops wait application/rhoai \
  --for=jsonpath='{.status.health.status}'=Healthy \
  --timeout=600s \
  --insecure-skip-tls-verify=true
~~~

### 8. DSC 영향 재확인

~~~bash
oc get datasciencecluster default-dsc \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}' \
  --insecure-skip-tls-verify=true
~~~

기대값: `Ready=True`, `ComponentsReady=True`. sync 직후 일시 NotReady 가능 — 5~10분 재확인.

## 검증

성공 기준:
- `oc -n openshift-gitops get application rhoai` → `Sync: Synced`, `Health: Healthy`
- `oc diff -f infra/rhoai/datasciencecluster.yaml` exit 0 (drift 0 유지)
- `default-dsc Ready=True`

## 실패 시

- **Application이 OutOfSync에서 풀리지 않음** → step 5 diff 결과 정밀 분석. live가 IaC보다 더 많은 필드를 가지고 있다면 IaC 측에 보강 필요. live가 빠진 필드를 가지고 있다면 운영자 자동 주입 — `ignoreDifferences`로 해결.
- **sync 후 DSC NotReady** → `oc describe dsc default-dsc` 컨디션 확인. 의존성(JobSet/LWS/MaaS Gateway)이 ArgoCD 외부에서 관리되고 있다면 직접 적용 상태 유지 — Session 14에서 보강된 의존성을 sync가 prune하지 않는지 확인 (`--prune=false` 보장).
- **repoURL 인증 실패** → step 2의 repository secret 확인. SSH 키/토큰 만료 가능성.
- **repoURL 확인 실패 (step 1 차단)** → `.env`의 `GITHUB_REMOTE`와 `infra/argocd/applications/rhoai.yaml`의 `repoURL` 일치 여부를 확인 후 재실행.

## 완료 후 기록

- `claude-context/current-state.md` 미결사항에서 "App-of-Apps/ArgoCD 소유권 구조 미완성" 항목 갱신 (rhoai 단일 Application은 owned)
- `claude-context/version-matrix.md` 에 ArgoCD 관리 범위 추가

## 다음 단계

→ `runbooks/031-rhoai-dependency-app-sync.md` — RHOAI 의존성(JobSet/LWS/MaaS Gateway) Application 등록

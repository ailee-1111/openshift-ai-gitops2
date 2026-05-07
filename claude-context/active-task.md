# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**Scope 4: PoC Application 편입**

**다음 진입지점 (Session 28 기록):** Scope 4 IaC 작성은 Session 27에서 완료했다(`workbench-smoke.yaml`, `llm-cpu.yaml`). 클러스터가 현재 미확보 상태이므로, 클러스터 확보 후 바로 실행한다: `oc apply --dry-run=server -k infra/argocd/bootstrap` → `oc apply` → sync → `Synced/Healthy` 확인. 클러스터 확보 전까지는 문서/IaC 정합성 검토와 Scope 5 준비만 진행한다.

Session 18에서 `ai-accelerator` 참고 패턴을 검토하고, 한 번에 ApplicationSet으로 흡수하지 않도록 `work-plans/002-gitops-handover-scope.md`에 Scope 0~5 단계 계획을 추가했다.

Session 19에서 Scope 1을 완료했다. `infra/argocd/bootstrap/kustomization.yaml`, AppProject 3개(`platform-operators`, `rhoai-core`, `rhoai-poc`), `rhoai` Application의 `rhoai-core` 프로젝트 편입, repo config replacement 패턴을 작성했고 `kubectl kustomize` 및 `oc apply --dry-run=client -k infra/argocd/bootstrap` 검증을 통과했다.

Session 20~22에서 Scope 2를 완료했다. `rhoai` Application은 ArgoCD `Synced/Healthy`, `default-dsc Ready=True`, `oc diff` exit 0이며 PoC 워크벤치/CPU LLM 영향 없음.

Session 23에서 Scope 3을 완료했다. `jobset`, `lws`, `maas-gateway` Application은 모두 ArgoCD `Synced/Healthy`이며, `default-dsc Ready=True`, JobSet/LWS/Gateway drift 0을 확인했다. MaaS Gateway sync에는 ArgoCD application-controller의 Gateway API patch 권한이 필요해 `infra/argocd/rbac/platform-operators-maas-gateway.yaml` ClusterRole/Binding으로 보강했다.

다음 세션은 **Scope 4: PoC(`workbench-smoke`, `llm-cpu`) Application 편입**만 진행한다. 실제 `oc apply` 또는 sync는 CHECKPOINT 승인 후 실행한다. Session 26에서는 승인 전 기록 요청으로 실행하지 않았다.

## 성공 기준 (Capabilities)

- [x] Scope 1~3 완료 — repoURL 정합화, AppProject/repo config/root bootstrap, `rhoai`, `jobset`, `lws`, `maas-gateway` Application `Synced/Healthy`
- [x] RHOAI/의존성 기준선 유지 — `default-dsc Ready=True`, RHOAI/JobSet/LWS/Gateway drift 0
- [x] CPU LLM PoC IaC 작성·적용 및 `/v1/models`, `/v1/completions` smoke 검증 완료
- [x] [CHECKPOINT] Scope 4 진행 승인 확인 (Session 28)
- [x] Scope 4 편입 방식 결정 — 각각 별도 Application으로 분리 (Session 27)
- [x] `infra/argocd/applications`에 PoC Application IaC 작성 (Session 27)
- [ ] `oc apply --dry-run=server -k infra/argocd/bootstrap` 검증 — **클러스터 확보 후**
- [ ] PoC Application 등록 후 `Synced/Healthy` 확인 — **클러스터 확보 후**
- [ ] 워크벤치 Pod와 CPU LLM InferenceService smoke 상태 유지 확인 — **클러스터 확보 후**

## 범위별 체크리스트

- [x] Scope 0: 계획과 체크리스트 정리. 클러스터 변경 없음.
- [x] Scope 1: ArgoCD 관리 뼈대 정리. AppProject, repo config, root/bootstrap 구조만 준비.
- [x] Scope 2: `infra/rhoai` 단일 Application diff/sync 검증. `prune=false`.
- [x] Scope 3: RHOAI 의존성(JobSet/LWS/MaaS Gateway) Application 편입.
- [ ] Scope 4: PoC(`workbench-smoke`, `llm-cpu`) Application 편입.
- [ ] Scope 5: 전체 Synced/Healthy와 drift 0 확인 후 BOOTSTRAP 완료 판단.

## 후속 태스크 (운영 트리거 완료 이후)

- [ ] ApplicationSet 승격 검토 — Scope 2~4 안정화 이후
- [ ] `automated.prune/selfHeal` 활성화 검토 (drift 안정화 후)
- [ ] PoC 항목 결정 (Phase 5) — 후보 백로그는 `work-plans/003-test-capability-catalog.md` 참조. 현재 Scope 4 태스크를 대체하지 않음.

## 참조 (Required Inputs)

- `work-plans/002-gitops-handover-scope.md` — GitOps 인계 범위와 단계별 편입 계획
- `work-plans/003-test-capability-catalog.md` — Scope 4/5 이후 승격할 후속 테스트 후보 카탈로그 (현재 실행 Scope 아님)
- `runbooks/30-argocd-app-sync.md` — ArgoCD Application 등록/diff/sync 표준 절차
- `infra/argocd/bootstrap/kustomization.yaml` — Scope 1에서 작성한 repo config/AppProject/Application 묶음
- `infra/argocd/applications/rhoai.yaml` — RHOAI Application CR (repoURL 치환 완료)
- `infra/argocd/rbac/rhoai-dsc-application-controller.yaml` — Scope 2에서 추가한 DSC 전용 ArgoCD RBAC
- `infra/argocd/applications/{jobset,lws,maas-gateway}.yaml` — Scope 3에서 등록한 RHOAI 의존성 Application
- `infra/argocd/rbac/platform-operators-{cluster-cr,maas-gateway}.yaml` — Scope 3에서 보강한 ArgoCD sync RBAC
- `infra/operators/job-set/`, `infra/operators/leader-worker-set/`, `infra/rhoai/gateway/` — Scope 3 편입 완료 대상
- `infra/rhoai/datasciencecluster.yaml` — Session 15에서 v2 live 스펙과 정합화 (drift 0)
- `infra/poc/llm-cpu/` — CPU LLM PoC IaC
- `infra/poc/workbench-smoke/` — 워크벤치 스모크 PoC IaC
- `runbooks/60-a-llm-cpu.md` — CPU LLM 검증 절차
- `.env` — `GITHUB_REMOTE` 확인 대상
- `claude-context/current-state.md` — Session 15 종료 시점 클러스터 상태
- `CLAUDE.md` — BOOTSTRAP/OPS 단계별 권한 경계

## 블로커 (Constraints)

- **클러스터 미확보** — 현재 접속 가능한 클러스터가 없다. Scope 4 실행과 Scope 5는 클러스터 확보 후 진행.
- ArgoCD가 사용할 Git 원격은 public 접근 가능하므로 현재 repository secret은 불필요. 단, 로컬 커밋을 GitHub `main`에 push해야 ArgoCD가 읽을 수 있다.
- `oc get application`은 OpenShift `applications.app.k8s.io`로 해석될 수 있으므로 ArgoCD Application 조회는 `applications.argoproj.io`를 명시한다.
- OPS 전환은 사람만 발동하며, 초기 구축 완료 선언도 사람 판단
- 한 번에 ApplicationSet으로 흡수하지 않는다. Scope 단위 CHECKPOINT와 체크리스트 갱신 후 진행한다.
- sync 후 운영자 자동 주입 필드와의 drift 가능성 — 발생 시 `ignoreDifferences` 적용
- `--prune=false` 보장 필요 — Session 14에서 직접 적용된 의존성(JobSet/LWS/MaaS Gateway)이 IaC에 빠져 있을 경우 자동 삭제 방지
- ArgoCD Application 조회/대기는 `applications.argoproj.io`를 명시한다. `application/...` 축약형은 OpenShift `applications.app.k8s.io`로 오인될 수 있다.
- `argocd` CLI가 없으면 Application `operation.sync` patch로 수동 sync를 요청한다.
- CPU LLM은 vLLM CPU x86 런타임이며 GPU request 없음. 초기 OOM 방지를 위해 `VLLM_CPU_KVCACHE_SPACE=2`, `--max-model-len=1024`, `Recreate` 전략 사용.

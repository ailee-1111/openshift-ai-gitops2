# GitOps 인계 범위와 단계별 편입 계획

- 작성일: 2026-04-30
- 최종 수정: 2026-05-07

## Why (왜 이 결정이 필요한가)

현재 클러스터는 BOOTSTRAP 단계에서 RHOAI 기준선, 의존성(JobSet/LWS/MaaS Gateway), PoC 워크벤치, CPU LLM 모델까지 직접 적용해 정상 상태를 확보했다. 그러나 이 상태를 한 번에 ArgoCD ApplicationSet으로 흡수하면 sync drift, prune 위험, Application 소유권 충돌, PoC 장애 원인 추적 난이도가 동시에 커진다.

따라서 운영 전환 전 작업 범위를 작게 나누고, 각 범위마다 체크리스트와 rollback 판단 지점을 둔다. `ai-accelerator` 저장소의 bootstrap/cluster/components 분리와 repoURL 주입 패턴은 참고하되, 본 프로젝트의 4계층 문서 체계와 현재 live cluster 상태를 우선한다.

## How (어떤 옵션이 있고, 어떻게 할 것인가)

### 옵션 A — 단일 App-of-Apps로 한 번에 편입

`infra/argocd/bootstrap` 아래 root Application을 만들고 RHOAI, 의존성, PoC를 한 번에 연결한다.

### 옵션 B — 개별 Application을 순차 등록

`infra/argocd/applications`에 리소스 묶음별 Application을 만들고, `rhoai` → 의존성 → PoC 순서로 등록·diff·sync한다.

### 옵션 C — ApplicationSet 중심 편입

`ai-accelerator`처럼 ApplicationSet으로 `operators`, `rhoai`, `poc` 묶음을 생성하고, repoURL/targetRevision은 ConfigMap replacement로 주입한다.

### 선택한 진행 방식

옵션 B를 1차 경로로 선택하고, 옵션 C의 repoURL/targetRevision 주입 패턴만 선별 도입한다. 즉, 자동 생성 구조를 처음부터 크게 만들지 않고, 작은 Application 단위로 정상 동작을 확인한 뒤 ApplicationSet으로 승격한다.

작업 범위는 다음 순서로 제한한다.

- Scope 0: 계획과 체크리스트 정리. 클러스터 변경 없음.
- Scope 1: ArgoCD 관리 뼈대 정리. AppProject, repo config, root/bootstrap 구조만 작성하고 sync는 하지 않음.
- Scope 2: `infra/rhoai` 단일 Application diff/sync 검증. `prune=false`.
- Scope 3: RHOAI 의존성 Application 편입. JobSet, LeaderWorkerSet, MaaS Gateway를 각각 또는 작은 묶음으로 등록.
- Scope 4: PoC Application 편입. `workbench-smoke`, `llm-cpu`를 별도 Application으로 등록.
- Scope 5: 전체 Synced/Healthy와 drift 0 확인 후 사람이 BOOTSTRAP 완료 여부 판단.

각 Scope는 별도 세션 또는 명시적 CHECKPOINT 단위로 진행한다. 다음 Scope로 넘어가기 전 `active-task.md`의 체크리스트를 갱신한다.

## Tradeoffs (각 옵션의 장단점)

| 옵션 | 장점 | 단점 | 판단 |
|---|---|---|---|
| A 단일 App-of-Apps | 구조가 단순하고 최종 형태에 빨리 도달 | 최초 sync 범위가 커서 장애 격리가 어려움 | 지금은 보류 |
| B 개별 Application | drift 원인 격리 쉬움, prune 위험 통제 쉬움 | Application 수가 늘고 반복 작업 발생 | 1차 선택 |
| C ApplicationSet 중심 | 장기 운영 자동화와 환경 overlay에 유리 | 초기 설계 비용과 생성 로직 복잡도 증가 | 2차 승격 후보 |

`ai-accelerator`의 패턴은 대규모 기반 구조에는 적합하지만, 현재 프로젝트는 이미 BOOTSTRAP 직접 적용 산출물이 존재한다. 그러므로 “큰 틀을 수입”하기보다 repo config replacement, AppProject 분리, bootstrap/cluster 책임 분리만 채택한다.

## Decision (무엇을 선택했고 그 이유)

- 결정: **개별 Application 순차 편입 후 ApplicationSet 승격**을 기본 경로로 한다.
- 결정: `prune=false`를 기본값으로 두고, 각 Application이 `Synced/Healthy` 및 live drift 0을 확인한 뒤 다음 범위로 넘어간다.
- 결정: `repoURL`과 `targetRevision`은 가능하면 `ai-accelerator`의 `gitops-repo-config` 유사 패턴으로 중앙화한다.
- 결정: PoC 리소스는 RHOAI core와 분리한다. CPU LLM 모델 장애가 RHOAI 기준선 sync 판단을 흐리지 않게 하기 위함이다.
- 결정: GPU 관련 Application은 이번 편입 범위에서 제외한다. 현재 GPU 노드는 관측되지만 GPU PoC는 Phase 5 판단 사항이다.

## Open Questions (미결 사항)

- [x] `GITHUB_REMOTE` 값이 실제 ArgoCD repoURL과 일치하는가 — `.env`와 `infra/argocd` 모두 `https://github.com/ssgkim/openshift-ai-gitops.git`
- [x] 현재 Git 원격이 public인지 private인지, ArgoCD repository secret이 필요한가 — `git ls-remote` 인증 없이 성공, 현재 기준 repository secret 불필요
- [x] AppProject를 `platform-operators`, `rhoai-core`, `rhoai-poc`로 나눌지 또는 더 단순화할지 — Scope 1에서 3개 AppProject로 분리
- [x] Scope 3에서 JobSet/LWS/MaaS Gateway를 하나의 `rhoai-dependencies` Application으로 묶을지 각각 분리할지 — Session 23에서 각각 분리(`jobset`, `lws`, `maas-gateway`)
- [x] Scope 4에서 PoC Application을 개별 파일로 둘지 ApplicationSet 승격까지 기다릴지 — Session 27에서 개별 파일(`workbench-smoke.yaml`, `llm-cpu.yaml`)로 결정
- [ ] ApplicationSet 승격 시점은 Scope 5 이후로 둘지, Scope 1에서 skeleton만 둘지

## Scope 5 — BOOTSTRAP 완료 판단 체크리스트 (Session 28 추가)

클러스터 확보 후 Scope 4 실행이 완료되면, 아래 체크리스트를 모두 통과해야 사람이 BOOTSTRAP 완료를 선언할 수 있다.

### 5-1. ArgoCD 전체 Application 상태

- [ ] 6개 Application 모두 `Synced/Healthy` — `rhoai`, `jobset`, `lws`, `maas-gateway`, `workbench-smoke`, `llm-cpu`
- [ ] 각 Application의 `oc diff`(또는 ArgoCD diff)에서 의미 있는 drift 없음
- [ ] `ignoreDifferences`가 필요한 필드는 IaC에 사전 반영 완료 (예: Operator 자동 주입 필드)

### 5-2. RHOAI 기준선

- [ ] `default-dsc Ready=True`
- [ ] RHOAI Dashboard Route 접근 가능
- [ ] RHOAI 관련 Pod(dashboard, operator)가 Running 상태

### 5-3. PoC 기능 검증

- [ ] `rhoai-poc-smoke/smoke-wb` Pod Running 2/2, Python 셀 `print(1+1)` 응답
- [ ] `rhoai-poc-llm-cpu/smollm2-135m-cpu` InferenceService Ready=True
- [ ] `/v1/models` 응답에 `smollm2-135m-cpu` 포함
- [ ] `/v1/completions` 텍스트 응답 반환

### 5-4. OPS 전환 조건

- [ ] 위 5-1~5-3 전부 통과
- [ ] 사람이 "BOOTSTRAP 완료" 선언
- [ ] `.claude/settings.local.json`을 OPS 모드 설정으로 전환 (읽기·진단 중심 권한)
- [ ] `claude-context/current-state.md` 환경 표기를 `BOOTSTRAP` → `OPS`로 변경

### 5-5. OPS 전환 후 후속 검토 항목

- [ ] `automated.prune` / `selfHeal` 활성화 여부 결정 (drift 안정 관측 후)
- [ ] ApplicationSet 승격 검토
- [ ] 후속 PoC 항목 선정 (`work-plans/003-test-capability-catalog.md`에서 하나씩 승격)

## References (외부 문서 링크)

- Red Hat AI Accelerator installation — https://github.com/redhat-ai-services/ai-accelerator/blob/main/documentation/installation.md
- Red Hat AI Accelerator overview — https://github.com/redhat-ai-services/ai-accelerator/blob/main/documentation/overview.md
- Red Hat AI Accelerator repository — https://github.com/redhat-ai-services/ai-accelerator
- Red Hat AI Accelerator Examples — https://github.com/redhat-ai-services/ai-accelerator-examples
- Argo CD ApplicationSet documentation — https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/

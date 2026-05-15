# 인수인계 노트

> **이 파일을 읽으면 세션별 완료·진행중·블로커·다음 할 일을 파악할 수 있다.** 형식 및 규칙: `guidelines/03-handoff-protocol.md`. 신규 엔트리는 **파일 하단에 추가**, 기존 엔트리 수정 금지.
> 2026-04-29: 오래된 엔트리는 `claude-context/archive/handoff-2026-Q2.md`로 이관함.

---

## 2026-04-29 Session 10 복구 — 새 샌드박스 survey 발견

- 완료: 중단점 복구 중 `survey-output/survey-20260422-210156.txt` 확인, `current-state.md`/`active-task.md`/`state.md`를 환경 재정렬 대기 상태로 보정
- 진행중: 새 샌드박스를 현재 타깃으로 전환할지 결정 필요
- 블로커: 새 survey는 OCP 4.21.9 / RHOAI 3.4.0-ea.1 / GitOps 미설치 / DSC NotReady이며 기존 version-matrix와 불일치
- 다음 세션이 할 일: 사람이 새 샌드박스 전환 여부와 RHOAI 3.4.0-ea.1 수용 여부 결정
- 발견된 제약: 샌드박스 교체 시 상태 재확정 필요 (`constraints.md` 반영)

---

## 2026-04-29 Session 11 — RHOAI 3.4.0 목표 확정

- 완료: 사용자 결정에 따라 새 샌드박스 RHOAI 목표를 3.4.0으로 확정하고 `version-matrix.md`, `current-state.md`, `active-task.md`, `infra/rhoai/`, `runbooks/20-rhoai-operator-install.md` 반영
- 진행중: 새 샌드박스 Phase 2~4 재검증
- 블로커: survey 기준 GitOps 미설치, `default-dsc NotReady`, 관측 CSV가 `3.4.0-ea.1`
- 다음 세션이 할 일: GitOps 설치 여부 확정 후 `default-dsc NotReady` 원인 조사
- 발견된 제약: RHOAI 3.4.0 목표와 관측 CSV 표기 차이 기록 (`constraints.md` 반영)

---

## 2026-04-29 Session 12 — 클러스터 접근 확인 + DSC 원인 확인

- 완료: 실제 클러스터 로그인, Console/API URL 확인, OpenShift 4.21.9, GitOps 1.20.2, RHOAI 3.4.0-ea.1, Dashboard Route 확인
- 진행중: `default-dsc NotReady` 해소 방향 결정
- 블로커: ModelsAsService는 `maas-default-gateway` 없음, Trainer는 JobSet Operator 없음
- 다음 세션이 할 일: PoC 범위 기준으로 ModelsAsService/Trainer를 Removed 처리할지 의존성 설치할지 결정
- 발견된 제약: DSC NotReady 원인 기록 (`constraints.md` 반영)

---

## 2026-04-29 Session 13 — 운영 유지관리 모드 전환

- 완료: 프로젝트 목적을 부트스트랩 실행에서 운영 유지관리로 재정의하고 `CLAUDE.md`, `README.md`, state/context에 권한 경계 반영
- 진행중: DSC NotReady 해소 방향 결정
- 블로커: 운영 모드에서는 직접 클러스터 변경이 기본 경로가 아니며 Git/IaC + ArgoCD 반영 절차 필요
- 다음 세션이 할 일: ModelsAsService/Trainer 처리 방향을 IaC 변경안으로 정리
- 발견된 제약: 부트스트랩 권한은 예외, 운영 기본 권한은 읽기 진단 중심 (`constraints.md` 반영)

---

## 2026-04-29 Session 14 — RHOAI 의존성 보강 및 DSC Ready 확보

- 완료: JobSet(v1.0.0), LeaderWorkerSet(v1.0.0), `openshift-ingress/maas-default-gateway`를 설치/생성해 `default-dsc` Ready 확인
- 진행중: live DSC v2 스펙과 `infra/rhoai/datasciencecluster.yaml` 정합화 필요
- 블로커: App-of-Apps/ArgoCD 소유권 구조 미완성, PoC 항목 미정
- 다음 세션이 할 일: DSC IaC 정합화 후 워크벤치 1개 생성 및 Python 셀 스모크 검증
- 발견된 제약: JobSet은 `openshift-jobset-operator`, LWS는 `openshift-lws-operator`, MaaS는 `maas-default-gateway` 필요

---

## 2026-04-29 Session 15 — RHOAI IaC 정합화 + PoC 워크벤치 스모크

- 완료: `infra/rhoai/datasciencecluster.yaml`를 live v2 스펙과 정합화(`oc diff` exit 0), `infra/argocd/applications/rhoai.yaml` + `runbooks/30-argocd-app-sync.md` 작성, `infra/poc/workbench-smoke/{namespace,pvc,notebook}.yaml` 작성·적용 후 `smoke-wb-0` 2/2 Running 및 `python -c 'print(1+1)'` 검증 통과
- 진행중: 부트스트랩 단계 종료, 운영 모드 전환 트리거 대기
- 블로커: `.env`의 `GITHUB_REMOTE`가 placeholder, ArgoCD repository 인증 수단 미확정
- 다음 세션이 할 일: `runbooks/30-argocd-app-sync.md` 따라 RHOAI Application 등록 → diff → sync 후 drift 0 유지 확인
- 발견된 제약: RHOAI 3.4의 워크벤치 인증 사이드카는 `oauth-proxy`가 아니라 `kube-rbac-proxy`로 자동 주입됨 (ArgoCD `ignoreDifferences` 후보)

---

## 2026-04-29 Session 16 — 프레임워크 정합화

- 완료: `CLAUDE.md`/`README.md`/state/context를 BOOTSTRAP → 완료 선언 → OPS 단계 모델로 정리하고 runbook 번호·infra 구조·PoC 네이밍 계약을 실제 구조에 맞춤
- 진행중: OPS 전환 트리거 대기
- 블로커: ArgoCD Application sync 검증과 사람의 초기 구축 완료 선언 필요
- 다음 세션이 할 일: `runbooks/30-argocd-app-sync.md`로 `rhoai` Application 등록/diff/sync 검증
- 발견된 제약: 단계 모델 정정은 `constraints.md`에 append-only로 기록

---

## 2026-04-29 Session 17 — CPU LLM PoC 배포

- 완료: `rhoai-poc-llm-cpu` 프로젝트, vLLM CPU x86 ServingRuntime, `smollm2-135m-cpu` InferenceService 적용 및 `/v1/completions` 검증 통과
- 진행중: BOOTSTRAP 산출물의 ArgoCD Application/ApplicationSet 편입
- 블로커: OPS 전환 전 PoC/의존성 리소스 관리 범위 결정 필요
- 다음 세션이 할 일: `rhoai`, JobSet/LWS/MaaS Gateway, PoC 리소스를 ArgoCD 관리 범위에 편입 후 sync 검증
- 발견된 제약: CPU vLLM은 KV cache/model length 튜닝과 Recreate rollout 필요 (`constraints.md` 반영)

---

## 2026-04-30 Session 18 — GitOps 인계 범위 분할

- 완료: `ai-accelerator` installation/overview 패턴을 참고해 `work-plans/002-gitops-handover-scope.md` 작성
- 진행중: BOOTSTRAP 산출물의 ArgoCD 인계를 Scope 1~5로 순차 진행
- 블로커: Git remote 공개/비공개 여부와 ArgoCD repository secret 필요 여부 미확정
- 다음 세션이 할 일: [CHECKPOINT] 후 Scope 1(AppProject/repo config/root bootstrap 구조)만 진행
- 발견된 제약: 한 번에 ApplicationSet 흡수 금지, Scope 단위 체크리스트 갱신 후 다음 단계 진행

---

## 2026-04-30 Session 19 — Scope 1 ArgoCD 관리 뼈대 작성

- 완료: `infra/argocd/bootstrap`, `applications/kustomization.yaml`, AppProject 3개(`platform-operators`, `rhoai-core`, `rhoai-poc`) 작성
- 진행중: Scope 2 `rhoai` Application 등록/diff/sync 검증 대기
- 블로커: ArgoCD가 최신 IaC를 읽으려면 로컬 커밋을 GitHub `main`에 push해야 함
- 다음 세션이 할 일: [CHECKPOINT] 후 Scope 2 server dry-run → apply → diff → sync
- 발견된 제약: GitHub repo는 public 조회 가능해 repository secret은 현재 불필요

---

## 2026-04-30 Session 22 — Scope 2 RHOAI Application sync 완료

- 완료: `rhoai` Application 등록/sync 완료, `Synced/Healthy`, `default-dsc Ready=True`, `oc diff` exit 0
- 진행중: Scope 3 RHOAI 의존성(JobSet/LWS/MaaS Gateway) Application 편입 대기
- 블로커: Scope 3에서 의존성을 하나로 묶을지 각각 분리할지 결정 필요
- 다음 세션이 할 일: [CHECKPOINT] 후 Scope 3 Application IaC 작성/dry-run/sync
- 발견된 제약: ArgoCD DSC 전용 RBAC, OperatorGroup live 이름, tracking annotation 정합화 필요

---

## 2026-04-30 Session 23 — Scope 3 RHOAI 의존성 Application sync 완료

- 완료: `jobset`, `lws`, `maas-gateway` Application 등록/sync 완료, 모두 `Synced/Healthy`
- 진행중: Scope 4 PoC(`workbench-smoke`, `llm-cpu`) Application 편입 대기
- 블로커: Scope 4에서 PoC를 개별 Application으로 둘지 묶을지 결정 필요
- 다음 세션이 할 일: [CHECKPOINT] 후 Scope 4 Application IaC 작성/dry-run/sync
- 발견된 제약: MaaS Gateway sync에는 Gateway API ClusterRole/Binding 필요, `argocd` CLI 없으면 Application operation patch 사용

---

## 2026-04-30 Session 24 — 후속 테스트 기능 카탈로그 작성

- 완료: `work-plans/003-test-capability-catalog.md` 작성 — K8S/HA/Gateway/CI-CD/AI/MCP/가상화/네트워크/멀티클러스터 후보 정리
- 진행중: 실행 중단지점은 변경 없음 — Scope 4 PoC Application 편입 대기
- 블로커: 후속 테스트는 Scope 4/5 완료 후 사람 선택으로 하나씩 `active-task.md`에 승격 필요
- 다음 세션이 할 일: [CHECKPOINT] 후 Scope 4 Application IaC 작성/dry-run/sync
- 발견된 제약: 카탈로그는 새 Scope가 아니며 현재 active task를 대체하지 않음

---

## 2026-04-30 Session 26 — 다음 진입지점 기록

- 완료: 세션 진입 프로토콜을 수행하고 Scope 4 진행안을 제안했으나, 승인 전 사용자가 다음 진입지점 기록을 요청해 문서만 갱신
- 진행중: Scope 4 PoC(`workbench-smoke`, `llm-cpu`) Application 편입 CHECKPOINT 승인 대기
- 블로커: Scope 4 실행 승인 전에는 `oc apply`/sync/Application operation patch 금지
- 다음 세션이 할 일: [CHECKPOINT] 후 PoC를 별도 Application 2개로 편입하는 안을 확정하고 IaC 작성/dry-run/sync 진행
- 발견된 제약: Git 최신 커밋은 Session 25였으나 handoff에는 Session 25 엔트리 없음; Session 25는 `active-task.md` 크기 정합화만 수행

---

## 2026-05-07 Session 28 — 클러스터 미확보 상태에서 문서/IaC 보강

- 완료: 상태 파일 갱신(세션 27 결과 반영), IaC/문서 정합성 검토(6개 Application path·project·namespace 교차 검증 통과, kustomize 빌드 6개 Application 정상), Scope 5 OPS 전환 체크리스트 작성(`work-plans/002` 보강), ignoreDifferences 추가(`workbench-smoke`: Notebook 사이드카/볼륨, `llm-cpu`: InferenceService annotation/ServingRuntime containers)
- 진행중: Scope 4 실행(dry-run/apply/sync) — 클러스터 확보 대기
- 블로커: 클러스터 미확보. 확보 후 즉시 `oc apply --dry-run=server -k infra/argocd/bootstrap` → apply → sync 진행 가능
- 다음 세션이 할 일: 클러스터 확보 시 Scope 4 실행, 미확보 시 후속 문서/IaC 작업 협의
- 발견된 제약: ignoreDifferences는 실제 sync 후 drift를 관찰해 조정 필요할 수 있음

---

## 2026-05-15 Session 29 — PoC 프로젝트 구조 재정의

- 완료: 프로젝트 목적 재정의 ("AI와 IaC를 활용한 고객 시나리오 기반 PoC 수행"), CLAUDE.md 갱신 (목적/POC 환경/PoC 프로세스), work-plans/004-poc-restructure.md 작성, guidelines/01-layer-contracts.md 넘버링 세분화 (60~65 구축/70~75 검증/80 종합), reports/_template/README.md 생성, active-task.md 갱신
- 진행중: 런북 변환 (poc-factory phase-0~5 → 60~75, 90), RTM 작성
- 블로커: 없음
- 다음 세션이 할 일: 런북 변환 실행, work-plans/ RTM 작성, current-state.md 갱신
- 발견된 제약: poc-factory 폐기 결정. 검증 항목 상세(85개)는 reports/ 산출물로 활용. 시나리오 설계는 런북 §목적에 흡수

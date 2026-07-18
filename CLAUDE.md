# OpenShift AI GitOps 프로젝트

AI와 IaC를 활용하여 고객 시나리오 기반 RHOAI PoC를 수행한다. GitOps(ArgoCD)로 OpenShift AI 스택을 구축·검증하고, 검증 결과를 리포팅하며, 완료된 클러스터의 운영 인계까지 담당한다.

PoC 생명주기: **고객 요구사항 수령 → 구축+검증 → 리포팅 → 운영 인계**

---

## 🔒 반드시 지킬 것 (MUST READ FIRST)

이 파일은 모든 세션의 진입점이다. 다음 순서를 위반하지 말 것:

1. `guidelines/00-methodology.md` — 4계층 방법론의 철학 (불변 원칙)
2. `guidelines/02-session-protocol.md` — 이 세션에서 해야 할 절차
3. `claude-context/current-state.md` — 현재 프로젝트 상태
4. `claude-context/active-task.md` — 다음 태스크
5. 해당 태스크의 `work-plans/NNN-*.md` 또는 `runbooks/NNN-*.md`

상세한 레이어 계약은 `guidelines/01-layer-contracts.md` 참조.

## 🚫 금지 사항

- `guidelines/`의 내용을 AI가 직접 수정 (사람 승인 필수, diff 제안만 가능)
- `runbooks/`의 번호 순서 위반 (0xx → 1xx → 2xx → 3xx → 5xx → 8xx → 9xx)
  - 0xx: 인프라 기반 | 1xx: 플랫폼 구성 | 2xx: RHOAI 토폴로지
  - 3xx: 시나리오 구축 | 5xx: 시나리오 검증 | 8xx: 종합 검증 | 9xx: 운영/정리
- state 파일(`claude-context/`)을 읽지 않고 실행 시작
- 비밀값(pull-secret, kubeconfig, token 등) 커밋
- ArgoCD가 관리하는 리소스를 `oc`로 직접 수정 (sync drift 유발)
- 기존 클러스터의 기존 설정·네임스페이스·Operator를 승인 없이 변경
- 초기 구축 단계라도 클러스터 변경 명령(`oc apply/create/patch/delete`, `argocd app sync` 등)을 사람 승인 없이 실행
- 값의 "추정" — 버전·채널·도메인 등은 반드시 `infra/` 또는 공식 문서 근거

## 🛡️ 환경별 권한

| 환경 | 설정 파일 | 허용 작업 |
|---|---|---|
| BOOTSTRAP | `.claude/settings.local.json` (gitignored) | 초기 설치·복구 목적의 제한적 쓰기. 각 변경 전 CHECKPOINT 필요 |
| POC | `.claude/settings.local.json` (gitignored) | 시나리오 구축·검증 목적의 쓰기. RTM 기반 런북 순서 실행 |
| OPS (완료 선언 후 기본) | `.claude/settings.prod.json` 또는 읽기 전용 local 설정 | 읽기·describe·logs·diff·문서/IaC 변경안 작성 |
| PROD | `.claude/settings.prod.json` (공유) | 읽기·describe·logs·argocd 읽기만 |

환경 전환은 사람만 수행. AI는 세션 시작 시 현재 활성 설정이 어느 환경인지 확인할 것. BOOTSTRAP에서는 승인된 직접 적용이 가능하되 기록과 IaC 정합화를 남긴다. OPS 전환 후에는 Git/IaC 변경과 ArgoCD 동기화 제안이 기본이며, 클러스터 직접 변경은 break-glass로 취급한다.

## 📋 레이어 요약

- **Layer 1 — `work-plans/`**: 사람용 의사결정 문서 (한국어)
- **Layer 2 — `claude-context/`**: AI용 증류된 최소 컨텍스트
  - `current-state.md` + 클러스터별 분리(`current-state-sandbox.md`, `current-state-customer.md`)
  - `active-task.md`: 현재/다음 태스크 및 블로커
  - `version-matrix.md` / `constraints.md`: 버전·채널·제약
  - `handoff-notes.md`: 세션 기록
- **Layer 3 — `runbooks/`**: 실행 가이드 (bash 블록 포함, 번호 순서 강제)
- **Layer 4 — `infra/`**: 불변 IaC (YAML)
- **산출물 — `reports/`**: PoC 검증 결과 (4-Layer 밖)

## 📊 PoC 운영 프로세스

1. 고객 요구사항 수령 → `work-plans/` RTM 작성
2. RTM 기반 런북 매핑 및 gap 식별
3. `runbooks/000~031` 인프라 기반 (preflight → ArgoCD → RHOAI 설치)
4. `runbooks/100~220` 플랫폼 구성 + RHOAI 토폴로지
5. `runbooks/300~390` 시나리오별 구축 (S1~S10)
6. `runbooks/500~590` 시나리오별 검증
7. `runbooks/800` 종합 검증
8. `reports/{customer}/` 검증 결과 리포팅
9. 운영 인계 (ArgoCD 관리 상태)

## 🎯 세션 종료 시 반드시 (순서 고정)

1. `claude-context/current-state.md` 갱신
2. `claude-context/active-task.md` 갱신 (다음 세션이 할 일)
3. `claude-context/handoff-notes.md`에 최대 10줄 기록
4. `git add` + `git commit -m "[세션 NN] <요약>"`

위 4단계를 건너뛴 세션 종료는 실패로 간주한다.

## 🧭 막힐 때

- 예상치 못한 상태 → `guidelines/06-failure-recovery.md` 참조
- 판단이 애매 → 실행 중단, `work-plans/`에 Open Question으로 기록 후 사람 호출
- 계약 위반 유혹 → `guidelines/01-layer-contracts.md` 마지막 섹션 참조

## 🔗 출처

본 방법론은 https://yozm.wishket.com/magazine/detail/3710/ 의 4계층 문서 체계를 OpenShift + OpenShift AI + GitOps 도메인에 적응한 것이다. 철학의 세부는 `guidelines/00-methodology.md`.

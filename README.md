# OpenShift AI GitOps

기존 OpenShift 클러스터에 GitOps(ArgoCD) 기반으로 **OpenShift AI 스택**과 **PoC 검증 환경**을 구축하고, 완료 선언 이후 유지관리·운영하는 프로젝트.

현재 상태는 초기 구축(BOOTSTRAP) 마무리 단계다. 사람이 "초기 구축 완료"를 선언하고 ArgoCD 인계가 검증되면 운영 유지관리(OPS) 단계로 전환한다.

---

## 🎯 목표

- OpenShift AI Operator + DataScienceCluster 구성을 GitOps 기준으로 유지관리
- 주요 PoC 항목 검증 (노트북 / KServe 서빙 / Pipelines / 분산 훈련)
- 운영 중 drift, 버전, 의존성, 장애 원인을 문서화하고 재현 가능한 변경 절차로 관리
- AI(Claude / Gemini / Codex)를 동료로 활용하되 **안전한 구조** 유지
- 세션이 단절돼도 누구든 이어받을 수 있는 **재현 가능성** 보장

---

## 📐 설계 원칙 — 4계층 문서 체계

본 프로젝트는 4계층 방법론을 채택한다.

```
Layer 1 (work-plans/)       사람이 의사결정 (Why/How/Tradeoffs)
       │  증류
       ▼
Layer 2 (claude-context/)   AI용 최소 컨텍스트
       │  지시
       ▼
Layer 3 (runbooks/)         번호 순서 강제 실행 가이드
       │  참조
       ▼
Layer 4 (infra/)            불변 IaC (YAML)
```

철학·불변 원칙 상세: [`guidelines/00-methodology.md`](guidelines/00-methodology.md)

### 불변 원칙 (요약)

1. **AI는 판단, 실행은 선언형 도구** — ArgoCD가 적용, AI는 매니페스트만
2. **판단의 여지를 줄인다** — 값은 파일로 고정, 추정 금지
3. **상태는 파일에 산다** — cold-start에서 재구성 가능해야 함
4. **번호 순서는 강제력** — `runbooks/`는 건너뛰기 금지
5. **실패는 데이터** — 은폐 금지, `constraints.md`에 누적
6. **계약 위반 시 중단** — 사람 승인 없이 우회 금지

### 단계별 권한 원칙

- BOOTSTRAP 단계에서는 초기 설치·복구를 위해 승인된 직접 적용을 사용할 수 있다.
- 모든 변경 명령(`oc apply/create/patch/delete`, `argocd app sync`)은 사람의 명시 승인과 CHECKPOINT 이후에만 실행한다.
- BOOTSTRAP 변경도 반드시 Git/IaC와 상태 문서에 정합화해 다음 단계에서 ArgoCD가 인계받을 수 있게 한다.
- OPS 전환 이후에는 읽기 진단, 문서 갱신, IaC 변경안 작성, ArgoCD diff 확인이 기본 작업이다.
- ArgoCD가 관리하는 리소스는 Git/IaC를 고친 뒤 ArgoCD로 반영한다.

---

## 🚀 Quick Start (Makefile)

```bash
# 1. 환경 설정
cp .env.example .env
vi .env

# 2. 환경 검증
make preflight

# 3. 에어갭이면 이미지 목록 추출
make mirror-list

# 4. 배포
make deploy

# 5. 상태 확인
make status

# 6. 검증
make validate
make validate SCENARIOS=S1,S3    # 선택적

# 7. 고객 태깅
make tag CUSTOMER=mobis-poc-v1
```

전체 타겟: `make help`

### Makefile 타겟 상세

#### `make preflight` — 환경 검증

PoC 시작 전 필수 점검. 클러스터 접속, 권한, OpenShift 버전, GPU 존재 여부를 확인한다.

```bash
make preflight

# 출력 예시:
# [1/5] oc CLI 확인...
# [2/5] 클러스터 접속 확인... admin
# [3/5] 권한 확인... nodes: OK / namespaces: OK
# [4/5] OpenShift 버전... 4.21.14
# [5/5] GPU 감지... GPU 노드: 1개 (NVIDIA-L40S)
```

#### `make status` — 전체 상태 출력

Operator, DSC, InferenceService, Pod, ScaledObject, Pipeline 상태를 한눈에 확인한다. ArgoCD 대시보드를 대체하는 경량 상태 뷰.

```bash
make status

# CUSTOMER 변수로 헤더 커스터마이징
make status CUSTOMER=mobis
```

#### `make diff` — 선언 vs 실제 비교

`oc diff -k`로 Git에 선언된 YAML과 클러스터 실제 상태를 비교한다. ArgoCD의 drift 감지를 대체.

```bash
make diff

# 차이가 없으면 "일치", 있으면 diff 내용 출력
# 마지막에 "차이 발견: N개 디렉토리" 요약
```

#### `make mirror-list` — 에어갭 이미지 목록

`infra/` 하위 모든 YAML에서 `image:` 참조를 추출하고 Operator 카탈로그 이미지를 추가한다. **클러스터 접속 불필요.**

```bash
make mirror-list

# 결과 파일: mirror-images.txt
# 미러링: oc image mirror -f mirror-images.txt --dest-registry=<내부레지스트리>
```

#### `make deploy` — 런북 순서 자동 배포

`infra/` 디렉토리를 런북 순서(RHOAI → Operators → Gateway → Observability → PoC → EvalHub)로 `oc apply -k` 실행한다.

```bash
make deploy

# 이미 적용된 리소스는 [SKIP] 표시
# 완료 후 'make status'로 상태 확인 권장
```

#### `make validate` — 시나리오별 검증

S1~S6 중 선택된 시나리오만 자동 검증한다. `.env`의 `SCENARIOS` 변수 또는 명령줄에서 지정.

```bash
# 전체 시나리오 검증
make validate

# 특정 시나리오만
make validate SCENARIOS=S1,S3,S6

# 출력: PASS / FAIL / SKIP 요약
```

| 시나리오 | 검증 방식 |
|----------|----------|
| S1 모델 서빙 | InferenceService Ready=True 확인 |
| S2 Pipeline | 최근 PipelineRun Succeeded 확인 |
| S3 Auto-scaling | ScaledObject Ready=True 확인 |
| S4 장애복구 | InferenceService replicas ≥ 1 확인 |
| S5 Scale-to-Zero | 수동 검증 필요 (런북 74 참조) |
| S6 운영관리 | ServiceMonitor 존재 확인 |

#### `make tag` — 고객별 스냅샷

현재 Git 상태를 고객별 태그로 저장한다. 나중에 동일 구성을 재현할 때 사용.

```bash
make tag CUSTOMER=mobis-poc-v1
# → 태그: poc/mobis-poc-v1/20260517

# 원격에 push
git push origin poc/mobis-poc-v1/20260517
```

### 환경 변수 (.env)

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `KUBECONFIG` | kubeconfig 경로 | (필수) |
| `CLUSTER_DOMAIN` | 클러스터 Ingress 도메인 | (필수) |
| `OCP_AI_ENV_MODE` | `CONNECTED` 또는 `AIRGAP` | `CONNECTED` |
| `SCENARIOS` | 대상 시나리오 (쉼표 구분) | `S1,S2,S3,S4,S5,S6` |
| `GPU` | `auto` / `none` / `L40S` / `A100` | `auto` |
| `CUSTOMER` | 고객 식별자 | `default` |
| `OCP_VERSION` | OpenShift 버전 (mirror-list용) | `4.21` |
| `AIRGAP_MIRROR_REGISTRY` | 에어갭 미러 레지스트리 | (에어갭 시 필수) |

---

## 📂 디렉토리 구조

```
.
├── CLAUDE.md                  AI 진입 프로토콜 (세션마다 로드)
├── README.md                  이 파일 (사람용 진입점)
├── state.md                   전체 진척도 체크리스트
├── .claude/
│   ├── settings.local.json    DEV 환경 권한 (gitignored)
│   └── settings.prod.json     PROD 환경 권한 (읽기 전용)
├── guidelines/                방법론·계약·프로토콜 (6종)
│   ├── 00-methodology.md
│   ├── 01-layer-contracts.md
│   ├── 02-session-protocol.md
│   ├── 03-handoff-protocol.md
│   ├── 04-naming-conventions.md
│   ├── 05-state-management.md
│   └── 06-failure-recovery.md
├── work-plans/                Layer 1 — 의사결정 문서
├── claude-context/            Layer 2 — AI용 증류 컨텍스트
├── runbooks/                  Layer 3 — 실행 가이드
└── infra/                     Layer 4 — IaC (YAML)
    ├── argocd/
    ├── operators/
    ├── rhoai/
    └── poc/
```

---

## 🚀 시작하기 (사람)

### 1. 환경 변수 준비
```bash
cp .env.example .env    # 만든 후
# .env 편집
#   KUBECONFIG=/path/to/kubeconfig
#   CLUSTER_DOMAIN=apps.example.com
```

### 2. 현재 진척도 확인
[`state.md`](state.md) — 어느 Phase에 있고 무엇이 남았는지

### 3. 방법론 이해
- [`guidelines/00-methodology.md`](guidelines/00-methodology.md) — 왜 4계층인가
- [`guidelines/01-layer-contracts.md`](guidelines/01-layer-contracts.md) — 각 레이어 규칙
- [`guidelines/02-session-protocol.md`](guidelines/02-session-protocol.md) — 작업 순서

### 4. AI 세션 시작
AI 도구(Claude Code 등)가 이 디렉토리에 진입하면 `CLAUDE.md`를 자동으로 읽는다. AI가 state를 읽고 다음 태스크를 제안한다.

---

## 🤖 AI 도구 지원

| 도구 | 진입 파일 | 권한 제어 | 상태 |
|---|---|---|---|
| Claude Code | `CLAUDE.md` | `.claude/settings.local.json` | ✅ 활성 |
| Gemini CLI | `GEMINI.md` → `CLAUDE.md` (심볼릭) | Gemini 설정 | ✅ 활성 |
| OpenAI Codex | `AGENTS.md` → `CLAUDE.md` (심볼릭) | Codex 설정 | ✅ 활성 |

다중 도구 동시 사용 가능. 모든 도구가 **동일한 진입점**(CLAUDE.md 실체)을 읽고 **동일한 4계층 규칙**을 따른다.

### 진입 파일 변경 시 주의
`CLAUDE.md`가 실체(source), 나머지는 심볼릭 링크. `CLAUDE.md`만 수정하면 3개 도구에 동시 반영.

---

## 🧭 빠른 탐색

- **지금 뭐 하면 되지?** → [`state.md`](state.md) + [`claude-context/active-task.md`](claude-context/active-task.md)
- **왜 이렇게 설계했지?** → [`guidelines/00-methodology.md`](guidelines/00-methodology.md)
- **파일 어떻게 쓰지?** → [`guidelines/01-layer-contracts.md`](guidelines/01-layer-contracts.md)
- **실행 막혔을 때?** → [`guidelines/06-failure-recovery.md`](guidelines/06-failure-recovery.md)
- **최근 뭐 했지?** → [`claude-context/handoff-notes.md`](claude-context/handoff-notes.md)

---

## 🔗 참조

- OpenShift AI 호환 매트릭스: https://access.redhat.com/support/policy/updates/rhoai
- OpenShift GitOps: https://docs.openshift.com/gitops/
- ArgoCD: https://argo-cd.readthedocs.io/

---

## 📝 라이선스 / 저작자

내부 PoC 프로젝트. 저작자는 리포 오너.

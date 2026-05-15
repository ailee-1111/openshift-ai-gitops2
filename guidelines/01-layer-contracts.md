# 레이어 계약 (Layer Contracts)

각 레이어의 형식·입력·출력·수정 권한을 명시한다. 여기 정의된 계약을 위반하는 AI 출력은 **유효하지 않다**.

---

## Layer 1 — `work-plans/` (사람용 의사결정 문서)

### 형식
- 파일명: `NNN-<kebab-case>.md`
  - NNN: 3자리, `001`부터 증가
  - 예: `001-gitops-boundary.md`, `002-operator-dependency.md`
- 언어: **한국어** (기술 용어는 영문 유지)
- 최상단에 문서 작성일·최종 수정일 명시

### 필수 섹션 (순서 고정)
```markdown
# <제목>

- 작성일: YYYY-MM-DD
- 최종 수정: YYYY-MM-DD

## Why (왜 이 결정이 필요한가)
## How (어떤 옵션이 있고, 어떻게 할 것인가)
## Tradeoffs (각 옵션의 장단점)
## Decision (무엇을 선택했고 그 이유)
## Open Questions (미결 사항)
## References (외부 문서 링크)
```

### 입력
- 사람의 판단, 도메인 지식, 팀 제약
- AI가 조사한 자료는 **References에만** 인용 (본문에 섞지 말 것)

### 출력
- `Decision` 섹션의 결정이 Layer 3/4에 반영되어야 한다.
- 반영되지 않은 Decision은 미완료 상태.

### 수정 권한
- ✅ 사람: 직접 edit
- 🟡 AI: diff 제안 가능, 사람 승인 후에만 edit
- ❌ AI: 직접 edit 금지

### 완료 기준
- `Open Questions`가 비어 있거나 명시적으로 "보류" 표기
- 참조된 Layer 3/4 파일이 실제 존재

---

## Layer 2 — `claude-context/` (AI용 증류 컨텍스트)

### 형식
- 파일명: **고정 세트** (아래 외 추가 금지, 단 확장은 허용)
  - `current-state.md` — 현재 스냅샷
  - `active-task.md` — 다음 1개 태스크
  - `constraints.md` — 누적 제약·교훈
  - `version-matrix.md` — OpenShift·Operator 버전 매트릭스
  - `handoff-notes.md` — 세션 인수인계 누적 로그
- 언어: **한국어 또는 영어** (파일 내 일관성 유지, 혼용 금지)
- **최대 길이: 파일당 500줄** (초과 시 증류 필요)

### `current-state.md` 필수 구조
```markdown
# 현재 상태 (YYYY-MM-DD 기준)

## 클러스터
- OpenShift 버전: X.Y.Z
- API endpoint: (placeholder, kubeconfig는 .env 참조)
- 도메인: apps.<cluster>.<base-domain>

## 설치 상태
- [ ] OpenShift GitOps (ArgoCD)
- [ ] ServiceMesh Operator
- [ ] Serverless Operator
- [ ] Pipelines Operator
- [ ] OpenShift AI Operator
- [ ] DataScienceCluster 적용

## 최근 이벤트 (최대 3건)
- YYYY-MM-DD: <이벤트>
```

### `active-task.md` 필수 구조 (단 1개 태스크)
```markdown
# 다음 태스크

## 태스크
<한 줄 요약>

## 참조
- work-plans/NNN-*.md
- runbooks/NN-*.md

## 성공 기준
- [ ] <검증 가능한 조건>

## 블로커
- 없음 / <내용>
```

### 수정 권한
- ✅ AI: 매 iteration 종료 시 갱신 (의무)
- ✅ 사람: 언제든 직접 edit (AI 변경보다 우선)

### 완료 기준
- 각 파일이 500줄 이내
- `active-task.md`에 단 **1개**의 태스크만 존재

---

## Layer 3 — `runbooks/` (실행 가이드)

### 형식
- 파일명: `NN-<kebab-case>.md`
  - NN: 2자리, `00/10/20/30/40/50/60/70/80/90` (10 단위 우선)
  - 같은 단위 내 세부 단계는 `NN-a`, `NN-b` (예: `60-a-notebook.md`)
- 언어: 한국어 설명 + 영어 명령

### 번호 할당 (고정)
| 번호 | 의미 |
|---|---|
| 00 | preflight / 전제조건 점검 (읽기 전용) |
| 10 | OpenShift GitOps Operator 부트스트랩 |
| 20 | OpenShift AI Operator + DataScienceCluster 부트스트랩 |
| 30 | ArgoCD Application 인계 / diff / sync |
| 40 | 플랫폼 Operator 추가 설치 (ServiceMesh / Serverless / Pipelines / cert-manager 등 필요 시) |
| 45 | GPU 스택 (NFD + NVIDIA GPU Operator) — 선택 |
| 50 | RHOAI 토폴로지 정합화 / 의존성 보강 |
| 60–65 | 시나리오별 PoC 구축 (S1~S6) |
| 70–75 | 시나리오별 PoC 검증 (S1~S6) |
| 80 | 종합 검증 |
| 90 | teardown (DEV 전용) |

**건너뛰기 금지**. 건너뛸 이유가 있으면 `work-plans/`에 사유 기록.

### 필수 구조
```markdown
# NN — <제목>

## 목적
<1–2문장>

## 전제 조건
- [ ] 이전 단계 완료 (NN-1)
- [ ] 필요한 권한/값이 존재

## 실행
~~~bash
# 설명
command
~~~

## 검증
~~~bash
# 성공 기준을 확인하는 명령
oc get ... -o jsonpath=...
~~~

## 실패 시
- 증상 A → 원인 → 대응
- 증상 B → 원인 → 대응

## 다음 단계
→ `runbooks/NN+10-*.md`
```

### bash 블록 규칙 (strict)
- 모든 명령은 **idempotent** (재실행 안전)
- 각 블록은 독립 실행 가능 (앞 블록 실패가 뒷 블록 문법을 깨지 않음)
- 하드코딩 금지: 값은 환경 변수 또는 `infra/` 파일 참조
- 긴 대기는 `oc wait --for=condition=...`로 명시

### 수정 권한
- ✅ 사람: 직접 edit
- 🟡 AI: diff 제안 + 사람 승인
- ⛔ 실행 도중 수정 금지 (실행 이력과 파일이 불일치하면 안 됨)

### 완료 기준
- 검증 섹션의 bash 블록이 전부 성공 exit code
- "실패 시" 섹션이 실제 경험한 장애를 반영

---

## Layer 4 — `infra/` (불변 IaC)

### 형식
- 확장자: `.yaml`, `.yml` (Kustomize, Helm values), 제한적으로 `.json`
- **명령·스크립트 금지** (실행은 Layer 3 runbook에서)

### 디렉토리 규칙
```
infra/
├── argocd/
│   ├── bootstrap/         App-of-Apps 루트
│   └── applications/      각 App의 Application CR
├── operators/
│   ├── subscriptions/     공통 OperatorGroup + Subscription
│   └── <operator-name>/   개별 Operator 의존성 묶음
├── rhoai/                 RHOAI Operator + DataScienceCluster + 관련 CR
│   └── gateway/           RHOAI Gateway API 리소스
└── poc/                   각 PoC의 매니페스트 (시나리오별 Kustomize)
```

### 값의 출처 규칙
- 모든 값(버전·채널·네임스페이스·도메인)은 **출처를 YAML 주석에 명시**
- 예시:
  ```yaml
  # 출처: Red Hat docs OCP 4.16 - ServiceMesh 2.6 호환 매트릭스
  # claude-context/version-matrix.md 참조
  channel: stable
  ```

### 수정 권한
- ✅ 사람: 직접 edit (PR 권장)
- 🟡 AI: diff 제안 + 사람 승인
- ❌ AI: 값을 "추정"으로 채우기 **절대 금지**

### 완료 기준
- 모든 YAML이 `oc apply --dry-run=client -f <file>` 통과
- ArgoCD에 반영 시 Application이 `Synced & Healthy`

---

## 레이어 간 참조 규칙

### 허용되는 참조 방향
```
Layer 1 → Layer 2, 3, 4    (상위가 하위를 지휘)
Layer 2 → Layer 3, 4       (AI가 하위를 참조)
Layer 3 → Layer 4          (runbook이 IaC 값 사용)
```

### 금지되는 참조 방향
```
Layer 4 → Layer 1, 2, 3    ❌
Layer 3 → Layer 1, 2       ❌ (runbook은 상위 결정의 결과)
Layer 2 → Layer 1          ❌ (claude-context가 work-plan을 인용하지 않음. 결정은 이미 증류되어 들어와야 함)
```

상위 참조가 필요해 보이면 **구조 오류를 의심**할 것. 대부분 상위 문서에 누락이 있거나 증류가 덜 된 상태.

---

## 계약 위반 시 행동 (MUST)

AI가 본 계약을 위반하는 출력을 내려고 할 때:

1. **즉시 중단**
2. 무엇이 위반되는지 한 줄 서술
3. 사람에게 **세 가지 선택지** 제시:
   - (a) 계약을 따르는 대안으로 수정
   - (b) 계약 자체를 변경 (이 파일 수정 필요, `[contracts] <사유>` 커밋)
   - (c) 이번만 예외 (`work-plans/`에 예외 사유 기록)
4. 사람의 결정 후 진행

**계약을 조용히 어기는 것이 가장 나쁜 실패 모드다.**

---

## 산출물 — `reports/`

- `reports/{customer}/` 하위에 PoC 검증 결과를 기록한다
- 4-Layer에 속하지 않는 프로젝트 산출물이다
- 런북 실행 결과(PASS/FAIL, 실측값)를 기록한다
- 수정 권한: AI + 사람 모두 가능

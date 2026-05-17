# 네이밍 컨벤션

모든 파일·브랜치·커밋·리소스의 이름 규칙.

---

## 파일

### `work-plans/`
`NNN-<kebab-case>.md` (3자리, 001부터)
예: `001-gitops-boundary.md`, `002-operator-dependency.md`

### `runbooks/`
`NNN-<kebab-case>.md` (3자리)
- 첫 자리: Phase (0=인프라, 1=플랫폼, 2=토폴로지, 3=S1~S6, 4=S7+, 5=검증, 8=종합, 9=운영)
- 둘째 자리: 시나리오/카테고리 (S1=0, S2=1, S3=2, ...)
- 셋째 자리: 세부 순서 (0=메인, 1~=변형/강화)
예: `300-model-serving.md`, `301-llm-cpu.md`, `311-pipeline-v3.md`
상세 매핑: `work-plans/010-runbook-3digit-migration.md`

### `claude-context/`
**고정 이름만 허용** (`01-layer-contracts.md` 참조)

### `infra/`
- YAML: 리소스 종류를 파일명에 반영
  - `subscription-servicemesh.yaml`
  - `datasciencecluster.yaml`
  - `application-rhoai-core.yaml`
- Kustomize: `kustomization.yaml` (표준 이름)

---

## Git

### 브랜치
- `main` — 기본, 보호 브랜치
- `feat/<kebab-case>` — 기능 추가
- `fix/<kebab-case>` — 수정
- `docs/<kebab-case>` — 문서만
- `wip/session-NN` — 세션별 실험 (병합 전 squash)

### 커밋 메시지 (한국어/영어 모두 허용)
- 세션 커밋: `[세션 NN] <한 줄 요약>`
- 일반 변경: `[타입] <요약>`
  - 타입: `feat` / `fix` / `refactor` / `docs` / `chore` / `methodology` / `contracts`
- 예시:
  - `[세션 03] ArgoCD 부트스트랩 완료, ServiceMesh 대기`
  - `[feat] RHOAI DataScienceCluster 최소 구성 추가`
  - `[contracts] Layer 3 번호에 45 (GPU) 추가`

---

## Kubernetes / OpenShift 네임스페이스

- `openshift-gitops` — ArgoCD (Operator 기본값, 변경 금지)
- `openshift-operators` — 일반 Operator (기본값)
- `redhat-ods-applications`, `redhat-ods-operator` — RHOAI (기본값, 변경 금지)
- PoC 전용: `rhoai-poc-<kebab-name>` 접두어

---

## ArgoCD 리소스

- `Application` 이름: `<area>-<component>` 또는 단일 핵심 영역은 `<area>`
  - 예: `platform-servicemesh`, `rhoai`, `poc-notebook`
- `ApplicationSet` 이름: `<area>-all` (예: `platform-all`)
- `AppProject` 이름: `<area>` (예: `platform`, `rhoai`, `poc`)

---

## 환경 변수 (`.env`)

`UPPER_SNAKE_CASE`. 예시:
~~~
KUBECONFIG=/path/to/kubeconfig
CLUSTER_DOMAIN=apps.example.com
PULL_SECRET_PATH=~/secrets/pull-secret.json
GIT_REMOTE_URL=git@github.com:org/openshift-ai-gitops.git
~~~

`.env` 자체는 gitignored. 공유용은 `.env.example`.

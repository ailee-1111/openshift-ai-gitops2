# OpenShift AI GitOps

클러스터에 빠르게 환경 구성을 하기 위한 퀵 스타트 실행 가이드 문서이다.
환경 변수를 식별하고 사용한다.

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

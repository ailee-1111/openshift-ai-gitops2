# S2: Pipeline 시나리오

> **시나리오 플로우**: 모델 등록 요청 -> (알람)승인 -> 모델 배포 요청 -> (알람)승인 -> vLLM 서빙 Pod 구동 & REST API Endpoint 생성 확인
>
> **구축 런북**: runbooks/61 | **검증 런북**: runbooks/71 | **IaC**: poc/pipeline/
>
> **결과**: 6/7 PASS, 1 SKIP (86%)

---

## No.1 : vLLM 지원

> **카테고리**: 모델 배포 엔진
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

vLLM 기반 모델 서빙 지원 여부를 확인한다.

### 수행 방법

#### Step 1: vLLM ServingRuntime 배포

RHOAI에 등록된 vLLM CUDA 기반 ServingRuntime이 정상 동작하는지 확인한다.

#### Step 2: InferenceService 추론 검증

vLLM 엔드포인트에 /v1/completions 요청을 보내 정상 응답을 확인한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| ServingRuntime | vLLM CUDA 기반 정상 |
| InferenceService | Ready=True |
| /v1/completions | HTTP 200 정상 응답 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| vLLM 서빙 | InferenceService Ready | CrashLoop |
| 추론 | HTTP 200 | 타임아웃 |

### 런북 참조

- runbooks/300-model-serving.md

---

## No.2 : TGI/TRT-LLM 등 대체 엔진

> **카테고리**: 모델 배포 엔진
> **판정**: SKIP

### SKIP 사유

본 PoC는 vLLM 단일 엔진으로 범위를 한정. RHOAI는 커스텀 ServingRuntime을 통해 다양한 엔진 지원 가능.

---

## No.3 : 엔진 버전 관리

> **카테고리**: 모델 배포 엔진
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

서빙 엔진 버전 선택 가능 여부를 확인한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| vLLM 버전 | ServingRuntime 이미지 태그로 확인 |
| 버전 전환 | 이미지 태그 변경으로 가능 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 버전 식별 | 이미지 태그 확인 | 식별 불가 |

### 런북 참조

- runbooks/300-model-serving.md

---

## No.10 : 모델 배포 자동화 파이프라인

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

기본 파이프라인 (등록 > 승인 > 배포 > 승인) 제공.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| PipelineRun | Succeeded |
| Task 순서 | S3검증 -> 승인 -> 서빙검증 |
| Tekton E2E | 전체 Succeeded |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| PipelineRun | Succeeded | Failed |

### 런북 참조

- runbooks/310-pipeline.md
- runbooks/510-pipeline-validation.md

---

## No.11 : 모델 등록 프로세스

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

등록 전 지정 직책자에게 승인 요청. ManualApprovalGate(K8s CR)으로 구현.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| 승인 대기 | ManualApprovalGate 차단 정상 |
| 승인 후 진행 | 다음 Task 정상 진행 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 차단 | 승인 전 대기 | 승인 없이 진행 |
| 진행 | 승인 후 완료 | 승인 후 실패 |

> **참고**: Email 알림 연동은 추가 작업 필요.

### 런북 참조

- runbooks/310-pipeline.md

---

## No.12 : 모델 승인 프로세스

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

배포 전 지정 직책자에게 승인 요청. 승인 후 PipelineRun Succeeded.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| 배포 승인 | 정상 차단 -> 승인 -> 완료 |
| PipelineRun | Succeeded |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 승인 프로세스 | 차단->승인->완료 | 우회 |

### 런북 참조

- runbooks/510-pipeline-validation.md

---

## No.43 : OpenAI 호환 API

> **카테고리**: 인증 및 권한
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

OpenAI API 형식 호환 여부를 확인한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| /v1/completions | HTTP 200 정상 |
| /v1/chat/completions | HTTP 200 정상 |
| 응답 형식 | OpenAI 호환 JSON |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| Completions | HTTP 200 + 유효 응답 | 에러 |
| Chat | HTTP 200 + 유효 응답 | 에러 |

### 런북 참조

- runbooks/500-model-serving-validation.md

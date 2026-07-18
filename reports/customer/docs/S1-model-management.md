# S1: 모델 관리 시나리오

> **시나리오 플로우**: MDIP-AI에서 S3 artifact 저장 & Model Registry에 모델 등록 -> RHOAI에서 v1 확인 <-> 모델 재등록 -> RHOAI v2 확인
>
> **구축 런북**: runbooks/300 | **검증 런북**: runbooks/500 | **IaC**: poc/model-serving/
>
> **결과**: 6/6 PASS (100%)

---

## No.4 : 모델 등록 기능 (수동/자동)

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

수동등록 + 자동등록(pipeline으로 S3 -> Model Registry 정보 등록) 기능을 제공한다.

### 수행 방법

#### Step 1: Model Registry REST API로 수동 등록

Model Registry Route를 통해 REST API 엔드포인트에 접근하고, 모델 메타데이터를 등록한다.

#### Step 2: Tekton Pipeline을 통한 자동 등록

S3에 모델 아티팩트를 저장한 후, Pipeline이 Model Registry에 자동으로 정보를 등록한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| Model Registry REST API | 정상 응답 (GET /api/model_registry/v1alpha3/registered_models) |
| 수동 모델 등록 | 성공 — ID 반환 |
| 파이프라인 자동 등록 | Tekton E2E Succeeded |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| REST API 모델 등록 | 모델 ID 반환 | 에러 또는 타임아웃 |
| 등록 모델 조회 | 정보 일치 | 조회 불가 |

### 런북 참조

- runbooks/300-model-serving.md
- runbooks/500-model-serving-validation.md

---

## No.5 : 모델 등록/업로드

> **카테고리**: 모델 라이프사이클
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

커스텀 모델(HuggingFace, safetensors 등) 등록 UI/API를 제공한다.

### 수행 방법

#### Step 1: S3에 모델 아티팩트 업로드

MinIO S3 버킷에 config.json, tokenizer, safetensors 파일을 업로드한다.

#### Step 2: Model Registry에 등록

REST API로 모델 이름, 아티팩트 URI, 형식을 등록하고 ID 반환을 확인한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| S3 아티팩트 | config.json / tokenizer / safetensors 저장 확인 |
| 신규 모델 등록 | 성공 — ID 반환 |
| RHOAI Dashboard | 정상 표시 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| S3 저장 | 파일 접근 가능 | 업로드 실패 |
| Registry 등록 | ID 반환 | 에러 |

### 런북 참조

- runbooks/300-model-serving.md

---

## No.6 : 모델 버전 관리

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

동일 모델의 여러 버전 관리 및 전환 기능을 제공한다.

### 수행 방법

#### Step 1: v1 / v2 등록

Model Registry에 동일 RegisteredModel 하위에 v1, v2 ModelVersion을 생성한다.

#### Step 2: 버전별 조회 및 전환

REST API로 버전 목록을 조회하고, InferenceService 모델 URI 변경으로 전환한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| v1 등록 | 성공 |
| v2 등록 | 성공 |
| 버전 목록 조회 | v1, v2 정상 표시 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 복수 버전 등록 | v1, v2 성공 | 중복 에러 |
| 버전별 조회 | 독립 조회 가능 | 구분 불가 |

### 런북 참조

- runbooks/500-model-serving-validation.md

---

## No.8 : 원클릭 배포/철수

> **카테고리**: 모델 라이프사이클
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

GUI/CLI로 모델 배포 및 해제를 간편 지원한다. replicas 0<->1 전환으로 구현.

### 수행 방법

#### Step 1: 배포 (replicas 0 -> 1)

RHOAI Dashboard 또는 `oc patch`로 InferenceService replicas를 1로 전환한다.

#### Step 2: 철수 (replicas 1 -> 0)

동일 방법으로 replicas 0 전환, Pod 삭제 및 GPU 해제를 확인한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| 0 -> 1 전환 | Pod 생성, Ready=True |
| 1 -> 0 전환 | Pod 삭제, GPU 해제 |
| Dashboard UI | 정상 동작 |
| CLI (oc patch) | 정상 동작 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 배포 | Pod Ready=True | CrashLoop 또는 생성 실패 |
| 철수 | Pod 삭제 + GPU 해제 | Pod 잔존 |

### 런북 참조

- runbooks/300-model-serving.md
- runbooks/500-model-serving-validation.md

---

## No.9 : 모델 메타데이터 관리

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

모델 설명, 알고리즘, 학습데이터 정보 viewing 및 관리. customProperties CRUD 지원.

### 수행 방법

#### Step 1: customProperties CRUD

Model Registry REST API로 메타데이터 조회/추가/수정/삭제를 수행한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| 조회 (Read) | 정상 |
| 추가 (Create) | 성공 |
| 수정 (Update) | 성공 |
| 삭제 (Delete) | 성공 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| CRUD 전체 | 모든 작업 정상 | 일부 실패 |

### 런북 참조

- runbooks/500-model-serving-validation.md

---

## No.13 : 모델 아티팩트 저장

> **카테고리**: 모델 라이프사이클
> **요청구분**: 플랫폼 관리
> **판정**: PASS

### 기능 정의

S3 저장소 연동, 플랫폼 파이프라인 연동을 통한 모델 아티팩트 저장.

### 수행 방법

#### Step 1: S3 버킷 구성 및 아티팩트 확인

MinIO S3 DataConnection 구성 후, 모델 파일(config/tokenizer/safetensors)이 정상 저장되어 있는지 확인한다.

#### Step 2: 모델 로딩 및 서빙 검증

InferenceService가 S3에서 아티팩트를 로딩하여 추론 서비스가 정상 동작하는지 확인한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| S3 연결 | MinIO DataConnection 정상 |
| 저장 파일 | config.json, tokenizer, safetensors |
| 모델 로딩 | InferenceService Ready=True |
| 추론 | /v1/completions 정상 응답 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| S3 접근 | 파일 다운로드 가능 | 404 또는 권한 오류 |
| 서빙 | 추론 응답 정상 | 로딩 실패 |

### 런북 참조

- runbooks/300-model-serving.md

## v3 강화 (306-multimodel-v3)

- 멀티모델 3개 동시 등록/서빙
- customProperties 기반 검색/필터
- v1→v2 버전 전환 다운타임 0
- 구축 런북: 306-multimodel-v3.md | 검증: 500 v3 섹션

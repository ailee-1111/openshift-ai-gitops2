# S5: Scale-to-Zero 시나리오

> **시나리오 플로우**: 일정 시간 요청 중단 -> Pod 수 감소 확인 -> 재요청 시 -> Pod 증가 확인
>
> **구축 런북**: runbooks/64 | **검증 런북**: runbooks/74 | **IaC**: poc/scale-to-zero/
>
> **결과**: 2/2 PASS (100%)

---

## No.23 : 스케일 투 제로

> **카테고리**: 오토스케일링
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

미사용 시 GPU 자원 완전 해제 (0으로 축소).

### 수행 방법

#### Step 1: Scale-to-Zero 트리거

KEDA ScaledObject `minReplicaCount=0` 설정 후, 요청 없을 때 Pod 0으로 축소 확인.

#### Step 2: VRAM 해제 확인

Pod 0개 상태에서 GPU VRAM 완전 해제 확인.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| minReplicaCount | 0 |
| Pod 축소 | 0개로 즉시 축소 |
| VRAM 해제 | 41,936 MiB -> 0 MiB |
| 자동 복원 경로 | llm-d EPP 큐 메트릭 + 클라이언트 재시도 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| Pod 축소 | 0개 | Pod 잔존 |
| VRAM 해제 | 0 MiB | VRAM 잔존 |

> **참고**: 자동 복원은 llm-d activator(DP)로 요청 버퍼링 가능 예정. WVA(Workload Variant Autoscaler)가 Cold Start 동안 KEDA 재축소 방지 예정.

### 런북 참조

- runbooks/64-scale-to-zero.md
- runbooks/74-scale-to-zero-validation.md

---

## No.24 : 콜드스타트 최적화

> **카테고리**: 오토스케일링
> **판정**: PASS

### 기능 정의

모델 로딩 시간 최소화 전략 (프리로드, 캐시 등).

### 수행 방법

#### Step 1: 1차 Cold Start 측정

Scale-to-Zero 상태에서 첫 요청 시 모델 로딩부터 추론 응답까지 시간 측정.

#### Step 2: 2차 Cold Start 측정

반복 사이클로 안정성 확인.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| 1차 Cold Start | **61초** |
| 2차 Cold Start | **73초** |
| 기준 | < 120초 |
| 복구 후 추론 | HTTP 200 |
| 테스트 모델 | SmolLM2-135M |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| Cold Start | < 120초 | >= 120초 |
| 추론 응답 | HTTP 200 | 에러 |

> **참고**: Cold Start 시간은 모델 크기에 비례. 대형 모델(HGX)에서는 시간 증가 예상.

### 런북 참조

- runbooks/64-scale-to-zero.md
- runbooks/74-scale-to-zero-validation.md

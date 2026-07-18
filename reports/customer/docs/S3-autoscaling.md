# S3: Auto-scaling 시나리오

> **시나리오 플로우**: Replica=1로 서빙 구동 -> 부하 트래픽 발생 -> replica 증가 확인
>
> **구축 런북**: runbooks/320 | **검증 런북**: runbooks/520 | **IaC**: poc/autoscaling/
>
> **결과**: 3/3 PASS (1 조건부, 100%)

---

## No.21 : 수평 오토스케일링 (HPA)

> **카테고리**: 오토스케일링
> **요청구분**: DS-LLM 운영/관리
> **판정**: 조건부 PASS

### 기능 정의

요청량 기반 모델 레플리카 자동 증감.

### 수행 방법

#### Step 1: ScaledObject 상태 확인

KEDA ScaledObject READY=True 여부와 min/max replicas 설정을 확인한다.

#### Step 2: 부하 테스트

동시 요청을 발생시켜 HPA desiredReplicas 변화를 관찰한다.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| ScaledObject | READY=True |
| min/maxReplicaCount | 1 / 3 |
| desiredReplicas | 부하 시 증가 확인 |
| 실 스케일업 | GPU 부족으로 Pod 증가 불가 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 트리거 동작 | desiredReplicas 증가 | 변화 없음 |

> **조건부 사유**: GPU 부족(L40S x4 전부 사용 중)으로 실 Pod 증가 불가. HGX(H200) 환경에서 재검증 권장.

### 런북 참조

- runbooks/320-autoscaling.md
- runbooks/520-autoscaling-validation.md

---

## No.22 : GPU 기반 스케일링 메트릭

> **카테고리**: 오토스케일링
> **요청구분**: DS-LLM 운영/관리
> **판정**: PASS

### 기능 정의

GPU 사용률, VRAM, 큐 깊이 기반 스케일링 메트릭 수집.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| DCGM 메트릭 | DCGM_FI_DEV_GPU_UTIL, FB_USED 수집 |
| vLLM 메트릭 | num_requests_waiting 수집 |
| Prometheus target | 15 target UP |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| GPU 메트릭 | Prometheus 조회 가능 | 미수집 |
| vLLM 메트릭 | 큐/캐시 노출 | 미노출 |

### 런북 참조

- runbooks/320-autoscaling.md

---

## No.25 : 스케일링 정책 커스터마이징

> **카테고리**: 오토스케일링
> **판정**: PASS

### 기능 정의

스케일링 임계값/쿨다운/최소-최대 레플리카 설정.

### 실측 결과 (2026-05-15)

| 항목 | 값 |
|------|-----|
| ScaledObject | READY=True |
| cooldownPeriod | 설정 가능 |
| threshold | 설정 가능 |
| min/max | 변경 가능 |

### 판정 기준

| 기준 | PASS | FAIL |
|------|------|------|
| 정책 변경 | CR 수정 후 반영 | 미반영 |

### 런북 참조

- runbooks/320-autoscaling.md

## v3 강화 (322-autoscaling-v3)

- GPU VRAM/큐 깊이 KEDA 트리거 2개
- 1→3→1 전체 스케일 사이클
- 계단형 부하 (10→50→100 RPS)
- 구축 런북: 322-autoscaling-v3.md | 검증: 520 v3 섹션

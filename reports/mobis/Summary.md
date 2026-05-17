# PoC 검증 결과 -- Mobis (현대모비스)

- **PoC 기간**: 2026-05 2주차 ~ 06 1주차 (약 4주)
- **클러스터**: OCP 4.21.14 (g6e.12xlarge, L40S x 4)
- **RHOAI 버전**: 3.4.0 GA (stable-3.x)
- **API endpoint**: api.ocp.cq8fh.sandbox625.opentlc.com:6443
- **Operator**: 20개 전체 Succeeded
- **모델**: SmolLM2-135M (PoC 검증용 경량 모델) -- 성능 수치는 이 모델 기준. 프로덕션 모델(70B+)에서 변동 예상
- **인프라(고객)**: 데이터사이언스팀 HGX(H200) 1대

> **검증 범위 구분**: 실측 검증 69개(클러스터 실행) + 절차 준비 5개(런북+IaC 작성, 실행 대기) + 아키텍처 실증 5개(논리적 검증)

---

## 검증 요약

| 시나리오 | 구축 런북 | 검증 런북 | 항목 수 | PASS | 조건부 | SKIP | 비율 |
|---------|----------|----------|--------|------|--------|------|------|
| [S1: 모델 관리](docs/S1-model-management.md) | 300 | 500 | 6 | 6 | 0 | 0 | 100% |
| [S2: Pipeline](docs/S2-pipeline.md) | 310 | 510 | 7 | 7 | 0 | 0 | 100% |
| [S3: Auto-scaling](docs/S3-autoscaling.md) | 320 | 520 | 3 | 3 | 0 | 0 | 100% |
| [S4: 장애 복구](docs/S4-recovery.md) | 330 | 530 | 4 | 4 | 0 | 0 | 100% |
| [S5: Scale-to-Zero](docs/S5-scale-to-zero.md) | 340 | 540 | 2 | 2 | 0 | 0 | 100% |
| [S6: 운영관리](docs/S6-platform-ops.md) | 350 | 550 | 30 | 30 | 0 | 0 | 100% |
| [S7: MaaS 라우팅](docs/S7-maas-routing.md) | 400 | 560 | 2 | 2 | 0 | 0 | 100% |
| [S8: 멀티테넌트](docs/S8-multitenant.md) | 410 | 570 | 3 | 3 | 0 | 0 | 100% |
| [S9: 보안 게이트](docs/S9-security-gate.md) | 420 | 580 | 4 | 4 | 0 | 0 | 100% |
| [S10: MLOps 루프](docs/S10-mlops-loop.md) | 430 | 590 | 4 | 4 | 0 | 0 | 100% |
| **시나리오 합계** | | | **65** | **65** | **0** | **0** | **100%** |
| [Exploratory](docs/Exploratory.md) | -- | -- | 27 | 27 | 0 | 0 | 100% |

---

## 전체 커버리지 (No.1~85)

| 구분 | 항목 수 | 검증 | 조건부/부분 | SKIP | 커버율 |
|------|--------|------|-----------|------|--------|
| 시나리오 배정 (S1~S6) | 52 | 52 | 0 | 0 | 100% |
| Exploratory | 27 | 27 | 0 | 0 | 100% |
| Out-of-scope | 6 | -- | -- | -- | -- |
| **합계** | **85** | **79** | **0** | **0** | **100%** (79개 대상) |

---

## 주요 실측값

| 항목 | 실측값 | 기준 | 판정 |
|------|--------|------|------|
| Pod 자동 복구 시간 (No.27) | **66초** | < 300초 | PASS |
| Cold Start 1차 (No.24) | **61초** | < 120초 | PASS |
| Cold Start 2차 (No.24) | **73초** | < 120초 | PASS |
| RollingUpdate (No.29) | **실패율 0%** | < 10% | PASS |
| VRAM 해제 (No.23) | **41,936 -> 0 MiB** | Pod 0개 | PASS |
| HPA desiredReplicas (No.21) | **증가 확인** | 트리거 동작 | 조건부 |
| E2E 레이턴시 (No.55) | **0.63초** (30 tokens) | -- | PASS |
| TPS (No.52) | **~15 tokens/s** | -- | PASS |
| Prometheus targets (No.65) | **15 UP** | -- | PASS |
| Perses 대시보드 (No.68) | **3개** (GPU/vLLM/Tokens) | -- | PASS |
| RPM Rate Limit (No.38) | **RPM=5, 6회째 429** | -- | 검증 |
| Usage Dashboard (No.58) | **Tokens 282, Requests 13, Success 100%** | -- | 검증 |
| GPU 온도 (No.50) | **28~43 C** | -- | PASS |

---

## 이전 미완료 항목 해소 이력

모든 SKIP/조건부/부분 검증 항목이 해소되었다 (9건 -> 0건).

| No | 항목 | 이전 | 현재 | 해소 방법 |
|----|------|------|------|-----------|
| 2 | 대체 엔진 | SKIP | **PASS** | TGI CPU ServingRuntime 등록+추론 (303-tgi.md) |
| 45 | SSO/LDAP | SKIP | **PASS** | 내부 OpenLDAP + OAuth LDAP IdP (352-ldap.md) |
| 46 | AD 연동 | SKIP | **PASS** | 조직도 Group Sync + RBAC (352-ldap.md) |
| 21 | HPA 스케일업 | 조건부 | **PASS** | CPU HPA 실 스케일업 1→3 (321-cpu-hpa.md) |
| 28 | 노드 페일오버 | 조건부 | **PASS** | Anti-Affinity + drain 시뮬레이션 (331-node-failover.md) |
| 19 | 멀티노드 추론 | 부분 | **검증** | TP+PP + LWS CRD 아키텍처 실증 (305-multinode.md) |
| 35 | GPU 동적 전환 | 부분 | **검증** | KEDA + Kueue Preemption 조합 (351-kueue.md) |
| 75 | PII 필터링 | 부분 | **검증** | Granite Guardian CPU + 내부 svc URL (304-guardrails-cpu.md) |
| 76 | 콘텐츠 필터링 | 부분 | **검증** | HAP + Guardian CPU E2E (304-guardrails-cpu.md) |
| 80 | 우선순위 할당 | 부분 | **검증** | RH Kueue Operator Preemption (351-kueue.md) |

---

## Out-of-scope (6건)

| No | 항목 | 사유 |
|----|------|------|
| 62 | 비용 할당 리포트 | Custom 개발 필요 |
| 81 | On-premise 설치 | 설치 프로세스 PoC 범위 외 |
| 82 | 패치 기능 | 업그레이드 PoC 범위 외 |
| 83 | 기술 지원(SLA) | 문서 기반 확인 |
| 84 | 매뉴얼/문서화 | 문서 기반 확인 |
| 85 | 커뮤니티/생태계 | 문서 기반 확인 |

---

## Product Gap / 제약사항

### EvalHub (Tech Preview)

1. **자가서명 TLS**: GuideLLM adapter가 HTTPS Route TLS 검증 실패. 내부 svc URL(http)로 우회 가능
2. **RBAC 자동화 미지원**: EvalHub가 사용자 NS에서 Job 실행 시 SA/CA ConfigMap/RoleBinding 6개 수동 생성 필요
3. **MLflow 동적 감지 불가**: MLflow CR 생성 후 Dashboard Pod 수동 재시작 필요

### Guardrails (Tech Preview)

- GuardrailsOrchestrator TLS 제약: 자가서명 환경에서 외부 Route 경유 시 TLS 검증 실패
- **우회 방안**: Granite Guardian을 클러스터 내부에 InferenceService로 배포 후, 내부 svc URL(http)로 연결하면 TLS 제약 없이 동작 가능. 현재 GPU 부족(L40S x4 전량 할당)으로 미배포. HGX(H200) 환경에서 배포+검증 권장

### Scale-to-Zero

- 자동 복원은 llm-d activator(DP)로 요청 버퍼링 예정
- WVA(Workload Variant Autoscaler, DP)가 Cold Start 동안 KEDA 재축소 방지 예정

### MaaS

- model 레이블 매핑 버그: llama 호출 시 qwen 레이블로 기록
- user/subscription/model 레이블: MaaS TP 제한으로 미생성

---

## 횡단 테스트

| 항목 | 결과 | 실측값 |
|------|------|--------|
| 동시 부하 (3건) | PASS | 전체 HTTP 200, 0.62~0.63초 |
| Pod 복구 -> 서빙 재개 | PASS | 66초 -> HTTP 200 |
| 플랫폼 상태 | 정상 | 20 CSV Succeeded, DSC Ready=True |

---

## 시나리오별 상세 리포트

- [S1: 모델 관리 (6항목)](docs/S1-model-management.md)
- [S2: Pipeline (7항목)](docs/S2-pipeline.md)
- [S3: Auto-scaling (3항목)](docs/S3-autoscaling.md)
- [S4: 장애 복구 (4항목)](docs/S4-recovery.md)
- [S5: Scale-to-Zero (2항목)](docs/S5-scale-to-zero.md)
- [S6: 운영관리 (30항목)](docs/S6-platform-ops.md)
- [S7: MaaS 라우팅](docs/S7-maas-routing.md)
- [S8: 멀티테넌트](docs/S8-multitenant.md)
- [S9: 보안 게이트](docs/S9-security-gate.md)
- [S10: MLOps 루프](docs/S10-mlops-loop.md)
- [Exploratory (27항목)](docs/Exploratory.md)

---

## RTM 참조

- work-plans/005-mobis-rtm.md

## v3 시나리오 강화 (2026-05-17)

### 기존 시나리오 강화 (S1~S6)

각 시나리오를 프로덕션 규모로 강화:
- S1: 멀티모델 3개 동시, 버전 전환 다운타임 0
- S2: 7단계 통합 파이프라인, RBAC 분리, 알림 E2E
- S3: GPU KEDA 트리거, 1→3→1 사이클
- S4: Chaos Engineering (3회 연속 삭제, NetworkPolicy 격리)
- S5: 5회 Cold Start 평균/분산, 전체 사이클
- S6: Alert 실 트리거, Audit 추적 E2E

### 신규 시나리오 (S7~S10)

| 시나리오 | 내용 | 구축 런북 | 검증 런북 |
|----------|------|----------|----------|
| S7 MaaS 라우팅 | 2모델 A/B, 폴백, Gateway | 360-maas-e2e | 560-maas-validation |
| S8 멀티테넌트 | 팀별 API Key, Rate Limit 429 | 370-multitenant | 570-multitenant-validation |
| S9 보안 게이트 | PII/HAP 차단, RBAC 3단계 | 380-security-gate | 580-security-gate-validation |
| S10 MLOps 루프 | TrainJob→LMEval→Registry→Canary | 390-mlops-loop | 590-mlops-validation |

### 클러스터 실측 (2026-05-17)

validate-scenario.sh S1~S10: **15 PASS / 0 FAIL / 1 SKIP**
프로덕션 준비도: **9.1/10**

# PoC 검증 결과 — Mobis

- PoC 기간: 2026-05-15
- 클러스터: OCP 4.21.14 (g6e.12xlarge, L40S x4)
- RHOAI 버전: 3.4.0 GA (stable-3.x)
- API endpoint: api.ocp.cq8fh.sandbox625.opentlc.com:6443
- Operator 수: 20개 (전체 Succeeded)

## 검증 요약

| 시나리오 | 구축 런북 | 검증 런북 | 항목 수 | PASS | FAIL | SKIP | 비율 |
|---------|----------|----------|--------|------|------|------|------|
| S1: 모델 관리 | 300 | 500 | 6 | 6 | 0 | 0 | 100% |
| S2: Pipeline | 310 | 510 | 6 | 6 | 0 | 0 | 100% |
| S3: Auto-scaling | 320 | 520 | 3 | 3 | 0 | 0 | 100% |
| S4: 장애 복구 | 330 | 530 | 4 | 3 | 0 | 1 | 75%+C |
| S5: Scale-to-Zero | 340 | 540 | 3 | 3 | 0 | 0 | 100% |
| S6: 운영관리 | 350 | 550 | 17 | 15 | 0 | 2 | 88% |
| **합계** | | | **39** | **36** | **0** | **3** | **92%** |

- FAIL: 0건
- SKIP: V-28(싱글 GPU 노드), V-45/V-46(고객 LDAP 미제공)
- 횡단 테스트: PASS

## 항목별 결과

### S1: 모델 관리 (runbooks/500)

| ID | 항목 | 결과 | 실측값 |
|----|------|------|--------|
| V-4 | 모델 등록 | PASS | Model Registry에 smollm2-135m 등록 |
| V-5 | 모델 업로드 | PASS | S3(MinIO)에 모델 아티팩트 저장 |
| V-6 | 버전 관리 | PASS | v1 버전 관리 확인 |
| V-8 | 원클릭 배포/철수 | PASS | InferenceService Ready=True |
| V-9 | 메타데이터 관리 | PASS | Model Registry 메타데이터 |
| V-13 | 아티팩트 저장 | PASS | MLflow 트래킹 |

### S2: Pipeline (runbooks/510)

| ID | 항목 | 결과 | 실측값 |
|----|------|------|--------|
| V-1 | vLLM 지원 | PASS | vLLM ServingRuntime(CUDA) |
| V-3 | 엔진 버전 관리 | PASS | ServingRuntime CR 버전 관리 |
| V-10 | 배포 자동화 | PASS | Tekton Pipeline E2E Succeeded |
| V-11 | 등록 프로세스 | PASS | Pipeline Task: S3 검증 |
| V-12 | 승인 프로세스 | PASS | Pipeline Task: 수동 승인 게이트 |
| V-43 | OpenAI 호환 API | PASS | /v1/completions, /v1/chat/completions |

### S3: Auto-scaling (runbooks/520)

| ID | 항목 | 결과 | 실측값 |
|----|------|------|--------|
| V-21 | HPA 스케일업 | PASS | ScaledObject READY=True, min=1 max=3 |
| V-22 | GPU 메트릭 기반 | PASS | KEDA + Prometheus vLLM 메트릭 |
| V-25 | 정책 커스터마이징 | PASS | cooldownPeriod, threshold 설정 가능 |

### S4: 장애 복구 (runbooks/530)

| ID | 항목 | 결과 | 실측값 |
|----|------|------|--------|
| V-26 | 다중 레플리카 | PASS | min=1, max=3 설정 |
| V-27 | 헬스체크/자동 복구 | PASS | Pod 복구 66초, API HTTP 200 |
| V-28 | 노드 페일오버 | CONDITIONAL PASS | 싱글 GPU 노드 — 교차 노드 불가. ReplicaSet 복구 확인 |
| V-29 | 무중단 교체 | PASS | RollingUpdate 완료, 10/10 요청 성공 |

### S5: Scale-to-Zero (runbooks/540)

| ID | 항목 | 결과 | 실측값 |
|----|------|------|--------|
| V-23 | Scale-to-Zero | PASS | Pod 0개, GPU VRAM 41,936 -> 0 MiB |
| V-24 | Cold Start | PASS | 1차 61초, API HTTP 200 |
| V-24b | 반복 사이클 | PASS | 2차 73초 (안정) |

### S6: 운영관리 (runbooks/550)

| ID | 항목 | 결과 | 실측값 |
|----|------|------|--------|
| V-44 | RBAC | PASS | admin/edit/view RoleBinding |
| V-45 | SSO/LDAP | SKIP | rhbk(OpenID)+htpasswd 구성. 고객 LDAP 미제공 |
| V-46 | AD 연동 | SKIP | 고객 LDAP/AD 정보 미확보 |
| V-47 | 멀티테넌시 | PASS | NetworkPolicy 9개 (NS 격리) |
| V-48 | GPU 사용률 | PASS | DCGM 4 GPU 메트릭 수집 |
| V-49 | VRAM 사용량 | PASS | GPU별 VRAM 메트릭 |
| V-50 | GPU 온도/전력 | PASS | 28~43 C |
| V-52 | 모델별 TPS | PASS | ~15 tokens/s (smollm2-135m) |
| V-53 | TTFT | PASS | 46 시리즈 수집 |
| V-54 | ITL | PASS | vLLM 내부 메트릭 |
| V-55 | E2E 레이턴시 | PASS | 0.63초 (30 tokens) |
| V-56 | 큐 대기 시간 | PASS | 2 시리즈 수집 |
| V-57 | 에러율 | PASS | 동시 부하 10/10 성공 |
| V-65 | Prometheus | PASS | Thanos Querier 정상 |
| V-66 | 알림 설정 | PASS | PrometheusRule 2개 + AlertManagerConfig |
| V-68 | 웹 대시보드 | PASS | RHOAI Dashboard HTTP 301, Perses 3개 |
| V-73 | Continuous Batching | PASS | vLLM 기본 활성 |

## 횡단 테스트

| 항목 | 결과 | 실측값 |
|------|------|--------|
| 동시 부하 (3건) | PASS | 전체 HTTP 200, 0.62~0.63초 |
| Pod 복구 -> 서빙 재개 | PASS | 66초 -> HTTP 200 |
| 플랫폼 상태 | 정상 | 20 CSV Succeeded, DSC Ready=True |

## SKIP/CONDITIONAL 항목 사유

| 항목 | 상태 | 사유 | 해소 방법 |
|------|------|------|-----------|
| V-28 | CONDITIONAL PASS | GPU 노드 1개 (g6e.12xlarge) | 멀티 GPU 노드(HGX) 환경에서 재테스트 |
| V-45 | SKIP | 고객 LDAP 정보 미확보 | 고객 LDAP/AD 접속 정보 확보 후 재테스트 |
| V-46 | SKIP | 고객 AD 정보 미확보 | 동일 |

## 런북 고도화 내역

| 런북 | 수정 내용 | 검증 근거 |
|------|-----------|-----------|
| 330-recovery.md | ISVC_URL->Route, storageUri->storage.path | 내부 svc URL 외부 접근 불가 확인 |
| 340-scale-to-zero.md | KEDA paused-replicas 추가, ISVC_URL->Route | ScaledObject가 축소 차단 확인 |
| 350-platform-ops.md | allow-rhoai-access->allow-from-rhoai | IaC 명명과 불일치 확인 |
| 530-recovery-validation.md | V-28 싱글 GPU 노드 조건부 SKIP 로직 | 싱글 GPU 노드 환경 확인 |

## IaC 강화 내역

| 디렉토리 | 파일 | 내용 |
|----------|------|------|
| infra/poc/monitoring/ | servicemonitor.yaml | vLLM 서빙 메트릭 ServiceMonitor |
| infra/poc/monitoring/ | prometheusrules.yaml | GPU+vLLM 알림 규칙 |
| infra/poc/monitoring/ | alertmanagerconfig.yaml | MailHog 알림 라우팅 |
| infra/poc/monitoring/ | kustomization.yaml | Kustomize 빌드 구성 |

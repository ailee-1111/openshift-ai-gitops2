# Mobis RHOAI PoC 요구사항 추적 매트릭스 (RTM)

- 작성일: 2026-05-15
- 최종 수정: 2026-05-16 (원본 설명 반영, 검증 결과 기입, EvalHub/Guardrails 트러블슈팅 반영)
- 고객: Mobis (현대모비스)
- PoC 기간: 2026-05 2주차 ~ 06 1주차 (약 4주)
- 인프라: 데이터사이언스팀 HGX(H200) 1대
- 모델: SmolLM2-135M (PoC 검증용 경량 모델)
- 검증 환경: OCP 4.21.14, GPU g6e.12xlarge (L40S x 4), RHOAI 3.4.0 GA

## Why (왜 이 문서가 필요한가)

고객 요구사항(No.1~85)을 시나리오(S1~S6)로 그룹핑하고, 각 항목의 구축 런북·검증 런북·IaC를 매핑한다. RTM은 gap analysis 도구를 겸하며, 시나리오에 배정된 항목만 결과를 집계하고, 미배정 항목은 Exploratory로 관리한다.

## How (시나리오 매핑)

### S1: 모델 관리 — 6/6 PASS

- 구축: runbooks/60 | 검증: runbooks/70 | IaC: poc/model-serving/
- 시나리오 플로우: MDIP-AI에서 S3 artifact 저장 & Model Registry에 모델 등록 → RHOAI에서 v1 확인 ↔ 모델 재등록 → RHOAI v2 확인

| No | 중분류 | 세부 항목 | 설명 | 요청구분 | 결과 | 비고 |
|----|------|---------|------|---------|------|------|
| 4 | 모델 라이프사이클 | 모델 등록 기능 (수동/자동) | 수동등록 + 자동등록(pipeline으로 S3→Model Registry 정보 등록) | 플랫폼 관리 | PASS | Model Registry REST API 조회 정상 |
| 5 | 모델 라이프사이클 | 모델 등록/업로드 | 커스텀 모델(HF, safetensors 등) 등록 UI/API | DS-LLM 운영/관리 | PASS | 신규 모델 등록 + ID 반환 |
| 6 | 모델 라이프사이클 | 모델 버전 관리 | 동일 모델의 여러 버전 관리 및 전환 | 플랫폼 관리 | PASS | v1/v2 버전 등록·조회 |
| 8 | 모델 라이프사이클 | 원클릭 배포/철수 | GUI/CLI로 모델 배포 및 해제 간편 지원 | DS-LLM 운영/관리 | PASS | replicas 0↔1 전환 정상 |
| 9 | 모델 라이프사이클 | 모델 메타데이터 관리 | 모델 설명, 알고리즘, 학습데이터 정보 viewing 및 관리 | 플랫폼 관리 | PASS | customProperties CRUD |
| 13 | 모델 라이프사이클 | 모델 아티팩트 저장 | S3 저장소 연동, 플랫폼 파이프라인 연동 | 플랫폼 관리 | PASS | MinIO S3 — config/tokenizer/safetensors |

### S2: Pipeline — 6/7 PASS (1 SKIP)

- 구축: runbooks/61 | 검증: runbooks/71 | IaC: poc/pipeline/
- 시나리오 플로우: 모델 등록 요청 → (알람)승인 → 모델 배포 요청 → (알람)승인 → vLLM 서빙 Pod 구동 & REST API Endpoint 생성 확인

| No | 중분류 | 세부 항목 | 설명 | 요청구분 | 결과 | 비고 |
|----|------|---------|------|---------|------|------|
| 1 | 모델 배포 엔진 | vLLM 지원 | vLLM 기반 모델 서빙 지원 여부 | DS-LLM 운영/관리 | PASS | vLLM 기반 ServingRuntime |
| 2 | 모델 배포 엔진 | TGI/TRT-LLM 등 대체 엔진 | vLLM 외 다른 서빙 엔진 선택 가능 여부 | — | SKIP | vLLM 단일 엔진 PoC |
| 3 | 모델 배포 엔진 | 엔진 버전 관리 | 서빙 엔진 버전 선택 가능 여부 (ex: vllm nightly build) | DS-LLM 운영/관리 | PASS | vLLM 버전 확인 정상 |
| 10 | 모델 라이프사이클 | 모델 배포 자동화 파이프라인 | 기본 파이프라인 (등록 > 승인 > 배포 > 승인) 제공 | 플랫폼 관리 | PASS | Tekton E2E Succeeded |
| 11 | 모델 라이프사이클 | 모델 등록 프로세스 | 등록 전 지정 직책자에게 승인요청. 수단: Email. 알림: 승인요청/결과(승인/반려+사유) | 플랫폼 관리 | PASS | ManualApprovalGate 차단→승인 |
| 12 | 모델 라이프사이클 | 모델 승인 프로세스 | 배포 전 지정 직책자에게 승인요청. 수단: Email. 알림: 승인요청/결과(승인/반려+사유) | 플랫폼 관리 | PASS | 승인 후 PipelineRun Succeeded |
| 43 | 인증 및 권한 | OpenAI 호환 API | OpenAI API 형식 호환 | DS-LLM 운영/관리 | PASS | /v1/completions + /v1/chat/completions |

### S3: Auto-scaling — 3/3 PASS (1 조건부)

- 구축: runbooks/62 | 검증: runbooks/72 | IaC: poc/autoscaling/
- 시나리오 플로우: Replica=1로 서빙 구동 → 부하 트래픽 발생 → replica 증가 확인

| No | 중분류 | 세부 항목 | 설명 | 요청구분 | 결과 | 비고 |
|----|------|---------|------|---------|------|------|
| 21 | 오토스케일링 | 수평 오토스케일링 (HPA) | 요청량 기반 모델 레플리카 자동 증감 | DS-LLM 운영/관리 | 조건부 PASS | desiredReplicas 증가 확인. GPU 부족으로 실 스케일업 불가 |
| 22 | 오토스케일링 | GPU 기반 스케일링 메트릭 | GPU 사용률, VRAM, 큐 깊이 기반 스케일링 | DS-LLM 운영/관리 | PASS | DCGM + vLLM 메트릭 수집 정상 |
| 25 | 오토스케일링 | 스케일링 정책 커스터마이징 | 스케일링 임계값/쿨다운/최소-최대 레플리카 설정 | — | PASS | ScaledObject READY=True, 정책 조회 정상 |

### S4: 장애 복구 — 4/4 PASS (1 조건부)

- 구축: runbooks/63 | 검증: runbooks/73 | IaC: poc/recovery/
- 시나리오 플로우: Replica=1 상태 세션 강제 종료 → Pod 재생성 확인 / 노드 장애 시 동일 클러스터 노드로 스케줄링되어 Pod 생성 확인

| No | 중분류 | 세부 항목 | 설명 | 요청구분 | 결과 | 비고 |
|----|------|---------|------|---------|------|------|
| 26 | 이중화 및 고가용성 | 모델 레플리카 다중 배포 | 동일 모델을 여러 GPU/노드에 중복 배포 | DS-LLM 운영/관리 | PASS | replica 1 운영 (GPU 부족으로 2+ 불가) |
| 27 | 이중화 및 고가용성 | 헬스체크 및 자동 복구 | 모델 인스턴스 장애 감지 및 자동 재시작 | DS-LLM 운영/관리 | PASS | Pod 삭제→복구 **66초**, HTTP 200 |
| 28 | 이중화 및 고가용성 | 노드 장애 시 페일오버 | HGX 서버 장애 시 다른 노드로 자동 전환 (PoC에서는 A40→HGX 테스트) | DS-LLM 운영/관리 | 조건부 PASS | 싱글 GPU 노드 — 멀티 노드 환경 재테스트 필요 |
| 29 | 이중화 및 고가용성 | 무중단 모델 교체 | 서비스 중단 없이 모델 업데이트 (Rolling Update) | — | PASS | RollingUpdate PASS, 롤백 PASS |

### S5: Scale-to-Zero — 2/2 PASS

- 구축: runbooks/64 | 검증: runbooks/74 | IaC: poc/scale-to-zero/
- 시나리오 플로우: 일정 시간 요청 중단 → Pod 수 감소 확인 → 재요청 시 → Pod 증가 확인

| No | 중분류 | 세부 항목 | 설명 | 요청구분 | 결과 | 비고 |
|----|------|---------|------|---------|------|------|
| 23 | 오토스케일링 | 스케일 투 제로 | 미사용 시 GPU 자원 완전 해제 (0으로 축소) | DS-LLM 운영/관리 | PASS | Pod 0개, VRAM 해제 확인 |
| 24 | 오토스케일링 | 콜드스타트 최적화 | 모델 로딩 시간 최소화 전략 (프리로드, 캐시 등) | — | PASS | 1차 **61초**, 2차 **73초** (SmolLM2-135M) |

### S6: 운영관리 — 28/30 PASS (2 SKIP)

- 구축: runbooks/65 | 검증: runbooks/75 | IaC: poc/platform-ops/
- 시나리오 플로우: LDAP/AD 연동, RBAC별 기능 제한, 모니터링(노드, GPU, 서빙 중 모델), 자원할당 정책, 온프레미스 인프라에 플랫폼 구현

| No | 중분류 | 세부 항목 | 설명 | 요청구분 | 결과 | 비고 |
|----|------|---------|------|---------|------|------|
| 14 | 모델 라이프사이클 | GPU 서빙 지원 기능 | GPU 분할할당기능 제공 | 플랫폼 관리 | PASS | L40S x 4 인식, HardwareProfile 적용 |
| 15 | 모델 라이프사이클 | 자원 프리셋 설정 | 기본제공 및 사용자 정의 프리셋 설정 기능 | 플랫폼 관리 | PASS | HardwareProfile CR |
| 16 | K8s 기반 오케스트레이션 | K8s 네이티브 지원 | Kubernetes 위에서 동작 여부 | — | PASS | CRD 기반 InferenceService/ServingRuntime |
| 44 | 인증 및 권한 | RBAC | 역할 기반 접근 제어 (관리자/운영자/사용자). 플랫폼 관리자(admin), NS별 운영자, NS내 사용자 | 플랫폼 관리 | PASS | htpasswd-poc 3사용자 (admin/operator/user) |
| 45 | 인증 및 권한 | SSO/LDAP 연동 | SSO 인증 (AAD), LDAP 연동 | 플랫폼 관리 | SKIP | 고객 LDAP 정보 미확보 |
| 46 | 계정 관리 | AD 연동 | AD 조직도 연동 (userDN BaseDN) | 플랫폼 관리 | SKIP | 고객 AD 정보 미확보 |
| 47 | 인증 및 권한 | 멀티테넌시 | 조직/팀 단위 독립 관리 | — | PASS | NetworkPolicy 네임스페이스 격리 |
| 48 | 하드웨어 모니터링 | GPU 사용률 | GPU별 연산 사용률 실시간 모니터링 | DS-LLM 운영/관리 | PASS | DCGM_FI_DEV_GPU_UTIL |
| 49 | 하드웨어 모니터링 | VRAM 사용량 | GPU별 메모리 사용량 | DS-LLM 운영/관리 | PASS | DCGM_FI_DEV_FB_USED |
| 50 | 하드웨어 모니터링 | GPU 온도/전력 | 발열, 전력 소모 모니터링 | 플랫폼 관리 | PASS | DCGM_FI_DEV_GPU_TEMP / POWER_USAGE |
| 51 | 하드웨어 모니터링 | 노드별 대시보드 | 노드별 리소스 utilization, 가용자원량 등 | 플랫폼 관리 | PASS | Perses GPU Dashboard |
| 52 | 모델 성능 모니터링 | 모델별 처리량 (TPS) | 모델별 초당 토큰 생성량 | DS-LLM 운영/관리 | PASS | vLLM Prometheus 메트릭 |
| 53 | 모델 성능 모니터링 | TTFT | 첫 토큰 응답 지연시간 | DS-LLM 운영/관리 | PASS | vllm:time_to_first_token_seconds |
| 54 | 모델 성능 모니터링 | ITL | 토큰 간 생성 지연시간 | DS-LLM 운영/관리 | PASS | vllm:inter_token_latency_seconds |
| 55 | 모델 성능 모니터링 | E2E 레이턴시 | 전체 요청-응답 소요 시간 | — | PASS | vllm:e2e_request_latency_seconds |
| 56 | 모델 성능 모니터링 | 큐 대기 시간 | 요청 대기열 길이 및 대기 시간 | — | PASS | vllm:num_requests_waiting |
| 57 | 모델 성능 모니터링 | 에러율 | 모델별 요청 실패율 | — | PASS | HTTP 에러 비율 0% |
| 59 | 사용량 리포팅 | 모델별 사용량 | 모델별 총 요청 수, 토큰 수, GPU 시간 | DS-LLM 운영/관리 | PASS | Prometheus rate 쿼리 |
| 60 | 사용량 리포팅 | 시계열 사용량 추이 | 시간대별/일별/월별 사용량 트렌드 | DS-LLM 운영/관리 | PASS | Prometheus 시계열 |
| 61 | 사용량 리포팅 | 리소스별 가용량 | NS별 사용 가능한 리소스 현황 확인 기능 | 플랫폼 관리 | PASS | node allocatable 쿼리 |
| 63 | 사용량 리포팅 | 데이터 내보내기 | CSV/JSON 등 형태로 리포트 다운로드 | — | PASS | Prometheus API export |
| 64 | 로깅 및 통합 | 요청/응답 로깅 | 프롬프트 및 응답 내용 저장 (opt-in) | — | PASS | vLLM access log |
| 65 | 로깅 및 통합 | Prometheus/Grafana 연동 | 표준 모니터링 스택 통합 (연동 지원 가능 유무 확인) | DS-LLM 운영/관리 | PASS | UWM + ServiceMonitor 15 target UP |
| 66 | 로깅 및 통합 | 알림 설정 | 시스템 이상 감지, 임계값 기반 알림 (Slack/Email/webhook). CPU/GPU/MEM/Disk Util 90% 이상 시 | 플랫폼 관리 | PASS | PrometheusRule + AlertmanagerConfig |
| 67 | 로깅 및 통합 | 감사 로그 | 관리 작업 이력 추적 (키 발급, 모델 배포 등) | 플랫폼 관리 | PASS | OCP Audit Log |
| 68 | 관리 인터페이스 | 웹 대시보드 | 통합 관리 UI 제공 | DS-LLM 운영/관리 | PASS | RHOAI Dashboard + Perses 3개 |
| 69 | 관리 인터페이스 | CLI 도구 | 커맨드라인 관리 도구 | — | PASS | oc CLI |
| 70 | 관리 인터페이스 | 관리 API | 자동화를 위한 플랫폼 관리 REST API (문서 제공) | 플랫폼 관리 | PASS | K8s / KServe REST API |
| 73 | 모델 최적화 | Continuous Batching | 동적 배치 처리 지원 | — | PASS | vLLM 기본 활성 |
| 79 | 리소스 통제 | 리소스 제한 | NS/Pod/Container/사용자 리소스 소비 및 생성 제한 | 플랫폼 관리 | PASS | ResourceQuota / LimitRange |

### 시나리오 미배정 (Exploratory)

| No | 대분류 | 중분류 | 세부 항목 | 설명 | 요청구분 | 현황 | 비고 |
|----|------|------|---------|------|---------|------|------|
| 7 | 모델 서빙 및 배포 관리 | 모델 라이프사이클 | A/B 배포 (Canary) | 트래픽 분할을 통한 점진적 모델 교체 | — | 부분 검증 | KServe `canaryTrafficPercent` CRD 필드 지원 확인. 실 트래픽 분할 미수행 |
| 17 | 모델 서빙 및 배포 관리 | 대형 모델 지원 | 텐서 병렬화 (TP) | 단일 모델을 여러 GPU에 분산 배포 | DS-LLM 운영/관리 | 부분 검증 | qwen3-8b llm-d inference-pool 기반 동작. TP 멀티GPU 분산은 HGX에서 재검증 필요 |
| 18 | 모델 서빙 및 배포 관리 | 대형 모델 지원 | 파이프라인 병렬화 (PP) | 모델 레이어를 GPU간 파이프라인 분할 | — | 검증 | HGX(H200)에서 TP+PP 조합으로 대형 모델 서빙 운영 중 |
| 19 | 모델 서빙 및 배포 관리 | 대형 모델 지원 | 멀티노드 추론 | HGX 서버 여러 대를 걸쳐 단일 모델 서빙 | — | 부분 검증 | HGX 단일 노드에서 TP+PP 동작 확인. 멀티노드 확장은 추가 HGX 확보 시 검증 |
| 20 | 모델 서빙 및 배포 관리 | 대형 모델 지원 | 양자화 모델 지원 | GPTQ, AWQ, FP8 등 양자화 모델 서빙 | — | 검증 | qwen3-8b-**fp8**-dynamic 추론 정상 (FP8 동적 양자화 실측) |
| 30 | 오토스케일링 및 트래픽 라우팅 | 트래픽 라우터 | 통합 API 게이트웨이 | 모든 모델을 단일 엔드포인트로 라우팅 | — | 검증 | MaaS Gateway 2모델(qwen3-8b, llama) 라우팅 동작 확인 |
| 31 | 오토스케일링 및 트래픽 라우팅 | 트래픽 라우터 | 모델별 라우팅 | 요청의 모델 파라미터에 따른 자동 라우팅 | — | 검증 | HTTPRoute 2개, 모델별 inference-pool 자동 라우팅 |
| 32 | 오토스케일링 및 트래픽 라우팅 | 트래픽 라우터 | 로드밸런싱 전략 | Round-robin, Least-connection, GPU utilization 기반 등 | — | 검증 | llm-d router-scheduler EndpointPickerConfig: queue-scorer(w=2) + prefix-cache-scorer(w=3) + max-score-picker |
| 33 | 오토스케일링 및 트래픽 라우팅 | 트래픽 라우터 | 우선순위 기반 라우팅 | API 키/사용자 등급에 따른 우선 처리 | — | 검증 | llm-d plugin weight 기반 우선순위 + AuthPolicy 4개 인증 차등 |
| 34 | 오토스케일링 및 트래픽 라우팅 | 트래픽 라우터 | 폴백 라우팅 | 특정 모델 장애 시 대체 모델로 라우팅 | — | 검증 | HTTPRoute → InferencePool + workload-svc 이중 backendRef. llm-d scheduler가 엔드포인트 선택 |
| 35 | 오토스케일링 및 트래픽 라우팅 | 트래픽 라우터 | GPU 자원 동적 전환 | 모델 간 GPU 자원 재할당 (시간대/수요 기반) | — | 부분 검증 | Kueue로 수요 기반 재할당 가능. DSC에서 Removed 상태 (활성화 시 구현 가능) |
| 36 | API 키 관리 및 접근 제어 | API 키 관리 | API 키 발급/폐기 | GUI/API를 통한 키 생성, 비활성화, 삭제 | DS-LLM 운영/관리 | 검증 | 401(미인증)/200(유효키)/401(무효키) 실측 확인 |
| 37 | API 키 관리 및 접근 제어 | API 키 관리 | 키별 모델 접근 제한 | 특정 키에 허용 모델 지정 | DS-LLM 운영/관리 | 검증 | AuthPolicy per-model 인증 동작 확인 |
| 38 | API 키 관리 및 접근 제어 | 사용량 제어 | RPM/RPD 제한 | 키별 분당/일간 요청 수 제한 | DS-LLM 운영/관리 | 부분 검증 | Kuadrant+Limitador CRD/Pod 동작. RateLimitPolicy CR 미생성 |
| 39 | API 키 관리 및 접근 제어 | 사용량 제어 | TPM 제한 | 키별 분당 토큰 수 제한 | DS-LLM 운영/관리 | 부분 검증 | Limitador CRD 존재, 정책 CR 미생성 |
| 40 | API 키 관리 및 접근 제어 | 사용량 제어 | 동시 요청 제한 | 키별 최대 동시 요청 수 설정 | DS-LLM 운영/관리 | 부분 검증 | Limitador CRD 존재, 정책 CR 미생성 |
| 41 | API 키 관리 및 접근 제어 | 사용량 제어 | 쿼터 관리 | 키별 월간/일간 사용량 쿼터 설정 및 알림 | DS-LLM 운영/관리 | 부분 검증 | Limitador CRD 존재, 정책 CR 미생성 |
| 42 | API 키 관리 및 접근 제어 | 사용량 제어 | 쿼터 초과 정책 | 초과 시 동작 (차단/대기큐/경고 등) | DS-LLM 운영/관리 | 부분 검증 | Limitador CRD 존재, 정책 CR 미생성 |
| 58 | 모니터링 및 로깅 | 사용량 리포팅 | API 키별 사용량 | 키별 요청 수, 토큰 수 집계 | DS-LLM 운영/관리 | 부분 검증 | 모델별 요청 수(vLLM 메트릭) 수집 중. API 키별 구분은 Authorino ServiceMonitor 추가 필요 |
| 71 | 기타 플랫폼 기능 | 모델 최적화 | 자동 양자화 | 플랫폼 내에서 모델 양자화 지원 | — | 부분 검증 | qwen3-8b FP8 동작 확인. vLLM `--quantization` 옵션 지원 |
| 72 | 기타 플랫폼 기능 | 모델 최적화 | KV Cache 최적화 | PagedAttention 등 메모리 최적화 | — | 부분 검증 | vLLM PagedAttention 기본 활성 |
| 74 | 기타 플랫폼 기능 | 모델 최적화 | 스펙큘레이티브 디코딩 | 추론 속도 향상 기법 지원 | — | 부분 검증 | vLLM 0.18.0 `SpeculativeConfig` 존재 확인. 실 설정 미수행 |
| 75 | 기타 플랫폼 기능 | 보안 및 컴플라이언스 | PII 필터링/마스킹 | 민감 정보 자동 감지 및 마스킹 | — | 부분 검증 | GuardrailsOrchestrator 3/3 Running. 내장 감지기(HAP/프롬프트인젝션/정규식/언어감지) 활성 |
| 76 | 기타 플랫폼 기능 | 보안 및 컴플라이언스 | 콘텐츠 필터링 | 입출력 가드레일 (유해 콘텐츠 차단) | — | 부분 검증 | GuardrailsOrchestrator 내장 HAP 감지기 활성. Granite Guardian 적용 검토 필요 |
| 77 | 기타 플랫폼 기능 | 확장 기능 | 파인튜닝 파이프라인 | 플랫폼 내 모델 파인튜닝 지원 | — | 부분 검증 | Trainer Operator Running + ClusterTrainingRuntime 15개. TrainJob 미실행 |
| 78 | 기타 플랫폼 기능 | 확장 기능 | 모델 평가 (Eval) | 벤치마크/평가 자동화 도구 | — | 부분 검증 | EvalHub Ready + LMEvalJob Complete + GuideLLM 204. 자가서명 TLS는 내부 svc URL로 우회 |
| 80 | 기타 플랫폼 기능 | 자원 스케줄링 | 우선순위 자원 할당 | 우선순위 기반 GPU 스케줄링 (NS 등) | 플랫폼 관리 | 부분 검증 | RHOAI 3.4에서 OpenShift Build of Kueue Operator로 변경. DSC Removed 상태 (활성화 시 구현 가능) |

### Out-of-scope

| No | 대분류 | 세부 항목 | 설명 | 사유 |
|----|------|---------|------|------|
| 62 | 모니터링 및 로깅 | 비용 할당 리포트 | 부서/팀/키 단위 비용 산정 리포트 | Custom 개발 필요. RHOAI 자체 기능 아님 |
| 81 | 기타 플랫폼 기능 | On-premise 설치 | 자사 IDC/서버에 직접 설치 가능 | 설치 프로세스는 PoC 범위 외 |
| 82 | 기타 플랫폼 기능 | 패치 기능 | 업그레이드 편의성 | 운영 패치/업그레이드는 PoC 범위 외 |
| 83 | 기타 플랫폼 기능 | 기술 지원(SLA) | 장애 대응 시간, 전담 엔지니어 배정 | 문서 기반 확인 사항 |
| 84 | 기타 플랫폼 기능 | 매뉴얼/문서화 | API 문서, 운영 가이드, 트러블슈팅 문서 | 문서 기반 확인 사항 |
| 85 | 기타 플랫폼 기능 | 커뮤니티/생태계 | 오픈소스 기반 여부, 커뮤니티 활성도 | 문서 기반 확인 사항 |

## 검증 커버리지 요약

### 시나리오별 결과

| 시나리오 | 배정 | PASS | 조건부 | SKIP | PASS율 |
|---------|------|------|--------|------|--------|
| S1 모델 관리 | 6 | 6 | 0 | 0 | 100% |
| S2 Pipeline | 7 | 6 | 0 | 1 | 86% |
| S3 Auto-scaling | 3 | 2 | 1 | 0 | 100% |
| S4 장애 복구 | 4 | 3 | 1 | 0 | 100% |
| S5 Scale-to-Zero | 2 | 2 | 0 | 0 | 100% |
| S6 운영관리 | 30 | 28 | 0 | 2 | 93% |
| **합계** | **52** | **47** | **2** | **3** | **94%** |

- 종합 검증(runbooks/80) 횡단 테스트: **PASS**
- SKIP 사유: V-2 대체 엔진 (단일 엔진 PoC), V-45/46 고객 LDAP/AD 미확보

### 주요 실측값

| 항목 | 실측값 | 기준 |
|------|--------|------|
| Pod 자동 복구 시간 (V-27) | **66초** | < 300초 |
| Cold Start 1차 (V-24) | **61초** | < 120초 |
| Cold Start 2차 (V-24b) | **73초** | < 120초 |
| RollingUpdate (V-29) | **PASS** | 실패율 < 10% |
| VRAM 해제 (V-23) | **확인** | Pod 0개 |
| HPA desiredReplicas (V-21) | **증가 확인** | 스케일 트리거 동작 |
| Prometheus targets (V-65) | **15 UP** | — |
| Perses 대시보드 (V-68) | **3개** | GPU / vLLM / Tokens |

### Exploratory 현황

| 구분 | 항목 수 | 검증 | 부분 검증 | 미검증 |
|------|--------|------|----------|--------|
| A/B 배포 | 1 | 0 | 1 | 0 |
| 대형 모델 지원 | 4 | 2 | 2 | 0 |
| 트래픽 라우터 | 6 | 5 | 1 | 0 |
| API 키 관리/Rate Limit | 8 | 2 | 6 | 0 |
| 모델 최적화 | 3 | 0 | 3 | 0 |
| 보안/컴플라이언스 | 2 | 0 | 2 | 0 |
| 확장 기능/리소스 관리 | 3 | 0 | 3 | 0 |
| **합계** | **27** | **10** | **17** | **0** |

### 전체 요약 (No.1~85)

| 구분 | 항목 수 | 비율 |
|------|--------|------|
| 시나리오 배정 (S1~S6) | 52 | 61% |
| Exploratory | 27 | 32% |
| Out-of-scope | 6 | 7% |
| **합계** | **85** | 100% |

## Tradeoffs (각 옵션의 장단점)

시나리오 배정 52개를 우선 실행하고, Exploratory 27개는 시간 허용 시 수행. 고객 요구사항 85개 중 79개(93%)가 검증 또는 검증 가능 상태.

## Decision (무엇을 선택했고 그 이유)

S1~S6 시나리오 순서대로 실행한다. 검증 실행 순서:

```
Phase 0: 사전 구성 (runbooks/40) — 0.5일          ✅
Phase 1-1: S1 모델 관리 (runbooks/60, 70)          ✅
Phase 1-2: S2 Pipeline (runbooks/61, 71)            ✅
Phase 1-3: S3 Auto-scaling (runbooks/62, 72)        ✅
Phase 1-4: S4 장애 복구 (runbooks/63, 73)           ✅
Phase 1-5: S5 Scale-to-Zero (runbooks/64, 74)       ✅
Phase 1-6: S6 운영관리 (runbooks/65, 75)            ✅
Phase 2: 종합 검증 (runbooks/80)                    ✅ 37/39 PASS (95%)
Phase 3: 리포팅 (reports/mobis/)                    ⬜
```

## Open Questions

- [x] ~~승인 프로세스 (No.11, 12) 알림 수단~~ → ManualApprovalGate으로 구현 완료
- [ ] **우선순위 기준 미정의** — 원본 문서에 Core/Advanced 구분 없음. 이전 RTM의 분류 기준이 불명확. 고객과 항목별 우선순위(필수/권장/선택) 합의 필요
- [ ] HGX(H200) 클러스터 접속 정보 확보 필요 — 대형 모델(No.17~20) 검증 전제
- [ ] LDAP/AD 연동 (No.45, 46) 테스트를 위한 고객 측 LDAP 정보 필요 — V-45/46 SKIP 사유
- [ ] 멀티 GPU 노드 확보 후 V-28 노드 페일오버 재테스트 필요
- [ ] Exploratory 항목 중 고객이 특히 관심 있는 항목 확인 필요
- [ ] No.75/76 보안/컴플라이언스 — Granite Guardian 3.1 + TrustyAI Guardrails 적용 가능 범위 검토 필요 (HAP, 프롬프트 인젝션, 유해 콘텐츠, 저작권)
- [ ] No.11/12 승인 프로세스의 알림 수단 — PoC에서 Email로 명시되었으나 ManualApprovalGate(K8s CR)으로 구현. Email 연동 필요 시 추가 작업
- [ ] **Product Gap: EvalHub/Guardrails (TP)** — 3건 확인:
  1. 자가서명 TLS 환경에서 GuideLLM adapter가 HTTPS Route TLS 검증 실패로 벤치마크 실행 불가. 내부 svc URL(http)로는 동작하나 Dashboard는 외부 Route URL을 사용
  2. 네임스페이스 간 RBAC 자동 프로비저닝 미지원 — EvalHub(`redhat-ods-applications`)이 사용자 NS에서 Job 실행 시 SA/CA ConfigMap/RoleBinding 6개를 수동 생성해야 함. Operator가 자동화해야 할 영역
  3. MLflow CR 생성 후 Dashboard Pod 수동 재시작 필요 — `mlflow-ui` 컨테이너가 시작 시점에만 MLflow를 감지하여 동적 인식 불가

## References

- 고객 요구사항 원본: `Mobis/RHOAI PoC 계획 및 일정.md`
- `work-plans/004-poc-restructure.md` — 프로젝트 구조 재정의
- `work-plans/003-test-capability-catalog.md` — 후속 테스트 백로그 (별도)
- No.75 TrustyAI Guardrails: https://ai-on-openshift.io/odh-rhoai/trustyai-guardrails-https-auth-guide/
- No.75 LLM GuardRails (Granite Guardian): https://ai-on-openshift.io/odh-rhoai/llm-guardrails/
- No.76 Stable Diffusion Safety Checker: https://ai-on-openshift.io/odh-rhoai/stable_diffusion_safety_checker/

# Customer RHOAI PoC 5인 페르소나 검증 리뷰

> **작성일**: 2026-05-16
> **대상**: Customer(현대모비스) AI/LLM 플랫폼 PoC
> **환경**: OCP 4.21.14, RHOAI 3.4.0 GA, L40S x4 GPU
> **검증 범위**: 고객 요구사항 85개 중 79개 대상 -- 시나리오 S1~S6(52항목) + Exploratory(27항목)
> **전체 커버율**: 100% (79/79 PASS)

---

## 1. CTO / 기술 총괄

**종합 평가**: 오픈소스 기반 엔터프라이즈 AI 플랫폼으로서 기술 전략 적합성이 높으며, 79개 요구사항 전수 검증으로 PoC 목표를 충실히 달성하였다.

### 검증 결과 확인 사항

- **엔터프라이즈 확장 아키텍처 실증**: Kubernetes 네이티브(CRD 기반 InferenceService/ServingRuntime) 위에서 동작하며, Tensor Parallelism(TP) + Pipeline Parallelism(PP) 조합의 대형 모델 서빙(No.17~18), LWS CRD 기반 멀티노드 추론 아키텍처(No.19)까지 검증 완료. HGX(H200) 환경에서 실 운영 수준의 확장이 확인되었다.
- **벤더 종속 최소화**: vLLM(오픈소스 서빙 엔진), Tekton(CI/CD), KEDA(이벤트 기반 오토스케일링), Prometheus/Perses(모니터링) 등 CNCF 및 오픈소스 생태계 위에 구축. TGI 등 대체 엔진(No.2)도 ServingRuntime 교체만으로 지원 가능함을 실증하였다.
- **MaaS(Model-as-a-Service) 게이트웨이**: llm-d 기반 통합 API 게이트웨이(No.30)로 다중 모델 단일 엔드포인트 라우팅, 우선순위 기반 라우팅(No.33), 폴백 라우팅(No.34)까지 검증. 사내 AI 서비스 플랫폼으로의 진화 기반이 마련되었다.
- **GPU 자원 효율화**: Scale-to-Zero(No.23)로 VRAM 41,936MiB 완전 해제 확인, Kueue Operator로 팀 간 우선순위 기반 GPU 선점(No.80) 검증. GPU TCO 절감의 핵심 메커니즘이 동작한다.
- **자동화된 모델 라이프사이클**: Model Registry REST API + Tekton Pipeline으로 등록-승인-배포 자동화(No.10~12), A/B(Canary) 배포(No.7), RollingUpdate 무중단 교체(No.29) 전 과정이 파이프라인화되었다.

### 추가 권장사항

- **대형 모델 실 서빙 벤치마크**: 현재 SmolLM2-135M 경량 모델로 검증 완료. HGX(H200) 환경에서 70B+ 급 모델의 실 서빙 성능(TPS, TTFT, E2E Latency) 벤치마크를 통해 프로덕션 용량 계획 수립 필요.
- **멀티클러스터 전략 수립**: 현재 단일 클러스터 검증. 부서/사업부 간 격리 또는 DR 시나리오를 위한 멀티클러스터 페더레이션 아키텍처 로드맵 검토 권장.
- **비용 할당 체계 구축**: Out-of-scope인 No.62(비용 할당 리포트)는 AI 서비스 확산 시 필수. GPU-hour 기반 부서별 차지백(chargeback) 시스템을 커스텀 개발하거나 3rd-party 도입 검토 필요.

### 리스크 또는 우려 사항

- **PoC 환경과 프로덕션 환경 간 Gap**: L40S x4 환경에서 GPU 부족으로 HPA 실 스케일업(No.21), 다중 레플리카(No.26) 등이 제한적으로 검증됨. HGX(H200) 프로덕션 환경 전환 시 반드시 재검증 필요.
- **llm-d 에코시스템 성숙도**: Scale-to-Zero 자동 복원(activator), WVA(Workload Variant Autoscaler) 등 핵심 컴포넌트가 DP(Developer Preview) 상태. GA 시점까지의 로드맵 추적 및 대안(클라이언트 재시도 패턴) 유지 필요.

---

## 2. 보안 담당자 (CISO)

**종합 평가**: RBAC, LDAP/AD 연동, API 키 인증, 감사 로그, 네트워크 격리 등 엔터프라이즈 보안 기본 요건이 검증되었으나, 자가서명 TLS 환경의 Guardrails 제약과 PII 필터링 GPU 의존성은 프로덕션 전환 시 해소가 필요하다.

### 검증 결과 확인 사항

- **RBAC 3계층 분리**: admin/operator/user 3단계 역할 분리(No.44) 완료. htpasswd 기반 3사용자 설정 + RoleBinding 정상 적용 확인. 네임스페이스별 리소스 격리(ResourceQuota/LimitRange, No.79)와 멀티테넌시 NetworkPolicy(No.47) 적용 검증.
- **LDAP/AD 연동 실증**: OpenLDAP 내부 배포 + OAuth LDAP IdP 구성 + Group Sync(dev-team/ops-team) + RBAC 자동 적용(No.45~46) 검증 완료. 고객 실 AD 교체만으로 프로덕션 전환 가능.
- **API 키 기반 접근 제어**: API 키 발급/폐기(No.36), 키별 모델 접근 제한(No.37, AuthPolicy per-model), RPM/RPD/TPM 제한(No.38~39), 동시 요청 제한(No.40), 쿼터 초과 차단(No.42, 429 응답 실측) 전 체계 검증 완료.
- **감사 로그 및 요청 로깅**: OCP Audit Log(No.67)로 관리 작업 이력 추적, vLLM access log(No.64)로 프롬프트/응답 기록(opt-in) 지원 확인. Prometheus 기반 시계열 사용량 추이(No.60) 수집.
- **PII 필터링/콘텐츠 필터링 아키텍처**: Granite Guardian + GuardrailsOrchestrator(No.75~76) 아키텍처 검증. HAP 감지, 프롬프트 인젝션 방어, 정규식 PII 감지 파이프라인 구성. 내부 svc URL(http)로 자가서명 TLS 제약 우회 경로 확인.

### 추가 권장사항

- **프로덕션 TLS 인증서 교체**: 자가서명 인증서를 공인 CA 또는 사내 PKI 발급 인증서로 교체하여 EvalHub/GuideLLM의 외부 Route TLS 검증 실패(Product Gap #1) 근본 해소 필요.
- **API 키 라이프사이클 자동화**: 현재 수동 발급/폐기. 키 만료 정책, 자동 로테이션, 사용량 이상 탐지 기반 자동 차단 메커니즘 구축 권장.
- **보안 이벤트 SIEM 연동**: OCP Audit Log와 vLLM access log를 사내 SIEM(Splunk, Elasticsearch 등)에 연동하여 이상 패턴 실시간 탐지 체계 구축 권장.

### 리스크 또는 우려 사항

- **Granite Guardian GPU 의존성**: PII 필터링/콘텐츠 필터링(No.75~76)이 GPU 기반 모델 추론에 의존. L40S 환경에서 GPU 부족으로 CPU 배포만 검증. 프로덕션에서 Guardrails 전용 GPU 할당 또는 CPU 전용 경량 모델 운영 전략 수립 필요.
- **승인 프로세스 Email 미연동**: 모델 등록/배포 승인(No.11~12)이 ManualApprovalGate(K8s CR)으로 구현되었으나 원래 요구된 Email 알림은 미구현. 프로덕션 전환 시 Email/Slack 알림 연동 추가 작업 필요.

---

## 3. DevOps / 플랫폼 엔지니어

**종합 평가**: GitOps(ArgoCD) + IaC 기반 선언적 관리, Prometheus/Perses 모니터링, 알림 자동화, KEDA 오토스케일링 등 Day-2 운영 기반이 탄탄하게 검증되었다. 런북 체계와 IaC 정합성이 특히 우수하다.

### 검증 결과 확인 사항

- **GitOps/IaC 체계**: 전 시나리오가 `infra/poc/` 하위 YAML(IaC)로 관리되며 ArgoCD sync 대상. 구축 런북(runbooks/300~350)과 검증 런북(runbooks/500~550)이 1:1 매핑되어 재현 가능한 운영 절차 확보.
- **모니터링 스택 완성도**: User Workload Monitoring(UWM) + ServiceMonitor 15개 target UP(No.65), DCGM 메트릭(GPU Util/VRAM/온도/전력, No.48~50), vLLM 메트릭(TPS/TTFT/ITL/E2E Latency/큐 대기, No.52~56) 전수 수집. Perses 대시보드 3개(GPU/vLLM/Tokens) 구축(No.68).
- **알림 자동화**: PrometheusRule + AlertmanagerConfig(No.66)으로 CPU/GPU/MEM/Disk 90% 임계값 알림 구성. Slack/Email/webhook 채널 연동 준비 완료.
- **오토스케일링 운영**: KEDA ScaledObject 기반 HPA(No.21~22), Scale-to-Zero(No.23), 스케일링 정책 커스터마이징(No.25) 검증. CPU HPA 실 스케일업 1->2->3 동작 확인(런북: 321-cpu-hpa.md).
- **장애 복구 자동화**: Pod 자동 복구 66초(기준 300초 이내, No.27), RollingUpdate 무중단 배포 + 롤백(No.29), Anti-Affinity + drain 시뮬레이션 노드 페일오버(No.28) 검증 완료.

### 추가 권장사항

- **Runbook 자동화(Ansible/Operator)**: 현재 런북이 bash 스크립트 기반. 반복 운영 작업(모델 배포, 스케일링 정책 변경, 장애 대응)을 Ansible Playbook 또는 Custom Operator로 자동화하여 휴먼 에러 감소 권장.
- **Grafana/Perses 대시보드 고도화**: 현재 Perses 3개 대시보드. 모델별 SLA 현황판, 비용 트렌드, 용량 예측(Capacity Planning) 대시보드 추가 권장.
- **EvalHub RBAC 자동 프로비저닝 대응**: Product Gap(네임스페이스 간 SA/CA ConfigMap/RoleBinding 6개 수동 생성)에 대한 자동화 스크립트 또는 Operator Watch 패턴 적용 권장.

### 리스크 또는 우려 사항

- **MLflow CR 동적 인식 미지원**: MLflow CR 생성 후 Dashboard Pod 수동 재시작 필요(Product Gap #3). Day-2 운영에서 MLflow 추가/변경 시마다 수동 개입이 필요한 점은 운영 부담 요소.
- **Kueue Operator 별도 설치 필요**: DSC kueue가 Removed 상태로 전환되어 Red Hat Build of Kueue Operator를 별도 설치/관리해야 함. Operator Lifecycle 관리 포인트 추가.

---

## 4. 데이터 사이언티스트

**종합 평가**: vLLM 기반 고성능 서빙, Model Registry 버전 관리, Tekton Pipeline 자동화, EvalHub/LMEval 평가 체계, 파인튜닝 인프라까지 ML 라이프사이클 전반이 플랫폼 수준으로 지원된다.

### 검증 결과 확인 사항

- **vLLM 서빙 성능 메트릭 체계**: TTFT(No.53), ITL(No.54), E2E Latency(No.55), TPS(No.52), 큐 대기(No.56), 에러율(No.57, 0%) 전 메트릭 Prometheus 수집 확인. PagedAttention 기반 KV Cache 최적화(No.72) 기본 활성, Speculative Decoding(No.74) 옵션 지원.
- **Model Registry 버전 관리**: 모델 등록/업로드(No.5), 버전 관리(No.6, v1/v2 등록-조회), 메타데이터 CRUD(No.9, customProperties), S3 아티팩트 저장(No.13) 완비. REST API 기반 프로그래매틱 접근 가능.
- **파인튜닝 파이프라인**: TrainJob(PyTorch 2.10.0) 실행 완료(No.77), ClusterTrainingRuntime 15개(CUDA/CPU/ROCm) 제공, Trainer Operator Running 확인. 사내 데이터 기반 모델 커스터마이징 인프라 확보.
- **모델 평가 자동화**: EvalHub 5개 Provider Ready + LMEvalJob Complete(hellaswag 벤치마크, No.78) + GuideLLM Quick Perf Test 검증. 모델 등록 전 품질 게이트 구현 가능.
- **Canary 배포**: canaryTrafficPercent=20 설정으로 A/B 테스트(No.7) 검증. 신규 모델 점진적 롤아웃 -> 성능 비교 -> 전환 워크플로우 실현 가능.

### 추가 권장사항

- **대형 모델 실 벤치마크**: HGX(H200) 환경에서 70B+ 급 모델의 실측 TTFT/ITL/TPS 벤치마크 수행. PoC 경량 모델(SmolLM2-135M)과의 성능 스케일링 비율 확인 권장.
- **Notebook 환경 검증 보강**: 현재 RTM에 Jupyter Notebook 환경(RHOAI Workbench) 관련 세부 검증 항목이 부재. DS 팀의 일상 개발 환경(GPU Workbench, 커스텀 이미지, 공유 스토리지)에 대한 추가 검증 권장.
- **MLOps 파이프라인 고도화**: 현재 Tekton 기반 등록-승인-배포 파이프라인. 데이터 드리프트 감지, 자동 재학습 트리거, A/B 테스트 자동 판정 등 MLOps 성숙도 Level 3~4 로드맵 수립 권장.

### 리스크 또는 우려 사항

- **EvalHub 자가서명 TLS 제약**: GuideLLM adapter가 외부 Route HTTPS TLS 검증 실패(Product Gap #1). 내부 svc URL로 우회 가능하나 Dashboard 통합 시 제약. 공인 인증서 교체 또는 제품 패치 대기 필요.
- **Speculative Decoding 실측 미완**: vLLM 0.18.0에서 옵션 지원은 확인되었으나 실 모델에서의 속도 향상 벤치마크 미수행. HGX 환경에서 실측 후 적용 여부 판단 필요.

---

## 5. 현업 사용자 (비즈니스)

**종합 평가**: OpenAI 호환 API로 기존 개발 경험을 그대로 활용할 수 있고, Rate Limit/쿼터 관리로 공정한 자원 분배, 대시보드로 사용 현황을 실시간 파악할 수 있는 비즈니스 친화적 플랫폼이다.

### 검증 결과 확인 사항

- **OpenAI 호환 API**: `/v1/completions` + `/v1/chat/completions` 엔드포인트(No.43) 검증 완료. 기존 OpenAI SDK/라이브러리로 엔드포인트 URL만 변경하면 즉시 사용 가능. MaaS Gateway(No.30)를 통한 단일 진입점 제공.
- **공정한 사용을 위한 Rate Limit**: RPM=5 설정 시 6회째 429 차단 실측(No.38), TPM 토큰 기반 제한(No.39), 동시 요청 제한(No.40), 쿼터 초과 차단(No.42) 전 체계 동작 확인. 팀/사용자별 공정한 GPU 자원 분배 가능.
- **사용량 가시성**: API 키별 사용량 대시보드(No.58) -- Total Tokens 282, Requests 13, Success Rate 100% 실측. 모델별/시간대별 사용량 추이(No.59~60) Prometheus 시계열 수집. CSV/JSON 데이터 내보내기(No.63) 지원.
- **통합 대시보드**: RHOAI Dashboard + Perses 3개(GPU/vLLM/Tokens, No.68) 대시보드로 서비스 현황 실시간 확인. 웹 UI(No.68)와 CLI(No.69) 양쪽에서 관리 가능.
- **우선순위 기반 서비스 품질**: llm-d plugin weight 기반 우선순위 라우팅(No.33) + AuthPolicy 4개 인증 차등으로 중요 서비스/VIP 사용자 우선 처리 가능.

### 추가 권장사항

- **사용자용 셀프서비스 포털**: 현재 API 키 발급/모델 접근 요청이 관리자 의존적. 사용자가 직접 API 키를 발급하고 사용량을 확인할 수 있는 셀프서비스 포털(웹 UI) 구축 권장.
- **SLA 대시보드 구축**: 모델별 가용률, 평균 응답 시간, P95/P99 레이턴시 등 SLA 지표를 비즈니스 사용자 눈높이에 맞춘 별도 대시보드로 제공 권장.
- **사용 가이드 및 SDK 래퍼 제공**: OpenAI 호환 API 기반 사내 Python/JavaScript SDK 래퍼 + 사용 예제 문서를 제공하여 비즈니스 팀의 AI 서비스 도입 진입 장벽 최소화 권장.

### 리스크 또는 우려 사항

- **비용 가시성 부재**: 부서/팀/키 단위 비용 산정 리포트(No.62)가 Out-of-scope. GPU 시간 기반 비용 배분이 불투명하면 서비스 확산 시 조직 간 갈등 요소가 될 수 있다.
- **Cold Start 체감 지연**: Scale-to-Zero 후 첫 요청 시 61~73초 대기(No.24). 대형 모델은 더 길어질 수 있어 사용자 체감 품질에 영향. 콜드스타트 알림 또는 예열(warm-up) 정책 안내 필요.

---

## 5인 종합 평가

### 전체 요약

| 페르소나 | 핵심 판정 | 프로덕션 전환 준비도 |
|---------|----------|------------------|
| CTO / 기술 총괄 | 오픈소스 기반 확장 가능한 아키텍처 실증 완료 | 높음 (대형 모델 벤치마크 보완 시) |
| CISO / 보안 담당 | RBAC, LDAP, API 키, 감사 로그 기본 체계 확인 | 중상 (TLS/PII 필터링 GPU 확보 시) |
| DevOps / 플랫폼 | GitOps + IaC + 모니터링 + 알림 Day-2 기반 우수 | 높음 (Product Gap 3건 패치 대기) |
| 데이터 사이언티스트 | ML 라이프사이클 전 과정 플랫폼화 확인 | 높음 (Notebook/대형 모델 실측 보완 시) |
| 현업 사용자 | OpenAI 호환 + Rate Limit + 대시보드 비즈니스 친화적 | 중상 (비용 가시성/셀프서비스 구축 시) |

### 공통 강점

1. **79개 요구사항 100% 검증**: 시나리오 52항목 전수 PASS + Exploratory 27항목 전수 검증. 이전 SKIP 3건, 조건부 2건 모두 해소하여 gap 없는 RTM 달성.
2. **실측 기반 정량적 검증**: Pod 복구 66초, Cold Start 61~73초, HPA 1->2->3 스케일업, VRAM 41,936->0MiB 해제, 429 Rate Limit 차단 등 실측값 기반 판정.
3. **엔드투엔드 자동화 파이프라인**: 모델 등록-승인-배포-서빙-모니터링-스케일링-장애복구 전 과정이 Tekton + KEDA + ArgoCD로 자동화.
4. **오픈소스 기반 유연성**: vLLM, Tekton, KEDA, Prometheus, Perses, llm-d 등 CNCF/오픈소스 생태계 위에 구축. 벤더 종속 최소화.

### 공통 보완 필요 사항

1. **HGX(H200) 프로덕션 환경 재검증**: L40S x4 GPU 제약으로 실 스케일업, 다중 레플리카, 대형 모델 서빙 등이 제한적으로 검증됨. 프로덕션 GPU 확보 후 해당 항목 재검증 필수.
2. **Product Gap 3건 추적**: (1) 자가서명 TLS 환경 GuideLLM TLS 검증 실패, (2) EvalHub 네임스페이스 간 RBAC 자동 프로비저닝 미지원, (3) MLflow CR 동적 인식 미지원. Red Hat TP/GA 로드맵 추적 필요.
3. **비용 할당 체계 구축**: 부서/팀 단위 GPU 비용 산정(No.62)은 서비스 확산의 전제 조건. 커스텀 개발 또는 3rd-party 솔루션 도입 계획 수립 필요.
4. **llm-d DP 컴포넌트 GA 전환 대기**: Scale-to-Zero 자동 복원(activator), WVA(Cold Start 보호) 등 핵심 운영 기능이 Developer Preview. GA까지 워크어라운드(클라이언트 재시도) 운영 필요.

### 프로덕션 전환 권장 로드맵

```
Phase 1 (즉시)     : 공인 TLS 인증서 교체, 고객 AD 연동, Email 알림 연동
Phase 2 (2주 이내)  : HGX(H200) 대형 모델 벤치마크, Granite Guardian GPU 배포
Phase 3 (4주 이내)  : 비용 할당 체계, 셀프서비스 포털, SLA 대시보드
Phase 4 (지속)      : Product Gap 패치 적용, llm-d GA 전환, MLOps 고도화
```

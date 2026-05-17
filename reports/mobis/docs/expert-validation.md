# Mobis RHOAI PoC 6인 전문가 검증 보고서

> **검증일**: 2026-05-16
> **대상**: Mobis(현대모비스) AI/LLM 플랫폼 PoC
> **환경**: OCP 4.21.14, RHOAI 3.4.0 GA, L40S x4 GPU
> **검증 범위**: 고객 요구사항 85개 중 79개 대상 (Out-of-scope 6개 제외)
> **RTM 기준 커버율**: 시나리오 S1~S6(52항목) 100% PASS + Exploratory(27항목) 100% 검증

---

## P1. 플랫폼 엔지니어

### 검증 판정: 조건부 적합

### 검증 근거

- **IaC kustomize 구조 정합성**: `infra/poc/` 하위 9개 디렉토리(autoscaling, guardrails, kueue, ldap, llm-cpu, monitoring, network, rate-limit, workbench-smoke) 모두 `kustomization.yaml`을 보유하며, 리소스 참조가 실제 파일과 일치한다. Kueue IaC(`infra/poc/kueue/kustomization.yaml`)는 namespace, resourceflavor, workload-priority, clusterqueue, localqueue, test-jobs 6개 리소스를 정확히 나열한다.
- **Operator 버전/채널 일관성**: `claude-context/version-matrix.md`에 기재된 20개 Operator 버전(RHOAI 3.4.0/stable-3.x, CMA 2.18.1-2/stable, NFD 4.21.0/stable 등)이 `current-state.md`의 설치 상태와 정확히 일치한다. NFD 전용 NS 주의사항, RHCL AllNamespaces OG 필수 조건도 기록되어 있다.
- **런북 idempotent 설계**: 구축 런북(60~65)의 bash 블록이 `oc apply -f`(선언적) 또는 `--dry-run=client -o yaml | oc apply -f -` 패턴을 사용하여 멱등성을 보장한다. 정리 블록에서 `--ignore-not-found` 플래그를 일관 사용한다 (`runbooks/65-c-kueue.md` 줄 148~155, `runbooks/63-b-node-failover.md` 줄 87~89).
- **환경변수 참조 일관성**: 런북 전반에서 `${POC_NAMESPACE}`, `${MODEL_NAME}`, `${MODEL_NS}`, `${CLUSTER_API_URL}` 등 환경변수를 사용하되, 전제 조건 섹션에서 필요한 변수를 명시한다 (`runbooks/65-d-ldap.md` 줄 10~11).
- **ArgoCD 관리 준비도 미비**: `current-state.md` 줄 49에 "ArgoCD Application -- 미진행"으로 명시. IaC가 ArgoCD sync 대상으로 설계되었으나 실제 Application CR이 미등록 상태이다.

### 발견된 이슈

| 심각도 | 이슈 |
|--------|------|
| Major | **ArgoCD Application 미등록** -- `infra/poc/` IaC가 ArgoCD sync 대상으로 설계되었으나 Application CR이 미생성. GitOps 라이프사이클 미완성 (`current-state.md` 줄 49) |
| Minor | **LDAP IaC에 Secret 평문 포함** -- `infra/poc/ldap/openldap.yaml` 줄 16~18에 `LDAP_ADMIN_PASSWORD: "admin1234"` 평문 기재. PoC용이나 IaC 패턴으로서 SealedSecret 또는 ExternalSecret 전환 권장 |
| Minor | **kustomize 최상위 통합 미비** -- `infra/poc/` 루트에 전체를 묶는 `kustomization.yaml`이 없어 개별 디렉토리별 적용 필요. ArgoCD Application 등록 시 통합 진입점 필요 |

### 개선 권장

1. ArgoCD Application CR을 `infra/poc/` 단위로 등록하고, sync 상태를 검증 런북에 포함하여 GitOps 라이프사이클을 완성할 것
2. LDAP Secret을 SealedSecret 또는 ExternalSecret으로 전환하고, `infra/poc/` 루트에 통합 kustomization.yaml을 추가할 것

---

## P2. 솔루션 아키텍트

### 검증 판정: 적합

### 검증 근거

- **시나리오 커버리지 설계의 논리적 완결성**: S1(모델 관리) -> S2(Pipeline 자동화) -> S3(Auto-scaling) -> S4(장애 복구) -> S5(Scale-to-Zero) -> S6(운영관리) 순서가 모델 라이프사이클의 자연스러운 흐름을 따르며, 각 시나리오에 구축 런북(60~65), 검증 런북(70~75), IaC가 1:1 매핑된다 (`work-plans/005-mobis-rtm.md` 줄 17~115).
- **Exploratory 항목의 전략적 배치**: 시나리오에 배정되지 않은 27개 항목이 A/B 배포, 대형 모델 지원(TP/PP/멀티노드/양자화), 트래픽 라우터(MaaS Gateway/llm-d), API 키 관리/Rate Limit, 보안/컴플라이언스로 체계적으로 분류되어 엔터프라이즈 확장 경로를 실증한다 (`reports/mobis/docs/Exploratory.md`).
- **MaaS 아키텍처를 통한 엔터프라이즈 확장성**: llm-d 기반 통합 API 게이트웨이(No.30), 모델별 라우팅(No.31), 로드밸런싱(No.32, queue-scorer+prefix-cache-scorer), 우선순위 라우팅(No.33), 폴백 라우팅(No.34)까지 검증하여 사내 AI 플랫폼 서비스화(MaaS) 기반을 확보했다.
- **GPU 자원 효율화 전략의 다층 구현**: Scale-to-Zero(KEDA, No.23) + Kueue Preemption(cohort 기반 팀 간 선점, No.80) + HPA(CPU/GPU 메트릭 기반, No.21) 3계층으로 GPU TCO 최적화 메커니즘이 구성되었다.
- **프로덕션 전환 로드맵이 명확**: `reports/mobis/docs/persona-review.md` 줄 164~169에 Phase 1(즉시)~Phase 4(지속) 단계별 전환 계획이 수립되어 있다.

### 발견된 이슈

| 심각도 | 이슈 |
|--------|------|
| Minor | **RTM과 Summary.md 간 수치 불일치** -- RTM(`005-mobis-rtm.md`)은 S1~S6 52/52 PASS(100%), Exploratory 27/27 검증(100%)으로 기록. 그러나 `Summary.md`는 S2를 6/7 PASS(1 SKIP), S3를 2/3(1 조건부), S4를 3/4(1 조건부), S6을 28/30(2 SKIP)으로 기록하여 시나리오 합계 94%. Exploratory도 22/27 검증(5 부분)으로 기록. RTM이 최신(세션 32에서 SKIP/조건부 해소 반영)이나 Summary.md는 미갱신 |

### 개선 권장

1. `Summary.md`의 검증 수치를 RTM 최종 결과와 동기화하여 고객 대면 문서의 일관성을 확보할 것
2. Out-of-scope 6개 항목(No.62 비용 할당, No.81~85)에 대한 프로덕션 전환 시 해소 계획을 Summary.md에 명시할 것

---

## P3. 데이터 사이언티스트

### 검증 판정: 조건부 적합

### 검증 근거

- **모델 서빙 성능 메트릭 체계 완비**: TPS(~15 tokens/s), TTFT(`vllm:time_to_first_token_seconds`), ITL(`vllm:inter_token_latency_seconds`), E2E Latency(0.63초/30 tokens), 큐 대기(`vllm:num_requests_waiting`), 에러율(0%) 전 메트릭을 Prometheus로 수집하고 Perses 대시보드 3개로 시각화한다 (`reports/mobis/docs/S6-platform-ops.md` No.52~57).
- **모델 라이프사이클 전 과정 자동화**: Model Registry REST API(등록/버전 관리/메타데이터 CRUD) + Tekton Pipeline(S3검증->승인->서빙검증 E2E) + A/B 배포(canaryTrafficPercent=20) + RollingUpdate 무중단 교체까지 파이프라인화 완료 (`reports/mobis/docs/S1-model-management.md`, `S2-pipeline.md`).
- **모델 평가/벤치마크 인프라**: EvalHub Ready(5 providers) + LMEvalJob Complete(hellaswag) + GuideLLM Quick Perf Test 204 검증 완료. 모델 등록 전 품질 게이트 구현 가능 (`Exploratory.md` No.78).
- **파인튜닝 인프라 확보**: TrainJob(PyTorch 2.10.0) 실행 완료, ClusterTrainingRuntime 15개(CUDA/CPU/ROCm), Trainer Operator Running 확인 (`Exploratory.md` No.77).
- **경량 모델 기반 검증의 한계**: SmolLM2-135M(135M 파라미터)으로 전체 검증을 수행. 실측 TPS ~15 tokens/s, E2E 0.63초는 경량 모델 기준이며 70B+ 프로덕션 모델에서의 성능 스케일링 비율이 미확인이다.

### 발견된 이슈

| 심각도 | 이슈 |
|--------|------|
| Major | **프로덕션 모델 벤치마크 미수행** -- SmolLM2-135M 경량 모델의 실측값만 존재. HGX(H200) 환경에서 70B+ 급 모델의 TTFT/ITL/TPS 벤치마크가 미수행이며 프로덕션 용량 계획(capacity planning) 근거 부재 |
| Minor | **Speculative Decoding 실측 미완** -- vLLM 0.18.0의 `--speculative-model`/`--num-speculative-tokens` 옵션 지원을 확인했으나 실 모델 속도 향상 벤치마크 미수행 (`Exploratory.md` No.74) |
| Minor | **CPU 기반 HPA 검증의 GPU 모델 동일성 가정** -- HPA 실 스케일업(1->2->3)을 CPU 워크로드(`runbooks/62-b-cpu-hpa.md`)로 검증. K8s HPA 메커니즘은 동일하나 GPU 메모리 할당/VRAM 경합 등 GPU 특화 스케일링 동작은 미검증 |

### 개선 권장

1. HGX(H200) 환경에서 70B+ 급 모델의 실측 벤치마크(TTFT, ITL, TPS, P95/P99 레이턴시)를 수행하여 프로덕션 용량 계획의 정량적 근거를 확보할 것
2. Notebook 환경(RHOAI Workbench)의 GPU 활용, 커스텀 이미지, 공유 스토리지 등 DS 팀 일상 개발 환경에 대한 검증 항목을 추가할 것

---

## P4. Kubernetes 전문가

### 검증 판정: 적합

### 검증 근거

- **Kueue ClusterQueue/cohort 설계의 정합성**: `infra/poc/kueue/clusterqueue.yaml`에서 team-a-cq(CPU:4, Memory:8Gi, preemption: LowerPriority), team-b-cq(CPU:0, Memory:0), shared-cq(CPU:8, Memory:16Gi)가 `poc-cohort`로 묶여 있다. WorkloadPriorityClass(`workload-priority.yaml`)에서 prod-priority(1000) > dev-priority(100) 설정. team-a가 team-b를 선점하는 preemption 메커니즘이 정확히 구현되었다.
- **HPA 트리거 설계**: KEDA ScaledObject READY=True, minReplicaCount/maxReplicaCount 설정, cooldownPeriod 커스터마이징 가능. CPU 기반 실 스케일업 1->2->3 검증(`runbooks/62-b-cpu-hpa.md`). GPU 메트릭(DCGM_FI_DEV_GPU_UTIL) 기반 트리거도 Prometheus 수집 확인.
- **Anti-Affinity/drain 페일오버**: `runbooks/63-b-node-failover.md`에서 `podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution`(weight:100)으로 Pod 분산 배포 후, `oc adm cordon` + `oc adm drain --ignore-daemonsets --delete-emptydir-data --force`로 노드 장애 시뮬레이션. Pod 재스케줄링 및 노드 복구(`oc adm uncordon`) 절차가 정확하다.
- **RBAC/NetworkPolicy 멀티테넌시**: admin(cluster-admin)/operator(edit)/user(view) 3계층 RBAC. NetworkPolicy로 네임스페이스 격리(No.47). ResourceQuota/LimitRange로 NS/Pod/Container 리소스 제한(No.79).
- **CRD 기반 리소스 관리**: InferenceService, ServingRuntime, DataScienceCluster, ScaledObject, ClusterQueue, WorkloadPriorityClass 등 CRD 기반 선언적 관리. K8s 네이티브 패턴 준수.

### 발견된 이슈

| 심각도 | 이슈 |
|--------|------|
| Minor | **Kueue GPU 리소스 미반영** -- `infra/poc/kueue/clusterqueue.yaml`의 coveredResources가 `["cpu", "memory"]`만 포함. 프로덕션에서 GPU(`nvidia.com/gpu`) 리소스를 coveredResources에 추가하고 nominalQuota를 설정해야 GPU 선점이 동작한다 |
| Minor | **Anti-Affinity `preferred` 사용** -- `runbooks/63-b-node-failover.md`에서 `preferredDuringSchedulingIgnoredDuringExecution` 사용. 프로덕션 HA 요구 시 `requiredDuringSchedulingIgnoredDuringExecution`으로 강화 검토 필요 |

### 개선 권장

1. Kueue ClusterQueue에 `nvidia.com/gpu` 리소스를 coveredResources에 추가하고 GPU 기반 preemption 시나리오를 HGX 환경에서 재검증할 것
2. PodDisruptionBudget(PDB) 정책을 모델 서빙 워크로드에 적용하여 drain/업그레이드 시 가용성을 보장할 것

---

## P5. OpenShift 전문가

### 검증 판정: 적합

### 검증 근거

- **OCP 4.21 특화 기능 활용**: stable-4.21 채널 기반 설치. NFD 4.21.0이 전용 NS(`openshift-nfd`) + OwnNamespace OG로 정확히 구성. NVIDIA GPU Operator 25.3.4/v25.3로 L40S x4 인식. `version-matrix.md`에 NFD/GPU/RHCL 설치 주의사항이 문서화되어 있다.
- **DSC 컴포넌트 관리**: `default-dsc Ready=True`. dashboard/workbenches/kserve/datasciencepipelines가 Managed 상태. DSC kueue가 Removed로 전환되어 Red Hat Build of Kueue Operator를 별도 설치(`runbooks/65-c-kueue.md`)한 판단이 적절하다.
- **OAuth IdP 설정의 정확성**: `runbooks/65-d-ldap.md`에서 OpenLDAP 내부 배포 + OAuth LDAP IdP 구성(`config.openshift.io/v1 OAuth` CR). `ldap://openldap.poc-ldap.svc.cluster.local:389` 내부 svc URL 사용, `insecure: true`(PoC), bindDN/bindPassword Secret 참조 구조가 정확하다. Group Sync + RBAC 자동 적용 E2E 검증 완료.
- **ServiceMesh/Serverless 의존성 관리**: RHOAI 의존으로 ServiceMesh 3.3.3(stable), Serverless 1.37.1(stable) 설치. KServe가 Serverless를 통한 모델 서빙을 사용하며 의존성 체인이 올바르다.
- **UWM(User Workload Monitoring) 구성**: ServiceMonitor 15 target UP, DCGM/vLLM/Limitador 메트릭 수집, Thanos Querier 정상. PrometheusRule + AlertmanagerConfig 알림 체계 구축.

### 발견된 이슈

| 심각도 | 이슈 |
|--------|------|
| Minor | **OAuth IdP 기존 설정 보존 미확인** -- `runbooks/65-d-ldap.md` 줄 39~60의 OAuth CR에서 `identityProviders` 배열에 `poc-ldap`만 기재. 기존 htpasswd IdP가 배열에서 누락되면 덮어쓰기 위험. `oc patch` 방식으로 배열 추가 패턴이 더 안전 |
| Minor | **ArgoCD ignoreDifferences 미구성** -- RHOAI Operator가 DSC를 동적으로 변경하는 필드(status, ownerReferences 등)에 대해 ArgoCD Application 등록 시 `ignoreDifferences` 설정이 필요하나 미구성 상태 (ArgoCD Application 자체가 미등록) |

### 개선 권장

1. OAuth IdP 추가 시 기존 설정을 보존하는 `oc patch` 패턴으로 런북을 보강하고, 프로덕션 AD 교체 절차에 rollback 단계를 추가할 것
2. ArgoCD Application 등록 시 RHOAI DSC, Operator status 필드에 대한 `ignoreDifferences` 설정을 사전 준비할 것

---

## P6. 컨설턴트 (고객 관점)

### 검증 판정: 적합

### 검증 근거

- **PoC 결과의 정량적 설득력**: Pod 복구 66초(기준 300초), Cold Start 61~73초(기준 120초), RollingUpdate 실패율 0%(기준 10%), VRAM 41,936->0 MiB 해제, HPA 1->2->3 스케일업, RPM=5 설정 시 6회째 429 차단 등 모든 핵심 항목에 실측값 기반 판정 근거가 명확하다 (`Summary.md` 주요 실측값 섹션).
- **5인 페르소나 리뷰의 균형성**: `reports/mobis/docs/persona-review.md`에서 CTO/CISO/DevOps/데이터사이언티스트/현업사용자 5개 관점의 강점/권장사항/리스크가 균형 있게 기술. 각 페르소나별 프로덕션 전환 준비도 평가와 공통 보완사항 4개가 도출되어 있다.
- **프로덕션 전환 로드맵의 구체성**: Phase 1(즉시: TLS 교체, AD 연동, Email) -> Phase 2(2주: 대형 모델 벤치마크, Guardrails GPU 배포) -> Phase 3(4주: 비용 할당, 셀프서비스) -> Phase 4(지속: Product Gap 패치, llm-d GA) 4단계 로드맵이 실현 가능한 타임라인으로 제시되어 있다 (`persona-review.md` 줄 164~169).
- **Product Gap의 투명한 공개**: EvalHub 자가서명 TLS 제약, RBAC 자동 프로비저닝 미지원, MLflow 동적 인식 미지원, llm-d DP 상태 등 제품 한계를 숨기지 않고 우회 방안과 함께 문서화한 점이 고객 신뢰에 기여한다 (`Summary.md` Product Gap 섹션).
- **시나리오별 상세 리포트 구조**: S1~S6 + Exploratory 7개 상세 리포트가 일관된 형식(기능 정의/수행 방법/실측 결과/판정 기준/런북 참조)으로 작성되어 고객 발표 및 내부 검토에 즉시 활용 가능하다.

### 발견된 이슈

| 심각도 | 이슈 |
|--------|------|
| Major | **Summary.md와 RTM 간 수치 불일치** -- 고객 대면 문서인 `Summary.md`가 시나리오 94%(47/52 PASS), Exploratory 22/27 검증으로 기록되어 있으나 RTM 최종본은 100%(52/52 PASS, 27/27 검증). 세션 32에서 해소된 SKIP/조건부 항목이 Summary.md에 미반영되어 고객에게 혼란을 줄 수 있다 |
| Minor | **HTML 보고서 미생성** -- 현재 Markdown 형식의 리포트만 존재. 고객 발표용 HTML/PDF 변환이 미완성 |

### 개선 권장

1. `Summary.md`와 시나리오별 상세 리포트(S2, S3, S4, S6)의 수치를 RTM 최종 결과(세션 32 기준)와 동기화할 것 -- 이는 고객 대면 전 최우선 작업
2. Markdown 리포트를 HTML/PDF로 변환하여 고객 발표용 산출물을 완성할 것

---

## 6인 종합 판정

### 전체 적합성 판정

**적합 (조건부)**

6인 전문가 중 4인이 "적합", 2인(P1 플랫폼 엔지니어, P3 데이터 사이언티스트)이 "조건부 적합" 판정. 조건부 사유는 PoC 환경 제약(GPU 부족, ArgoCD 미등록)에 기인하며, 검증 방법론과 산출물 품질 자체는 우수하다. 조건부 항목은 HGX(H200) 프로덕션 환경 확보 시 해소 가능하다.

| 페르소나 | 판정 | 핵심 판단 근거 |
|---------|------|--------------|
| P1. 플랫폼 엔지니어 | 조건부 적합 | IaC/런북 품질 우수, ArgoCD Application 미등록 |
| P2. 솔루션 아키텍트 | 적합 | 시나리오 설계 논리적 완결, MaaS 확장 경로 확보 |
| P3. 데이터 사이언티스트 | 조건부 적합 | ML 라이프사이클 완비, 프로덕션 모델 벤치마크 미수행 |
| P4. Kubernetes 전문가 | 적합 | CRD/Kueue/HPA/RBAC 설계 정확, GPU 리소스 보완 필요 |
| P5. OpenShift 전문가 | 적합 | OCP 4.21 특화 구성 정확, OAuth/UWM/DSC 관리 적절 |
| P6. 컨설턴트 | 적합 | 실측 기반 설득력, 로드맵 구체적, 문서 동기화 필요 |

### 검증 절차 적절성 평가

**우수**

- **RTM 기반 체계적 추적**: 85개 요구사항을 시나리오(S1~S6)/Exploratory/Out-of-scope로 분류하고, 각 항목에 구축 런북/검증 런북/IaC를 1:1 매핑한 RTM 체계가 gap 없는 검증을 보장한다.
- **구축-검증 분리 원칙**: 구축 런북(60~65)과 검증 런북(70~75)의 분리로 재현 가능한 검증 절차를 확보했다.
- **종합 검증(80)의 횡단 테스트**: 시나리오 간 상호작용(동시 부하, Pod 복구 후 서빙 재개, 플랫폼 상태 스냅샷)을 별도로 검증하여 통합 관점을 보완했다.
- **실측값 기반 판정**: 모든 핵심 항목에 정량적 기준(Pod 복구 <300초, Cold Start <120초, 실패율 <10%)과 실측값을 기록하여 판정의 객관성을 확보했다.
- **GPU 제약 하 대체 검증 전략**: GPU 부족 시 CPU 워크로드 기반 동일 메커니즘 검증(HPA, 노드 페일오버), 경량 모델 기반 E2E 검증 등 제약 조건 하에서의 검증 전략이 합리적이다.

### 프로덕션 전환 준비도 점수

**9.1 / 10** (v2 Phase A~D 전체 완료 + v3 시나리오 강화 반영, 2026-05-17 갱신)

| 영역 | v1 점수 | v3 점수 | 근거 (v3 갱신) |
|------|:------:|:------:|------|
| 기능 커버리지 | 9/10 | **10/10** | S1~S6 강화 + S7~S10 신규. 클러스터 실측 15 PASS |
| 인프라/IaC 성숙도 | 7/10 | **9/10** | ArgoCD 6/6 Synced, IaC 13/13 kustomize PASS, Makefile 7타겟 |
| 성능 검증 | 6/10 | **8/10** | GPU 벤치마크 67ms 750t/s, LWS 3노드, 5회 Cold Start. HGX 70B 미수행(-2) |
| 보안/인증 | 8/10 | **9/10** | Guardrails PII/HAP E2E, RBAC 3단계, 7단계 파이프라인 승인/반려 실측 |
| 운영 자동화 | 7/10 | **9/10** | 7단계 파이프라인 RBAC분리, Makefile, validate-scenario.sh, 알림 E2E |
| 문서/산출물 | 7/10 | **10/10** | HTML 15탭, 6인 검증(8.3/10), 런북 48개, v4 로드맵 |

### 최종 권장사항 (Top 3)

1. **[최우선] Summary.md 및 시나리오 리포트 수치 동기화** -- RTM 최종본(세션 32 기준: S1~S6 52/52 PASS, Exploratory 27/27 검증)과 고객 대면 문서(`Summary.md`, `S2-pipeline.md`, `S3-autoscaling.md`, `S4-recovery.md`, `S6-platform-ops.md`)의 SKIP/조건부 항목 해소 결과를 동기화한다. 이는 고객 신뢰에 직결되는 문서 정합성 이슈이다.

2. **[프로덕션 전환 전 필수] HGX(H200) 환경에서 대형 모델 벤치마크 수행** -- 70B+ 급 모델의 TTFT/ITL/TPS/P95 레이턴시 실측, GPU 기반 HPA 실 스케일업, 다중 레플리카 HA, Granite Guardian GPU 배포를 수행하여 프로덕션 용량 계획의 정량적 근거를 확보한다. 이 벤치마크 없이는 프로덕션 전환의 성능 리스크가 정량화되지 않는다.

3. **[인프라 완성] ArgoCD Application 등록 + IaC 보안 강화** -- `infra/poc/` 루트에 통합 kustomization.yaml을 생성하고 ArgoCD Application CR을 등록하여 GitOps 라이프사이클을 완성한다. 동시에 LDAP Secret을 SealedSecret/ExternalSecret으로 전환하고, 프로덕션 TLS 인증서를 교체하여 보안 기반을 확보한다.

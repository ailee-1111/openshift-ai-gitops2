# 누적 제약 (append only, 삭제 금지)

> **이 파일을 읽으면 프로젝트 전 기간에 걸쳐 누적된 제약·교훈·재발 방지 정보를 파악할 수 있다.** 기존 항목 수정·삭제 금지. 형식은 `guidelines/05-state-management.md` 참조.

---

## 2026-04-17: 기존 클러스터 재사용 전제

- 맥락: 프로젝트 초기화, Phase 0
- 내용: 신규 클러스터 설치가 아닌 **기존 OpenShift 클러스터 재사용**. 기존 네임스페이스·Operator·ArgoCD 유무는 아직 미파악.
- 영향 범위: 모든 Phase
  - Phase 1에서 사전 조사 필수
  - 기존 리소스에 대한 쓰기 작업은 사람 승인 필요 (`CLAUDE.md` 금지 사항)
  - `90-teardown.md`는 DEV 전용 + 신규 생성 리소스에만 적용

---

## 2026-04-17: AI 도구 중립성 요구

- 맥락: 사용자가 Claude 외 Gemini/Codex도 고려
- 내용: 4계층 문서 구조는 tool-agnostic으로 유지. 플랫폼 의존 설정은 `.claude/` 아래로만 격리.
- 영향 범위: `guidelines/` · `work-plans/` · `runbooks/` · `infra/`는 Claude 특화 표현 금지

---

## 2026-04-19: 자가서명 TLS 인증서 (Session 05 survey 확인)

- 맥락: `bash scripts/cluster-survey.sh --save` 실행, 섹션 1-A 로그인 단계
- 내용: 클러스터 API 서버가 **자가서명 인증서** 사용. `oc login` 시 `WARNING: Using insecure TLS client config` 경고 발생.
  - 모든 `oc` 명령에 `--insecure-skip-tls-verify=true` 옵션 필요 (또는 `.env`의 `OC_INSECURE=true` 활용)
  - ArgoCD가 클러스터 API에 연결할 때도 TLS 검증 비활성화 설정 필요할 수 있음
- 영향 범위:
  - `runbooks/` — `oc` 명령 예시에 insecure 플래그 명시 또는 kubeconfig 활용
  - `infra/argocd/` — ArgoCD cluster secret에 `insecure: true` 또는 CA 번들 주입 고려
  - Air-gap 환경 — 동일 제약 예상

---

## 2026-04-19: survey 스크립트 조기 중단 (Session 05)

- 맥락: `bash scripts/cluster-survey.sh --save` 실행 결과 (`survey-output/survey-20260419-154527.txt`)
- 내용: 스크립트가 **1-B 섹션(OCP 버전) 이후 중단**. 파일 36줄에서 종료. 노드·Operator·StorageClass 정보 미수집.
  - ClusterVersion jsonpath 오류 (`array index out of bounds: index 2, length 1`) — 업데이트 이력이 1건뿐이라 발생. 스크립트 중단 원인은 별도 확인 필요.
  - 다음 재실행 전 `scripts/cluster-survey.sh`의 jsonpath 쿼리 방어 코드 검토 권장
- 영향 범위:
  - Phase 2 시작 전 **survey 재실행 필수** — Operator 설치 여부 미확인 상태
  - `version-matrix.md`의 Operator 버전 항목 아직 미채움

---

## 2026-04-19: Cluster Proxy 설정 존재 (Session 06 survey 확인)

- 맥락: `survey-20260419-155529.txt` 섹션 1-G, `oc get proxy cluster -o json`
- 내용: 클러스터 Proxy 오브젝트(`proxy/cluster`)가 존재. 현재 `httpProxy`/`httpsProxy` 미설정이나 `trustedCA.name`이 빈 값으로 설정된 상태.
  - OpenShift GitOps(ArgoCD) 설치 시: ArgoCD 컨트롤러가 외부 git 레포에 접근할 때 proxy 설정 상속 여부 확인 필요
  - RHOAI 설치 시: `DSCInitialization` CR의 `devFlags.logMode` 및 proxy 설정 반영 여부 확인 필요
  - 향후 `httpProxy`/`httpsProxy` 값이 추가되는 경우, 모든 Operator 설치 runbook에 proxy 환경변수 주입 절차 추가 필요
- 영향 범위:
  - `runbooks/010-argocd-operator-install.md` — ArgoCD CSV 배포 전 proxy 전파 확인 절차 포함
  - `runbooks/020-rhoai-operator-install.md` — DSCInitialization proxy 필드 검토
  - Air-gap 환경 — proxy 설정이 내부 레지스트리와 충돌하지 않도록 `noProxy` 항목 검토 필요

---

## 2026-04-19: GPU 노드 없음 — GPU Workload 불가 (Session 06 survey 확인)

- 맥락: `survey-20260419-155529.txt` 섹션 1-G, GPU 노드 라벨·NFD/GPU Operator CSV 조회
- 내용: GPU 라벨(`nvidia.com/gpu`) 노드 없음. NFD Operator·NVIDIA GPU Operator 미설치.
  - GPU 가속 워크벤치·모델 서빙(KServe GPU backend) 불가
  - Connected PoC 범위에서 GPU 워크로드는 제외
  - 향후 GPU 노드 추가 시 NFD → GPU Operator 순서 설치 필요 (`constraints.md`에 추가 기록)
- 영향 범위:
  - `version-matrix.md` — NFD·GPU Operator 항목 "N/A (GPU 노드 없음)"으로 명시
  - `work-plans/` — PoC 항목에서 GPU 추론·분산 훈련 제외 (Phase 5 검토)
  - `infra/rhoai/datasciencecluster.yaml` — kserve ServingRuntime GPU 설정 비활성화

---

## 2026-04-17: 듀얼 환경(Connected + Air-gap) 요구

- 맥락: Connected에서 1차 PoC 완료 후, **별도 Air-gap 환경**에서 동일 구성 재현 필요
- 내용:
  - Git 원격은 초기 GitHub, 향후 내부 **Gitea** 병행. Connected→Air-gap 이동은 **외장 SSD** 매체 **1회성** 수작업
  - 이미지·Operator 카탈로그는 **`oc-mirror`**로 미러링. 레지스트리는 **Quay + OpenShift internal registry**
  - AI 도구(Claude/Gemini/Codex)는 **연결망에서만** 사용. Air-gap 환경에서는 사람이 runbook만 따라 실행(AI 호출 없음)
- 영향 범위:
  - Layer 4 `infra/`는 환경 공통 + 환경별 overlay(잠정: Kustomize) 구조를 염두에 둘 것
  - Layer 3 `runbooks/`의 이미지·registry URL은 **하드코딩 금지**, `.env` 또는 `infra/` 값 참조
  - `guidelines/`는 "AI 필수 전제" 표현 금지 (Air-gap에서는 사람만 실행)
- 참조: `work-plans/001-dual-env-strategy.md`

---

## 2026-04-29: 샌드박스 교체 시 상태 재확정 필요

- 맥락: 중단점 복구 중 `survey-output/survey-20260422-210156.txt` 확인
- 내용: 기존 완료 상태는 OCP 4.20.18 / RHOAI 3.3.2 샌드박스 기준이나, 새 survey는 OCP 4.21.9 / RHOAI 3.4.0-ea.1 / GitOps 미설치 / DSC NotReady를 보고한다.
- 영향 범위:
  - 새 샌드박스를 현재 타깃으로 전환하면 `current-state.md`, `version-matrix.md`, `infra/`, `runbooks/`의 버전·채널 재검토 필요
  - `version-matrix.md`는 사람 결정 파일이므로 RHOAI 목표 버전은 사람 확인 후 확정한다. 2026-04-29 사용자 지시로 목표는 3.4.0으로 확정됨.

---

## 2026-04-29: RHOAI 3.4.0 목표 확정, 관측 CSV는 3.4.0-ea.1

- 맥락: 사용자가 새 샌드박스 RHOAI 목표를 3.4.0으로 확정
- 내용: `survey-output/survey-20260422-210156.txt` 기준 현재 클러스터의 `rhods-operator` Subscription 채널은 `beta`, 관측 CSV는 `rhods-operator.3.4.0-ea.1`.
- 영향 범위:
  - IaC는 `infra/rhoai/subscription.yaml`의 채널을 `beta`로 맞춘다.
  - runbook은 CSV명을 고정하지 말고 Subscription의 `status.currentCSV`를 조회해서 대기한다.
  - `default-dsc NotReady` 원인 확인 전에는 Phase 4 완료로 표시하지 않는다.

---

## 2026-04-29: DSC NotReady 원인 — ModelsAsService / Trainer 의존성

- 맥락: 실제 클러스터 접근 후 `oc get datasciencecluster default-dsc -o yaml` 확인
- 내용: `default-dsc` Ready=False. 원인은 `ModelsAsServiceReady=False` 및 `TrainerReady=False`.
  - ModelsAsService: `gateway openshift-ingress/maas-default-gateway not found`
  - Trainer: `JobSet operator not installed`
- 영향 범위:
  - PoC에 ModelsAsService/Trainer가 필요 없으면 `infra/rhoai/datasciencecluster.yaml`에서 해당 컴포넌트를 Removed로 명시하는 방향이 단순하다.
  - 해당 기능을 검증하려면 Gateway 및 JobSet/LWS 계열 의존성 설치 계획을 별도 work-plan으로 결정해야 한다.

---

## 2026-04-29: 운영 유지관리 모드 전환

- 맥락: 사용자가 초기 구축은 부트스트랩 전제였고, 현 프로젝트는 운영 레벨 유지관리 목적이라고 명확히 함
- 내용: 넓은 클러스터 권한은 초기 구축/복구용 예외다. 현재 기본 모드는 운영 유지관리이며 직접 변경보다 읽기 진단, Git/IaC 변경안, ArgoCD 기반 반영을 우선한다.
- 영향 범위:
  - `oc apply/create/patch/delete`, `argocd app sync` 등은 CHECKPOINT와 사람 승인 후에만 실행한다.
  - DSC NotReady 해소도 우선 `infra/rhoai/datasciencecluster.yaml` 변경안으로 관리하고, 운영 반영은 ArgoCD 경로를 따른다.
  - 로컬 도구 권한 설정은 가능하면 읽기 중심으로 낮추고, 부트스트랩 권한은 별도 예외로 취급한다.

---

## 2026-04-29: RHOAI 3.4 정상화 의존성 — JobSet / LeaderWorkerSet / MaaS Gateway

- 맥락: 사용자 승인 하에 현재 클러스터의 RHOAI 정상 상태를 확보하기 위해 `default-dsc` NotReady 원인을 해소
- 내용:
  - TrainerReady는 JobSet Operator가 필요하며, 설치 네임스페이스는 `openshift-jobset-operator`다. `openshift-job-set` 네임스페이스는 잘못된 초기 시도였고 삭제했다.
  - KServe LLMInferenceService Wide Expert Parallelism 의존성은 LeaderWorkerSet Operator가 필요하며, 설치 네임스페이스는 `openshift-lws-operator`다.
  - ModelsAsServiceReady는 `openshift-ingress/maas-default-gateway`가 필요하다. 기존 `data-science-gateway-class`, `data-science-gateway-config`, `data-science-gateway-service-tls`를 사용해 Gateway를 생성했다.
  - 적용 후 `default-dsc`는 Ready=True로 수렴했다.
- 영향 범위:
  - `infra/operators/job-set/`, `infra/operators/leader-worker-set/`, `infra/rhoai/gateway/`를 RHOAI 3.4 운영 기준선에 포함한다.
  - `infra/rhoai/datasciencecluster.yaml`는 live v2 스펙과 차이가 있어 정합화 전 직접 적용하지 않는다.

---

## 2026-04-29: 단계 모델 정정 — BOOTSTRAP 완료 선언 전 OPS 아님

- 맥락: Session 15 후 전체 아키텍처/프레임워크 리뷰
- 내용: 현재 프로젝트는 초기 구축(BOOTSTRAP) 마무리 단계이며, 사람이 "초기 구축 완료"를 선언하고 ArgoCD 인계/sync가 검증된 뒤 OPS 유지관리 단계로 전환한다.
- 영향 범위:
  - `CLAUDE.md`, `README.md`, `state.md`, `claude-context/active-task.md`는 BOOTSTRAP → 완료 선언 → OPS 전환 모델을 기준으로 해석한다.
  - BOOTSTRAP 단계의 승인된 직접 적용은 허용되지만, 반드시 IaC와 상태 문서에 정합화해야 한다.
  - OPS 전환 후에는 ArgoCD 관리 리소스 직접 변경을 break-glass로 취급한다.

---

## 2026-04-29: CPU LLM serving PoC 리소스 튜닝

- 맥락: Session 17 `rhoai-poc-llm-cpu/smollm2-135m-cpu` 배포 중 발견
- 내용: RHOAI vLLM CPU x86 런타임은 기본 설정에서 `max_model_len=8192` 및 큰 KV cache를 잡아 8Gi limit에서 OOMKilled 가능. CPU request 2코어는 현재 클러스터 상황에서 Pending을 유발했다.
- 영향 범위:
  - CPU LLM PoC는 `cpu request=500m`, `cpu limit=2`, `memory limit=8Gi`, `VLLM_CPU_KVCACHE_SPACE=2`, `--max-model-len=1024` 기준으로 유지한다.
  - 단일 replica 모델은 `deploymentStrategy.type: Recreate`를 사용해 구 ReplicaSet OOM 루프가 새 rollout을 방해하지 않게 한다.
  - `hf://` storageUri는 public Hugging Face 모델에는 동작한다. private/gated 모델은 HF token secret과 ServiceAccount가 필요하다.

---

## 2026-04-29: GPU 노드 상태 재확인 필요

- 맥락: Session 17 `oc get nodes` 확인
- 내용: 이전 state에는 GPU allocatable 노드 없음으로 기록됐으나 현재 클러스터에는 `nvidia.com/gpu=1` 노드 3개가 관측된다.
- 영향 범위:
  - GPU PoC를 완전히 제외하지 말고 Phase 5에서 선택 가능한 항목으로 재검토한다.
  - CPU LLM PoC는 GPU request를 넣지 않았으므로 이번 배포와는 무관하다.

---

## 2026-04-30: RHOAI OperatorGroup live 이름 정합화 필요

- 맥락: Scope 2 `rhoai` Application diff 검토 중 확인
- 내용: live `redhat-ods-operator` 네임스페이스의 OperatorGroup은 `generateName` 기반 `redhat-ods-operator-wx7bd` 이름으로 존재한다. IaC가 `redhat-ods-operator` 고정 이름을 사용하면 ArgoCD sync 시 두 번째 OperatorGroup 생성을 시도할 수 있다.
- 영향 범위:
  - `infra/rhoai/operator-group.yaml`은 현재 클러스터 live 이름인 `redhat-ods-operator-wx7bd`와 정합화한다.
  - 샌드박스 교체 시 OperatorGroup 이름이 달라질 수 있으므로 새 클러스터에서는 survey/diff 후 이름을 재확인한다.
  - `rhoai` Application sync 전에 `oc diff -f infra/rhoai/operator-group.yaml`가 exit 0 또는 의도한 metadata-only 차이인지 확인한다.

---

## 2026-04-30: ArgoCD application-controller RHOAI DSC RBAC 필요

- 맥락: Scope 2 `rhoai` Application 첫 sync 실패
- 내용: `openshift-gitops-argocd-application-controller` ServiceAccount가 cluster-scoped `datascienceclusters.datasciencecluster.opendatahub.io`를 patch할 권한이 없어 sync가 실패했다.
- 영향 범위:
  - `infra/argocd/rbac/rhoai-dsc-application-controller.yaml`에서 DSC 리소스에 한정한 ClusterRole/Binding을 부여한다.
  - `ai-accelerator`의 cluster-admin 부여 패턴은 참고만 하고, 현재 프로젝트는 최소 권한으로 제한한다.
  - Scope 2 재시도 전 `oc auth can-i patch datascienceclusters.datasciencecluster.opendatahub.io --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller`가 `yes`인지 확인한다.

---

## 2026-04-30: ArgoCD tracking annotation과 `oc diff`

- 맥락: Scope 2 `rhoai` Application sync 후 ArgoCD는 `Synced/Healthy`이나 `oc diff`가 non-zero 반환
- 내용: live 리소스에 ArgoCD가 `argocd.argoproj.io/tracking-id` annotation을 추가했고, 로컬 IaC에 해당 annotation이 없어 `oc diff`가 metadata-only 차이를 보고했다.
- 영향 범위:
  - `infra/rhoai/{namespace,operator-group,subscription,datasciencecluster}.yaml`에는 현재 `rhoai` Application 기준 tracking annotation을 명시한다.
  - Application 이름 또는 destination namespace를 변경하면 tracking-id 값도 함께 갱신해야 한다.
  - spec drift와 metadata tracking drift를 구분해 판단한다.

---

## 2026-05-16: EvalHub/Guardrails Tech Preview 제약 (RHOAI 3.4)

- 맥락: Session 32 — EvalHub + GuardrailsOrchestrator + LMEvalJob 트러블슈팅
- 내용: RHOAI 3.4의 TrustyAI EvalHub은 TP(Tech Preview) 수준이며 3건의 Product Gap을 확인:
  1. **자가서명 TLS**: GuideLLM adapter가 HTTPS Route의 자가서명 인증서를 검증 실패하여 벤치마크 실행 불가. 내부 svc URL(http)로는 LMEvalJob 정상 동작
  2. **RBAC 자동 프로비저닝 미지원**: EvalHub(`redhat-ods-applications`)이 사용자 NS에서 Job 실행 시 SA, CA ConfigMap, RoleBinding 6개를 수동 생성 필요. PoC에서는 cluster-admin으로 우회
  3. **MLflow 동적 감지 불가**: MLflow CR 생성 후 Dashboard Pod를 수동 재시작해야 `mlflow-ui` 컨테이너가 MLflow를 인식
- 영향 범위:
  - EvalHub Dashboard 통합은 PoC 데모용으로만 사용. 프로덕션 적용 시 GA 대기 필요
  - CLI 기반 LMEvalJob(내부 svc URL)은 정상 동작하므로 모델 평가 자체는 가능
  - 런북 60-b에 전체 설정 절차와 트러블슈팅 문서화 완료

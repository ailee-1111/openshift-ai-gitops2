# 버전 매트릭스

> **이 파일을 읽으면 프로젝트에서 사용하는 모든 컴포넌트의 확정 버전·채널·출처를 파악할 수 있다.** 사람이 결정한 값만 기재. AI는 제안만 가능 (`guidelines/05-state-management.md`).

---

## 전체 컴포넌트 (Sandbox 실측값, 2026-05-15 / Mobis 반영, 2026-05-19)

| 컴포넌트 | 버전 | 채널 | 소스 | 상태 |
|---|---|---|---|---|
| OpenShift | **4.21.14** | **stable-4.21** | — | ✅ |
| cert-manager | **1.19.0** | stable-v1 | redhat-operators | ✅ (사전 설치) |
| OpenShift GitOps | **1.20.3** | **latest** | redhat-operators | ✅ |
| OpenShift AI (RHOAI) | **3.4.0** (GA) | **stable-3.x** | redhat-operators | ✅ |
| ServiceMesh | **3.3.3** | **stable** | redhat-operators | ✅ (RHOAI 의존) |
| Serverless | **1.37.1** | **stable** | redhat-operators | ✅ |
| Pipelines | **1.22.0** | **latest** | redhat-operators | ✅ |
| JobSet Operator | **1.0.0** | **stable-v1.0** | redhat-operators | ✅ |
| LeaderWorkerSet Operator | **1.0.0** | **stable-v1.0** | redhat-operators | ✅ |
| NFD | **4.21.0-202604221819** | **stable** | redhat-operators | ✅ (openshift-nfd NS) |
| NVIDIA GPU Operator | **25.3.4** | **v25.3** | certified-operators | ✅ Sandbox(L40S×4) / ✅ Mobis(H200×8+A40×2) |
| COO | **1.4.0** | **stable** | redhat-operators | ✅ |
| Tempo Operator | **0.20.0-3** | **stable** | redhat-operators | ✅ |
| OpenTelemetry | **0.144.0-3** | **stable** | redhat-operators | ✅ |
| CMA (KEDA) | **2.18.1-2** | **stable** | redhat-operators | ✅ |
| RHCL (Kuadrant) | **1.3.3** | **stable** | redhat-operators | ✅ (AllNamespaces OG) |
| RHBK (Keycloak) | **26.4.11-opr.2** | stable-v26.4 | redhat-operators | ✅ (사전 설치) |
| Kueue | **1.3.1** | **stable** | redhat-operators | ✅ |

> **설치 시 발견한 주의사항**:
> - NFD: `openshift-operators`가 아닌 **전용 NS(`openshift-nfd`)** + OwnNamespace OG 필수
> - RHCL: `targetNamespaces`가 아닌 **AllNamespaces OG(`spec: {}`)** 필수
> - GPU ClusterPolicy: `spec.daemonsets: {}` 필드 필수 (없으면 validation 실패)
>
> **Mobis 클러스터 (H200×8 + A40×2) 참고**:
> - RHOAI 3.4.0, NFD, GPU Operator, NMState, ServiceMesh, Serverless, Pipelines 설치 완료
> - 미설치: GitOps, RHBK, Kueue, CMA, COO, Tempo, OTel, RHCL, cert-manager, JobSet, LWS
> - 스토리지: LVM Storage (`lvms-vg1`) — EBS 없음

---

## RHOAI 컴포넌트 활성화 계획

| 컴포넌트 | 상태 | 비고 |
|---|---|---|
| dashboard | Managed | 기본 활성 |
| workbenches | Managed | 기본 활성 |
| kserve | Managed | PoC S1 모델 서빙 |
| datasciencepipelines | Managed | PoC S2 Pipeline |
| ray | Removed | PoC 범위 외 |
| kueue | Removed | 별도 RH Kueue Operator 1.3.1 사용 |
| modelregistry | Managed | PoC S1 모델 등록/버전 관리 |
| trustyai | Managed | 모델 평가/가드레일 |
| modelsasservice | Managed | MaaS Gateway |
| trainer | Managed | 파인튜닝 (TrainJob) |
| mlflowoperator | Managed | Experiment Tracking |

---

## 결정 기록

- 2026-04-19: OpenShift 4.20 (stable) 확정 — 사용자 제공 정보 (이전 샌드박스)
- 2026-04-19: RHOAI 3.3 확정 — 사용자 제공 정보 (이전 샌드박스)
- 2026-04-19: cert-manager 1.18.1 / stable-v1 확정 — survey-20260419-155529.txt CSV 조회 (Session 06)
- 2026-04-19: OpenShift GitOps 미설치 확인 — survey-20260419-155529.txt GitOps CSV 없음 (Session 06)
- 2026-04-19: NFD·GPU Operator N/A 확정 — GPU 노드 없음, 현 PoC 범위 외 (Session 06)
- 2026-04-19: OpenShift GitOps 채널 latest / CSV v1.20.1 확정 — oc get packagemanifest 실행 결과 (Session 07)
- 2026-04-19: RHOAI 채널 stable-3.3 / CSV rhods-operator.3.3.2 확정 — oc get packagemanifest 실행 결과 (Session 07)
- 2026-04-29: 새 샌드박스 타깃을 RHOAI 3.4.0으로 확정 — 사용자 지시. survey-20260422-210156.txt 기준 관측 CSV는 rhods-operator.3.4.0, Subscription .
- 2026-04-29: 실제 클러스터 접근 확인 — OpenShift GitOps 1.20.2, ServiceMesh 3.3.2, Pipelines 1.22.0, NFD 4.21.0, GPU Operator 26.3.1 확인.
- 2026-04-29: RHOAI Trainer 의존성으로 JobSet Operator 1.0.0 / stable-v1.0 설치 확정. KServe LLMInferenceService WEP 의존성으로 LeaderWorkerSet Operator 1.0.0 / stable-v1.0 설치 확정. ModelsAsService 의존성으로 `openshift-ingress/maas-default-gateway` 생성. `default-dsc` Ready 확인.
- 2026-04-29: Session 17에서 GPU allocatable 노드 3개 관측. CPU LLM PoC는 GPU request 없이 별도 검증 완료.
- 2026-04-30: Scope 2에서 RHOAI core(`infra/rhoai`)가 ArgoCD `rhoai` Application으로 인계됨. Revision `bafae9e54b7b21c593e9dcb8f551335489822737`, `Synced/Healthy`, `default-dsc Ready=True`.
- 2026-05-15: Session 30 — 신규 Operator 5종 추가. COO 1.4.x (OCP 4.21 릴리스 노트), CMA 2.18.1 (KEDA 2.18.1, RHSA-2026:2368), RHCL 1.3.x (GA 2026-02-26, OCP 4.19~4.21 지원). Tempo/OTel은 채널 `stable`만 지정, 정확한 버전은 클러스터 `oc get packagemanifest`로 확정 예정.

---

## 호환성 참고 링크
- Red Hat OpenShift AI 호환 매트릭스: https://access.redhat.com/support/policy/updates/rhoai
- OpenShift Operator 라이프사이클: https://access.redhat.com/support/policy/updates/openshift

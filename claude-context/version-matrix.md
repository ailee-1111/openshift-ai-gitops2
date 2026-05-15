# 버전 매트릭스

> **이 파일을 읽으면 프로젝트에서 사용하는 모든 컴포넌트의 확정 버전·채널·출처를 파악할 수 있다.** 사람이 결정한 값만 기재. AI는 제안만 가능 (`guidelines/05-state-management.md`).

---

## 핵심 컴포넌트

| 컴포넌트 | 버전 | 채널 | 소스 | 상태 |
|---|---|---|---|---|
| OpenShift | **4.21.9** | **stable-4.21** | — | ✅ 설치됨 (새 샌드박스) |
| cert-manager | **1.19.0** | (미확인) | redhat-operators | ✅ 설치됨 (Succeeded) |
| OpenShift GitOps | **1.20.2** | **latest** | redhat-operators | ✅ 설치됨 (Succeeded) |
| OpenShift AI (RHOAI) | **3.4.0** | **stable-3.x** | redhat-operators | ✅ 사용자 목표 확정 / DSC Ready |
| ServiceMesh | **3.3.2** | **stable** | redhat-operators | ✅ 설치됨 (Succeeded) |
| Serverless | (미정) | (미정) | redhat-operators | ❌ 미설치 |
| Pipelines | **1.22.0** | **latest** | redhat-operators | ✅ 설치됨 (Succeeded) |
| JobSet Operator | **1.0.0** | **stable-v1.0** | redhat-operators | ✅ 설치됨 (Succeeded) |
| LeaderWorkerSet Operator | **1.0.0** | **stable-v1.0** | redhat-operators | ✅ 설치됨 (Succeeded) |
| NFD | **4.21.0-202604200440** | **stable** | redhat-operators | ✅ 설치됨, GPU 노드 3개 관측 |
| NVIDIA GPU Operator | **26.3.1** | **v26.3** | certified-operators | ✅ 설치됨, GPU 노드 3개 관측 |

## 신규 Operator (Session 30 추가, 클러스터 확보 후 설치)

| 컴포넌트 | 목표 버전 | 채널 | 소스 | 상태 | 출처 |
|---|---|---|---|---|---|
| COO (Cluster Observability Operator) | **1.4.x** | **stable** | redhat-operators | ❌ 미설치 | OCP 4.21 릴리스 노트, COO 1.4 (2026-03) |
| Tempo Operator | **(미확인)** | **stable** | redhat-operators | ❌ 미설치 | RHOAI 3.4 Observability Stack 의존 |
| Red Hat build of OpenTelemetry | **(미확인)** | **stable** | redhat-operators | ❌ 미설치 | RHOAI 3.4 Observability Stack 의존 |
| CMA (Custom Metrics Autoscaler) | **2.18.1** | **stable** | redhat-operators | ❌ 미설치 | KEDA 2.18.1 기반, Rolling Stream (RHSA-2026:2368) |
| RHCL (Red Hat Connectivity Link) | **1.3.x** | **stable** | redhat-operators | ❌ 미설치 | OCP 4.19/4.20/4.21 지원 (GA 2026-02-26) |

> **주의**: Tempo/OTel 정확한 버전은 클러스터에서 `oc get packagemanifest` 실행 후 확정 필요. COO/CMA/RHCL은 `installPlanApproval: Automatic` + `channel: stable`이므로 채널 내 최신 버전이 자동 설치됨.

---

## RHOAI 컴포넌트 활성화 계획

| 컴포넌트 | 상태 | 비고 |
|---|---|---|
| dashboard | Managed | 기본 활성 |
| workbenches | Managed | 기본 활성 |
| kserve | Managed | PoC S1 모델 서빙 |
| datasciencepipelines | Managed | PoC S2 Pipeline |
| ray | (미정) | 분산 훈련 PoC 시 |
| kueue | (미정) | Ray와 함께 |
| modelregistry | (미정) | PoC에 따라 |

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

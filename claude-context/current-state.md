# 현재 상태 (2026-05-07 Session 28 기준)

> **현재 상태: 부트스트랩 단계 마무리. RHOAI 기준선은 마지막 클러스터 접근(Session 23) 시점 정상 (`default-dsc Ready=True`, drift 0). ArgoCD 인계는 Scope 0~5로 분할 진행 중이며, Scope 4 IaC 작성까지 완료했다(Session 27). 단, 클러스터가 현재 미확보 상태이므로 Scope 4 실행(dry-run/apply/sync)은 클러스터 확보 후 진행한다.** 이 파일을 읽으면 클러스터 설치 현황, 미결 사항, 최근 이벤트를 한눈에 파악할 수 있다.

## 클러스터

- OpenShift 버전: **4.21.9** (stable-4.21)
- API endpoint: `https://api.ocp.9qn8g.sandbox805.opentlc.com:6443` ✅
- Console URL: `https://console-openshift-console.apps.ocp.9qn8g.sandbox805.opentlc.com` ✅
- Ingress 도메인: `.env`의 `${OCP_DOMAIN}` 참조 ✅ (`apps.ocp.9qn8g.sandbox805.opentlc.com` 새 survey 확인)
- OS: Red Hat Enterprise Linux CoreOS 9.6.20260401-0 (Plow)
- Kubernetes: v1.34.6
- 환경: BOOTSTRAP 마무리 / OPS 전환 대기 / Connected (인터넷 연결 가능)
- 인증: htpasswd (`admin` / cluster-admin) ✅ — 로그인 확인
- TLS: 자가서명 인증서 ⚠️ — `--insecure-skip-tls-verify` 필요 (`constraints.md` 참조)
- 접근 가능 프로젝트: 96개 (2026-04-29 로그인 확인)

## 노드 구성

| 역할 | 수 | CPU (Allocatable) | Memory (Allocatable) | Max Pods |
|---|---|---|---|---|
| control-plane | 3 | — | — | — |
| worker | 8 | 7500m x8 | ~30 GB x5 / ~60 GB x3 | 250 |
| infra | 0 | — | — | — |

- GPU allocatable 노드: 3개 (`nvidia.com/gpu=1`, L40S 계열 기존 샘플 관측)
- 워커 실사용률: CPU/Memory는 워크로드 변동 큼. CPU LLM Pod는 `rhoai-poc-llm-cpu`에서 500m request / 2 CPU limit / 8Gi limit로 실행.

## 스토리지

| StorageClass | Provisioner | Default | VolumeBinding |
|---|---|---|---|
| gp2-csi | ebs.csi.aws.com | — | WaitForFirstConsumer |
| gp3-csi | ebs.csi.aws.com | ✅ | WaitForFirstConsumer |

## 설치 상태

- [x] cert-manager Operator — **v1.19.0** (새 survey)
- [x] OpenShift GitOps (ArgoCD) — **v1.20.2 / latest** (Route 확인)
- [x] ServiceMesh Operator — **v3.3.2** (stable)
- [ ] Serverless Operator — 미설치 (RHOAI 의존성 여부 확인 필요)
- [x] Pipelines Operator — **v1.22.0 / latest**
- [x] NFD Operator — **4.21.0-202604200440 / stable** (GPU 노드 3개 관측)
- [x] NVIDIA GPU Operator — **v26.3.1 / v26.3** (GPU 노드 3개 관측)
- [x] OpenShift AI Operator (RHOAI) — 목표 **3.4.0**, 관측 CSV **3.4.0-ea.1** / beta (새 survey)
- [x] JobSet Operator — **v1.0.0 / stable-v1.0** (`openshift-jobset-operator`)
- [x] LeaderWorkerSet Operator — **v1.0.0 / stable-v1.0** (`openshift-lws-operator`)
- [x] MaaS Gateway — `openshift-ingress/maas-default-gateway` Programmed=True
- [x] DataScienceCluster 적용 — **default-dsc Ready** (Session 14)
- [x] DataScienceCluster IaC 정합화 — `infra/rhoai/datasciencecluster.yaml` v2, drift 0 (Session 15)
- [x] ArgoCD Application IaC + sync runbook 작성 — `infra/argocd/applications/rhoai.yaml`, `runbooks/30-argocd-app-sync.md` (Session 15)
- [x] ArgoCD Scope 1 관리 뼈대 작성 — `infra/argocd/bootstrap/kustomization.yaml`, AppProject 3개, repo config replacement, dry-run 통과 (Session 19)
- [x] ArgoCD Scope 2 RHOAI core 인계 — `rhoai` Application Synced/Healthy, `default-dsc Ready=True`, `oc diff` exit 0 (Session 22)
- [x] ArgoCD Scope 3 RHOAI 의존성 인계 — `jobset`, `lws`, `maas-gateway` Application Synced/Healthy, `default-dsc Ready=True`, 의존성 drift 0 (Session 23)
- [x] 워크벤치 1개 생성 — `rhoai-poc-smoke/smoke-wb` Pod Running 2/2, Python 셀 스모크 통과 (Session 15)
- [x] CPU LLM 모델 배포 — `rhoai-poc-llm-cpu/smollm2-135m-cpu` Ready=True, `/v1/completions` 응답 확인 (Session 17)

## OperatorHub 카탈로그 상태

| 카탈로그 | 상태 |
|---|---|
| redhat-operators | READY ✅ |
| certified-operators | READY ✅ |
| community-operators | READY ✅ |
| redhat-marketplace | READY ✅ |

## Phase 1 진행 현황

- [x] `.env` 작성 (Session 03)
- [x] `runbooks/01-cluster-survey.md` 작성 (Session 04)
- [x] `scripts/cluster-survey.sh` 작성 (Session 04) — 파라메터화·재사용 가능
- [x] survey 전체 실행 완료 — 전 섹션(1-A~1-G) 정상 수집 (새 샌드박스: 2026-04-22)
- [x] 노드·Operator·StorageClass·Proxy·GPU 현황 반영 (새 샌드박스: 2026-04-29)
- [x] `version-matrix.md` · `constraints.md` 갱신 (RHOAI 3.4.0 목표 확정)
- **Phase 1 완료 ✅**

## 최근 이벤트 (최대 3건)

- 2026-05-07 Session 28: 클러스터 미확보 확인. 클러스터 없이 가능한 작업 수행 — 상태 파일 갱신(세션 27 결과 반영), IaC/문서 정합성 검토, Scope 5 OPS 전환 준비 체크리스트, ignoreDifferences 후보 정리.
- 2026-05-07 Session 27: Scope 4 IaC 작성 완료 — `workbench-smoke.yaml`, `llm-cpu.yaml` Application CR 작성, `applications/kustomization.yaml` 등록, `workbench-smoke/kustomization.yaml` 추가, `kubectl kustomize` 로컬 빌드 검증(6개 Application). 클러스터 적용은 미실행.
- 2026-04-30 Session 23: Scope 3 완료 — `jobset`, `lws`, `maas-gateway` Application을 등록/sync해 모두 `Synced/Healthy` 확인. MaaS Gateway sync 권한을 ClusterRole/Binding으로 보강했고 `default-dsc Ready=True`, JobSet/LWS/Gateway drift 0 유지.

## 미결 사항

- **클러스터 미확보** — 현재 접속 가능한 클러스터가 없다. Scope 4 실행(dry-run/apply/sync)과 Scope 5는 클러스터 확보 후 진행.
- Scope 4 IaC 작성 완료, 실행 미완 — `workbench-smoke`, `llm-cpu` Application CR이 IaC에 있으나 클러스터에 적용되지 않았다.
- 운영 모드 전환 트리거는 부분 실행됨 — RHOAI core와 의존성은 ArgoCD owned. PoC는 IaC까지 준비 완료, 클러스터 적용 대기.
- PoC 항목(스모크/CPU LLM 외) 미정 — 후속 후보 카탈로그는 `work-plans/003-test-capability-catalog.md` 참조. 이 문서는 현재 active task를 대체하지 않으며 Scope 4/5 이후 하나씩 승격한다.

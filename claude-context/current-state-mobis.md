# Mobis PoC 클러스터 상태 (bare metal)

> 고객 대상 실제 PoC 수행 클러스터. H200×8 + A40×2, 온프레미스 bare metal 2노드 구성.

## 클러스터 접속 정보

- OpenShift 버전: **4.21.14** (stable-4.21)
- API endpoint: `https://api.poc.mobis.com:6443`
- API (내부): `https://api-int.poc.mobis.com:6443`
- Console URL: `https://console-openshift-console.apps.poc.mobis.com`
- RHOAI Dashboard: `https://rh-ai.apps.poc.mobis.com`
- Ingress 도메인: `apps.poc.mobis.com`
- 환경: **POC** / Restricted (외부 NTP/DNS 제한)
- 인증: htpasswd (`admin` / `admin` / cluster-admin)
- 스토리지: LVM Storage — `lvms-vg-master`(default) + `lvms-vg-worker`, S3/NFS 없음
- TLS: `proxy/cluster` trustedCA = `user-ca-bundle` (HMG Secure ROOT CA 등록됨)
- 제약: 단일 Master(control-plane+worker 겸용), proxy/cluster 변경 시 API 일시 중단 가능

## 서버 인프라

| 역할 | 서버 | 수량 | vCPU | Memory | GPU |
|------|------|:----:|:----:|--------|-----|
| Master+Worker | HPE Cray XD670 | 1 | 192 | 1.5 TiB | H200×8 (HGX) |
| Worker | Dell PowerEdge R750 | 1 | 96 | 251 GiB | A40×2 |

- 총 GPU 10장, VRAM ~1,220 GB
- worker01: cordon(SchedulingDisabled) 상태 — uncordon 필요 시 `oc adm uncordon worker01.poc.mobis.com`

## 사전 작업 (2026-05-18 완료)

- [x] NMState Operator — v4.21.0 (노드 네트워크 선언적 관리)
- [x] DNS fallback (NNCP) — worker01에 master01 DNS 추가 (단일 장애점 제거)
- [x] CoreDNS upstream — master01(1차) + bastion(2차) Sequential
- [x] NTP chrony — master01 Stratum 10 로컬 서버, worker01 동기화 완료

## 설치 상태 (2026-05-21 실측)

### Operator (설치됨 — 25개)

- [x] OpenShift AI Operator (RHOAI) — **3.4.0 GA / stable-3.x**
- [x] NFD — **4.21.0 / stable**
- [x] NVIDIA GPU Operator — **26.3.1 / v26.3** (H200×8 + A40×2 인식)
- [x] NMState Operator — **4.21.0 / stable**
- [x] ServiceMesh Operator — **3.3.3 / stable** (Manual approval)
- [x] Serverless Operator — **1.37.1 / stable**
- [x] Pipelines Operator — **1.22.0 / latest**
- [x] cert-manager — **1.19.0 / stable-v1**
- [x] COO (Cluster Observability Operator) — **1.4.0 / stable**
- [x] Tempo Operator — **0.20.0-3 / stable**
- [x] OpenTelemetry — **0.144.0-3 / stable**
- [x] CMA (KEDA) — **2.18.1-2 / stable**
- [x] RHCL (Kuadrant) — **1.3.3 / stable** (Manual approval)
- [x] Authorino — **1.3.0 / stable** (RHCL 의존, OLM 자동 관리)
- [x] Limitador — **1.3.0 / stable** (RHCL 의존, OLM 자동 관리)
- [x] DNS Operator — **1.3.0 / stable** (Kuadrant DNS, OLM 자동 관리)
- [x] Kueue — **1.3.1 / stable-v1.3**
- [x] JobSet Operator — **1.0.0 / stable-v1.0**
- [x] LeaderWorkerSet Operator — **1.0.0 / stable-v1.0**
- [x] MetalLB — **4.21.0 / stable** (bare metal LoadBalancer)
- [x] LVM Storage — **4.21.0 / stable-4.21** (로컬 디스크 PVC)
- [x] Lightspeed — **1.1.0 / stable** (OpenShift AI 어시스턴트)
- [x] Kiali — **2.22.3 / stable** (ServiceMesh 관측성, Manual approval)
- [x] Cluster Logging — **6.5.1 / stable-6.5**
- [x] Loki Operator — **6.5.0 / stable-6.5** (Manual approval)

### Operator (미설치 — 구축 필요)

- [ ] OpenShift GitOps (ArgoCD)
- [ ] RHBK (Keycloak)

### IaC 커버리지 (2026-05-21)

- 신규 Operator IaC 16개 디렉토리 생성 (infra/operators/)
- DSCI (default-dsci) IaC 추가 (infra/rhoai/dsci.yaml)
- DSC wva/mcpGuardrailsMode 보정
- MaaS Gateway listener×2 + TLS cert 보정
- UIPlugin logging(LokiStack) 보정
- MonitoringStack replicas/RBAC 보정
- kustomize build 46/46 PASS

### RHOAI 컴포넌트 (DSC)

- [x] Dashboard — Ready
- [x] KServe — Ready (InferenceService: smollm2-135m, qwen3-8b)
- [x] ModelRegistry — Ready (mobis-registry, model-catalog)
- [x] AI Pipelines — Ready (DSPA + 7-stage E2E 파이프라인 실행 완료)
- [x] ModelsAsService — Reconciled (MaaS API + Gateway + Subscription)
- [x] TrustyAI — Ready (mcpGuardrailsMode: false)
- [x] MLflow — Ready
- [x] LlamaStack — Ready (Gen AI Studio Playground)
- [x] Trainer — Ready
- [x] Workbenches — Ready
- [x] Ray — Ready
- [x] Feast — Ready
- [x] Spark — Ready
- [x] WVA — Removed
- [ ] Kueue — Removed
- [ ] TrainingOperator — Removed

### ClusterOperator 상태 (2026-05-21)

- 34/34 ClusterOperator: Available=True, Degraded=False ✅
- 25/25 OLM CSV: Succeeded ✅
- LVMCluster: **Degraded** — vg-master /dev/sda→/dev/sdb 패치 완료, vg-worker worker01 cordon 미해결

### 시나리오 검증

- [x] S1 모델 서빙 — smollm2-135m Ready + 추론 정상, qwen3-8b MaaS 서빙 중
- [x] S2 Pipeline — 7-stage E2E Succeeded (v1/v2 모두 Completed)
- [ ] S3 Auto-scaling
- [ ] S4 장애복구
- [ ] S5 Scale-to-Zero
- [ ] S6 운영관리
- [ ] 종합 검증

## 에코시스템 (2026-05-21 실측)

### 배포됨

- MinIO (S3 호환 스토리지) — mobis-poc NS
- PostgreSQL×4 (Model Registry, MaaS, MLflow, Lightspeed)
- MariaDB (DSPA) — mobis-poc NS
- MailHog (SMTP 테스트) — mobis-poc NS
- Gitea (Git 서버) — mobis-poc NS + gitea-operator
- MLflow (experiment tracking) — redhat-ods-applications NS
- Perses — openshift-cluster-observability-operator NS + redhat-ods-monitoring NS
- DataScienceCluster — `default-dsc` Ready=True
- DCGM Exporter — nvidia-gpu-operator NS (master01 + worker01 양 노드)
- TrustyAI — mobis-poc NS (Running)
- EvalHub — redhat-ods-applications NS (Ready)
- LMEval — mobis-poc NS (smollm2-135m-eval-v3 Complete)
- LlamaStack + Gen AI Studio Playground — mobis-poc NS (Running)
- MaaS API — redhat-ods-applications NS (Running, health=200)
- MaaS Gateway — openshift-ingress NS (openshift-default GatewayClass, listener http+https, hostname maas.apps.poc.mobis.com)
- Authorino + Limitador — kuadrant-system NS (Running)
- Model Registry — rhoai-model-registries NS (mobis-registry + model-catalog)
- DSPA — mobis-poc NS (Ready=True)
- HardwareProfile — 5개 (cpu-small, default-profile, gpu-small/medium/large)
- LokiStack — openshift-logging NS (1x.demo, lvms-vg-master StorageClass)
- MonitoringStack — kuadrant-system NS (maas-alerting-stack) + redhat-ods-monitoring NS (data-science)
- UIPlugin — monitoring(Perses) + dashboards + logging(LokiStack)
- PersesDashboard — 12개 (GPU/vLLM/Tokens/APIKey/MaaS Token/Usage Trend 등)
- ScaledObject — mobis-poc NS (vllm-autoscaler, Prometheus 트리거)
- KedaController — openshift-keda NS
- NMState — nmstate CR (노드 네트워크 관리)
- MetalLB — metallb-system NS (worker nodeSelector)
- LVMCluster — openshift-storage NS (vg-master: /dev/sdb+/dev/sdc, vg-worker: /dev/sdb)

### 미배포 (구축 필요)

- RHBK (Keycloak) — 멀티테넌트 OIDC 인증용
- ManualApprovalGate — TektonConfig `enable-manual-approval-gates` 미설정
- GuardrailsOrchestrator — CR 미생성 (AI Safety 감지기)

## 트러블슈팅 이력

| 날짜 | 이슈 | 런북 | 결과 |
|------|------|------|:----:|
| 2026-05-19 | MaaS Gateway 403 (Wasm TLS CA 실패) | 115-proxy-trusted-ca | PASS |
| 2026-05-19 | worker01 SchedulingDisabled | uncordon | PASS |
| 2026-05-19 | alertmanager Pending (anti-affinity + cordon) | uncordon 후 자동 해결 | PASS |
| 2026-05-19 | MaaS Route 누락 (maas.apps.poc.mobis.com) | Route 수동 생성 | PASS |
| 2026-05-21 | LVMCluster Degraded (vg-master /dev/sda OS 디스크) | /dev/sda→/dev/sdb 패치 | PASS |
| 2026-05-21 | LVMCluster vg-worker no valid node | worker01 cordon 상태 | 미해결 |

## 최근 이벤트 (최대 3건)

- 2026-05-21: IaC 전면 동기화(Operator 16개+DSC/DSCI+Gateway+monitoring). LVMCluster /dev/sda 패치. ClusterOperator 34/34 정상.
- 2026-05-19: TLS CA 트러블슈팅 완료(115). worker01 uncordon. MaaS API Key 201 정상.
- 2026-05-18: 클러스터 정보 수령. NMState/DNS/NTP 사전 작업 완료 확인.

## 미결 사항

- **worker01 cordon** — SchedulingDisabled 상태. LVMCluster vg-worker Degraded 원인. uncordon 필요
- **GitOps** — ArgoCD 미설치. IaC 동기화 전에 010-argocd 실행 필요
- **시나리오 검증** — S1/S2 부분 완료, S3~S6 미착수
- **LDAP** — 고객 LDAP 정보 미확보 (S6 RBAC 검증용)
- **HardwareProfile** — gpu-xlarge-h200 (16C/128Gi/8GPU) 미생성 — 70B 모델 서빙 시 필요

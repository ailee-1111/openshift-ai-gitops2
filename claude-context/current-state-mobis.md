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
- 인증: htpasswd (`admin` / cluster-admin)
- 스토리지: LVM Storage (topolvm) — 로컬 디스크, S3/NFS 없음
- 제약: 단일 Master(control-plane+worker 겸용), Rolling Update 시 API 일시 중단 가능

## 서버 인프라

| 역할 | 서버 | 수량 | vCPU | Memory | GPU |
|------|------|:----:|:----:|--------|-----|
| Master+Worker | HPE Cray XD670 | 1 | 192 | 1.5 TiB | H200×8 (HGX) |
| Worker | Dell PowerEdge R750 | 1 | 96 | 251 GiB | A40×2 |

- 총 GPU 10장, VRAM ~1,220 GB

## 사전 작업 (2026-05-18 완료)

- [x] NMState Operator — v4.21.0 (노드 네트워크 선언적 관리)
- [x] DNS fallback (NNCP) — worker01에 master01 DNS 추가 (단일 장애점 제거)
- [x] CoreDNS upstream — master01(1차) + bastion(2차) Sequential
- [x] NTP chrony — master01 Stratum 10 로컬 서버, worker01 동기화 완료

## 설치 상태 (2026-05-19 실측)

### Operator (설치됨 — 23개)

- [x] OpenShift AI Operator (RHOAI) — **3.4.0 GA / stable-3.x**
- [x] NFD — **4.21.0 / stable**
- [x] NVIDIA GPU Operator — **26.3.1 / v26.3** (H200×8 + A40×2 인식)
- [x] NMState Operator — **4.21.0 / stable**
- [x] ServiceMesh Operator — **3.3.3 / stable**
- [x] Serverless Operator — **1.37.1 / stable**
- [x] Pipelines Operator — **1.22.0 / latest**
- [x] cert-manager — **1.19.0 / stable-v1**
- [x] COO (Cluster Observability Operator) — **1.4.0 / stable**
- [x] Tempo Operator — **0.20.0-3 / stable**
- [x] OpenTelemetry — **0.144.0-3 / stable**
- [x] CMA (KEDA) — **2.18.1-2 / stable**
- [x] RHCL (Kuadrant) — **1.3.3 / stable**
- [x] Authorino — **1.3.0 / stable** (RHCL 의존)
- [x] Limitador — **1.3.0 / stable** (RHCL 의존)
- [x] DNS Operator — **1.3.0 / stable** (Kuadrant DNS)
- [x] Kueue — **1.3.1 / stable-v1.3**
- [x] JobSet Operator — **1.0.0 / stable-v1.0**
- [x] LeaderWorkerSet Operator — **1.0.0 / stable-v1.0**
- [x] MetalLB — **4.21.0 / stable** (bare metal LoadBalancer)
- [x] LVM Storage — **4.21.0 / stable-4.21** (로컬 디스크 PVC)
- [x] Lightspeed — **1.0.12 / stable** (OpenShift AI 어시스턴트)
- [x] Kiali — **2.22.3 / stable** (ServiceMesh 관측성)

### Operator (미설치 — 구축 필요)

- [ ] OpenShift GitOps (ArgoCD)
- [ ] RHBK (Keycloak)

### 시나리오 검증

- [ ] S1 모델 서빙
- [ ] S2 Pipeline
- [ ] S3 Auto-scaling
- [ ] S4 장애복구
- [ ] S5 Scale-to-Zero
- [ ] S6 운영관리
- [ ] 종합 검증

## 에코시스템 (2026-05-19 실측)

### 배포됨

- MinIO (S3 호환 스토리지) — mobis-poc NS
- PostgreSQL×4 (Model Registry, MaaS, MLflow, Lightspeed)
- MariaDB (DSPA) — mobis-poc NS
- MailHog (SMTP 테스트) — mobis-poc NS
- Gitea (Git 서버) — mobis-poc NS + gitea-operator
- MLflow (experiment tracking) — redhat-ods-applications NS
- Perses (관측성 대시보드) — openshift-cluster-observability-operator NS
- DataScienceCluster — `default-dsc` Ready=True

### 미배포 (구축 필요)

- RHBK (Keycloak)
- DCGM Exporter (GPU 모니터링 메트릭)
- Gen AI Studio
- ManualApprovalGate
- GuardrailsOrchestrator + TrustyAI (AI Safety)

## 최근 이벤트 (최대 3건)

- 2026-05-19: H200×8 서버 확보. 블로커 해소. 런북 최신화 착수 (Session 37).
- 2026-05-18: 클러스터 정보 수령. NMState/DNS/NTP 사전 작업 완료 확인. current-state 분리 시작.

## 미결 사항

- ~~런북 최신화~~ — Session 37에서 완료 (환경변수 이식성 확보)
- **Platform Setup** — Operator 23/25 설치 완료. 미설치: GitOps(ArgoCD), RHBK(Keycloak)
- **GitOps** — ArgoCD 미설치. 100번 런북 기반 IaC 동기화 전에 010-argocd 실행 필요
- **시나리오 검증** — S1~S6 미착수. 000-preflight → 001-survey → 시나리오 순서 실행 필요
- **LDAP** — 고객 LDAP 정보 미확보 (S6 RBAC 검증용)
- **네트워크 제약** — Restricted 환경. 이미지 미러링 필요 여부 확인

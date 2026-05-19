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

## 설치 상태

### Operator (설치됨)

- [x] OpenShift AI Operator (RHOAI) — **3.4.0 GA / stable-3.x**
- [x] NFD — **4.21.0 / stable**
- [x] NVIDIA GPU Operator — H200×8 + A40×2 인식
- [x] NMState Operator — **4.21.0**
- [x] ServiceMesh Operator
- [x] Serverless Operator
- [x] Pipelines Operator

### Operator (미설치 — 구축 필요)

- [ ] OpenShift GitOps (ArgoCD)
- [ ] RHBK (Keycloak)
- [ ] Kueue
- [ ] CMA (KEDA)
- [ ] COO (Cluster Observability Operator)
- [ ] Tempo Operator
- [ ] OpenTelemetry
- [ ] RHCL (Kuadrant)
- [ ] cert-manager
- [ ] JobSet Operator
- [ ] LeaderWorkerSet Operator

### 시나리오 검증

- [ ] S1 모델 서빙
- [ ] S2 Pipeline
- [ ] S3 Auto-scaling
- [ ] S4 장애복구
- [ ] S5 Scale-to-Zero
- [ ] S6 운영관리
- [ ] 종합 검증

## 에코시스템

### 배포됨

- MinIO (S3 호환 스토리지)

### 미배포 (구축 필요)

- PostgreSQL (Model Registry, MaaS, MLflow, Keycloak용)
- MariaDB (DSPA)
- RHBK (Keycloak)
- Authorino + Limitador (API GW)
- MailHog (SMTP 테스트)
- DCGM (GPU 모니터링)
- Perses + Tempo + OTel (관측성)
- MLflow (experiment tracking)
- Gen AI Studio
- ManualApprovalGate
- GuardrailsOrchestrator + TrustyAI (AI Safety)

## 최근 이벤트 (최대 3건)

- 2026-05-18: 클러스터 정보 수령. NMState/DNS/NTP 사전 작업 완료 확인. current-state 분리 시작.

## 미결 사항

- **Platform Setup** — 40번 런북 기반 Operator 설치 (bare metal 환경 맞춤 조정 필요)
- **S3 스토리지** — MinIO 활용 (NFS/외부 S3 없음)
- **LDAP** — 고객 LDAP 정보 미확보
- **네트워크 제약** — 외부 인터넷 제한, 이미지 미러링 필요 여부 확인

# 현재 상태 (2026-05-15 Session 30 기준)

> **프로젝트 목적이 재정의되었다: "AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC 수행".** poc-factory는 폐기되었으며, 필요한 문서(런북, 시나리오, 검증 항목)를 이 프로젝트에 흡수 중이다. CLAUDE.md, guidelines, reports/ 구조 변경은 완료. 런북 변환과 RTM 작성이 진행 중이다. 기존 Scope 4/5(ArgoCD PoC Application 편입)는 클러스터 확보 후 별도 진행.

## 클러스터 (신규 — 2026-05-15)

- OpenShift 버전: **4.21.14** (stable-4.21)
- API endpoint: `https://api.ocp.cq8fh.sandbox625.opentlc.com:6443` ✅
- Console URL: `https://console-openshift-console.apps.ocp.cq8fh.sandbox625.opentlc.com` ✅
- Ingress 도메인: `apps.ocp.cq8fh.sandbox625.opentlc.com`
- 환경: **POC** (PoC 수행 단계) / Connected
- 인증: htpasswd (`admin` / cluster-admin) + htpasswd-poc (poc-admin/poc-operator/poc-user)
- GPU: **g6e.12xlarge × 1** (L40S × 4)
- TLS: 자가서명 인증서 ⚠️ — `--insecure-skip-tls-verify` 필요

## 설치 상태

- [x] OpenShift GitOps (ArgoCD) — **v1.20.3 / latest**
- [x] ServiceMesh Operator — **v3.3.3** (stable, RHOAI 의존)
- [x] Serverless Operator — **v1.37.1 / stable**
- [x] Pipelines Operator — **v1.22.0 / latest**
- [x] OpenShift AI Operator (RHOAI) — **3.4.0 GA / stable-3.x**
- [x] JobSet Operator — **v1.0.0 / stable-v1.0**
- [x] LeaderWorkerSet Operator — **v1.0.0 / stable-v1.0**
- [x] NFD — **4.21.0 / stable** (openshift-nfd NS)
- [x] NVIDIA GPU Operator — **25.3.4 / v25.3** (L40S×4 인식)
- [x] CMA (KEDA) — **2.18.1-2 / stable**
- [x] COO — **1.4.0 / stable**
- [x] Tempo Operator — **0.20.0-3 / stable**
- [x] OpenTelemetry — **0.144.0-3 / stable**
- [x] RHCL (Kuadrant) — **1.3.3 / stable** (AllNamespaces OG)
- [x] DataScienceCluster — **default-dsc Ready=True**
- [x] MaaS — **maas-api Running** (PoC PostgreSQL)
- [x] 40-platform-setup 17단계 완료
- [x] 50~54 RHOAI 토폴로지 (Model Registry, ServingRuntime, HardwareProfile, DSPA, TrustyAI, MLflow)
- [x] 55 Perses 대시보드 3개 (GPU/vLLM/Tokens) + DCGM/Limitador ServiceMonitor
- [x] S1 모델 서빙 — InferenceService Ready + 추론 정상
- [x] S2 Pipeline — Tekton E2E Succeeded (S3검증→승인→서빙검증)
- [x] S3 Auto-scaling — ScaledObject READY=True, HPA 정상 (조건부 PASS)
- [x] MaaS API Key + Gen AI Studio Playground 정상 (qwen3-8b)
- [ ] S4~S6 시나리오 — 다음 세션
- [ ] ArgoCD Application — 미진행

## 구조 변경 진행 현황 (Session 30)

- [x] `CLAUDE.md` — 목적 재정의, POC 환경 추가, PoC 프로세스 추가
- [x] `work-plans/004-poc-restructure.md` — 의사결정 기록
- [x] `guidelines/01-layer-contracts.md` — 넘버링 세분화 (60~65 구축/70~75 검증/80 종합), reports/ 추가
- [x] `reports/_template/README.md` — 산출물 템플릿
- [x] `work-plans/005-mobis-rtm.md` — RTM 작성 완료 (S1~S6 + Exploratory + Out-of-scope)
- [x] 런북 변환 완료 — 70~75 검증 런북 + 80 종합 검증 신규 작성
- [x] 구축 런북(60-a, 64, 65) "다음 단계" 링크 → 검증 런북으로 수정

## 최근 이벤트 (최대 3건)

- 2026-05-15 Session 30: S1~S3 시나리오 구축 완료. Perses 대시보드 3개(GPU/vLLM/Tokens). MaaS/Gen AI Studio 트러블슈팅 해결 (Authorino TLS, tier-to-group, LlamaStack base_url). Prometheus 15 target 전체 UP.
- 2026-05-15 Session 30: 신규 클러스터(4.21.14, g6e.12xlarge L40S×4) 확보. 17개 Operator + 40번 런북 17단계 + 50~55 토폴로지 구성 완료.
- 2026-05-15 Session 30: 검증 런북 70~75 + 80 작성 + IaC 27개 + 런북 보강.

## 미결 사항

- **S4~S6 시나리오** — 장애복구, Scale-to-Zero, 운영관리 구축+검증 미진행
- **ArgoCD Application 미등록** — 신규 클러스터에서 Scope 재진행 필요
- **Usage 대시보드** — user/subscription/model 레이블 미생성 (MaaS TP 제한)
- **LDAP/AD 연동 테스트 정보 미확보** — 고객 측 LDAP 정보 필요 (RTM V-45/46)

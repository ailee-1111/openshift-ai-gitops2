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
- [x] RHCL (Kuadrant) — **1.3.3 / stable** (AllNamespaces OG, Authorino 1.3.0 + Limitador 1.3.0 의존)
- [x] cert-manager — **1.19.0 / stable-v1**
- [x] RHBK (Keycloak) — **26.4.11-opr.2 / stable-v26.4**
- [x] Kueue — **1.3.1 / stable**
- [x] DataScienceCluster — **default-dsc Ready=True**
- [x] MaaS — **maas-api Running** (PoC PostgreSQL)
- [x] 40-platform-setup 17단계 완료
- [x] 50~54 RHOAI 토폴로지 (Model Registry, ServingRuntime, HardwareProfile, DSPA, TrustyAI, MLflow)
- [x] 55 Perses 대시보드 3개 (GPU/vLLM/Tokens) + DCGM/Limitador ServiceMonitor
- [x] S1 모델 서빙 — InferenceService Ready + 추론 정상
- [x] S2 Pipeline — Tekton E2E Succeeded (S3검증→승인→서빙검증)
- [x] S3 Auto-scaling — ScaledObject READY=True, HPA 정상 (조건부 PASS)
- [x] MaaS API Key + Gen AI Studio Playground 정상 (qwen3-8b)
- [x] S4 장애복구 — Pod복구 66초, RollingUpdate PASS, 롤백 PASS
- [x] S5 Scale-to-Zero — VRAM 해제 확인, Cold Start 61초/73초
- [x] S6 운영관리 — RBAC/GPU모니터링/서빙성능/알림/대시보드 전체 PASS
- [x] 종합 검증(80) — 52/52 PASS(100%), 횡단 테스트 PASS
- [x] GuardrailsOrchestrator — 3/3 Running (PII/HAP/프롬프트인젝션 감지기)
- [x] EvalHub — Ready (Dashboard Evaluations 탭, 5 providers)
- [x] LMEvalJob — Complete (hellaswag, CLI 정상)
- [x] MLflow — Available (experiment tracking)
- [x] PoC v1 리포팅 — HTML 대시보드(12탭) + 6인 전문가 검증 + 시니어 컨설턴트 리뷰
- [x] 런북 7개 신규 — 65-c(Kueue), 65-d(LDAP), 62-b(HPA), 63-b(drain), 60-c(TGI), 60-d(Guardian), 60-e(멀티노드)
- [x] IaC 2개 신규 — infra/poc/kueue/(7파일), infra/poc/ldap/(3파일)
- [x] ArgoCD Application — 6개 등록. 4/6 Synced/Healthy. 2/6 OutOfSync/Healthy (RHOAI 주입 diff)
- [x] ArgoCD RBAC — KServe/Notebook ClusterRole, kustomize exclusion 추가
- [x] v3 E1 S1~S6 강화 런북 6개 — 60/61/62/63/64/65-v3-*.md
- [x] v3 E2 S7~S10 신규 런북 4개 — 66(MaaS), 67(멀티테넌트), 68(보안게이트), 69(MLOps)
- [x] v3 Phase F — .env.example 확장(S7~S10 변수), scripts/validate-scenario.sh(S1~S10)
- [x] v3 6인 페르소나 검증 — reviews/v3-persona-review.md (8.3/10 + 클러스터 실측 15 PASS)
- [x] v4 로드맵 — work-plans/009-roadmap-v4.md (Phase I~N)
- [x] S2 파이프라인 실측 — 7단계 E2E Succeeded (poc-operator→poc-admin/group:rhods-admins 승인)
- [x] S2 MailHog 알림 — Stage 2/5 SMTP 발송 확인 (5건 수신)
- [x] validate-scenario.sh 클러스터 실행 — 15 PASS / 0 FAIL / 1 SKIP
- [x] Phase D 리포트 강화 — HTML 15탭 (스크린샷 갤러리, 프로덕션 전환 로드맵, 비용 할당 추가)
- [x] Phase I IaC 실체화 — infra/poc/{maas-routing,multitenant,security-gate,mlops-loop} 4개, kustomize 13/13 PASS
- [x] Phase L 검증 런북 v3 동기화 — 70~75에 v3 강화 항목 추가, 76~79 신규 생성, 80 종합 갱신
- [x] Phase J Kustomize overlay — overlays/{dev,staging,prod} 3환경, kustomize 16/16 PASS
- [x] 정합성 검증 — 런북↔IaC 9/9 PASS, kustomize 16/16, 클러스터 13 PASS/0 FAIL
- [x] llm-d/qwen3 Ready=True — Gateway allowedRoutes에 rhoai-poc 추가로 HTTPRoutesNotReady 해소
- [x] 에코시스템 아키텍처 — HTML에 서버 인프라(6노드) + 에코시스템 22개 테이블 + 트래픽 플로우 추가

## 서버 인프라

| 역할 | 인스턴스 | 수량 | vCPU | Memory | GPU |
|------|----------|:----:|:----:|--------|-----|
| Control Plane | m6a.4xlarge | 3 | 16 | 64 GiB | - |
| Worker (CPU) | m5a.4xlarge | 2 | 16 | 64 GiB | - |
| Worker (GPU) | g6e.12xlarge | 1 | 48 | 384 GiB | L40S×4 |

## 에코시스템

- MinIO(S3), PostgreSQL×4, MariaDB(DSPA), OpenLDAP, RHBK(Keycloak)
- Authorino+Limitador(API GW), MailHog(SMTP), DCGM(GPU)
- Perses+Tempo+OTel(관측성), MLflow, Gen AI Studio, ManualApprovalGate
- GuardrailsOrchestrator+TrustyAI(AI Safety)

## 구조 변경 진행 현황 (Session 30)

- [x] `CLAUDE.md` — 목적 재정의, POC 환경 추가, PoC 프로세스 추가
- [x] `work-plans/004-poc-restructure.md` — 의사결정 기록
- [x] `guidelines/01-layer-contracts.md` — 넘버링 세분화 (60~65 구축/70~75 검증/80 종합), reports/ 추가
- [x] `reports/_template/README.md` — 산출물 템플릿
- [x] `work-plans/005-mobis-rtm.md` — RTM 작성 완료 (S1~S6 + Exploratory + Out-of-scope)
- [x] 런북 변환 완료 — 70~75 검증 런북 + 80 종합 검증 신규 작성
- [x] 구축 런북(60-a, 64, 65) "다음 단계" 링크 → 검증 런북으로 수정

## 최근 이벤트 (최대 3건)

- 2026-05-17 Session 35: **v3~v4 완성 + 리포트 12스프린트**. 런북 51개(NNN), HTML 11탭(16→11 재구축), 탭 토글, 9차트, 5다이어그램, 6인 페르소나(9.5~9.6), S7~S10 리포트 4개, 모델 4개, validate 15/0/1, kustomize 15/15, Operator 21개
- 2026-05-17 Session 34: Phase A~C 전체 완료. B: 6/6 Synced. C-1: GPU 벤치마크 67ms/req.
- 2026-05-16 Session 33: Phase A 5/5 실측 PASS. v2 로드맵. 6인 검증.

## 미결 사항

- **Phase D** — 발표 자료 (일정 미확정)
- **Usage 대시보드** — MaaS TP 제한
- **v4 Phase I** — S7~S10 IaC 실체화 대기
- **qwen3-8b** — vLLM 응답 불가 블로커
- **HGX 후속** — 70B+ 모델 벤치마크, 멀티노드 GPU 추론 (현 환경에서는 8B GPU + LWS CPU로 검증 완료)

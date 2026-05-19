# 현재 상태 (2026-05-18 Session 36 기준)

> **프로젝트**: AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC 수행. 모비스 고객 on-prem 클러스터에서 PoC Day 2 운영 중.

## 클러스터

- OpenShift 버전: **4.21.14** (stable-4.21)
- API endpoint: `https://api.poc.mobis.com:6443` ✅
- Console URL: `https://console-openshift-console.apps.poc.mobis.com` ✅
- Ingress 도메인: `apps.poc.mobis.com`
- Dashboard: `https://rhods-dashboard-redhat-ods-applications.apps.poc.mobis.com`
- 환경: **POC** (PoC Day 2 운영) / On-prem bare metal
- 인증: htpasswd (`admin` / cluster-admin)
- TLS: 자가서명 인증서 ⚠️

## 서버 인프라

| 역할 | 호스트명 | GPU | GPU 모델 | 상태 |
|------|----------|:---:|----------|:----:|
| Control Plane + Worker | master01.poc.mobis.com | 8 | **NVIDIA H200** | ✅ Ready |
| Worker | worker01.poc.mobis.com | 2 | **NVIDIA A40** | ✅ Ready |

## 설치 상태

- [x] RHOAI Operator — **3.4.0 GA / stable-3.x**
- [x] ServiceMesh — **3.3.3 / stable**
- [x] Serverless — **1.37.1 / stable**
- [x] Pipelines — **1.22.0 / latest**
- [x] JobSet — **1.0.0 / stable-v1.0**
- [x] LeaderWorkerSet — **1.0.0 / stable-v1.0**
- [x] NFD — **4.21.0 / stable**
- [x] NVIDIA GPU Operator — **26.3.1 / v26.3** (H200×8 + A40×2)
- [x] COO — **1.4.0 / stable**
- [x] Tempo — **0.20.0-3 / stable**
- [x] OpenTelemetry — **0.144.0-3 / stable**
- [x] CMA (KEDA) — **2.18.1-2 / stable**
- [x] RHCL (Kuadrant) — **1.3.3 / stable** (Authorino 1.3.0 + Limitador 1.3.0)
- [x] cert-manager — **1.19.0 / stable-v1**
- [x] Kueue — **1.3.1 / stable**
- [x] DataScienceCluster — **default-dsc Ready=True**
- [ ] OpenShift GitOps (ArgoCD) — **미설치**

## PoC 네임스페이스: `mobis-poc`

### 모델 서빙

| 모델 | 타입 | 상태 | GPU | 비고 |
|------|------|:----:|-----|------|
| smollm2-135m | KServe IS | ✅ Ready | A40 | KServe Route 직접 서빙 |
| qwen3-8b-fp8-dynamic-version-1 | llm-d LLMIS | ✅ Ready | H200 | MaaS Gateway HTTPRoute |
| qwen3.5-35b-a3b-fp8-dynamic-ver | llm-d LLMIS | ⏸️ Stopped | - | 의도적 중지 |

### 서비스 상태

| 서비스 | 상태 | 비고 |
|--------|:----:|------|
| MaaS Gateway | ✅ Running | Wasm TLS 해소 (CA 번들 주입), API Key 추론 정상 |
| MaaS API | ✅ Running | |
| ModelRegistry | ✅ Available | |
| TrustyAI Service | ✅ Running | |
| DSPA | ✅ Running | ds-pipeline + mariadb |
| MLflow | ✅ Running | |
| ScaledObject (KEDA) | ✅ Ready | smollm2-135m, 1-3 replicas |
| DCGM Exporter | ✅ Running | 2노드 |
| Perses 대시보드 | ✅ 10개 | GPU/vLLM/Tokens/Usage 등 |
| PrometheusRule | ✅ 2개 | poc-gpu-alerts, vllm-alerts |
| ServiceMonitor | ✅ 5개 | |
| EvalHub | ✅ Available | evalhub Route 존재 |
| GuardrailsOrchestrator | ❌ 미배포 | |
| 한국 PII 감지기 | ❌ 미배포 | |
| ArgoCD | ❌ 미설치 | |

## 최근 이벤트 (최대 3건)

- 2026-05-18 Session 36: 전체 런북 55개 점검, 링크 오류 7건 수정, 클러스터 검증 — **poc.mobis.com 실측 반영**, MaaS Gateway Wasm TLS 근본 원인 발견
- 2026-05-18 Session 35: 리포트 12스프린트(11탭), 한국 PII 감지기(381/581/IaC), 전수 검사 18/18
- 2026-05-17 Session 34: Phase A~C 전체 완료. B: 6/6 Synced. C-1: GPU 벤치마크 67ms/req

## 미결 사항

- **MaaS Gateway Wasm TLS — 해결됨** — `trusted-ca-bundle` ConfigMap(노드 CA 147개)을 Gateway Pod에 마운트하여 해소. `SSL_CERT_FILE` 환경변수 설정. API Key `poc-test-key` 생성, qwen3-8b 추론 정상 (200, 5.4초)
- **smollm2-135m MaaS 미등록** — KServe IS라서 HTTPRoute 자동 생성 안 됨. MaaS Gateway 통한 접근 불가
- **GuardrailsOrchestrator 미배포** — S9 보안 게이트 시나리오 미실행
- **ArgoCD 미설치** — GitOps 미적용 상태
- **qwen3.5-35b Stopped** — GPU 자원 관리 목적 의도적 중지

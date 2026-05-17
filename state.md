# 프로젝트 진척도

전체 로드맵의 체크리스트. 세션 단위의 세부 상태는 [`claude-context/current-state.md`](claude-context/current-state.md), 누적 인수인계는 [`claude-context/handoff-notes.md`](claude-context/handoff-notes.md) 참조.

**진척 요약**: PoC v1~v3 전체 완성. 10개 시나리오(S1~S10) 런북 52개 + IaC 16개 디렉토리(kustomize 16/16 PASS) + overlay 3환경 + HTML 15탭 리포트 + 프로덕션 준비도 9.1/10. v4(Phase K~N) 대기.

---

## 📍 현재 Phase

> **PoC v4 Phase K~N 대기** — v1~v3 문서/런북/IaC/리포트 전체 완성. 클러스터 15 PASS/0 FAIL. llm-d/qwen3-8b Ready. 남은 작업은 GPU TrainJob(LoRA), HGX 벤치마크, 최종 리포트(클러스터 의존).

---

## Phase 0 — 방법론 체계 구축 ✅

- [x] 4계층 디렉토리 + guidelines 6종 + CLAUDE.md + README.md
- [x] claude-context/ 초기 스켈레톤 5파일
- [x] GEMINI.md / AGENTS.md 심볼릭 링크

---

## Phase 1 — 클러스터 조사 ✅

- [x] 00-preflight.md + 01-cluster-survey.md + scripts/cluster-survey.sh
- [x] OCP 4.21.14 / RHOAI 3.4.0 GA 확정
- [x] version-matrix.md 전체 컴포넌트 확정 (21개 Operator)

---

## Phase 2 — GitOps 부트스트랩 ✅

- [x] OpenShift GitOps v1.20.3
- [x] ArgoCD Application 6/6 Synced/Healthy
- [x] AppProject 3개 + RBAC + ignoreDifferences

---

## Phase 3 — 플랫폼 Operator ✅ (21개)

- [x] RHOAI 3.4.0 GA + DSC Ready=True
- [x] ServiceMesh 3.3.3 / Serverless 1.37.1 / Pipelines 1.22.0
- [x] JobSet 1.0.0 / LWS 1.0.0 / NFD 4.21.0 / GPU 25.3.4
- [x] CMA 2.18.1-2 / COO 1.4.0 / Tempo 0.20.0-3 / OTel 0.144.0-3
- [x] RHCL 1.3.3 / RHBK 26.4.11-opr.2 / cert-manager 1.19.0 / Kueue 1.3.1

---

## Phase 4 — OpenShift AI + 토폴로지 ✅

- [x] 40-platform-setup 17단계
- [x] 50~55 RHOAI 토폴로지 + Perses 대시보드 3개
- [x] MaaS Gateway + API Key + Gen AI Studio

---

## Phase 5 — PoC v1 시나리오 검증 ✅ (S1~S6)

- [x] S1~S6 구축+검증 52/52 PASS (100%)
- [x] Exploratory 27개 (22검증/5부분)
- [x] GuardrailsOrchestrator + EvalHub + LMEvalJob + MLflow
- [x] PoC v1 리포팅 — HTML 12탭 + 6인 전문가 검증

---

## Phase 6 — PoC v2 프레임워크 강화 ✅ (A~D)

- [x] Phase A: 런북 7개 + 실측 5/5 PASS
- [x] Phase B: ArgoCD 6/6 Synced
- [x] Phase C: GPU 벤치마크 67ms + LWS 3노드
- [x] Phase D: HTML 15탭 (스크린샷/프로덕션 전환/비용 할당)
- [x] Makefile 7타겟 + 준비도 7.5→9.1/10

---

## Phase 7 — PoC v3 시나리오 강화 ✅ (E1~E2 + F)

- [x] E1: S1~S6 강화 런북 6개
- [x] E2: S7~S10 신규 런북 4개
- [x] Phase F: .env.example + validate-scenario.sh
- [x] S2 파이프라인 실측 — 7단계 E2E + RBAC 분리 + 그룹 승인 + MailHog
- [x] 6인 페르소나 검증 8.3/10 + 클러스터 15 PASS
- [x] v4 로드맵 (009-roadmap-v4.md)

---

## Phase 8 — PoC v4 IaC/검증/Overlay ✅ (I + L + J)

- [x] Phase I: IaC 4개 디렉토리 + kustomize 16/16 PASS
- [x] Phase L: 검증 런북 70~80 v3 동기화 + 76~79 신규
- [x] Phase J: Kustomize overlay 3환경 PASS
- [x] 런북↔IaC 9/9 PASS + Operator Gap 해소
- [x] Gateway rhoai-poc → llm-d/qwen3 Ready
- [x] 에코시스템 아키텍처 (서버 6노드 + 22개 서비스 + 트래픽 플로우)

---

## Phase 9 — PoC v4 실행 (대기 중)

- [ ] Phase K: GPU LoRA/QLoRA TrainJob + Slack 알림
- [ ] Phase M: HGX 70B+ 벤치마크
- [ ] Phase N: RTM/리포트 v4

**블로커**: HGX 미확보, version-matrix 사람 갱신 필요

---

## 🗂 세션 히스토리

| 세션 | 날짜 | 마일스톤 |
|:----:|------|----------|
| 01 | 04-17 | Phase 0 완료 |
| 02~06 | 04-18~19 | Phase 1 완료 |
| 07~09 | 04-19~20 | Phase 2~3 GitOps+RHOAI |
| 10~17 | 04-29 | 새 샌드박스, 의존성 보강, CPU LLM |
| 18~28 | 04-30~05-07 | ArgoCD Scope, IaC 보강 |
| 29~30c | 05-15 | PoC 구조 재정의, 런북 변환 |
| 31 | 05-15 | S4~S6 + 종합 + 리포트 |
| 32 | 05-16 | RTM 85개 + TrustyAI |
| 33 | 05-16 | v1 100% + v2 로드맵 |
| 34 | 05-17 | Phase A~C + v3 로드맵 |
| **35** | **05-17** | **v3~v4 전체 완성**, D/I/L/J, 에코시스템, 9.1/10 |

---

## 📊 산출물

| 카테고리 | 수량 |
|----------|:----:|
| 런북 | 52 |
| IaC 디렉토리 | 16 (+3 overlay) |
| work-plans | 9 |
| HTML 리포트 탭 | 15 |
| Makefile 타겟 | 7 |
| 스크립트 | 2 |

---

## 📎 범례

- `[x]` 완료 · `[ ]` 미완료 · `✅` Phase 완료

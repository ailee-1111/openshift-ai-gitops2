# 인수인계 노트

> **이 파일을 읽으면 세션별 완료·진행중·블로커·다음 할 일을 파악할 수 있다.** 형식 및 규칙: `guidelines/03-handoff-protocol.md`. 신규 엔트리는 **파일 하단에 추가**, 기존 엔트리 수정 금지.
> 2026-04-29: 오래된 엔트리는 `claude-context/archive/handoff-2026-Q2.md`로 이관함.

> 2026-05-17: Session 10~28 엔트리를 `claude-context/archive/handoff-2026-Q2-b.md`로 이관함.

---

## 2026-05-15 Session 29 — PoC 프로젝트 구조 재정의

- 완료: 프로젝트 목적 재정의 ("AI와 IaC를 활용한 고객 시나리오 기반 PoC 수행"), CLAUDE.md 갱신 (목적/POC 환경/PoC 프로세스), work-plans/004-poc-restructure.md 작성, guidelines/01-layer-contracts.md 넘버링 세분화 (60~65 구축/70~75 검증/80 종합), reports/_template/README.md 생성, active-task.md 갱신
- 진행중: 런북 변환 (poc-factory phase-0~5 → 60~75, 90), RTM 작성
- 블로커: 없음
- 다음 세션이 할 일: 런북 변환 실행, work-plans/ RTM 작성, current-state.md 갱신
- 발견된 제약: poc-factory 폐기 결정. 검증 항목 상세(85개)는 reports/ 산출물로 활용. 시나리오 설계는 런북 §목적에 흡수

---

## 2026-05-15 Session 30 — 검증 런북(70~75, 80) 작성 완료

- 완료: 검증 런북 7개 신규 작성 (70-model-serving-validation, 71-pipeline-validation, 72-autoscaling-validation, 73-recovery-validation, 74-scale-to-zero-validation, 75-platform-ops-validation, 80-comprehensive-validation). 구축 런북(60-a, 64, 65) "다음 단계" 링크를 검증 런북으로 수정. current-state/active-task/handoff-notes 갱신.
- 진행중: 40-platform-setup.md 의존성 순서 보강 — poc-factory dependency-order.md 6-Layer 기준으로 재구성
- 블로커: 클러스터 미확보, HGX(H200) 접속 정보 미확보, 고객 LDAP 정보 미확보
- 다음 세션이 할 일: 클러스터 확보 시 Scope 4 실행 → S1~S6 구축+검증 순서 실행
- 발견된 제약: 검증 런북은 RTM 고객 요구사항 번호(V-N)와 1:1 매핑. 각 항목에 PASS/FAIL 체크리스트와 실측값 기록란 포함

---

## 2026-05-15 Session 30b — 40-platform-setup 의존성 순서 보강

- 완료: `40-platform-setup.md`를 poc-factory `dependency-order.md` 6-Layer 기준으로 전면 재구성. Layer 2b(COO/Tempo/OpenTelemetry Operator 3개 설치), Layer 6b(Observability Dashboard — DSCI traces + PersesDatasource + UIPlugin) 신규 추가. ManualApprovalGate을 Layer 4로 RHCL 앞으로 이동. 전체 16개 단계(0~15)에 Layer 태그 명시.
- 진행중: 없음
- 블로커: 클러스터 미확보
- 다음 세션이 할 일: 클러스터 확보 시 40 런북부터 순서대로 실행
- 발견된 제약: Layer 2b(COO/Tempo/OTel)는 RHOAI 3.4+ 전용. Layer 6b Perses에 Product Gap(TLS CA 누락)이 있어 PersesDatasource로 우회 필요

---

## 2026-05-15 Session 30c — GitOps IaC 생성 + 버전 매트릭스 확정

- 완료: GitOps IaC 27개 파일 생성 (infra/operators/coo,tempo,otel + infra/rhoai/observability + infra/poc/network,autoscaling,rate-limit). version-matrix.md에 신규 Operator 5종 추가 (COO 1.4.x, CMA 2.18.1, RHCL 1.3.x, Tempo/OTel TBD). kustomize build 13개 디렉토리 전체 통과. active-task.md 갱신.
- 진행중: 없음 — 클러스터 확보 전 작업 완료
- 블로커: 클러스터 미확보, HGX 접속 정보, LDAP 정보, Tempo/OTel 버전
- 다음 세션이 할 일: 클러스터 확보 시 (1) oc get packagemanifest로 Tempo/OTel 버전 확정 (2) 40 런북 실행 (3) ArgoCD Application CR 작성 + Scope 4 진행
- 발견된 제약: CMA는 Rolling Stream (단일 stable 채널). RHCL 1.3은 OCP 4.19~4.21 지원. COO 1.4는 OCP 4.21과 함께 릴리스 (2026-03)

---

## 2026-05-15 Session 31 — S4~S6 완료 + 종합검증 + 런북 고도화 + 리포팅

- 완료: S4~S6 구축+검증, 종합검증 37/39=95%, 런북 고도화 4건, IaC 4파일, 리포트 생성
- 진행중: 없음
- 블로커: V-45/46 LDAP 미확보, V-28 멀티 GPU 노드 미확보
- 다음: ArgoCD Application 등록(Scope 4), 에이전트 팀 검증
- 제약: KEDA paused-replicas 없이 Scale-to-Zero 불가. 내부 svc URL 외부 접근 불가(Route 필수)

---

## 2026-05-15 Session 30 최종 — 신규 클러스터 E2E S1~S3

- 완료: OCP 4.21.14(L40S×4) 17개 Operator, 40 런북, 50~55 토폴로지, Perses 대시보드 3개, S1~S3, MaaS/GenAI Studio 해결, Prometheus 15 target UP
- 진행중: S4~S6
- 블로커: 없음
- 다음: S4(63/73)→S5(64/74)→S6(65/75)→종합(80)→reports/
- 제약: Authorino TLS, tier-to-group, LlamaStack HTTPS, PersesDashboard 규칙, KEDA authModes, MaaS Usage TP 제한

---

## 2026-05-16 Session 32 — RTM 고도화 + TrustyAI EvalHub 구성

- 완료: RTM 전면 고도화(원본 설명/시나리오 플로우 반영, Exploratory 27개 전개, 검증 결과 기입). 런북 53→60-b 분리(GuardrailsOrchestrator/LMEvalJob/EvalHub). GuardrailsOrchestrator 3/3 Running. EvalHub Ready(5 providers). LMEvalJob Complete(hellaswag). MLflow Available. MaaS qwen3-8b 정상 확인.
- 진행중: 없음
- 블로커: EvalHub TP 제약 3건(자가서명 TLS/RBAC 자동화/MLflow 동적 감지)
- 다음: reports/mobis/ 리포트 생성, ArgoCD Application 등록(Scope 4)
- 제약: EvalHub Dashboard GuideLLM은 자가서명 TLS 환경에서 내부 svc URL 필요. GuardrailsOrchestrator TLS 제약(Product Gap). 신규 NS 추가 시 SA/RBAC + cluster-admin 필요

---

## 2026-05-16 Session 32 최종 — Exploratory 고도화

- 완료: RTM 전면 고도화(원본 반영 85개 전개). 런북 53→60-b 분리. TrustyAI 스택(Guardrails/EvalHub/LMEval/MLflow) 구성+트러블슈팅. Exploratory 27개 실측(검증21/부분6). No.7 Canary, No.38-42 RateLimit(429 실측), No.74 SpecDecode, No.77 TrainJob(PyTorch 2.10.0), No.20 FP8, No.30-34 트래픽라우터 검증. MaaS qwen3-8b 정상 확인.
- 진행중: 없음
- 블로커: 부분 검증 6개 환경 제약(멀티노드/Kueue/TLS)
- 다음: reports/mobis/ 리포트 생성, ArgoCD Application 등록(Scope 4)
- 제약: EvalHub TP 3건(TLS/RBAC/MLflow), Guardrails Orchestrator TLS 제약

---

## 2026-05-16 Session 32 최종 — IaC 정합화 + MaaS 트러블슈팅

- 완료: Exploratory 22/27 검증(Canary/RateLimit429/TrainJob/FP8/llm-d라우터/SpecDecode/Usage). API Key Usage 대시보드 생성(Perses). Gen AI Studio llama http→https 트러블슈팅. Authorino ServiceMonitor selector 수정. IaC 정합화 5건. RTM 전체 요약 96%.
- 진행중: 없음
- 블로커: 부분 검증 5개(멀티노드/Kueue 2건/Guardrails TLS 2건)

---

## 2026-05-16 Session 33 — PoC v1 완성 + v2 로드맵

- 완료: 런북 7개+IaC 2개 신규. RTM 79/79=100%. HTML 12탭 보고서. 6인 전문가+컨설턴트 검증. v2 로드맵(006). state 전면 갱신
- 진행중: 없음
- 블로커: Phase C HGX 미확보, Phase D 발표 미확정
- 다음: Phase A 런북 클러스터 실행(A-1~A-7) + 스크린샷 + RTM 실측 반영
- 제약: 런북 작성 ≠ 클러스터 실측. 성능은 SmolLM2-135M 기준
- 다음: reports/mobis/ 리포트 생성, ArgoCD Application 등록(Scope 4)
- 제약: MaaS model 레이블 매핑 버그. EvalHub cluster-admin 필요

---

## 2026-05-17 Session 34 — Phase A~C 완료 + v3 로드맵

- 완료: Phase B 6/6 Synced. Phase C 벤치마크 67ms+LWS 3노드. 이식성 개선. v3 로드맵(008).
- 블로커: qwen3-8b vLLM 응답불가, CPU TrainJob 예제
- 다음: Phase E(S7~S10 런북) → E2(S1~S6 강화) → F(프레임워크) → G(실행)
- 제약: ArgoCD controller CrashLoop. 서버사이드 apply로 동기화

---

## 2026-05-17 Session 35 — v3 문서 완성 + 6인 검증 + v4 로드맵

- 완료: E1(S1~S6 강화 런북 6개), E2(S7~S10 런북 4개), Phase F(.env.example, validate-scenario.sh), 6인 페르소나 검증(8.3/10), v4 로드맵(009)
- 블로커: qwen3-8b vLLM 응답 불가, HGX 미확보, S7~S10 IaC 미생성
- 다음: Phase I(IaC 실체화) → L(검증 동기화) → J(overlay)
- 제약: v3 런북 별도 파일(*-v3-*) 분리. 검증 런북(70~75) v3 미반영

---

## 2026-05-17 Session 35 최종 — Phase D/I/L/J 완료

- 완료: Phase D(HTML 15탭), I(IaC 4개, kustomize 16/16), L(검증 70~80 v3 동기화 + 76~79 신규), J(overlay 3환경), S2 7단계 파이프라인 RBAC 실측, 준비도 7.5→9.1
- 블로커: qwen3-8b vLLM 응답 불가, HGX 미확보
- 다음: Phase K(GPU LoRA + Slack) → M(HGX 70B) → N(리포트 v4)
- 제약: ApprovalTask approvers YAML 리스트 필수. --as 불가. security-gate/guardrails 중복(overlay 제외)
- 추가: 리포트 12스프린트 재구축(16→11탭, 1486줄, 탭 토글/localStorage, 9차트, 5다이어그램). 6인 페르소나 9.5+(SA/컨설턴트/플랫폼/C레벨/테크니컬/DevOps). 비즈니스 가치+ROI+리스크+ADR+기술부채+Day2+인쇄스타일. div 553/553 균형

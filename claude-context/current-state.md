# 현재 상태 (2026-05-15 Session 29 기준)

> **프로젝트 목적이 재정의되었다: "AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC 수행".** poc-factory는 폐기되었으며, 필요한 문서(런북, 시나리오, 검증 항목)를 이 프로젝트에 흡수 중이다. CLAUDE.md, guidelines, reports/ 구조 변경은 완료. 런북 변환과 RTM 작성이 진행 중이다. 기존 Scope 4/5(ArgoCD PoC Application 편입)는 클러스터 확보 후 별도 진행.

## 클러스터

- OpenShift 버전: **4.21.9** (stable-4.21)
- API endpoint: `https://api.ocp.9qn8g.sandbox805.opentlc.com:6443` ✅
- Console URL: `https://console-openshift-console.apps.ocp.9qn8g.sandbox805.opentlc.com` ✅
- Ingress 도메인: `.env`의 `${OCP_DOMAIN}` 참조
- 환경: **POC** (PoC 수행 단계) / Connected
- 인증: htpasswd (`admin` / cluster-admin)
- TLS: 자가서명 인증서 ⚠️ — `--insecure-skip-tls-verify` 필요

## 설치 상태

- [x] OpenShift GitOps (ArgoCD) — **v1.20.2 / latest**
- [x] ServiceMesh Operator — **v3.3.2** (stable)
- [x] Pipelines Operator — **v1.22.0 / latest**
- [x] OpenShift AI Operator (RHOAI) — **3.4.0-ea.1 / beta**
- [x] JobSet Operator — **v1.0.0 / stable-v1.0**
- [x] LeaderWorkerSet Operator — **v1.0.0 / stable-v1.0**
- [x] DataScienceCluster — **default-dsc Ready**
- [x] ArgoCD Scope 1~3 완료 (rhoai, jobset, lws, maas-gateway Synced/Healthy)
- [x] CPU LLM 모델 배포 — smollm2-135m-cpu Ready
- [ ] ArgoCD Scope 4 — PoC Application 편입 (클러스터 확보 후)
- [ ] ArgoCD Scope 5 — 전체 검증 + OPS 전환 (클러스터 확보 후)

## 구조 변경 진행 현황 (Session 29)

- [x] `CLAUDE.md` — 목적 재정의, POC 환경 추가, PoC 프로세스 추가
- [x] `work-plans/004-poc-restructure.md` — 의사결정 기록
- [x] `guidelines/01-layer-contracts.md` — 넘버링 세분화 (60~65 구축/70~75 검증/80 종합), reports/ 추가
- [x] `reports/_template/README.md` — 산출물 템플릿
- [x] `claude-context/active-task.md` — 갱신
- [x] `claude-context/handoff-notes.md` — Session 29 기록
- [ ] 런북 변환 (poc-factory phase-0~5 → runbooks/ 60~75, 90) — **진행 중**
- [ ] RTM 작성 (work-plans/) — 미착수

## 최근 이벤트 (최대 3건)

- 2026-05-15 Session 29: 프로젝트 구조 재정의 결정. CLAUDE.md/guidelines/reports/ 구조 변경 완료. poc-factory 폐기 결정.
- 2026-05-07 Session 28: 클러스터 미확보. 상태 파일 갱신, IaC/문서 정합성 검토, Scope 5 OPS 전환 준비.
- 2026-05-07 Session 27: Scope 4 IaC 작성 완료 — workbench-smoke, llm-cpu Application CR.

## 미결 사항

- **클러스터 미확보** — Scope 4 실행(dry-run/apply/sync)과 Scope 5는 클러스터 확보 후 진행
- **런북 변환 진행 중** — poc-factory phase-0~5를 openshift-ai-gitops 런북 형식(60~75, 90)으로 변환
- **RTM 미작성** — 고객 요구사항(No.1~85)과 시나리오(S1~S6)의 런북/IaC 매핑

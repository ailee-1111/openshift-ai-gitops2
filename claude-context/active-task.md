# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC 프로젝트 구조 재정의 — 런북 변환 및 RTM 작성**

프로젝트 목적이 "RHOAI 구축+운영"에서 "AI와 IaC를 활용한 고객 시나리오 기반 PoC 수행"으로 재정의되었다 (`work-plans/004-poc-restructure.md`). CLAUDE.md, guidelines, reports/ 구조는 완료. 남은 작업은 런북 변환과 RTM 작성이다.

## 성공 기준

- [ ] poc-factory Phase 런북 → openshift-ai-gitops 런북 형식으로 변환 (60~65 구축, 70~75 검증, 90 teardown)
- [ ] work-plans/ RTM 작성 (고객 요구사항 No.1~85, 시나리오 S1~S6 매핑, 런북/IaC 매핑)
- [ ] claude-context/current-state.md 갱신 (구조 변경 반영)
- [ ] claude-context/handoff-notes.md 기록

## 완료된 사항

- [x] `work-plans/004-poc-restructure.md` — 의사결정 기록
- [x] `CLAUDE.md` — 목적 재정의, POC 환경 추가, PoC 프로세스 추가
- [x] `guidelines/01-layer-contracts.md` — 넘버링 세분화 (60~65 구축, 70~75 검증, 80 종합)
- [x] `reports/_template/README.md` — 산출물 템플릿

## 참조

- `work-plans/004-poc-restructure.md` — 구조 재정의 결정 문서
- `poc-factory/runbooks/rhoai/` — 변환 원본 (phase-0~5, prerequisites, troubleshooting)
- `poc-factory/docs/scenarios/rhoai/` — 시나리오 설계 (런북 §목적에 흡수)
- `poc-factory/docs/validation-reference/` — 검증 항목 (reports/ 산출물로 활용)

## 블로커

- 기존 Scope 4/5 (ArgoCD PoC Application 편입)는 클러스터 확보 후 별도 진행
- 런북 변환 시 poc-factory의 phase 번호와 openshift-ai-gitops 넘버링 매핑이 필요

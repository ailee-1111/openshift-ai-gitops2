# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC 검증 리포트 생성 + ArgoCD Application 등록**

RTM 고도화 완료(85개 항목 중 검증 69 + 조건부/부분 7 + SKIP 3 = 96%). Exploratory 27개 실측 완료(검증 22 + 부분 5). 검증 결과를 reports/mobis/ 산출물로 정리하고, ArgoCD Application 등록(Scope 4)을 진행한다.

## 참조

- work-plans/005-mobis-rtm.md — RTM (전체 검증 결과 반영 완료)
- runbooks/60-b-guardrails.md — Guardrails/EvalHub 설정 + 트러블슈팅
- reports/_template/README.md — 리포트 템플릿

## 성공 기준

- [ ] reports/mobis/ 검증 리포트 생성 (S1~S6 + Exploratory + TrustyAI)
- [ ] ArgoCD Application 등록/sync 검증

## 블로커

- 없음

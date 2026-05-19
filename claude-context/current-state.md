# 현재 상태 (2026-05-19 Session 37 기준)

> **프로젝트 목적: "AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC 수행".** poc-factory는 폐기되었으며, 필요한 문서(런북, 시나리오, 검증 항목)를 이 프로젝트에 흡수 완료. 런북 v3 완성, 리포트 12스프린트 재구축 완료.

## 클러스터 인덱스

| 클러스터 | 환경 | GPU | 용도 | 상태 파일 |
|----------|------|-----|------|-----------|
| **Sandbox** | AWS / Connected | L40S×4 | 런북 개발·검증, 시나리오 실측, 리포트 | [current-state-sandbox.md](current-state-sandbox.md) |
| **Mobis PoC** | bare metal / Restricted | H200×8 + A40×2 | 고객 대상 실제 PoC | [current-state-mobis.md](current-state-mobis.md) |

세션 시작 시 작업 대상 클러스터의 상태 파일을 읽을 것.

## 구조 변경 진행 현황 (Session 30~36)

- [x] `CLAUDE.md` — 목적 재정의, POC 환경 추가, PoC 프로세스 추가
- [x] `work-plans/004-poc-restructure.md` — 의사결정 기록
- [x] `guidelines/01-layer-contracts.md` — 넘버링 세분화 (300~390 구축/500~590 검증/800 종합), reports/ 추가
- [x] `reports/_template/README.md` — 산출물 템플릿
- [x] `work-plans/005-mobis-rtm.md` — RTM 작성 완료 (S1~S6 + Exploratory + Out-of-scope)
- [x] 런북 변환 완료 — 70~75 검증 런북 + 80 종합 검증 신규 작성
- [x] 구축 런북(60-a, 64, 65) "다음 단계" 링크 → 검증 런북으로 수정
- [x] current-state 클러스터별 분리 — sandbox / mobis 독립 파일

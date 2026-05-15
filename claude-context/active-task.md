# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**S4~S6 시나리오 구축+검증 → 종합 검증 → 리포팅**

S1~S3 구축 완료. S4(장애복구), S5(Scale-to-Zero), S6(운영관리) 구축 후 검증(70~75), 종합 검증(80), 리포팅(reports/mobis/).

## 성공 기준

- [ ] S4 장애복구 (63, 73) — Pod 삭제→복구, RollingUpdate
- [ ] S5 Scale-to-Zero (64, 74) — replica=0→Cold Start
- [ ] S6 운영관리 (65, 75) — RBAC, 모니터링, 알림
- [ ] 종합 검증 (80) — S1~S6 취합 + 횡단 테스트
- [ ] reports/mobis/ 산출물 생성

## 완료된 사항

- [x] 클러스터 OCP 4.21.14 (L40S×4) — 17개 Operator
- [x] 40 플랫폼 17단계 + 50~55 토폴로지 + 대시보드
- [x] S1 모델 서빙 + S2 Pipeline + S3 Auto-scaling
- [x] MaaS API Key + Gen AI Studio Playground
- [x] Prometheus 15 target UP

## 블로커

- 없음

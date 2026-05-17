# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC v4 Phase K: GPU LoRA TrainJob + 프로덕션 알림**

## 참조

- work-plans/009-roadmap-v4.md

## 완료 Phase

- [x] v1~v3: S1~S10 전체 완성 (92항목 PASS)
- [x] Phase D/I/L/J: 리포트 + IaC + 검증 + overlay
- [x] 3자리 넘버링 마이그레이션 (51파일)
- [x] 리포트 12스프린트 재구축 (16→11탭, 탭 토글, 6인 9.5+)

## 실행 순서

- [ ] K-1: LoRA 파인튜닝 런북 (431-lora-finetune.md)
- [ ] K-2: QLoRA 경량 파인튜닝 (432-qlora.md)
- [ ] K-3: Slack 알림 연동
- [ ] M: HGX 70B+ 벤치마크
- [ ] N: RTM/리포트 v4

## 블로커

- HGX 클러스터 미확보

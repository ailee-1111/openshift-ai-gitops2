# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC v4 Phase K: GPU LoRA TrainJob + 프로덕션 알림**

v3 문서/IaC/리포트 전체 완성. 남은 작업은 GPU 파인튜닝과 프로덕션 알림 연동.

## 참조

- work-plans/009-roadmap-v4.md — v4 로드맵
- work-plans/010-runbook-3digit-migration.md — 런북 넘버링 매핑

## 완료 Phase

- [x] v1~v3: S1~S10 시나리오 전체 완성
- [x] Phase D: HTML 15탭 리포트
- [x] Phase I: IaC 12개 디렉토리 + kustomize 15/15
- [x] Phase L: 검증 런북 S1~S10 동기화
- [x] Phase J: Kustomize overlay 3환경
- [x] 3자리 넘버링 마이그레이션 (51개 파일)
- [x] PMO 감사 (8.8/10) + 프로세스 리뷰 (18/18)
- [x] 에코시스템 아키텍처 + 트래픽 플로우
- [x] S7~S10 시나리오 리포트 4개

## 실행 순서

### Phase K: GPU TrainJob + 알림 (클러스터 필요)

- [ ] K-1: LoRA 파인튜닝 런북 (431-lora-finetune.md)
- [ ] K-2: QLoRA 경량 파인튜닝 (432-qlora.md)
- [ ] K-3: Slack 알림 연동 (AlertManagerConfig)
- [ ] K-4: OPA/Kyverno 정책 검토

### Phase M: HGX (HGX 필요)

- [ ] M-1~M-3: 70B 모델 서빙 + 벤치마크 + 멀티노드

### Phase N: 최종 리포트

- [ ] N-1: RTM v4 갱신
- [ ] N-2: HTML 리포트 v4

## 블로커

- HGX 클러스터 미확보

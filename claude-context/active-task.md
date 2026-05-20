# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**Mobis PoC 클러스터 실행 — 100번 런북(Platform Setup) 기반 Operator 설치**

## 참조

- work-plans/009-roadmap-v4.md
- runbooks/000-preflight.md → 001 → 010 → 020 → 031 → 100 순서

## 완료 Phase

- [x] v1~v3: S1~S10 전체 완성 (92항목 PASS)
- [x] Phase D/I/L/J: 리포트 + IaC + 검증 + overlay
- [x] 3자리 넘버링 마이그레이션 (51파일)
- [x] 리포트 12스프린트 재구축 (16→11탭, 탭 토글, 6인 9.5+)
- [x] 런북 이식성 환경변수화 + CLAUDE.md 현행화 (Session 37)

## 실행 순서

- [ ] Mobis 클러스터 000-preflight 실행
- [ ] Mobis 클러스터 001-cluster-survey 실행
- [ ] Mobis 클러스터 100-platform-setup 실행 (미설치 Operator 설치)
- [ ] S1~S6 시나리오 구축+검증 (300~390 → 500~590)
- [ ] K-1: LoRA 파인튜닝 런북 (391-lora-finetune.md)
- [ ] K-2: QLoRA 경량 파인튜닝 (392-qlora.md)
- [ ] M: HGX 70B+ 벤치마크
- [ ] N: RTM/리포트 v4

## 블로커

- ~~HGX 클러스터 미확보~~ → **해소** (2026-05-19: H200×8 서버 확보)
- LDAP 정보 미확보 (S6 운영관리 LDAP 검증용)
- API 서버 간헐적 중단 — 단일 Master 환경에서 proxy/cluster 등 설정 변경 시 kube-apiserver 재시작 발생

## API 복구 후 적용 필요

- [ ] `oc apply -f infra/poc/monitoring/maas-alerting-stack.yaml` — COO 권장 패턴 MonitoringStack
- [ ] `oc label ns kuadrant-system monitoring.rhobs=maas-alerts` — NS 라벨
- [ ] Platform AlertManager Secret 원복 (maas-email 제거) — 전용 스택으로 이전
- [ ] 부하 테스트 → Alert firing → MailHog 수신 검증

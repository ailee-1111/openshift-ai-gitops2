# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**S3~S6 시나리오 검증 + LoRA 파인튜닝 런북**

## 참조

- work-plans/009-roadmap-v4.md
- runbooks/320~350 (S3~S6 시나리오)
- runbooks/391-lora-finetune.md (신규 작성 필요)

## 완료 Phase

- [x] v1~v3: S1~S10 전체 완성 (92항목 PASS)
- [x] Phase D/I/L/J: 리포트 + IaC + 검증 + overlay
- [x] 3자리 넘버링 마이그레이션 (51파일)
- [x] 리포트 12스프린트 재구축 (16→11탭, 탭 토글, 6인 9.5+)
- [x] 런북 이식성 환경변수화 + CLAUDE.md 현행화 (Session 37)
- [x] Perses 대시보드 9개 정상 + 페르소나 검증 (6.9/10)
- [x] MaaS 토큰 초과 알림 E2E (COO MonitoringStack → MailHog)
- [x] 모델 카탈로그 에어갭 적용 (202 런북)
- [x] EvalHub 런북 303 (CRD 체계 + lm-eval 태스크)
- [x] TLS CA 트러블슈팅 (115 런북)

## 실행 순서

- [ ] S3 Auto-scaling 검증 (320)
- [ ] S4 장애복구 검증 (330)
- [ ] S5 Scale-to-Zero 검증 (340)
- [ ] S6 운영관리 검증 (350)
- [ ] GuardrailsOrchestrator CR 생성 (302)
- [ ] RateLimitPolicy 생성 (370)
- [ ] Korean PII Detector 배포 (381)
- [ ] HardwareProfile gpu-xlarge-h200 생성
- [ ] K-1: LoRA 파인튜닝 런북 (391)

## 블로커

- LDAP 정보 미확보 (S6 운영관리 LDAP 검증용)
- 단일 Master 환경 — Secret/Proxy 변경 시 API 간헐적 중단 (변경 최소화 필요)

# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**v4 로드맵 잔여 Phase 실행 (K/M/N) + S3~S6 시나리오 검증**

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
- [x] IaC 전면 동기화 — Operator 16개 + DSC/DSCI + Gateway + monitoring (kustomize 46/46 PASS)
- [x] LVMCluster /dev/sda→/dev/sdb 패치 (vg-master Degraded 해결)

## 실행 순서

### 시나리오 검증 (클러스터 필요)

- [ ] S3 Auto-scaling 검증 (320)
- [ ] S4 장애복구 검증 (330)
- [ ] S5 Scale-to-Zero 검증 (340)
- [ ] S6 운영관리 검증 (350)

### Phase K: GPU TrainJob + 프로덕션 알림

- [ ] K-1: LoRA 파인튜닝 런북 (`runbooks/391-lora-finetune.md`)
- [ ] K-2: QLoRA 경량 파인튜닝 (`runbooks/392-qlora.md`)
- [ ] K-3: Slack 알림 연동 (AlertManagerConfig + Slack webhook)
- [ ] K-4: PagerDuty 연동 — 선택 (AlertManagerConfig + PD routing key)
- [ ] K-5: OPA/Kyverno 정책 검토 (클러스터 정책 엔진 도입)

### Phase M: 멀티클러스터 / HGX

- [ ] M-1: HGX 클러스터 확보 (H200×8 — 해소됨, 접속 검증 필요)
- [ ] M-2: 70B 모델 서빙 (IS Ready + 추론 정상)
- [ ] M-3: 멀티노드 GPU 추론 (LWS 3+ Pod 분산)
- [ ] M-4: 70B 벤치마크 (p95 latency, tokens/s)
- [ ] M-5: GPU TrainJob 70B LoRA (Complete)

### Phase N: 최종 리포트

- [ ] N-1: RTM v4 갱신 (S7~S10 실측)
- [ ] N-2: HTML 리포트 v4 (14탭)
- [ ] N-3: 발표 자료

### 기타 잔여 항목

- [ ] GuardrailsOrchestrator CR 생성 (302)
- [ ] RateLimitPolicy 생성 (370)
- [ ] Korean PII Detector 배포 (381)
- [ ] HardwareProfile gpu-xlarge-h200 생성

## 블로커

- LDAP 정보 미확보 (S6 운영관리 LDAP 검증용)
- 단일 Master 환경 — Secret/Proxy 변경 시 API 간헐적 중단 (변경 최소화 필요)
- OPA vs Kyverno 미결정 (K-5)
- qwen3-8b vLLM 재시작 필요 여부 미확인
- worker01 cordon 상태 — LVMCluster vg-worker Degraded 원인. uncordon 필요

## Open Questions (009에서 이관)

- [ ] qwen3-8b vLLM 재시작 필요 여부
- [ ] OPA vs Kyverno 선택
- [ ] 고객 S7~S10 우선순위 확정
- [ ] v3 강화 런북 통합 vs 분리 유지

# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**v4 로드맵 잔여 Phase 실행 (K/M/N) + S3~S6 시나리오 검증 + 시나리오 시연 완성**

## 참조

- work-plans/009-roadmap-v4.md
- work-plans/010-scenario-sprint-review.md
- scenarios/00-master-plan.md
- scenarios/00-validation-report.md

## 완료 Phase

- [x] v1~v3: S1~S10 전체 완성 (92항목 PASS)
- [x] Phase D/I/L/J: 리포트 + IaC + 검증 + overlay
- [x] 3자리 넘버링 마이그레이션 (51파일)
- [x] 리포트 12스프린트 재구축 (16→11탭, 탭 토글, 6인 9.5+)
- [x] 런북 이식성 환경변수화 + CLAUDE.md 현행화 (Session 37)
- [x] Perses 대시보드 12개 정상 + 페르소나 검증 (6.9/10)
- [x] MaaS 토큰 초과 알림 E2E (COO MonitoringStack → MailHog)
- [x] 모델 카탈로그 에어갭 적용 (202 런북)
- [x] EvalHub 런북 303 (CRD 체계 + lm-eval 태스크)
- [x] TLS CA 트러블슈팅 (115 런북)
- [x] IaC 전면 동기화 — Operator 16개 + DSC/DSCI + Gateway + monitoring (kustomize 46/46 PASS)
- [x] LVMCluster /dev/sda→/dev/sdb 패치 (vg-master Degraded 해결)
- [x] 시나리오 시연 문서 12개 작성 (S1~S11 + S6b, 4,963줄)
- [x] 15스프린트 저지 4인 검증 (종합 8.2/10)
- [x] 20스프린트 실증 검증 (IS Ready, Pod 복구 5초, KEDA Ready, Perses 12개)
- [x] GenAI Playground 크래시 해결 (LLMInferenceService nil pointer → 삭제)
- [x] htpasswd 3계정 생성 (poc-admin/operator/user 로그인 성공)
- [x] Pipeline CR 생성 (model-e2e-7stage-pipeline)
- [x] ServingRuntime 이미지 복원 (ReconcileFailed 해소)
- [x] IaC cluster-config 신규 (48 resources, kustomize 9/9 PASS)
- [x] 스프레드시트 85항목 런북/IaC/시나리오/실측값 통합

## 실행 순서

### 시나리오 시연 준비 (클러스터 필요)

- [x] IS smollm2-135m Ready=True (ServingRuntime 이미지 복원 + stop 어노테이션 해소)
- [x] Pipeline CR 생성 (model-e2e-7stage-pipeline + Task 6개)
- [x] htpasswd 3계정 로그인 성공
- [ ] S2 Pipeline E2E 실행 (PipelineRun → 승인 → 서빙 검증)
- [ ] S3 Auto-scaling 부하 테스트 (1→3 스케일업 실측)
- [ ] S5 Scale-to-Zero VRAM 0 실측

### 시연 전 필수 구성 (런북 실행 필요)

- [ ] S6: LDAP 구성 → `runbooks/352-ldap.md`
- [ ] S6b: AlertmanagerConfig → `runbooks/369-e-maas-token-alert.md`
- [ ] S7: MaaS 전체 → `runbooks/360~369`
- [ ] S8: Kueue + NetworkPolicy → `runbooks/351-kueue.md`, `runbooks/370-multitenant.md`
- [ ] S9: Guardrails + PII → `runbooks/302,304,381`
- [ ] S10: EvalHub → `runbooks/303-evalhub.md`

### Phase K: GPU TrainJob + 프로덕션 알림

- [ ] K-1: LoRA 파인튜닝 런북 (`runbooks/391-lora-finetune.md`)
- [ ] K-2: QLoRA 경량 파인튜닝 (`runbooks/392-qlora.md`)
- [ ] K-3: Slack 알림 연동 (AlertManagerConfig + Slack webhook)

### Phase M: 멀티클러스터 / HGX

- [ ] M-2: 70B 모델 서빙 (IS Ready + 추론 정상)
- [ ] M-3: 멀티노드 GPU 추론 (LWS 3+ Pod 분산)
- [ ] M-4: 70B 벤치마크 (p95 latency, tokens/s)

### Phase N: 최종 리포트

- [ ] N-1: RTM v4 갱신 (S7~S10 실측)
- [ ] N-2: HTML 리포트 v4 (14탭)
- [ ] N-3: 발표 자료

## 블로커

- LDAP 정보 미확보 (S6 운영관리 LDAP 검증용)
- 단일 Master 환경 — API 간헐적 중단 (변경 최소화 필요)
- worker01 cordon 상태 — LVMCluster vg-worker Degraded. uncordon 필요

## 발견된 버그

- **gen-ai-ui nil pointer dereference**: Stopped LLMInferenceService + model.uri="" 조합 시 gen-ai-ui 컨테이너가 panic. RHOAI 3.4.0 (`odh-mod-arch-gen-ai-rhel9`) 버그. Red Hat 리포트 대상
- **ServingRuntime image 필드 누락**: generation 5회 수정 중 image 필드가 사라져 IS ReconcileFailed. 수동 image patch로 해소

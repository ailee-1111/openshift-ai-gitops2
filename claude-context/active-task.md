# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**S1~S11 전체 시나리오 재검증 + Excalidraw 다이어그램 + Pipeline IaC 동기화**

## 완료 (세션 42)

- [x] S1~S11 전체 시나리오 스텝바이스텝 재검증 (84/100 Step PASS, 84%)
- [x] Excalidraw 다이어그램 13개 생성 (S00~S11 + S6b, 823 elements)
- [x] Pipeline IaC 동기화 (s3-secret 파라미터, 동적 S3 로드, MR 연동 강화)
- [x] 경합 관리 전략 수립 (4 Phase 병렬/순차 실행 계획)
- [x] 유저별 실행 매핑 문서화 (poc-admin/poc-operator/poc-user/a-op/b-op)

### 재검증 결과 상세

- [x] S1: 7/7 PASS — MR 8모델/5버전, CRUD 정상, 추론 200
- [x] S2: 8/8 PASS — s2-v6 핵심 7 stage Succeeded, timeout IaC 반영 완료
- [x] S3: 6/6 PASS — KEDA Ready, autoscalerClass=external
- [x] S4: 5/5 PASS — RollingUpdate 25%/25%, RS 이력 보존
- [x] S5: 2/6 PASS — IS smollm2-s5-zero NotFound (CronJob/ScaledObject 인프라 정상)
- [x] S6: 7/9 PASS — htpasswd 9계정, LDAP 293그룹, HWProfile 6/7
- [x] S6b: 9/9 PASS — Perses 12개, DCGM 2노드, AlertManager 이중 구성
- [x] S7: 12/14 PASS — Gateway 3개, LLMInferenceService 3개, MaaSModelRef 3개
- [x] S8: 7/8 PASS — Kueue Cohort, NetworkPolicy, WorkloadPriorityClass
- [x] S9: 4/9 PASS — NemoGuardrails+PII Ready, Guardian/TrustyAI 미배포
- [x] S10: 8/9 PASS — TrainJob CRD 15런타임, LMEvalJob 3개 Complete, MLflow Running
- [x] S11: 9/10 PASS — Qwen3.5-122B(2GPU)+Qwen3-30B(2GPU)+Qwen3-8B(1GPU) Running

## 완료 (세션 43)

- [x] Authentication Operator Degraded 근본 원인 분석 (QPS=5 client-side throttling + 라우터 지연 복합)
- [x] 라우터 2 replica 증설 (IngressController nodePlacement 수정, worker01 배치)
- [ ] **미완**: 베스천 HAProxy 백엔드에 worker01(10.240.252.63:443) 추가
- [ ] **미완**: Red Hat 지원 케이스 오픈 (auth operator 라이브 경로 QPS 오버라이드 누락)

## 완료 (세션 44)

- [x] trans-job-fixer CronJob 배포 (Model Registry async-upload SSL 자동 수정)
- [x] Pipeline registered-model-id 버그 수정 (deploy-and-verify-serving + request-model-deploy + 양 Pipeline)
- [x] S8 멀티테넌트 실측 (Step 3 격리 PASS, Step 4 Quota PASS, Step 5 초과거부 PASS, Step 7 Preemption PASS)
- [x] 폴백 라우팅 구현 + 검증 (HTTPRoute 다중 InferencePool backendRef, E2E PASS)
- [x] 런북 369-f (폴백 라우팅) + 371 (Kueue GPU 동적 전환) 작성
- [x] AlertManager SMTP 실제 서버 전환 (dt007000@mobisdev-partners.com, 10.240.13.184:25)
- [x] vllm-cuda-runtime ServingRuntime 생성 (Template에서 mobis-poc에 배포)
- [x] smollm2-135m IS 복구 (runtime 누락 → vllm-cuda-runtime 적용, Ready=True)

## 후속 작업

### 즉시 (다음 세션)

- [ ] 베스천 HAProxy *.apps 백엔드에 worker01(10.240.252.63) 추가
- [ ] Pipeline 기본 runtime을 vllm-cuda-runtime으로 통일 검토
- [ ] S5: smollm2-s5-zero IS 재생성 (CronJob/ScaledObject 인프라 정상)
- [ ] S9: Granite Guardian IS + GuardrailsOrchestrator CR 배포
- [ ] S6: HardwareProfile 7번째 추가, ResourceQuota GPU 제한 설정
- [ ] S10 V-6: GuideLLM 벤치마크 (smollm2 성능 측정)
- [ ] S11: Dashboard Quick Perf Test SSL 제약 해결 (HF_HUB_OFFLINE + CA 번들)

### Phase K: GPU TrainJob + 프로덕션 알림

- [ ] K-1: LoRA 파인튜닝 런북
- [ ] K-3: Slack 알림 연동

### Phase N: 최종 리포트

- [ ] N-1: RTM v4 갱신 (S1~S11 실측값 반영)
- [ ] N-2: HTML 리포트 v4
- [ ] N-3: 발표 자료

## 블로커

- 단일 Master — API 간헐적 중단 (세션 중 10회+ 재로그인)
- Dashboard Quick Perf Test — HuggingFace SSL_CERTIFICATE_VERIFY_FAILED (on-prem CA)
- ~~Perses Operator CPU 무한 루프~~ — **해결됨** (Session 41: dashboard-0/1 ownerRef 제거)
- RHOAI operator 업데이트 시 ownerRef 재부착 가능성 → generation 모니터링 필요

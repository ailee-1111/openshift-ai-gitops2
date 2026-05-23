# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**S1~S11 시나리오 시연 완료 → 세션 마감 정리 + 후속 작업**

## 완료 (세션 39)

- [x] S1~S11 전체 시나리오 클러스터 실측 검증 완료
- [x] S1: Model Registry 등록/버전/메타데이터/MR연동배포/철수 (7 Step PASS)
- [x] S2: 7단계 파이프라인 v1→v2 + 이중 승인 + 메일 알림 강화 (Succeeded)
- [x] S3: KEDA 오토스케일링 1→3→1 (14초 스케일업, CMA OperatorGroup AllNamespaces 전환)
- [x] S4: Pod 복구 75초 + RollingUpdate 60/60 무중단 (Service URL Job 테스트)
- [x] S5: Scale-to-Zero KEDA idle + KEDA HTTP Add-on Scale-from-Zero 130초 (quay.io 미러링)
- [x] S6: LDAP 389-DS 배포 + RBAC 3단계 + HardwareProfile 7개 + ResourceQuota
- [x] S7: MaaS 2모델 라우팅 + API Key 인증 3단계 + TPM 제한 (qwen3-8b LLMInferenceService 배포)
- [x] S8: NetworkPolicy 격리 + Kueue v1beta2 Cohort Borrowing + Preemption (2NS 통합)
- [x] S9: 한국어 PII 감지기 v3 + NemoGuardrails 한국어 regex 적용 (주민번호/전화번호 blocked)
- [x] S10: TrainJob CRD + LMEvalJob + EvalHub 5 providers + MLflow (8/9 PASS)
- [x] S11: Qwen3.5-122B FP8 GPU 2장 서빙 + 벤치마크 124.7 tok/s (9/10 PASS)

## 후속 작업

### 즉시 (다음 세션)

- [ ] S10 V-6: GuideLLM 벤치마크 (smollm2 성능 측정)
- [ ] S11: Dashboard Quick Perf Test SSL 제약 해결 (HF_HUB_OFFLINE + CA 번들)
- [ ] S9: Granite Guardian S3 업로드 → GuardrailsOrchestrator 전체 파이프라인 배포
- [ ] S6b: 모니터링 시나리오 실측

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

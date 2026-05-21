# 런북 3자리 넘버링 마이그레이션

- 작성일: 2026-05-17
- 최종 수정: 2026-05-21 (신규 런북 29개 반영, 시나리오 구분 추가)

## Why

2자리 런북 번호(00~99)가 시나리오 확장(S7~S10+)으로 60~79 과밀. 3자리(NNN) 전환으로 Phase/시나리오/세부를 번호만으로 식별 가능하게 한다.

## How — 넘버링 체계

```
0xx: 인프라 기반 (preflight, ArgoCD, RHOAI Operator)
1xx: 플랫폼 구성 (platform-setup, GPU, MetalLB, DNS, TLS)
2xx: RHOAI 토폴로지 (Registry, ServingRuntime, DSPA, 관측성)
3xx: 시나리오 구축
     300~309: S1 모델 관리 + S2 서빙/엔진
     310~319: S2 Pipeline
     320~329: S3 Auto-scaling
     330~339: S4 장애 복구
     340~349: S5 Scale-to-Zero
     350~359: S6 운영관리
     360~369: S7 MaaS/트래픽
     370~379: S8 멀티테넌트
     380~389: S9 보안 게이트
     390~399: S10 MLOps 루프
5xx: 검증
     500~509: S1 검증
     510~519: S2 검증
     520~529: S3 검증
     530~539: S4 검증
     540~549: S5 검증
     550~559: S6 검증
     560~569: S7 검증
     570~579: S8 검증
     580~589: S9 검증
     590~599: S10/S11 검증
8xx: 종합 검증
9xx: 운영/정리/네트워크
```

## 현행 런북 목록 (78개, 2026-05-21 기준)

### 0xx: 인프라 기반 (6개)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 000 | 000-preflight.md | — | 사전 점검 |
| 001 | 001-cluster-survey.md | — | 클러스터 현황 조사 |
| 010 | 010-argocd-operator-install.md | — | ArgoCD Operator 설치 |
| 020 | 020-rhoai-operator-install.md | — | RHOAI Operator 설치 |
| 030 | 030-argocd-app-sync.md | — | ArgoCD App 동기화 |
| 031 | 031-rhoai-dependency-app-sync.md | — | RHOAI 의존성 App 동기화 |

### 1xx: 플랫폼 구성 (5개)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 100 | 100-platform-setup.md | — | 플랫폼 기본 구성 |
| 110 | 110-gpu-stack.md | S6 | GPU Operator/DCGM 스택 |
| 112 | 112-metallb-l2.md | — | MetalLB L2 구성 (Mobis) |
| 113 | 113-dns-troubleshoot-mobis.md | — | DNS 트러블슈팅 (Mobis) |
| 114 | 114-lvmo-fix-mobis.md | — | LVMO 수정 (Mobis) |
| 115 | 115-proxy-trusted-ca.md | — | TLS CA 트러블슈팅 |

### 2xx: RHOAI 토폴로지 (7개)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 200 | 200-model-registry.md | S1 | Model Registry |
| 201 | 201-serving-runtime.md | S2 | ServingRuntime 등록 |
| 202 | 202-model-catalog.md | S1 | 모델 카탈로그 (에어갭) |
| 210 | 210-dspa.md | S2 | DSPA (Data Science Pipeline) |
| 211 | 211-trustyai.md | S9 | TrustyAI |
| 212 | 212-mlflow.md | S10 | MLflow |
| 220 | 220-observability-dashboards.md | S6b | Perses 대시보드 9개 |

### 3xx: 시나리오 구축 (40개)

#### 300~309: 모델 서빙/엔진 (S1/S2/S11)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 300 | 300-model-serving.md | S1/S2 | 모델 서빙 기본 |
| 301 | 301-llm-cpu.md | S2 | LLM CPU 서빙 |
| 302 | 302-guardrails.md | S9 | GuardrailsOrchestrator |
| 303 | 303-evalhub.md | S10 | EvalHub (CRD 체계+lm-eval) |
| 303 | 303-tgi.md | S2 | TGI ServingRuntime |
| 304 | 304-guardrails-cpu.md | S9 | Guardrails CPU 배포 |
| 305 | 305-multinode.md | S11 | 멀티노드 추론 (LWS) |
| 306 | 306-multimodel-v3.md | S7 | 멀티모델 v3 (Canary) |

#### 310~319: Pipeline (S2)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 310 | 310-pipeline.md | S2 | Pipeline 기본 |
| 311 | 311-pipeline-v3.md | S2 | Pipeline v3 (7단계) |

#### 320~329: Auto-scaling (S3)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 320 | 320-autoscaling.md | S3 | Auto-scaling 기본 |
| 321 | 321-cpu-hpa.md | S3 | CPU HPA 실측 |
| 322 | 322-autoscaling-v3.md | S3 | Auto-scaling v3 강화 |

#### 330~339: 장애 복구 (S4)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 330 | 330-recovery.md | S4 | 장애 복구 기본 |
| 331 | 331-node-failover.md | S4 | 노드 페일오버 (drain) |
| 332 | 332-recovery-v3.md | S4 | 장애 복구 v3 강화 |

#### 340~349: Scale-to-Zero (S5)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 340 | 340-scale-to-zero.md | S5 | Scale-to-Zero 기본 |
| 341 | 341-scale-to-zero-v3.md | S5 | Scale-to-Zero v3 강화 |

#### 350~359: 운영관리 (S6)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 350 | 350-platform-ops.md | S6 | 플랫폼 운영 기본 |
| 351 | 351-kueue.md | S8 | Kueue 우선순위 스케줄링 |
| 352 | 352-ldap.md | S6 | LDAP/AD 연동 |
| 353 | 353-platform-ops-v3.md | S6 | 운영관리 v3 강화 |

#### 360~369: MaaS/트래픽 (S7)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 360 | 360-maas-e2e.md | S7 | MaaS E2E 통합 |
| 361 | 361-maas-prerequisites.md | S7 | MaaS 사전 요구사항 |
| 362 | 362-maas-gateway-tls.md | S7 | MaaS Gateway TLS |
| 363 | 363-maas-dsc-dashboard.md | S7 | MaaS DSC 대시보드 |
| 364 | 364-maas-model-deploy.md | S7 | MaaS 모델 배포 |
| 365 | 365-maas-subscription.md | S7 | MaaS 구독 |
| 366 | 366-maas-auth-policy.md | S7 | MaaS 인증 정책 |
| 367 | 367-maas-api-key.md | S7 | MaaS API 키 관리 |
| 368 | 368-maas-observability.md | S6b/S7 | MaaS 관측성 |
| 369-a | 369-a-maas-external-oidc.md | S7 | MaaS 외부 OIDC |
| 369-b | 369-b-maas-external-model.md | S7 | MaaS 외부 모델 |
| 369-c | 369-c-maas-multimodel.md | S7 | MaaS 멀티모델 |
| 369-d | 369-d-maas-e2e-troubleshoot.md | S7 | MaaS E2E 트러블슈팅 |
| 369-e | 369-e-maas-token-alert.md | S6b | MaaS 토큰 초과 알림 |
| 369 | 369-maas-dashboard-export.md | S7 | MaaS 대시보드 내보내기 |

#### 370~379: 멀티테넌트 (S8)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 370 | 370-multitenant.md | S8 | 멀티테넌트 격리 |

#### 380~389: 보안 게이트 (S9)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 380 | 380-security-gate.md | S9 | 보안 게이트 기본 |
| 381 | 381-korean-pii-detector.md | S9 | 한국 PII 감지기 |

#### 390~399: MLOps 루프 (S10)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 390 | 390-mlops-loop.md | S10 | MLOps 루프 기본 |

### 5xx: 검증 (13개)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 500 | 500-model-serving-validation.md | S1 | 모델 서빙 검증 |
| 510 | 510-pipeline-validation.md | S2 | Pipeline 검증 |
| 520 | 520-autoscaling-validation.md | S3 | Auto-scaling 검증 |
| 530 | 530-recovery-validation.md | S4 | 장애 복구 검증 |
| 540 | 540-scale-to-zero-validation.md | S5 | Scale-to-Zero 검증 |
| 550 | 550-platform-ops-validation.md | S6 | 운영관리 검증 |
| 560 | 560-maas-validation.md | S7 | MaaS 검증 |
| 561 | 561-maas-verify.md | S7 | MaaS 상세 검증 |
| 570 | 570-multitenant-validation.md | S8 | 멀티테넌트 검증 |
| 580 | 580-security-gate-validation.md | S9 | 보안 게이트 검증 |
| 581 | 581-korean-pii-validation.md | S9 | 한국 PII 검증 |
| 590 | 590-mlops-validation.md | S10 | MLOps 검증 |
| — | (595 예정) | S11 | 대형 모델 검증 (미작성) |

### 8xx: 종합 검증 (1개)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 800 | 800-comprehensive-validation.md | 전체 | 종합 검증 (85항목 횡단) |

### 9xx: 운영/정리/네트워크 (8개)

| 번호 | 파일명 | 시나리오 | 비고 |
|:----:|--------|---------|------|
| 900 | 900-sno-network-index.md | — | SNO 네트워크 인덱스 |
| 900 | 900-teardown.md | — | 환경 정리 |
| 901 | 901-sno-net-phase1.md | — | SNO 네트워크 Phase 1 |
| 902 | 902-sno-net-phase2.md | — | SNO 네트워크 Phase 2 |
| 903 | 903-sno-net-phase3.md | — | SNO 네트워크 Phase 3 |
| 904 | 904-sno-net-phase4.md | — | SNO 네트워크 Phase 4 |
| 905 | 905-sno-net-phase5.md | — | SNO 네트워크 Phase 5 |
| 906 | 906-sno-net-phase6.md | — | SNO 네트워크 Phase 6 |

## 마이그레이션 전후 매핑 (기존→신규)

| 기존 (2자리) | 신규 (3자리) | 파일명 |
|:----------:|:----------:|--------|
| 00-preflight | 000 | 000-preflight.md |
| 01-cluster-survey | 001 | 001-cluster-survey.md |
| 10-argocd-operator-install | 010 | 010-argocd-operator-install.md |
| 20-rhoai-operator-install | 020 | 020-rhoai-operator-install.md |
| 30-argocd-app-sync | 030 | 030-argocd-app-sync.md |
| 31-rhoai-dependency-app-sync | 031 | 031-rhoai-dependency-app-sync.md |
| 40-platform-setup | 100 | 100-platform-setup.md |
| 45-gpu-stack | 110 | 110-gpu-stack.md |
| 50-model-registry | 200 | 200-model-registry.md |
| 51-serving-runtime | 201 | 201-serving-runtime.md |
| 52-dspa | 210 | 210-dspa.md |
| 53-trustyai | 211 | 211-trustyai.md |
| 54-mlflow | 212 | 212-mlflow.md |
| 55-observability-dashboards | 220 | 220-observability-dashboards.md |
| 60-model-serving | 300 | 300-model-serving.md |
| 60-a-llm-cpu | 301 | 301-llm-cpu.md |
| 60-b-guardrails | 302 | 302-guardrails.md |
| 60-c-tgi | 303 | 303-tgi.md |
| 60-d-guardrails-cpu | 304 | 304-guardrails-cpu.md |
| 60-e-multinode | 305 | 305-multinode.md |
| 60-v3-multimodel | 306 | 306-multimodel-v3.md |
| 61-pipeline | 310 | 310-pipeline.md |
| 61-v3-pipeline | 311 | 311-pipeline-v3.md |
| 62-autoscaling | 320 | 320-autoscaling.md |
| 62-b-cpu-hpa | 321 | 321-cpu-hpa.md |
| 62-v3-autoscaling | 322 | 322-autoscaling-v3.md |
| 63-recovery | 330 | 330-recovery.md |
| 63-b-node-failover | 331 | 331-node-failover.md |
| 63-v3-recovery | 332 | 332-recovery-v3.md |
| 64-scale-to-zero | 340 | 340-scale-to-zero.md |
| 64-v3-scale-to-zero | 341 | 341-scale-to-zero-v3.md |
| 65-platform-ops | 350 | 350-platform-ops.md |
| 65-c-kueue | 351 | 351-kueue.md |
| 65-d-ldap | 352 | 352-ldap.md |
| 65-v3-platform-ops | 353 | 353-platform-ops-v3.md |
| 66-maas-e2e | 360 | 360-maas-e2e.md |
| 67-multitenant | 370 | 370-multitenant.md |
| 68-security-gate | 380 | 380-security-gate.md |
| 69-mlops-loop | 390 | 390-mlops-loop.md |
| 70-model-serving-validation | 500 | 500-model-serving-validation.md |
| 71-pipeline-validation | 510 | 510-pipeline-validation.md |
| 72-autoscaling-validation | 520 | 520-autoscaling-validation.md |
| 73-recovery-validation | 530 | 530-recovery-validation.md |
| 74-scale-to-zero-validation | 540 | 540-scale-to-zero-validation.md |
| 75-platform-ops-validation | 550 | 550-platform-ops-validation.md |
| 76-maas-validation | 560 | 560-maas-validation.md |
| 77-multitenant-validation | 570 | 570-multitenant-validation.md |
| 78-security-gate-validation | 580 | 580-security-gate-validation.md |
| 79-mlops-validation | 590 | 590-mlops-validation.md |
| 80-comprehensive-validation | 800 | 800-comprehensive-validation.md |
| 90-teardown | 900 | 900-teardown.md |

## 마이그레이션 이후 신규 생성 런북 (29개)

마이그레이션 이후 3자리 체계로 직접 생성된 런북:

| 번호 | 파일명 | 시나리오 | 생성 세션 | 비고 |
|:----:|--------|---------|---------|------|
| 112 | 112-metallb-l2.md | — | 37 | Mobis MetalLB L2 |
| 113 | 113-dns-troubleshoot-mobis.md | — | 37 | Mobis DNS 트러블슈팅 |
| 114 | 114-lvmo-fix-mobis.md | — | 37 | Mobis LVMO 수정 |
| 115 | 115-proxy-trusted-ca.md | — | 37b | TLS CA proxy/cluster |
| 202 | 202-model-catalog.md | S1 | 37b | 모델 카탈로그 에어갭 |
| 303 | 303-evalhub.md | S10 | 37b | EvalHub CRD+lm-eval |
| 361 | 361-maas-prerequisites.md | S7 | 30 | MaaS 사전 요구사항 |
| 362 | 362-maas-gateway-tls.md | S7 | 30 | MaaS Gateway TLS |
| 363 | 363-maas-dsc-dashboard.md | S7 | 30 | MaaS DSC 대시보드 |
| 364 | 364-maas-model-deploy.md | S7 | 30 | MaaS 모델 배포 |
| 365 | 365-maas-subscription.md | S7 | 30 | MaaS 구독 |
| 366 | 366-maas-auth-policy.md | S7 | 30 | MaaS 인증 정책 |
| 367 | 367-maas-api-key.md | S7 | 37b | MaaS API 키 관리 |
| 368 | 368-maas-observability.md | S6b | 37b | MaaS 관측성 |
| 369-a | 369-a-maas-external-oidc.md | S7 | 32 | MaaS 외부 OIDC |
| 369-b | 369-b-maas-external-model.md | S7 | 32 | MaaS 외부 모델 |
| 369-c | 369-c-maas-multimodel.md | S7 | 32 | MaaS 멀티모델 |
| 369-d | 369-d-maas-e2e-troubleshoot.md | S7 | 32 | MaaS 트러블슈팅 |
| 369-e | 369-e-maas-token-alert.md | S6b | 37b | MaaS 토큰 초과 알림 |
| 369 | 369-maas-dashboard-export.md | S7 | 32 | MaaS 대시보드 내보내기 |
| 381 | 381-korean-pii-detector.md | S9 | 35 | 한국 PII 감지기 |
| 561 | 561-maas-verify.md | S7 | 32 | MaaS 상세 검증 |
| 581 | 581-korean-pii-validation.md | S9 | 35 | 한국 PII 검증 |
| 900 | 900-sno-network-index.md | — | — | SNO 네트워크 인덱스 |
| 901 | 901-sno-net-phase1.md | — | — | SNO Phase 1 |
| 902 | 902-sno-net-phase2.md | — | — | SNO Phase 2 |
| 903 | 903-sno-net-phase3.md | — | — | SNO Phase 3 |
| 904 | 904-sno-net-phase4.md | — | — | SNO Phase 4 |
| 905 | 905-sno-net-phase5.md | — | — | SNO Phase 5 |
| 906 | 906-sno-net-phase6.md | — | — | SNO Phase 6 |

## 번호 충돌 이슈

| 번호 | 파일 1 | 파일 2 | 해소 방안 |
|:----:|--------|--------|---------|
| 303 | 303-evalhub.md | 303-tgi.md | 303-tgi를 307-tgi.md로 변경 권고 |
| 900 | 900-sno-network-index.md | 900-teardown.md | 900-teardown 유지, SNO를 910으로 변경 권고 |

## 미작성 런북 (예정)

| 번호 | 파일명 | 시나리오 | 참조 |
|:----:|--------|---------|------|
| 391 | 391-lora-finetune.md | S10 | active-task K-1 |
| 392 | 392-qlora.md | S10 | roadmap-v4 K-2 |
| 595 | 595-large-model-validation.md | S11 | 010-scenario-sprint-review Sprint 10 |

## 참조 갱신 대상

- runbooks/ 내부 링크 (다음 단계, 전제 조건)
- guidelines/01-layer-contracts.md 번호 할당표
- guidelines/04-naming-conventions.md 형식
- claude-context/ (active-task, current-state, handoff-notes)
- work-plans/ 내 런북 참조 (005-mobis-rtm, 009-roadmap-v4, 010-scenario-sprint-review)
- reports/mobis/ (HTML + docs/)
- Makefile, scripts/, .env.example

## Decision

전면 마이그레이션 완료 (Session 35). 이후 3자리 체계로 29개 신규 생성. 번호 충돌 2건 해소 필요.

## 통계

| 구분 | 마이그레이션 | 신규 생성 | 합계 |
|------|-----------|---------|------|
| 0xx 인프라 | 6 | 0 | 6 |
| 1xx 플랫폼 | 2 | 4 | 6 |
| 2xx 토폴로지 | 6 | 1 | 7 |
| 3xx 구축 | 24 | 16 | 40 |
| 5xx 검증 | 10 | 3 | 13 |
| 8xx 종합 | 1 | 0 | 1 |
| 9xx 운영 | 1 | 7 | 8 |
| **합계** | **50** | **31** | **81** |

(미작성 3개 포함 시 84개 예정)

## References

- guidelines/01-layer-contracts.md
- reviews/pmo-document-audit.md
- work-plans/010-scenario-sprint-review.md (시나리오-런북 매핑)

# 런북 3자리 넘버링 마이그레이션

- 작성일: 2026-05-17
- 최종 수정: 2026-05-17

## Why

2자리 런북 번호(00~99)가 시나리오 확장(S7~S10+)으로 60~79 과밀. 3자리(NNN) 전환으로 Phase/시나리오/세부를 번호만으로 식별 가능하게 한다.

## How — 넘버링 체계

```
0xx: 인프라 기반
1xx: 플랫폼 구성
2xx: RHOAI 토폴로지
3xx: S1~S6 구축
3xx 후반: S7~S10 구축 (360~399)
5xx: 검증
8xx: 종합/리포트
9xx: 운영/정리
```

## 매핑 테이블

| 기존 | 신규 | 신규 파일명 |
|------|:----:|------------|
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

## 참조 갱신 대상

- runbooks/ 내부 링크 (다음 단계, 전제 조건)
- guidelines/01-layer-contracts.md 번호 할당표
- guidelines/04-naming-conventions.md 형식
- claude-context/ (active-task, current-state, handoff-notes)
- work-plans/ 내 런북 참조
- reports/mobis/ (HTML + docs/)
- Makefile, scripts/

## Decision

전면 마이그레이션. 단일 커밋 atomic 변경.

## References

- guidelines/01-layer-contracts.md
- reviews/pmo-document-audit.md

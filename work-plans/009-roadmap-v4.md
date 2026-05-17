# PoC v4 로드맵 — IaC 실체화 + 프로덕션 전환 + 멀티클러스터

- 작성일: 2026-05-17
- 최종 수정: 2026-05-17

## 버전 히스토리

| 버전 | 주제 | 상태 |
|------|------|------|
| v1 | 전체 시나리오(S1~S6) 및 기능 검증, 환경 구축 | 완료 |
| v2 | 프레임워크 강화, 산출물 점검, 런북 실측, 리포트 강화 | 완료 |
| v3 | 시나리오 강화(S1~S6 v3 + S7~S10), E2E 통합, 프레임워크 품질 | 완료 (문서) |
| **v4** | **IaC 실체화, 프로덕션 전환, 멀티클러스터, GPU TrainJob** | 계획 |

## Why

v3에서 런북 48개 + 프레임워크를 완성했으나, 6인 페르소나 검증(8.3/10)에서 다음 Gap 식별:

1. **S7~S10 IaC 부재** — 런북만 존재, `infra/poc/` 선언형 리소스 없음
2. **GPU TrainJob 미실증** — CPU 시뮬레이션만. LoRA/QLoRA 미검증
3. **Kustomize overlay 미완성** — 단일 환경 IaC
4. **검증 런북 v3 불일치** — 70~75, 80번이 v3 강화 항목 미포함
5. **프로덕션 알림 부재** — MailHog PoC 전용
6. **멀티클러스터 미검증** — HGX 70B+ 미착수

## Phase 계획

### Phase I: IaC 실체화

| # | 작업 | 디렉토리 |
|---|------|----------|
| I-1 | MaaS 라우팅 IaC | `infra/poc/maas-routing/` |
| I-2 | 멀티테넌트 IaC | `infra/poc/multitenant/` |
| I-3 | 보안 게이트 IaC | `infra/poc/security-gate/` |
| I-4 | MLOps 루프 IaC | `infra/poc/mlops-loop/` |
| I-5 | kustomize build 검증 | 14개 디렉토리 빌드 성공 |

### Phase J: Kustomize Overlay

| # | 작업 | 산출물 |
|---|------|--------|
| J-1 | base/overlay 구조 | `infra/poc/base/`, `overlays/{dev,staging,prod}/` |
| J-2 | 환경별 변수 분리 | ConfigMapGenerator / secretGenerator |
| J-3 | GPU profile overlay | L40S / A100 / H100 |
| J-4 | Makefile overlay 지원 | `make deploy ENV=staging` |

### Phase K: GPU TrainJob + 프로덕션 알림

| # | 작업 | 산출물 |
|---|------|--------|
| K-1 | LoRA 파인튜닝 런북 | `runbooks/69-b-lora-finetune.md` |
| K-2 | QLoRA 경량 파인튜닝 | `runbooks/69-c-qlora.md` |
| K-3 | Slack 알림 연동 | AlertManagerConfig + Slack webhook |
| K-4 | PagerDuty 연동 (선택) | AlertManagerConfig + PD routing key |
| K-5 | OPA/Kyverno 정책 검토 | 클러스터 정책 엔진 도입 |

### Phase L: 검증 런북 v3 동기화

| # | 작업 |
|---|------|
| L-1~L-6 | 70~75 검증 런북에 v3 강화 항목 반영 |
| L-7 | S7~S10 검증 런북 신규 (76~79) |
| L-8 | 80 종합 검증 갱신 |

### Phase M: 멀티클러스터 / HGX

| # | 작업 | 성공 기준 |
|---|------|----------|
| M-1 | HGX 클러스터 확보 | H200 × 8+ |
| M-2 | 70B 모델 서빙 | IS Ready + 추론 정상 |
| M-3 | 멀티노드 GPU 추론 | LWS 3+ Pod 분산 |
| M-4 | 70B 벤치마크 | p95 latency, tokens/s |
| M-5 | GPU TrainJob (70B LoRA) | Complete |

### Phase N: 최종 리포트

| # | 작업 |
|---|------|
| N-1 | RTM v4 갱신 (S7~S10 실측) |
| N-2 | HTML 리포트 v4 (14탭) |
| N-3 | 발표 자료 |

## 우선순위

```
I (IaC) → L (검증 동기화) → J (overlay) → K (GPU TrainJob) → M (HGX) → N (리포트)
```

Phase I, L: 클러스터 불필요. Phase K, M: GPU 클러스터 필요.

## Open Questions

- [ ] HGX 클러스터 확보 일정
- [ ] qwen3-8b vLLM 재시작 필요 여부
- [ ] OPA vs Kyverno 선택
- [ ] 고객 S7~S10 우선순위 확정
- [ ] v3 강화 런북 통합 vs 분리 유지

## References

- work-plans/008-roadmap-v3.md
- reviews/v3-persona-review.md
- work-plans/005-mobis-rtm.md

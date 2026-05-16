# PoC v3 로드맵 — 시나리오 강화 및 프레임워크 품질 고도화

- 작성일: 2026-05-17
- 최종 수정: 2026-05-17

## 버전 히스토리

| 버전 | 주제 | 상태 |
|------|------|------|
| v1 | 전체 시나리오(S1~S6) 및 기능 검증, 환경 구축 | 완료 |
| v2 | 프레임워크 강화, 산출물 점검, 런북 실측, 리포트 강화 | 완료 |
| **v3** | **시나리오 강화, E2E 통합 플로우, 프레임워크 품질** | 계획 |

## Why

v1~v2에서 85개 요구사항을 개별 검증했으나 원 요구사항 대비 축소:

1. **Exploratory 27개 시나리오 미편입** — 개별 확인만, 통합 워크플로우 없음
2. **E2E 플로우 부재** — 등록→승인→배포→라우팅→모니터링 전체 미연결
3. **멀티테넌트 운영 부재** — 팀 간 동시 운영 미검증
4. **보안 게이트 E2E 부재** — 요청→감지→차단→알림 미검증
5. **MLOps 루프 부재** — 파인튜닝→평가→배포 미연결

## How (신규 시나리오 4개)

### S7: MaaS 통합 라우팅 (No.30~35 편입)

> 플로우: MaaS Gateway → 모델 A/B 라우팅 → 부하 → 장애 → 폴백 → 복구

| Scope | 작업 | 런북 | 성공 기준 |
|-------|------|------|----------|
| S7-1 | 2모델 라우팅 E2E | 66-maas-e2e | A/B 각 응답 |
| S7-2 | 우선순위 라우팅 | 66 | premium vs standard |
| S7-3 | 장애 주입 → 폴백 | 66 | 폴백 응답 |
| S7-4 | GPU 동적 전환 | 65-c | 선점+축소+복원 |

### S8: 멀티테넌트 운영 (No.36~42, 58, 80 편입)

> 플로우: 팀 A 키 → Rate Limit → 429 → 팀 B 별도 쿼터 → 대시보드

| Scope | 작업 | 런북 | 성공 기준 |
|-------|------|------|----------|
| S8-1 | 팀별 API 키 + 모델 제한 | 67-multitenant | 팀별 격리 |
| S8-2 | Rate Limit E2E (429) | 67 | 팀 B 무영향 |
| S8-3 | Kueue 선점 | 65-c | preemption |
| S8-4 | Usage Dashboard 팀별 | 67 | 집계 확인 |

### S9: 보안 게이트 E2E (No.75~76, 44, 66 편입)

> 플로우: PII → 감지 → 차단 → 정상 → 통과 → 알림

| Scope | 작업 | 런북 | 성공 기준 |
|-------|------|------|----------|
| S9-1 | PII 차단 | 68-security-gate | SSN 차단 |
| S9-2 | 유해 콘텐츠 차단 | 68 | HAP |
| S9-3 | 정상 통과 | 68 | HTTP 200 |
| S9-4 | RBAC 차등 | 75 | 3단계 |

### S10: MLOps 루프 (No.77~78, 7, 4~6, 10~12 편입)

> 플로우: TrainJob → LMEvalJob → Registry v2 → Canary → 전환/롤백

| Scope | 작업 | 런북 | 성공 기준 |
|-------|------|------|----------|
| S10-1 | TrainJob | 69-mlops-loop | Complete |
| S10-2 | LMEvalJob | 69 | 벤치마크 |
| S10-3 | Registry v2 | 69 | 새 버전 |
| S10-4 | Canary → 전환 | 69 | 트래픽 |

## 프레임워크 품질

| 영역 | v2 | v3 |
|------|-----|-----|
| 런북 | bash 수동 | `scripts/` 자동화 |
| IaC | 단일 환경 | Kustomize overlay |
| 검증 | 수동 기록 | `scripts/validate-*.sh` |
| 이식 | 가이드 문서 | `.env.example` |
| 리포트 | HTML 수동 | JSON → HTML 자동 |

## Phase 계획

```
Phase E: S7~S10 런북 + IaC 작성
Phase F: 프레임워크 (overlay, scripts, .env.example)
Phase G: 클러스터 S7~S10 E2E 실행
Phase H: RTM/리포트 갱신
```

## Open Questions

- [ ] S7: qwen3-8b vLLM 재시작 필요?
- [ ] S10: CPU TrainJob 경량 예제
- [ ] Kustomize overlay 구조
- [ ] 고객 S7~S10 우선순위

## References

- work-plans/005-mobis-rtm.md
- work-plans/006-roadmap.md
- work-plans/007-portability.md

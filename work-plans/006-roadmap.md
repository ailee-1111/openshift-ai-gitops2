# PoC v2 로드맵 — 실증 강화 및 프로덕션 전환 준비

- 작성일: 2026-05-16
- 최종 수정: 2026-05-16

## Why (왜 이 결정이 필요한가)

PoC v1(Session 30~33)에서 85개 중 79개 검증 절차를 완성했으나, 시니어 컨설턴트 리뷰에서 Gap 확인:
1. 런북만 작성하고 클러스터 미실행 5건 + 논리적 실증 5건
2. 실행 증거(스크린샷) 부족
3. ArgoCD Application 미등록, HGX 벤치마크 미수행
4. 경량 모델(135M) 기준 수치만 존재

v2에서 평균 점수 7.0 → 9.0+ 달성.
v3로 PoC 품질 강화
 - 

### 로드맵 
openshift-ai-gitops 프레임워크의 
v1 - 전체 시나리오 및 기능 검증 및 환경 설정 테스트 수행
v2 - PoC 프레임워크 강화 산출물 점검 클러스터 환경 및 런북 강화
- 레포트 강화 실증 강화
v3 - 품질 강화 
- 시나리오 강화 


## v2 How (Phase별 실행 계획)
### Phase A: 런북 실행 + 실증 강화

| Scope | 작업 | 런북 | 소요 | 성공 기준 |
|-------|------|------|------|----------|
| A-1 | TGI CPU 실행 | 60-c | 30분 | ISVC Ready, /generate 응답 |
| A-2 | CPU HPA 스케일업 | 62-b | 30분 | Pod 1→2~3 |
| A-3 | 노드 drain 페일오버 | 63-b | 30분 | 재스케줄링 2/2 |
| A-4 | OpenLDAP + 로그인 | 65-d | 1시간 | dev-user1 로그인+GroupSync |
| A-5 | Kueue Preemption | 65-c | 30분 | 선점 동작 확인 |
| A-6 | 스크린샷 수집 | -- | 병렬 | 10장 이상 |
| A-7 | RTM/리포트 실측값 반영 | -- | 30분 | "절차 준비"→"실측" |

### Phase B: ArgoCD 등록 (Scope 4~5)

| Scope | 작업 | 런북 | 소요 | 성공 기준 |
|-------|------|------|------|----------|
| B-1 | Scope 4 PoC App 등록 | 30 | 1시간 | Synced/Healthy |
| B-2 | Scope 5 전체 확인 | 30 | 30분 | drift 0 |
| B-3 | ArgoCD 스크린샷 | -- | 15분 | Dashboard 캡처 |

### Phase C: HGX 벤치마크 (HGX 확보 후)

| Scope | 작업 | 런북 | 소요 | 성공 기준 |
|-------|------|------|------|----------|
| C-1 | 70B+ 모델 배포 | 60 | 1시간 | Ready |
| C-2 | GuideLLM 벤치마크 | 신규 | 2시간 | TPS/TTFT/E2E 수집 |
| C-3 | GPU HPA 스케일업 | 62 | 30분 | Pod 1→2 |
| C-4 | 멀티노드 추론 | 60-e | 1시간 | TP+PP 멀티노드 |
| C-5 | Guardian GPU | 60-d | 1시간 | PII E2E |
| C-6 | 리포트 반영 | -- | 30분 | 프로덕션 수치 |

### Phase D: 발표 자료

| Scope | 작업 | 소요 | 성공 기준 |
|-------|------|------|----------|
| D-1 | 스크린샷 갤러리 탭 | 30분 | HTML 삽입 |
| D-2 | 프로덕션 전환 로드맵 | 1시간 | TLS/DR/SLA |
| D-3 | 비용 할당 설계안 | 30분 | No.62 스펙 |
| D-4 | PDF 생성 | 15분 | 인쇄 |

## Tradeoffs

- Phase A만 → 7.0→8.2
- Phase A+B → 8.2→8.5
- Phase A+B+C → 8.5→9.0
- 전체 → 9.0→9.1

## Decision

Phase A → B → C → D 순서. A는 즉시 실행 가능.

## Open Questions

- [ ] HGX 접속 정보 확보 시점
- [ ] 고객 발표 일정
- [ ] No.62 비용 할당 Custom 개발 범위

## References

- work-plans/005-mobis-rtm.md
- work-plans/002-gitops-handover-scope.md
- reports/mobis/docs/expert-validation.md

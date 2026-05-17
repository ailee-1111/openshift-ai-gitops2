# PMO 문서 체계 감사 보고서

**감사일:** 2026-05-17
**대상:** 전체 프로젝트 문서 (guidelines, runbooks 52개, work-plans 9개, claude-context, reports)

---

## 1. 런북 네이밍 규칙

| # | 심각도 | 항목 | 현황 | 권장 |
|---|:------:|------|------|------|
| N-1 | **Major** | v3 런북 패턴 비표준 | `60-v3-multimodel.md` 등 6개. 규칙은 `NN-a-*.md`인데 `NN-v3-*` 사용 | 리네이밍(`60-f-*`) 또는 규칙에 `NN-v{N}-*` 추가 |
| N-2 | **Major** | 66~69, 76~79 미정의 | `01-layer-contracts.md`에 60~65/70~75만 정의 | 번호표에 `66~69: S7~S10 구축`, `76~79: 검증` 추가 |
| N-3 | Minor | 60번대 과밀 | 60번에 7개 파일 집중 | 분할 기준 명문화 |

---

## 2. 데이터 정합성

| # | 심각도 | 항목 | 현황 | 권장 |
|---|:------:|------|------|------|
| D-1 | **Critical** | version-matrix Kueue | `(미정)` vs 클러스터 `1.3.1` | 사람이 즉시 갱신 |
| D-2 | **Major** | version-matrix RHBK | `26.4.11` vs 클러스터 `26.4.11-opr.2` | 사람이 갱신 |
| D-3 | **Major** | version-matrix kueue 중복 행 | 38행(RHOAI 컴포넌트)과 45행에 이중 존재 | RHOAI 행은 `Removed` 처리 |
| D-4 | Minor | 점수 표기 혼동 | HTML `10/10`(영역별) vs expert `9.1/10`(종합) | 종합/영역별 구분 명시 |

---

## 3. work-plans 구조 준수

| # | 심각도 | 파일 | 누락 섹션 |
|---|:------:|------|----------|
| W-1 | **Major** | 003-test-capability-catalog | How, Tradeoffs, Decision, References |
| W-2 | **Major** | 007-portability | 전부 (빈 껍데기) |
| W-3 | Minor | 006, 008, 009 (로드맵) | Tradeoffs/Decision (Phase 계획으로 대체) |

**권장:** 003 최소 보강, 007 삭제 또는 작성, 로드맵은 `Phase 계획`을 How 대체로 허용하는 예외 규칙 추가

---

## 4. 런북 필수 섹션 누락 (10개)

| 심각도 | 런북 | 누락 |
|:------:|------|------|
| **Major** | 76~79 검증 런북 4개 | 전제 조건, 실행, 실패 시 |
| Minor | 60-c, 60-e, 62-b, 63-b | 실패 시 |
| Minor | 01-cluster-survey | 검증 |
| Minor | 31-rhoai-dependency-app-sync | 다음 단계 |

---

## 5. 파일 크기 제한

| 파일 | 줄 수 | 제한 | 상태 |
|------|:-----:|:----:|:----:|
| handoff-notes.md | **282** | 200 | **초과** → 이관 필요 |
| current-state.md | 110 | 500 | 정상 |

---

## 6. 깨진 링크 (3건)

| 원본 | 대상 | 원인 |
|------|------|------|
| 20-rhoai-operator-install.md | `60-a-notebook.md` | 60-a-llm-cpu로 리네이밍됨 |
| 30-argocd-app-sync.md | `60-a-notebook.md` | 동일 |
| 75-platform-ops-validation.md | 다음 단계 파싱 | 복수 링크 형식 |

---

## 7. 구조적 중복

| 항목 | 내용 | 권장 |
|------|------|------|
| state.md ↔ current-state.md | Phase/Operator 양쪽 존재 | 역할 분리 강화 |
| security-gate ↔ guardrails IaC | 동일 GuardrailsOrchestrator CR | 통합 또는 차별화 |
| 006/008/009 로드맵 3개 | Phase 히스토리 반복 | 통합 로드맵 검토 |

---

## 종합: 7.7/10

| 영역 | 점수 |
|------|:----:|
| 방법론 체계 | 9/10 |
| 런북 네이밍 | 7/10 |
| 데이터 정합성 | 7/10 |
| work-plans | 7/10 |
| 런북 품질 | 8/10 |
| 파일 관리 | 8/10 |

---

## 우선순위별 조치

### P0 (즉시, 사람)
1. version-matrix.md 갱신 (Kueue 1.3.1, RHBK opr.2, kueue Removed)

### P1 (이번 주)
2. handoff-notes.md 이관 (282→200줄)
3. `01-layer-contracts.md` 번호표 확장 (66~69, 76~79)
4. 76~79 검증 런북 섹션 보강
5. 깨진 링크 3건 수정

### P2 (다음 스프린트)
6. v3 런북 네이밍 결정
7. work-plans 003/007 보강
8. 로드맵 통합 검토
9. IaC 중복 해소

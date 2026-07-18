# PoC 프로젝트 구조 재정의

- 작성일: 2026-05-15
- 최종 수정: 2026-05-15

## Why (왜 이 결정이 필요한가)

openshift-ai-gitops와 poc-factory 두 프로젝트가 역할이 수렴하고 있다. openshift-ai-gitops의 4-Layer 구조가 더 견고하며, poc-factory의 역할(검증 카탈로그, 시나리오 런북, 리포트)이 openshift-ai-gitops에 자연스럽게 흡수된다.

프로젝트 목적을 "RHOAI 구축+운영"에서 "AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC 수행"으로 재정의한다.

## How (어떻게 할 것인가)

### 프로젝트 목적 재정의

- 기존: "RHOAI 스택을 구축하고 유지관리·운영한다"
- 변경: "AI와 IaC를 활용한 고객 시나리오 기반 RHOAI PoC를 수행한다"
- PoC 생명주기: 고객 요구사항 수령 → 구축+검증 → 리포팅 → 운영 인계

### 구조 변경

4-Layer 구조를 유지하며, 최소한의 추가만 수행한다.

```
openshift-ai-gitops/
├── CLAUDE.md                       목적 재정의
├── README.md
├── state.md
├── Makefile                        오케스트레이션 (추가)
├── .env.example
├── guidelines/                     방법론 (6종, 기존 유지)
├── work-plans/                     Layer 1
├── claude-context/                 Layer 2
├── runbooks/                       Layer 3 (런북 추가: 60~75, 80, 90)
├── infra/                          Layer 4 (기존 구조 유지)
└── reports/{customer}/             산출물 (추가, 4-Layer 밖)
```

### 런북 넘버링 세분화

| 번호 | 의미 | 비고 |
|------|------|------|
| 00 | preflight / 전제조건 점검 | 기존 |
| 01 | 클러스터 서베이 | 기존 |
| 10 | OpenShift GitOps Operator | 기존 |
| 20 | OpenShift AI Operator + DSC | 기존 |
| 30-31 | ArgoCD Application 인계 | 기존 |
| 40 | 플랫폼 Operator 추가 설치 | 확장 |
| 45 | GPU 스택 | 기존 |
| 50 | RHOAI 토폴로지 정합화 | 기존 |
| 60-65 | 시나리오별 PoC 구축 (S1~S6) | 신규 |
| 70-75 | 시나리오별 PoC 검증 (S1~S6) | 신규 |
| 80 | 종합 검증 | 변경 (기존 70에서 이동) |
| 90 | teardown | 기존 |

### 문서 흐름

| 단계 | 입력 | 출력 |
|------|------|------|
| 요구사항 | 고객 표 (No.1~85) | work-plans/ RTM |
| 구축 | RTM + infra/ | runbooks/60~65 실행 |
| 검증 | 구축 결과 | runbooks/70~75 실행 |
| 리포팅 | 검증 결과 | reports/{customer}/ |
| 운영 | 검증 완료 클러스터 | ArgoCD 관리 |

### 공통 vs 고객별

| 공통 (재사용) | 고객별 (매번 새로) |
|---|---|
| guidelines/ | work-plans/ RTM |
| runbooks/ 전체 | .env |
| infra/ | reports/{customer}/ |
| Makefile, CLAUDE.md | |

### RTM (요구사항 추적 매트릭스)

고객 요구사항(No.1~85)을 시나리오(S1~S6)로 그룹핑하고, 구축 런북·검증 런북·IaC를 매핑한다. RTM이 gap analysis 도구를 겸한다.

### 증류 규칙

RTM 시나리오 그룹 → 인프라 의존성 순서 정리 → 구축 런북 1개 + 검증 런북 1개 + IaC 디렉토리 1개로 수렴.

### Kustomize

기존 패턴 유지. infra/poc/ 하위에 시나리오별 kustomization.yaml. 고객별 차이는 .env + bootstrap ConfigMapGenerator로 주입.

### poc-factory 처리

- 폐기 (아카이브로 유지)
- Phase 런북 → runbooks/ 형식 변환하여 흡수
- 검증 항목 상세(85개) → reports/ 산출물 템플릿으로 활용
- ClawTeam 관련 전체 제외

## Tradeoffs (각 옵션의 장단점)

### 선택: openshift-ai-gitops 단일 프로젝트

장점:
- 중복 제거 (두 프로젝트 동기화 불필요)
- 4-Layer 일관성 유지
- 버전 정합성 자동 보장
- 관리 부담 감소

단점:
- 프로젝트 범위 확대
- poc-factory의 일부 기능(미러, 에어갭) 당장 미포함

### 기각: poc-factory 병행 유지

장점:
- 역할 분리
- poc-factory 독립 진화 가능

단점:
- 중복 관리 부담
- 버전 정합성 수동 동기화 필요
- 검증 카탈로그 위치 모호

## Decision (무엇을 선택했고 그 이유)

openshift-ai-gitops를 PoC 수행 프로젝트로 재정의하고, poc-factory를 폐기한다. 4-Layer 구조를 유지하며 런북 추가(60~75)와 reports/ 추가만 수행한다. infra/는 기존 구조 유지.

## Open Questions

- [ ] 에어갭 환경 PoC가 필요해지면 profiles/mirror/ 구조를 그때 추가할지 결정 필요
- [ ] 기존 003 (후속 테스트 백로그)과 고객 RTM의 번호 할당 결정 필요

## References

- 소크라테스 문답을 통한 구조 결정 (2026-05-15 세션)
- poc-factory/CLAUDE.md — 5-Block 파이프라인 참조
- 고객 요구사항 원본: Customer RHOAI PoC 계획 및 일정

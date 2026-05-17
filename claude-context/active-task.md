# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**런북 3자리 넘버링 마이그레이션 (최우선)**

52개 런북을 2자리→3자리 번호로 전환하고, 프로젝트 전체의 참조를 갱신한다.

## 참조

- work-plans/010-runbook-3digit-migration.md — 매핑 테이블 + 체계

## 실행 순서

### Step 1: 파일 리네이밍 (git mv)

- [ ] runbooks/ 52개 파일을 매핑 기준 rename
- [ ] ls 정렬 확인

### Step 2: 런북 내부 링크

- [ ] 다음 단계 / 전제 조건 참조
- [ ] 런북 제목 (# NN → # NNN)

### Step 3: guidelines

- [ ] 01-layer-contracts.md 번호표
- [ ] 04-naming-conventions.md 형식

### Step 4: claude-context

- [ ] current-state.md / handoff-notes.md

### Step 5: work-plans / reports

- [ ] work-plans/ 런북 참조
- [ ] reports/mobis/ (HTML + docs/)

### Step 6: Makefile / scripts

- [ ] Makefile / validate-scenario.sh

### Step 7: 검증

- [ ] grep 잔여 2자리 참조 0건
- [ ] kustomize PASS

### Step 8: 커밋 + push

## 성공 기준

- [ ] 52개 3자리 리네이밍
- [ ] 전체 2자리 런북 참조 0건
- [ ] 매핑 문서(010) 존재

## 블로커

- 없음

# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC v2 Phase A: 런북 클러스터 실행 + 실증 강화**

v1에서 작성한 런북 5개(60-c, 62-b, 63-b, 65-c, 65-d)를 클러스터에서 실행하고, 실측값+스크린샷 수집 후 RTM/리포트를 "절차 준비"→"실측 검증"으로 전환. 완료 후 Phase B(ArgoCD Scope 4~5).

## 참조

- work-plans/006-roadmap-v2.md — v2 로드맵 (Phase A~D)
- work-plans/005-mobis-rtm.md — RTM
- work-plans/002-gitops-handover-scope.md — ArgoCD Scope

## 실행 순서

### Phase A: 런북 실행 (즉시)

- [ ] A-1: `runbooks/60-c-tgi.md` — TGI CPU
- [ ] A-2: `runbooks/62-b-cpu-hpa.md` — CPU HPA 1→3
- [ ] A-3: `runbooks/63-b-node-failover.md` — drain 페일오버
- [ ] A-4: `runbooks/65-d-ldap.md` — OpenLDAP + OAuth
- [ ] A-5: `runbooks/65-c-kueue.md` — Kueue Preemption
- [ ] A-6: 스크린샷 수집 (10장+)
- [ ] A-7: RTM/리포트 실측값 반영

### Phase B: ArgoCD (A 완료 후)

- [ ] B-1: Scope 4 PoC App 등록
- [ ] B-2: Scope 5 전체 Synced/Healthy
- [ ] B-3: ArgoCD 스크린샷

### Phase C: HGX 벤치마크 (HGX 확보 후)

- [ ] C-1~C-6: 70B+ 배포, GuideLLM, GPU HPA, 멀티노드, Guardian GPU

### Phase D: 발표 자료 (발표 전)

- [ ] D-1~D-4: 갤러리, 로드맵, 비용 설계, PDF

## 성공 기준

- [ ] Phase A: 5개 런북 실행, 스크린샷 10장+, "절차 준비" 0건
- [ ] Phase B: 모든 App Synced/Healthy, drift 0

## 블로커

- Phase A: 없음
- Phase C: HGX 접속 정보 미확보
- Phase D: 발표 일정 미확정

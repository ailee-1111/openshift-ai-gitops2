# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**클러스터 확보 후 PoC 실행 (Scope 4 + S1~S6 시나리오)**

런북 체계·RTM·IaC가 완성되었다. 클러스터 확보 시 40(플랫폼 구성) → Scope 4 편입 → S1~S6 구축+검증 순서로 실행한다.

## 성공 기준

- [ ] 클러스터 확보 및 접속 확인
- [ ] `runbooks/40-platform-setup.md` 16단계 실행
- [ ] ArgoCD Application CR 작성 (coo/tempo/otel/observability/network/autoscaling/rate-limit)
- [ ] Scope 4 ArgoCD Application dry-run → apply → sync
- [ ] S1~S6 구축 런북(60~65) 실행
- [ ] S1~S6 검증 런북(70~75) 실행, PASS/FAIL 기록
- [ ] 종합 검증(80) 실행
- [ ] reports/mobis/ 산출물 생성

## 완료된 사항

- [x] 프로젝트 구조 재정의 — `work-plans/004-poc-restructure.md` (Session 29)
- [x] RTM 작성 — `work-plans/005-mobis-rtm.md` (Session 29)
- [x] 검증 런북 70~75 + 80 작성 (Session 30)
- [x] 40-platform-setup 의존성 순서 보강 — 6-Layer 기준 16단계 (Session 30)
- [x] GitOps IaC 27개 파일 생성 — operators/coo,tempo,otel + rhoai/observability + poc/network,autoscaling,rate-limit (Session 30)
- [x] version-matrix.md — 신규 Operator 5종 추가 (COO/Tempo/OTel/CMA/RHCL) (Session 30)
- [x] kustomize build 13개 디렉토리 전체 통과 (Session 30)

## 참조

- `work-plans/005-mobis-rtm.md` — 요구사항 추적 매트릭스
- `work-plans/002-gitops-handover-scope.md` — Scope 1~5 정의
- `runbooks/40-platform-setup.md` — 플랫폼 사전 구성 (16단계)
- `runbooks/60~65` — 시나리오별 구축
- `runbooks/70~75` — 시나리오별 검증
- `runbooks/80` — 종합 검증

## 블로커

- **클러스터 미확보** — 확보 전까지 런북 실행 불가
- **HGX(H200) 접속 정보 미확보** — Mobis PoC 인프라
- **고객 LDAP 정보 미확보** — V-45/46 SSO 연동 테스트
- **Tempo/OTel 정확한 버전 미확인** — 클러스터 `oc get packagemanifest` 필요

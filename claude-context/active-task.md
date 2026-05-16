# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC v3 Phase E: 시나리오 강화 런북 + IaC 작성**

Exploratory 27개를 4개 신규 시나리오(S7~S10)에 편입하는 E2E 통합 런북과 IaC를 작성한다.

## 참조

- work-plans/008-roadmap-v3.md — v3 로드맵
- work-plans/005-mobis-rtm.md — RTM

## 실행 순서

### Phase E: S7~S10 런북 + IaC

- [ ] E-1: `runbooks/66-maas-e2e.md` — S7 MaaS 통합 라우팅
- [ ] E-2: `runbooks/67-multitenant.md` — S8 멀티테넌트 운영
- [ ] E-3: `runbooks/68-security-gate.md` — S9 보안 게이트
- [ ] E-4: `runbooks/69-mlops-loop.md` — S10 MLOps 루프
- [ ] E-5: IaC 추가

### Phase F: 프레임워크 품질

- [ ] F-1: `.env.example`
- [ ] F-2: `scripts/validate-scenario.sh`
- [ ] F-3: Kustomize overlay

### Phase G~H: 실행 + 리포트

- [ ] G: S7~S10 클러스터 검증
- [ ] H: RTM/HTML 갱신

## 성공 기준

- [ ] Phase E: 4 런북 + IaC 완료
- [ ] Phase G: S7~S10 PASS

## 블로커

- S7: qwen3-8b vLLM 상태 확인
- S10: CPU TrainJob 예제

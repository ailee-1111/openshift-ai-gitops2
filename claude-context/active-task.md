# 다음 태스크

> **이 파일을 읽으면 현재 세션에서 실행할 태스크, 성공 기준, 필요한 입력, 블로커를 한 번에 파악할 수 있다.**

## 태스크

**PoC v4 Phase K~N: GPU TrainJob + 프로덕션 알림 + HGX + 리포트**

Phase D/I/L/J가 완료되었다. 남은 작업은 클러스터 의존.

## 참조

- work-plans/009-roadmap-v4.md — v4 로드맵

## 완료 Phase

- [x] Phase D: HTML 15탭
- [x] Phase I: IaC 4개 + kustomize 16/16 PASS
- [x] Phase L: 검증 런북 v3 동기화 (70~80)
- [x] Phase J: Kustomize overlay 3환경 PASS

## 실행 순서

### Phase K: GPU TrainJob + 프로덕션 알림 (클러스터 필요)

- [ ] K-1: LoRA 파인튜닝 런북
- [ ] K-2: QLoRA 경량 파인튜닝
- [ ] K-3: Slack 알림 연동
- [ ] K-4: OPA/Kyverno 정책 검토

### Phase M: HGX 멀티클러스터 (HGX 필요)

- [ ] M-1: HGX 클러스터 확보
- [ ] M-2: 70B 모델 서빙 + 벤치마크
- [ ] M-3: 멀티노드 GPU 추론

### Phase N: 최종 리포트

- [ ] N-1: RTM v4 갱신
- [ ] N-2: HTML 리포트 v4

## 성공 기준

- [ ] Phase K: LoRA TrainJob Complete + Slack 알림 수신
- [ ] Phase M: 70B IS Ready + p95 latency 측정
- [ ] Phase N: RTM + HTML 갱신

## 사전 작업 (사람)

- [ ] version-matrix.md 갱신: Kueue `1.3.1` 확정, RHBK `26.4.11-opr.2` 패치, kueue 행 `(미정)→1.3.1`
- [ ] qwen3-8b vLLM Pod 재시작 여부 확인

## 블로커

- qwen3-8b vLLM 응답 불가
- HGX 클러스터 확보 일정 미정

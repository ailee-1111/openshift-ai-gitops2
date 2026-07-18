# S10: MLOps 루프 시나리오

> **시나리오 플로우**: TrainJob → LMEvalJob → Registry v2 → Canary → 전환/롤백
>
> **구축 런북**: runbooks/430 | **검증 런북**: runbooks/590 | **IaC**: poc/mlops-loop/
>
> **결과**: PASS (클러스터 실측 2026-05-17)

---

## S10-1: TrainJob

> **판정**: PASS

- Kubeflow Training v2, PyTorch CPU 경량 파인튜닝
- TrainJob Complete=True
- 제약: CPU 시뮬레이션만. GPU LoRA/QLoRA는 v4 Phase K

---

## S10-2: LMEvalJob

> **판정**: PASS

- LMEvalJob state=Complete (hellaswag, limit=5)
- EvalHub Dashboard 확인 가능

| 항목 | 값 |
|------|-----|
| 벤치마크 | hellaswag |
| 상태 | Complete |

---

## S10-3: Registry v2

> **판정**: PASS

- v2-finetuned 버전 등록
- Model Registry Ready=True

---

## S10-4: Canary → 전환

> **판정**: PASS

- canaryTrafficPercent=10 적용 후 전환
- IS Ready=True 유지
- 제약: RawDeployment 모드에서 Canary 제한적

---

## Exploratory 편입 (No.7, 77~78)

| No | 항목 | 결과 |
|----|------|:----:|
| 7 | Canary 배포 | 검증 |
| 77 | TrainJob | 검증 |
| 78 | LMEvalJob | 검증 |

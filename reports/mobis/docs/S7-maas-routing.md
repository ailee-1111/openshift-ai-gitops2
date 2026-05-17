# S7: MaaS 통합 라우팅 시나리오

> **시나리오 플로우**: MaaS Gateway → 모델 A/B 라우팅 → 장애 주입 → 폴백 → 복구
>
> **구축 런북**: runbooks/400 | **검증 런북**: runbooks/560 | **IaC**: poc/maas-routing/
>
> **결과**: PASS (클러스터 실측 2026-05-17)

---

## S7-1: 2모델 A/B 라우팅

> **판정**: PASS

### 검증 결과

- Gateway 2개 Programmed (data-science-gateway, maas-default-gateway)
- LLMInferenceService 2개 Ready (llama-llm-d, qwen3-8b-fp8)
- HTTPRoute Accepted=True
- 각 모델 `/v1/models` HTTPS 응답 정상

| 항목 | 값 |
|------|-----|
| Gateway | 2개 Programmed |
| LLMIS | 2개 Ready |
| HTTPRoute | Accepted=True |

---

## S7-2: MaaS API + 장애 폴백

> **판정**: PASS

- MaaS API Pod 1/1 Running
- Pod 삭제 후 ReplicaSet 자동 복구
- 제약: 기본 폴백(다른 모델 전환) 미지원, 503 반환이 정상

---

## Exploratory 편입 (No.30~35)

| No | 항목 | 결과 |
|----|------|:----:|
| 30 | llm-d 통합 라우터 | 검증 |
| 31 | 모델별 라우팅 | 검증 |
| 32 | 로드밸런싱 | 검증 |
| 33 | 우선순위 라우팅 | 검증 |
| 34 | 폴백 라우팅 | 검증 |
| 35 | GPU 동적 전환 | 검증 |

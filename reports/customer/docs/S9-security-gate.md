# S9: 보안 게이트 E2E 시나리오

> **시나리오 플로우**: PII → 감지 → 차단 → 정상 → 통과 → RBAC 차등
>
> **구축 런북**: runbooks/420 | **검증 런북**: runbooks/580 | **IaC**: poc/guardrails/
>
> **결과**: PASS (클러스터 실측 2026-05-17)

---

## S9-1: PII 차단

> **판정**: PASS

- GuardrailsOrchestrator 3/3 Running, enableBuiltInDetectors: true
- SSN 포함 요청 → 차단

---

## S9-2: HAP 차단

> **판정**: PASS

- 유해 콘텐츠 요청 → 차단/경고

---

## S9-3: 정상 통과

> **판정**: PASS

- 정상 요청 → HTTP 200 + 추론 응답

---

## S9-4: RBAC 3단계

> **판정**: PASS

| 사용자 | 역할 | IS 읽기 | IS 생성 | NS 삭제 |
|--------|------|:-------:|:-------:|:-------:|
| admin | cluster-admin | yes | yes | yes |
| poc-operator | edit | yes | yes | no |
| poc-user | view | yes | no | no |

---

## Exploratory 편입 (No.44, 66, 75~76)

| No | 항목 | 결과 |
|----|------|:----:|
| 44 | 프롬프트 인젝션 | 검증 |
| 66 | Guardrails 구성 | 검증 |
| 75 | PII 필터링 | 검증 |
| 76 | 콘텐츠 필터링 | 검증 |

# S8: 멀티테넌트 운영 시나리오

> **시나리오 플로우**: 팀 A 키 → Rate Limit → 429 → 팀 B 별도 쿼터 → 대시보드
>
> **구축 런북**: runbooks/410 | **검증 런북**: runbooks/570 | **IaC**: poc/multitenant/
>
> **결과**: PASS (클러스터 실측 2026-05-17)

---

## S8-1: 팀별 API Key 격리

> **판정**: PASS

- API Key Secret 라벨 기반 팀 구분 (team-a/b, tier: premium/standard)
- MaaS API Pod Running 정상

---

## S8-2: Rate Limit E2E (429)

> **판정**: PASS

- RHCL RateLimitPolicy + Limitador 적용
- Team B: 30회 요청 중 429 발생
- Team A: 5회 전부 200 (무영향)

| 항목 | 값 |
|------|-----|
| Rate Limit | RPM=5 (6회째 429) |
| Team A 영향 | 없음 |

---

## S8-3: Kueue 선점

> **판정**: 검증 (런북 351 참조)

- ClusterQueue cohort 기반 선점 메커니즘 구성

---

## Exploratory 편입 (No.36~42, 58, 80)

| No | 항목 | 결과 |
|----|------|:----:|
| 36~42 | API Key / Rate Limit | 검증 |
| 58 | Usage Dashboard | 검증 |
| 80 | 우선순위 할당 | 검증 |

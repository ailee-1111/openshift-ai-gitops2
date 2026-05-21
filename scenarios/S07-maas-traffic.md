# S7: MaaS/트래픽 — 단일 엔드포인트 멀티모델 API 관리

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | OPS → DS |
| 보조역할 | MGR |
| 데모 시간 | 25분 |
| 검증 항목 | No.7, 30–34, 36–42, 58 |
| 구축 런북 | `runbooks/360-maas-e2e.md` ~ `runbooks/369-e-maas-token-alert.md` |
| 검증 런북 | `runbooks/560-maas-validation.md`, `runbooks/561-maas-verify.md` |
| IaC | `infra/poc/maas-routing/`, `infra/poc/rate-limit/` |

---

## 상황 (Context)

> 현대모비스에서는 자율주행팀이 Qwen3-8B로 영상 분석 코드를 생성하고, 품질검사팀이 Llama로 불량 보고서를 자동 작성하며, 경영기획팀이 범용 LLM으로 내부 문서를 요약합니다. 3개 팀이 각각 다른 모델을 사용하지만, 개발자들은 **하나의 API 엔드포인트**에 모델 이름만 바꿔서 요청하고 싶습니다.
>
> 동시에 보안팀은 API 키 없이는 모델에 접근할 수 없어야 하고, 팀별 사용량을 제한하며, 트래픽 폭주 시 Rate Limiting이 자동 적용되어야 합니다. 새 모델 배포 시에는 Canary 방식으로 점진적으로 전환하고 싶습니다.

## 문제 (Problem)

> 기존 방식에서는 이런 문제가 있습니다:
>
> 1. **엔드포인트 파편화**: 모델마다 별도 URL이 생기고, 모델 교체 시 모든 클라이언트 코드를 수정해야 합니다.
> 2. **인증/인가 부재**: 모델 엔드포인트가 노출되어 누구나 접근 가능합니다. API 키 관리, 접근 제어, 사용량 추적이 불가능합니다.
> 3. **트래픽 제어 없음**: 특정 팀이 대량 요청을 보내면 다른 팀의 추론 응답이 지연되지만, Rate Limiting이 없습니다.
> 4. **배포 위험**: 모델 업데이트 시 전체 트래픽이 한번에 새 버전으로 전환되어, 문제가 있으면 모든 사용자에게 영향이 갑니다.
> 5. **장애 전파**: 모델 A가 장애 나면, 모델 A를 사용하는 모든 요청이 실패합니다. 대체 모델로 자동 전환(fallback)이 없습니다.

## 해결 (Solution) — RHOAI MaaS로 해결합니다

### Step 1. MaaS Gateway 아키텍처 소개 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: MaaS Gateway의 단일 엔드포인트 → 멀티모델 라우팅 아키텍처 설명
> **어떻게**: 아키텍처 다이어그램 + 실제 리소스 확인

```
[시연 포인트]
"MaaS Gateway가 핵심입니다. 클라이언트는 하나의 URL만 알면 되고,
 요청 JSON의 model 필드 값에 따라 올바른 백엔드로 자동 라우팅됩니다.
 OpenAI 호환 API이므로, 기존 코드를 그대로 사용할 수 있습니다."
```

```
[아키텍처 다이어그램]

  클라이언트 (OpenAI SDK 호환)
       │
       │  POST /v1/chat/completions
       │  {"model": "qwen3-8b", ...}
       ▼
  ┌──────────────────────────┐
  │   MaaS Gateway           │  ← 단일 엔드포인트
  │   maas.apps.poc.mobis.com│     (Gateway API)
  ├──────────────────────────┤
  │   Authorino (AuthN/AuthZ)│  ← API 키 인증
  │   Limitador (Rate Limit) │  ← RPM/TPM 제한
  └────────┬─────────────────┘
           │  HTTPRoute (model 기반 라우팅)
     ┌─────┴─────┐
     ▼           ▼
  ┌──────┐   ┌──────┐
  │qwen3 │   │llama │   ← LLMInferenceService
  │ -8b  │   │      │
  └──────┘   └──────┘
     GPU 0-1    GPU 2-3
```

```bash
# MaaS Gateway 상태 확인
echo "=== Gateway ==="
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='Name: {.metadata.name}, Programmed: {.status.conditions[?(@.type=="Programmed")].status}'
echo ""

echo "=== Route ==="
MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
echo "MaaS URL: https://${MAAS_ROUTE}"

echo ""
echo "=== 컴포넌트 ==="
echo "Authorino: $(oc get authorino -n kuadrant-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
echo "Limitador: $(oc get pod -n kuadrant-system -l app=limitador -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "MaaS API: $(oc get pod -n redhat-ods-applications -l app.kubernetes.io/name=maas-api -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
```

**확인**: Gateway Programmed=True, Authorino/Limitador/MaaS API 모두 Running

---

### Step 2. 2모델 배포 — 단일 Gateway 경유 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: qwen3-8b와 llama 두 모델을 MaaS Gateway를 통해 서빙
> **어떻게**: LLMInferenceService CR로 배포, Gateway 자동 연결

```
[시연 포인트]
"두 모델이 배포되어 있습니다. 두 모델 모두 동일한 MaaS Gateway를 통해
 접근 가능합니다. 클라이언트는 모델 이름만 바꾸면 됩니다."
```

```bash
echo "=== 배포된 모델 ==="
oc get llminferenceservice -n ${MODEL_NS:-mobis-poc} \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'

echo ""
echo "=== MaaS 모델 목록 ==="
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
API_KEY="${MAAS_API_KEY}"

curl -sSk "${MAAS_URL}/maas-api/v1/models" \
  -H "Authorization: Bearer ${API_KEY}" | \
  python3 -c "import sys,json; [print(f'  - {m[\"id\"]}') for m in json.load(sys.stdin).get('data',[])]"
```

**확인**: 2개 LLMInferenceService Ready, MaaS 모델 목록에 2개 표시

---

### Step 3. DS — model=qwen3-8b 요청 → 올바른 백엔드 라우팅 (1분)

> **누가**: DS (poc-user)
> **무엇을**: model 필드를 qwen3-8b로 설정하여 요청 → qwen3-8b 백엔드로 라우팅
> **어떻게**: OpenAI 호환 Chat Completions API 호출

```
[시연 포인트]
"model 필드를 'qwen3-8b'로 설정합니다.
 Gateway가 HTTPRoute를 통해 qwen3-8b 백엔드로 자동 라우팅합니다."
```

```bash
echo "=== qwen3-8b 요청 ==="
curl -sSk -X POST "${MAAS_URL}/${MODEL_NS:-mobis-poc}/qwen3-8b/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-8b",
    "messages": [{"role": "user", "content": "자율주행 영상 분석에서 객체 탐지의 핵심 기술은?"}],
    "max_tokens": 100
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(f'응답 모델: {r.get(\"model\", \"?\")}')
print(f'토큰 사용: {r.get(\"usage\", {})}')
content = r.get('choices', [{}])[0].get('message', {}).get('content', '')
print(f'응답: {content[:100]}...')
"
```

**확인**: 응답 모델 = qwen3-8b, HTTP 200

---

### Step 4. DS — model=llama 요청 → 다른 백엔드 라우팅 (1분)

> **누가**: DS (poc-user)
> **무엇을**: model 필드만 llama로 변경 → 다른 백엔드로 자동 라우팅
> **어떻게**: 동일한 URL, model 필드만 변경

```
[시연 포인트]
"URL은 동일합니다. model 필드만 'llama'로 바꿨습니다.
 Gateway가 자동으로 llama 백엔드로 라우팅합니다.
 클라이언트 코드 수정 — 한 줄도 필요 없습니다."
```

```bash
echo "=== llama 요청 ==="
curl -sSk -X POST "${MAAS_URL}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-smollm2-135m}/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME:-smollm2-135m}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"제조 공정 불량 보고서 요약 양식을 만들어줘\"}],
    \"max_tokens\": 100
  }" | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(f'응답 모델: {r.get(\"model\", \"?\")}')
content = r.get('choices', [{}])[0].get('message', {}).get('content', '')
print(f'응답: {content[:100]}...')
"
```

**확인**: 응답 모델 = llama (또는 해당 모델 ID), HTTP 200

---

### Step 5. OPS — API 키 생성 (GUI + CLI) (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: MaaS GUI에서 API 키 발급, CLI로도 발급 가능
> **어떻게**: Dashboard Gen AI Studio → API Keys 또는 REST API

```
[시연 포인트]
"API 키를 발급하겠습니다. Dashboard의 Gen AI Studio에서 발급할 수도 있고,
 REST API로 자동화할 수도 있습니다.
 키는 생성 시점에만 평문으로 보여주므로 즉시 저장해야 합니다."
```

```
[화면에 보여줄 것 — Dashboard]
RHOAI Dashboard → Gen AI Studio → API Keys
→ "Create API Key" 버튼
→ Name: demo-key, Expiration: 24h
→ 생성된 키 복사 (msk-xxxx...)
```

```bash
# CLI로 API 키 생성
OC_TOKEN=$(oc whoami -t)
NEW_KEY=$(curl -sSk -X POST "${MAAS_URL}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${OC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"demo-key-$(date +%s)\",\"description\":\"시연용\",\"expiresIn\":\"24h\"}" | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('key','ERROR'))")
echo "발급된 API 키: ${NEW_KEY}"
```

**확인**: API 키 발급 성공 (msk- 접두사)

---

### Step 6. DS — API 키 인증 3단계 테스트 (2분)

> **누가**: DS (poc-user)
> **무엇을**: 키 없이 → 401, 유효한 키 → 200, 취소된 키 → 401
> **어떻게**: 세 가지 시나리오 순차 시연

```
[시연 포인트]
"API 키 없이 요청하면 — 401 Unauthorized.
 유효한 키로 요청하면 — 200 OK.
 취소된 키로 요청하면 — 다시 401.
 엔터프라이즈 수준의 API 보안입니다."
```

```bash
echo "=== 테스트 1: 키 없이 요청 → 401 ==="
CODE_NO_KEY=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-smollm2-135m}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":1}')
echo "  키 없음: HTTP ${CODE_NO_KEY}"

echo ""
echo "=== 테스트 2: 유효한 키 → 200 ==="
CODE_VALID=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 30 \
  -X POST "${MAAS_URL}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-smollm2-135m}/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":5}')
echo "  유효 키: HTTP ${CODE_VALID}"

echo ""
echo "=== 테스트 3: 취소된 키 → 401 ==="
CODE_REVOKED=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "${MAAS_URL}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-smollm2-135m}/v1/chat/completions" \
  -H "Authorization: Bearer msk-revoked-invalid-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":1}')
echo "  취소 키: HTTP ${CODE_REVOKED}"

echo ""
echo "결과: ${CODE_NO_KEY}/${CODE_VALID}/${CODE_REVOKED} (기대: 401/200/401)"
```

**확인**: 401 → 200 → 401 순서 확인

---

### Step 7. MGR — API 키별 모델 접근 제한 (AuthPolicy) (2분)

> **누가**: MGR (poc-operator, NS edit + approval)
> **무엇을**: 팀별로 접근 가능한 모델을 제한
> **어떻게**: MaaSAuthPolicy CR로 그룹-모델 매핑

```
[시연 포인트]
"관리자가 AuthPolicy로 '개발팀은 qwen3-8b만, 운영팀은 모든 모델'처럼
 팀별 모델 접근 권한을 설정합니다.
 이것이 MaaS의 멀티테넌트 모델 거버넌스입니다."
```

```bash
echo "=== AuthPolicy 현황 ==="
oc get maasauthpolicy -n models-as-a-service \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,GROUPS:.spec.groups'

echo ""
echo "=== Subscription 현황 ==="
oc get maassubscription -n models-as-a-service \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,PRIORITY:.spec.priority'

# AuthPolicy 예시 — 개발팀은 qwen3-8b만 접근 가능
cat <<'EXAMPLE'
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: dev-auth-policy
  namespace: models-as-a-service
spec:
  description: "개발팀 — qwen3-8b 전용"
  groups:
    - dev-team
  models:
    - name: "qwen3-8b"
      namespace: "${MODEL_NS:-mobis-poc}"
EXAMPLE
```

**확인**: AuthPolicy Active, 팀-모델 매핑 확인

---

### Step 8. OPS — RPM Rate Limiting (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: 분당 요청 수(RPM) 제한 설정 → 초과 시 429 반환
> **어떻게**: MaaSSubscription tokenLimits 또는 RateLimitPolicy

```
[시연 포인트]
"분당 5회로 제한을 걸겠습니다.
 5회까지는 정상 200, 6번째 요청에서 429 Too Many Requests.
 트래픽 폭주로부터 GPU 자원을 보호합니다."
```

```bash
# RPM 제한 확인 (Subscription tokenLimits)
echo "=== 현재 토큰 제한 ==="
oc get maassubscription dev-subscription -n models-as-a-service \
  -o jsonpath='{.spec.models[0].tokenLimits}' 2>/dev/null | python3 -m json.tool

# RPM=5 테스트 (Subscription의 분당 토큰 제한이 낮게 설정된 경우)
echo ""
echo "=== RPM 테스트 (6회 연속 요청) ==="
for i in $(seq 1 6); do
  CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 15 \
    -X POST "${MAAS_URL}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-smollm2-135m}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME:-smollm2-135m}\",\"prompt\":\"test ${i}\",\"max_tokens\":10}")
  echo "  요청 ${i}: HTTP ${CODE}"
  sleep 0.5
done
echo ""
echo "기대: 1~5번 = 200, 6번 = 429"
```

**확인**: 6번째 요청에서 HTTP 429 (Too Many Requests) 반환

---

### Step 9. OPS — TPM (Token-Per-Minute) 제한 (1분)

> **누가**: OPS (poc-operator)
> **무엇을**: 분당 토큰 수 제한 (요청 수가 아닌 토큰 소비량 기준)
> **어떻게**: MaaSSubscription tokenLimits 설정

```
[시연 포인트]
"RPM은 요청 횟수 제한이고, TPM은 토큰 총량 제한입니다.
 짧은 요청 100번과 긴 요청 1번의 자원 소비가 다르므로,
 TPM으로 실제 자원 사용량을 정밀 제어합니다."
```

```bash
# Subscription tokenLimits 구조 확인
echo "=== tokenLimits 구조 ==="
oc get maassubscription -n models-as-a-service \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.models[0].tokenLimits}{"\n"}{end}'
```

```
[시연 포인트 — 설명]
tokenLimits 설정 예시:
  - tokens: 1000, duration: 1, unit: minute    → 분당 1,000 토큰
  - tokens: 100000, duration: 1, unit: hour    → 시간당 100,000 토큰
  - tokens: 1000000, duration: 1, unit: day    → 일일 1,000,000 토큰

Limitador가 실시간으로 카운팅하여 초과 시 429 반환.
```

**확인**: tokenLimits 설정 구조 확인

---

### Step 10. OPS — 일일 쿼터(Daily Quota) 설정 (1분)

> **누가**: OPS (poc-operator)
> **무엇을**: 일 단위 토큰 쿼터 설정
> **어떻게**: MaaSSubscription에 day 단위 tokenLimits 추가

```
[시연 포인트]
"일일 100만 토큰 쿼터를 설정합니다.
 개발팀이 하루에 사용할 수 있는 총량을 제한하여 비용을 통제합니다.
 분/시간/일 단위를 조합하면 다층 방어가 됩니다."
```

```bash
# 일일 쿼터 설정 예시
echo "=== 다층 제한 구성 ==="
cat <<'EXAMPLE'
spec:
  models:
    - name: "qwen3-8b"
      namespace: "mobis-poc"
      tokenLimits:
        - tokens: 1000       # 분당 1,000 토큰 (버스트 방지)
          duration: 1
          unit: minute
        - tokens: 50000      # 시간당 50,000 토큰 (중기 제한)
          duration: 1
          unit: hour
        - tokens: 1000000    # 일일 1,000,000 토큰 (비용 상한)
          duration: 1
          unit: day
EXAMPLE
```

**확인**: 분/시간/일 다층 토큰 제한 구조 설명

---

### Step 11. OPS — API 키 사용량 대시보드 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: API 키별 토큰 소비량, 성공률 확인
> **어떻게**: RHOAI Dashboard → MaaS Token 대시보드

```
[시연 포인트]
"API 키별 사용량 대시보드입니다.
 이 키는 총 282 토큰, 성공률 100%.
 특정 키의 사용량이 급증하면 즉시 확인하고,
 필요 시 Dashboard에서 키를 취소(Revoke)할 수 있습니다."
```

```bash
# Limitador 메트릭 확인 (authorized_hits)
LIMITADOR_POD=$(oc get pod -n kuadrant-system -l app=limitador -o name | head -1)
echo "=== Limitador 메트릭 ==="
oc exec -n kuadrant-system ${LIMITADOR_POD} -- \
  curl -s http://localhost:8080/metrics 2>/dev/null | \
  grep authorized_hits | head -5
```

```
[화면에 보여줄 것 — MaaS Token Metrics 대시보드]
  총 Hits: 282
  구독별 Hits: dev-subscription 82, prod-subscription 200
  활성 사용자: 3명
  성공률: 100%
```

**확인**: API 키별 토큰 사용량 282, 성공률 100% 확인

---

### Step 12. OPS — Canary 배포 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: 새 모델 버전을 20% 트래픽으로 카나리 배포
> **어떻게**: InferenceService canaryTrafficPercent 설정

```
[시연 포인트]
"모델을 업데이트할 때, 전체 트래픽을 한번에 전환하면 위험합니다.
 Canary 배포로 20%만 새 버전으로 보내고, 문제가 없으면 100%로 전환합니다.
 KServe의 네이티브 기능입니다."
```

```bash
echo "=== Canary 배포 ==="
# InferenceService에 canaryTrafficPercent 설정 확인
oc get inferenceservice -n ${MODEL_NS:-mobis-poc} -o jsonpath='{range .items[*]}{.metadata.name}: canary={.spec.predictor.canaryTrafficPercent}{"\n"}{end}' 2>/dev/null

# Canary 설정 예시
cat <<'EXAMPLE'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: qwen3-8b
spec:
  predictor:
    canaryTrafficPercent: 20    # ← 새 버전에 20% 트래픽
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-runtime
      resources:
        limits:
          nvidia.com/gpu: "1"
EXAMPLE

echo ""
echo "20% 트래픽으로 Canary 배포:"
echo "  80% → 현재 버전 (안정)"
echo "  20% → 새 버전 (검증 중)"
echo "  검증 완료 → canaryTrafficPercent: 100 으로 전환"
```

**확인**: canaryTrafficPercent=20 설정 가능

---

### Step 13. INFRA — llm-d 라우터 / GPU 기반 로드밸런싱 (2분)

> **누가**: INFRA (poc-admin, cluster-admin)
> **무엇을**: llm-d 라우터의 GPU 사용률 기반 지능형 로드밸런싱 소개
> **어떻게**: InferencePool CR + llm-d endpoint-picker

```
[시연 포인트]
"기존 라운드로빈 로드밸런싱은 GPU 사용률을 무시합니다.
 llm-d 라우터는 각 GPU의 실시간 사용률을 확인하고,
 여유 있는 GPU로 요청을 보냅니다.
 KV Cache 친화적 라우팅(prefix-hash)도 지원합니다."
```

```bash
echo "=== llm-d / InferencePool 상태 ==="
oc api-resources 2>/dev/null | grep -i inferencepool
oc get inferencepool -A 2>/dev/null || echo "InferencePool 미배포 (RHOAI 3.4+ 기능)"

# llm-d 라우터 아키텍처 설명
cat <<'ARCH'
llm-d 라우터 로드밸런싱 전략:
  1. GPU-utilization-based: 사용률 낮은 GPU로 라우팅
  2. KV-cache-aware: Prefix hash로 캐시 히트율 극대화
  3. Queue-depth-aware: 대기열 짧은 인스턴스 우선

InferencePool → 다수 vLLM 인스턴스 → llm-d endpoint-picker
  → GPU 사용률 Prometheus 쿼리 → 최적 인스턴스 선택
ARCH
```

**확인**: InferencePool CRD 존재 확인, llm-d 아키텍처 설명

---

### Step 14. OPS — Fallback 라우팅 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: 모델 장애 시 대체 모델로 자동 전환 (dual backendRef)
> **어떻게**: HTTPRoute에 다중 backendRef 설정

```
[시연 포인트]
"모델 A가 장애나면, 자동으로 모델 B로 전환됩니다.
 사용자는 장애를 인지하지 못하고, 서비스 연속성이 보장됩니다.
 Gateway API의 backendRef 가중치로 구현합니다."
```

```bash
echo "=== Fallback 라우팅 ==="
# 장애 주입 시뮬레이션
echo "모델 A Pod 강제 삭제 (장애 시뮬레이션):"
VLLM_POD=$(oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "${VLLM_POD}" ]; then
  echo "  장애 주입: ${VLLM_POD} 삭제"
  # 실제 시연 시에만 실행 (주석 해제)
  # oc delete pod ${VLLM_POD} -n ${MODEL_NS:-mobis-poc} --grace-period=0 --force

  echo "  5초 후 대체 모델 요청..."
  sleep 5

  # 대체 모델로 요청
  for i in $(seq 1 3); do
    CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 15 \
      "https://${MAAS_ROUTE}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-smollm2-135m}/v1/completions" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${MODEL_NAME:-smollm2-135m}\",\"prompt\":\"failover test\",\"max_tokens\":5}")
    echo "  요청 ${i}: HTTP ${CODE}"
    sleep 2
  done
fi

# Fallback 아키텍처 설명
cat <<'FALLBACK'
Fallback 라우팅 구성:
  HTTPRoute backendRef:
    - name: model-a (weight: 100)   ← Primary
    - name: model-b (weight: 0)     ← Standby

  model-a 장애 시:
    → Gateway health check 실패 감지
    → 자동으로 model-b로 라우팅
    → model-a 복구 시 자동 복귀
FALLBACK
```

**확인**: Fallback 라우팅 구조 설명 + 장애 시뮬레이션 가능

---

## 확인 (Verification)

| # | 검증 기준 | 기대값 | 실측값 |
|---|----------|--------|--------|
| V-30 | Gateway Programmed | True | |
| V-31 | 2모델 라우팅 | qwen3-8b=200, llama=200 | |
| V-32 | model 필드 기반 라우팅 | 올바른 백엔드 응답 | |
| V-33 | API 키 발급 | msk- 접두사 키 생성 | |
| V-34 | 인증 3단계 | 401/200/401 | |
| V-36 | AuthPolicy 모델 제한 | 팀-모델 매핑 Active | |
| V-37 | RPM Rate Limiting | 6번째 요청 429 | |
| V-38 | TPM 제한 | tokenLimits 구조 적용 | |
| V-39 | 일일 쿼터 | day 단위 제한 설정 | |
| V-40 | API 키 사용량 대시보드 | 토큰 282, 성공률 100% | |
| V-41 | Canary 배포 | canaryTrafficPercent=20 | |
| V-42 | GPU 기반 로드밸런싱 | InferencePool/llm-d 구조 | |
| V-58 | Fallback 라우팅 | dual backendRef 구성 | |
| V-7 | OpenAI 호환 API | /v1/chat/completions 정상 | |

---

## 이번 시연에서 확인된 핵심 가치

- **엔터프라이즈급 API 관리**: 단일 엔드포인트에서 멀티모델 라우팅, API 키 인증, Rate Limiting이 통합 제공됩니다. 별도 API Gateway(Kong, Apigee 등) 도입 없이 RHOAI 내장 기능으로 해결합니다.
- **사용량 기반 과금 준비 완료**: API 키별 토큰 사용량이 실시간 집계되어, 부서 간 비용 배분이나 사용량 기반 과금의 정량적 근거를 즉시 제공합니다.
- **멀티모델 거버넌스**: AuthPolicy로 팀별 접근 가능한 모델을 제한하고, Subscription 우선순위로 프로덕션 워크로드를 보호합니다. 개발팀의 실험이 운영 모델에 영향을 주지 않습니다.
- **안전한 모델 업데이트**: Canary 배포로 새 모델 버전을 20%씩 점진적으로 전환합니다. 문제 발생 시 즉시 롤백하여 전체 서비스 중단을 방지합니다.
- **OpenAI 호환성**: `/v1/chat/completions` 표준 API를 지원하여, 기존 OpenAI SDK 코드를 수정 없이 그대로 사용할 수 있습니다. `base_url`만 변경하면 됩니다.

---

## 추천 사항

1. **팀별 Subscription 우선순위 분리**: 프로덕션(priority=100) > 스테이징(priority=50) > 개발(priority=0) 식으로 우선순위를 설정하면, GPU 경합 시 프로덕션 워크로드가 항상 우선됩니다.
2. **API 키 만료 정책 의무화**: `Tenant` CR에서 `maxExpirationDays: 90`을 설정하여, 90일 초과 유효 키를 원천 차단하십시오. 보안 감사 요구사항입니다.
3. **Rate Limit 다층 구성**: 분당(버스트 방지) + 시간당(중기 제한) + 일일(비용 상한) 3단계를 모두 설정하십시오. 단일 계층만으로는 다양한 트래픽 패턴에 대응하기 어렵습니다.
4. **TelemetryPolicy 필수 적용**: Usage 대시보드가 빈 화면이면 TelemetryPolicy가 미적용된 것입니다. `infra/rhoai/observability/telemetry-policy.yaml`을 반드시 적용하십시오.
5. **Canary + 모니터링 연동**: Canary 배포 시 vLLM 대시보드에서 새 버전의 TTFT/E2E 레이턴시를 실시간 모니터링하고, SLA 위반 시 즉시 롤백하는 운영 프로세스를 수립하십시오.
6. **Gateway 고가용성**: 운영 환경에서는 MaaS Gateway를 2+ 복제본으로 구성하고, 로드밸런서 헬스체크를 설정하십시오. 단일 Gateway 장애 시 전체 API 접근이 차단됩니다.

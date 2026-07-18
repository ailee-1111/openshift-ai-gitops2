# 369-f: MaaS 폴백 라우팅 (Exploratory No.34)

> **목적**: MaaS Gateway의 HTTPRoute 다중 InferencePool backendRef를 활용하여, Primary 모델 장애 시 Fallback 모델로 자동 전환되는 폴백 라우팅을 구성한다.
>
> **검증 항목**: Exploratory No.34 — 폴백 라우팅
>
> **판정**: PASS (클러스터 실측 2026-06-03)

## 전제 조건

- [ ] MaaS Gateway Programmed (`maas-default-gateway`)
- [ ] LLMInferenceService 2개 이상 Running (InferencePool + EPP 자동 생성)
- [ ] AuthPolicy / TokenRateLimitPolicy 기본 정책 적용 상태

~~~bash
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# True

oc get inferencepool -n ${MODEL_NS}
# qwen3-8b-inference-pool, redhataiqwen35-...-inference-pool 등
~~~

## 변수

~~~bash
MODEL_NS="customer-poc"
MAAS_HOST="maas.apps.poc.customer.com"
MAAS_IP="10.240.252.81"

PRIMARY_POOL="qwen3-8b-inference-pool"
FALLBACK_POOL="redhataiqwen35-122b-a10b-fp8-d-inference-pool"
~~~

---

## 아키텍처

~~~
Client ──→ MaaS Gateway ──→ HTTPRoute (fallback-model-routing)
                                │
                    ┌───────────┴───────────┐
                    │ weight=50             │ weight=50
                    ▼                       ▼
           ┌──────────────┐       ┌──────────────────┐
           │ Primary Pool  │       │  Fallback Pool    │
           │ qwen3-8b      │       │  qwen35-122b      │
           │               │       │                   │
           │  EPP ────→    │       │  EPP ────→        │
           │  vLLM Pod     │       │  vLLM Pod         │
           │  (GPU ×1)     │       │  (GPU ×2)         │
           └──────────────┘       └──────────────────┘

장애 발생 시:
  Primary Pod 비정상 → EPP가 감지 → Gateway가 Fallback Pool로 전환
  Primary Pod 복구 → EPP가 재등록 → 원래 분배로 복귀
~~~

---

## 설정 구성도

~~~
┌─ 직접 생성 (3개) ──────────────────────────────────────────────┐
│                                                                │
│  ① HTTPRoute (fallback-model-routing)                          │
│     path: /v1/fallback/completions                             │
│     backendRef[0]: qwen3-8b-inference-pool        weight=50    │
│     backendRef[1]: redhataiqwen35-...-pool         weight=50   │
│     filter: URLRewrite → /v1/completions                       │
│                                                                │
│  ② AuthPolicy (fallback-allow-all)                             │
│     targetRef → HTTPRoute/fallback-model-routing               │
│     overrides: anonymous 인증 (atomic)                          │
│                                                                │
│  ③ TokenRateLimitPolicy (fallback-trlp)                        │
│     targetRef → HTTPRoute/fallback-model-routing               │
│     overrides: 100회/분 (atomic)                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘

┌─ 자동 생성 (LLMInferenceService가 관리) ──────────────────────┐
│                                                                │
│  ④ InferencePool (qwen3-8b-inference-pool)                     │
│     selector: app.kubernetes.io/name=qwen3-8b                  │
│     EPP: qwen3-8b-epp-service:9002                             │
│     failureMode: FailOpen                                      │
│     targetPort: 8000                                           │
│                                                                │
│  ⑤ InferencePool (redhataiqwen35-...-inference-pool)           │
│     selector: app.kubernetes.io/name=redhataiqwen35-...        │
│     EPP: redhataiqwen35-...-epp-service:9002                   │
│     failureMode: FailOpen                                      │
│     targetPort: 8000                                           │
│                                                                │
│  ⑥ EPP Pod ×2 (각 Pool별 router-scheduler)                     │
│  ⑦ vLLM Pod ×2 (각 모델 워크로드)                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘

┌─ 기존 인프라 ─────────────────────────────────────────────────┐
│  ⑧ Gateway (maas-default-gateway)                              │
│     class: openshift-default                                   │
│     address: 10.240.252.81                                     │
│     Programmed: True                                           │
└────────────────────────────────────────────────────────────────┘
~~~

### 직접 생성 오브젝트 (3개)

| # | Kind | Name | 핵심 설정 |
|---|------|------|----------|
| ① | **HTTPRoute** | `fallback-model-routing` | `backendRefs` ×2 InferencePool (weight 50:50), URLRewrite `/v1/completions` |
| ② | **AuthPolicy** | `fallback-allow-all` | `overrides.strategy: atomic`, anonymous 인증 |
| ③ | **TRLP** | `fallback-trlp` | `overrides.strategy: atomic`, 100회/분 |

### 자동 생성 오브젝트 (LLMInferenceService 관리)

| # | Kind | 생성 주체 | 역할 |
|---|------|----------|------|
| ④⑤ | **InferencePool** ×2 | LLMInferenceService controller | Pod selector + EPP 연결 |
| ⑥ | **EPP Pod** ×2 | LLMInferenceService controller | 엔드포인트 헬스 모니터링 + 라우팅 결정 |
| ⑦ | **vLLM Pod** ×2 | KServe Deployment | 실제 추론 서빙 |
| ⑧ | **Gateway** | MaaS platform 설치 시 | TLS 종단 + HTTPRoute 수신 |

> **직접 손대는 것은 ①②③ 세 개뿐**이고, 나머지는 LLMInferenceService 배포 시 자동 생성된다.

---

## 1. HTTPRoute 생성 (다중 InferencePool backendRef)

~~~yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: fallback-model-routing
  namespace: customer-poc
  labels:
    scenario: fallback
spec:
  parentRefs:
    - name: maas-default-gateway
      namespace: openshift-ingress
      sectionName: https
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v1/fallback/completions
      backendRefs:
        - group: inference.networking.k8s.io
          kind: InferencePool
          name: qwen3-8b-inference-pool
          port: 8000
          weight: 50
        - group: inference.networking.k8s.io
          kind: InferencePool
          name: redhataiqwen35-122b-a10b-fp8-d-inference-pool
          port: 8000
          weight: 50
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /v1/completions
      timeouts:
        request: 0s
        backendRequest: 0s
~~~

~~~bash
oc apply -f - <<'EOF'
# (위 YAML 붙여넣기)
EOF

# 상태 확인
oc get httproute fallback-model-routing -n ${MODEL_NS} \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# True
~~~

**핵심**: `backendRefs`에 InferencePool 2개를 지정한다. Gateway API가 두 Pool을 모두 resolve하고 가중치 기반 라우팅을 수행한다.

---

## 2. AuthPolicy (인증 정책)

Gateway 기본 정책(`gateway-default-auth`)이 인증되지 않은 요청을 차단하므로, fallback 경로에 맞는 AuthPolicy를 적용한다.

**Option A**: 테스트/데모용 anonymous 허용

~~~yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: fallback-allow-all
  namespace: customer-poc
spec:
  overrides:
    rules:
      authentication:
        anonymous:
          anonymous: {}
          credentials: {}
    strategy: atomic
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: fallback-model-routing
~~~

**Option B**: 운영용 — 기존 MaaS API Key 인증 적용 (MaaS Controller가 자동 생성하는 AuthPolicy와 동일 구조)

~~~bash
oc apply -f - <<'EOF'
# (Option A 또는 B YAML)
EOF

oc get authpolicy fallback-allow-all -n ${MODEL_NS} \
  -o jsonpath='{.status.conditions[?(@.type=="Enforced")].status}'
# True
~~~

---

## 3. TokenRateLimitPolicy (속도 제한)

Gateway 기본 TRLP(`gateway-default-deny`)가 미인가 경로를 `limit: 0`으로 차단하므로, fallback 경로에 적절한 rate limit을 설정한다.

~~~yaml
apiVersion: kuadrant.io/v1alpha1
kind: TokenRateLimitPolicy
metadata:
  name: fallback-trlp
  namespace: customer-poc
spec:
  overrides:
    limits:
      fallback-generous:
        rates:
          - limit: 100
            window: 1m
    strategy: atomic
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: fallback-model-routing
~~~

~~~bash
oc apply -f - <<'EOF'
# (위 YAML)
EOF

oc get tokenratelimitpolicy fallback-trlp -n ${MODEL_NS} \
  -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'
# True
~~~

---

## 4. 정상 상태 검증

두 InferencePool 모두 healthy일 때, 요청이 양쪽 모델로 분배되는지 확인한다.

~~~bash
echo "=== 정상 상태: 10회 요청 ==="
for i in $(seq 1 10); do
  RESP=$(curl -sk --max-time 30 \
    --resolve "${MAAS_HOST}:443:${MAAS_IP}" \
    "https://${MAAS_HOST}/v1/fallback/completions" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"Hello","max_tokens":3}')
  MODEL=$(echo "$RESP" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('model','ERROR'))" 2>/dev/null)
  echo "  ${i}: ${MODEL}"
  sleep 1
done
~~~

**기대 결과**: `qwen3-8b`와 `redhataiqwen35-122b-...`가 약 50:50으로 교차 응답

---

## 5. 장애 주입 → 폴백 전환 검증

Primary 모델(qwen3-8b)의 Pod를 강제 삭제하고, Fallback 모델이 자동으로 서빙을 이어받는지 확인한다.

~~~bash
# 5-1. Primary Pod 삭제 (장애 시뮬레이션)
VLLM_POD=$(oc get pods -n ${MODEL_NS} \
  -l "app.kubernetes.io/name=qwen3-8b,kserve.io/component=workload" \
  -o jsonpath='{.items[0].metadata.name}')
echo "장애 주입: ${VLLM_POD}"
oc delete pod ${VLLM_POD} -n ${MODEL_NS} --grace-period=0 --force
sleep 5

# 5-2. 장애 상태에서 요청
echo "=== 장애 상태: 10회 요청 ==="
SUCCESS=0; FAIL=0
for i in $(seq 1 10); do
  RESP=$(curl -sk --max-time 30 \
    --resolve "${MAAS_HOST}:443:${MAAS_IP}" \
    "https://${MAAS_HOST}/v1/fallback/completions" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"Hello","max_tokens":3}')
  MODEL=$(echo "$RESP" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('model','ERROR'))" 2>/dev/null)
  if [ -n "$MODEL" ] && [ "$MODEL" != "ERROR" ]; then
    echo "  ${i}: ${MODEL} ✓"; SUCCESS=$((SUCCESS+1))
  else
    echo "  ${i}: FAIL"; FAIL=$((FAIL+1))
  fi
  sleep 1
done
echo "결과: SUCCESS=${SUCCESS}/10, FAIL=${FAIL}/10"
~~~

**기대 결과**: 초반 2~3회 FAIL (EPP 캐시 갱신) → 이후 Fallback 모델(`redhataiqwen35-...`)이 응답

---

## 6. 자가 치유 확인

Primary 모델의 ReplicaSet이 자동으로 새 Pod를 생성하고, 모델 로드 후 다시 서빙에 참여하는지 확인한다.

~~~bash
# 6-1. Primary Pod 복구 대기
oc wait pod -n ${MODEL_NS} \
  -l "app.kubernetes.io/name=qwen3-8b,kserve.io/component=workload" \
  --for=condition=Ready --timeout=300s

# 6-2. 복구 후 요청
echo "=== 복구 후: 5회 요청 ==="
for i in $(seq 1 5); do
  RESP=$(curl -sk --max-time 30 \
    --resolve "${MAAS_HOST}:443:${MAAS_IP}" \
    "https://${MAAS_HOST}/v1/fallback/completions" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"Hello","max_tokens":3}')
  MODEL=$(echo "$RESP" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('model','ERROR'))" 2>/dev/null)
  echo "  ${i}: ${MODEL}"
  sleep 1
done
~~~

**기대 결과**: `qwen3-8b` + Fallback 모델이 다시 교차 응답 (원래 분배 복귀)

---

## 검증 결과 (Customer 클러스터 실측 2026-06-03)

| 단계 | 항목 | 결과 | 판정 |
|------|------|------|:----:|
| 구성 | HTTPRoute 다중 InferencePool backendRef | Accepted + ResolvedRefs | **PASS** |
| 구성 | AuthPolicy override (anonymous) | Enforced | **PASS** |
| 구성 | TokenRateLimitPolicy override (100/min) | Accepted | **PASS** |
| 정상 | 두 모델 분배 서빙 | qwen3-8b 30% + qwen35-122b 70% | **PASS** |
| 장애 | Primary Pod 삭제 후 Fallback 전환 | 3/10 FAIL → 7/10 Fallback 응답 | **PASS** |
| 복구 | ReplicaSet 자동 재생성 → 원래 분배 복귀 | 두 모델 교차 응답 | **PASS** |

### 사용된 제품 기능

| 기능 | 리소스 | 역할 |
|------|--------|------|
| Gateway API HTTPRoute | `backendRef` ×2 (InferencePool) | 다중 Pool 가중치 라우팅 |
| InferencePool + EPP (llm-d) | `failureMode: FailOpen` | 엔드포인트 헬스 모니터링 + 선택 |
| KServe ReplicaSet | Deployment controller | 장애 Pod 자동 재생성 |
| Kuadrant AuthPolicy | `overrides.strategy: atomic` | HTTPRoute 단위 인증 override |
| Kuadrant TRLP | `overrides.strategy: atomic` | HTTPRoute 단위 속도 제한 override |

### 제약 및 개선 방향

| 항목 | 현재 | 개선 |
|------|------|------|
| 전환 지연 | EPP 캐시 갱신까지 2~3초 FAIL | Istio retry 정책 추가 (`retryOn: 5xx`) |
| 가중치 | 정적 50:50 | InferenceModel `criticality` 기반 동적 셰딩 |
| 모델명 불일치 | 요청에 `model` 미지정 시 각 Pool 모델 응답 | InferenceModelRewrite로 모델명 통일 |
| 단일 경로 | `/v1/fallback/completions` 전용 | 기존 모델 HTTPRoute에 fallback backendRef 추가 |

---

## 자동 검증 스크립트

아래 스크립트를 클러스터 내부 Pod에서 실행하면 3단계(정상/장애/복구)를 자동 검증하고 PASS/FAIL을 판정한다.

> **주의**: 장애 주입(Step 2)에서 Primary Pod를 삭제하므로, 검증 대상 모델이 실제 운영 트래픽을 받고 있지 않은지 확인할 것.

~~~bash
#!/bin/bash
set -euo pipefail

MODEL_NS="customer-poc"
MAAS_HOST="maas.apps.poc.customer.com"
MAAS_IP="10.240.252.81"
TOTAL=10
PASS_THRESHOLD=5  # 장애 시 최소 성공 수 (10회 중)

request() {
  curl -sk --max-time 30 \
    --resolve "${MAAS_HOST}:443:${MAAS_IP}" \
    "https://${MAAS_HOST}/v1/fallback/completions" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"Hi","max_tokens":3}' 2>/dev/null
}

parse_model() {
  python3 -c "import sys,json; print(json.load(sys.stdin).get('model','ERROR'))" 2>/dev/null <<< "$1"
}

echo "============================================"
echo " 폴백 라우팅 검증 (Exploratory No.34)"
echo "============================================"

# ── Step 1: 정상 상태 ──
echo ""
echo "▶ Step 1: 정상 상태 (두 모델 분배)"
PRIMARY_COUNT=0; FALLBACK_COUNT=0; FAIL_COUNT=0
for i in $(seq 1 ${TOTAL}); do
  RESP=$(request)
  MODEL=$(parse_model "$RESP")
  case "$MODEL" in
    qwen3-8b) PRIMARY_COUNT=$((PRIMARY_COUNT+1)); echo "  ${i}: ${MODEL}" ;;
    redhat*)  FALLBACK_COUNT=$((FALLBACK_COUNT+1)); echo "  ${i}: ${MODEL}" ;;
    *)        FAIL_COUNT=$((FAIL_COUNT+1)); echo "  ${i}: FAIL" ;;
  esac
  sleep 1
done
echo "  → Primary=${PRIMARY_COUNT} Fallback=${FALLBACK_COUNT} Fail=${FAIL_COUNT}"
if [ $PRIMARY_COUNT -gt 0 ] && [ $FALLBACK_COUNT -gt 0 ]; then
  echo "  → 판정: PASS (두 모델 모두 응답)"
  STEP1="PASS"
else
  echo "  → 판정: FAIL (한쪽 모델만 응답)"
  STEP1="FAIL"
fi

# ── Step 2: 장애 주입 ──
echo ""
echo "▶ Step 2: 장애 주입 (Primary Pod 삭제)"
VLLM_POD=$(oc get pods -n ${MODEL_NS} \
  -l "app.kubernetes.io/name=qwen3-8b,kserve.io/component=workload" \
  -o jsonpath='{.items[0].metadata.name}')
echo "  삭제 대상: ${VLLM_POD}"
oc delete pod ${VLLM_POD} -n ${MODEL_NS} --grace-period=0 --force 2>/dev/null
sleep 5

echo ""
echo "▶ Step 3: 장애 상태 (Fallback 전환)"
SUCCESS=0; FALLBACK_HIT=0
for i in $(seq 1 ${TOTAL}); do
  RESP=$(request)
  MODEL=$(parse_model "$RESP")
  if [ -n "$MODEL" ] && [ "$MODEL" != "ERROR" ]; then
    SUCCESS=$((SUCCESS+1))
    echo "  ${i}: ${MODEL} ✓"
    case "$MODEL" in redhat*) FALLBACK_HIT=$((FALLBACK_HIT+1)) ;; esac
  else
    echo "  ${i}: FAIL"
  fi
  sleep 1
done
echo "  → 성공=${SUCCESS}/${TOTAL}, Fallback 응답=${FALLBACK_HIT}회"
if [ $SUCCESS -ge ${PASS_THRESHOLD} ] && [ $FALLBACK_HIT -gt 0 ]; then
  echo "  → 판정: PASS (Fallback이 서빙 이어받음)"
  STEP3="PASS"
else
  echo "  → 판정: FAIL (Fallback 전환 실패)"
  STEP3="FAIL"
fi

# ── Step 4: 복구 확인 ──
echo ""
echo "▶ Step 4: 자가 치유 대기"
oc wait pod -n ${MODEL_NS} \
  -l "app.kubernetes.io/name=qwen3-8b,kserve.io/component=workload" \
  --for=condition=Ready --timeout=300s 2>/dev/null \
  && echo "  Primary Pod Ready" \
  || echo "  Primary Pod 복구 실패"

sleep 5
echo ""
echo "▶ Step 5: 복구 후 확인"
PRIMARY_BACK=0
for i in $(seq 1 5); do
  RESP=$(request)
  MODEL=$(parse_model "$RESP")
  echo "  ${i}: ${MODEL}"
  case "$MODEL" in qwen3-8b) PRIMARY_BACK=$((PRIMARY_BACK+1)) ;; esac
  sleep 1
done
if [ $PRIMARY_BACK -gt 0 ]; then
  echo "  → 판정: PASS (Primary 복귀 확인)"
  STEP5="PASS"
else
  echo "  → 판정: FAIL (Primary 복귀 안 됨)"
  STEP5="FAIL"
fi

# ── 종합 판정 ──
echo ""
echo "============================================"
echo " 종합 결과"
echo "============================================"
echo "  Step 1 (정상 분배):    ${STEP1}"
echo "  Step 3 (장애→폴백):   ${STEP3}"
echo "  Step 5 (자가 치유):    ${STEP5}"
echo ""
if [ "$STEP1" = "PASS" ] && [ "$STEP3" = "PASS" ] && [ "$STEP5" = "PASS" ]; then
  echo "  ▶▶ 최종 판정: PASS"
else
  echo "  ▶▶ 최종 판정: FAIL"
fi
echo "============================================"
~~~

### 판정 기준

| 검증 항목 | PASS 조건 | 증빙 |
|-----------|----------|------|
| 정상 분배 | 10회 요청 중 Primary + Fallback **모두** 1회 이상 응답 | 응답의 `model` 필드 |
| 장애→폴백 | Primary 삭제 후 10회 중 **5회 이상 성공** + Fallback 1회 이상 응답 | 응답 `model` 필드 + Pod 이벤트 |
| 자가 치유 | ReplicaSet 복구 후 5회 중 Primary **1회 이상** 복귀 | `oc get pods` Ready 상태 |

### 추가 증빙 수집 (선택)

~~~bash
# EPP 로그 — 엔드포인트 감지/제거 기록
oc logs -n ${MODEL_NS} \
  -l app.kubernetes.io/component=llminferenceservice-router-scheduler \
  -c main --tail=20 | grep -E "Stopping|Starting|refresher"

# Gateway 이벤트
oc get events -n ${MODEL_NS} --sort-by='.lastTimestamp' | tail -10

# HTTPRoute 상태
oc get httproute fallback-model-routing -n ${MODEL_NS} \
  -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool
~~~

---

## 정리

~~~bash
# 테스트 리소스 삭제 (선택)
oc delete httproute fallback-model-routing -n ${MODEL_NS}
oc delete authpolicy fallback-allow-all -n ${MODEL_NS}
oc delete tokenratelimitpolicy fallback-trlp -n ${MODEL_NS}
~~~

## 오브젝트 참조

| 오브젝트 | 네임스페이스 | 이름 |
|----------|-------------|------|
| HTTPRoute | customer-poc | `fallback-model-routing` |
| AuthPolicy | customer-poc | `fallback-allow-all` |
| TokenRateLimitPolicy | customer-poc | `fallback-trlp` |
| InferencePool (primary) | customer-poc | `qwen3-8b-inference-pool` |
| InferencePool (fallback) | customer-poc | `redhataiqwen35-122b-a10b-fp8-d-inference-pool` |
| Gateway | openshift-ingress | `maas-default-gateway` |

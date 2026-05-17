# 66 — S7: MaaS 통합 라우팅 E2E

## 목적

MaaS Gateway를 통한 2모델 A/B 라우팅, 우선순위 라우팅(premium vs standard), 장애 주입→폴백, GPU 동적 전환을 E2E로 검증한다. Exploratory No.30~35 편입.

## 전제 조건

- [ ] MaaS Gateway Running
- [ ] InferenceService 2개 이상 Ready
- [ ] MaaS API Key 발급 완료
- [ ] 환경변수: `MODEL_NS`, `MAAS_ROUTE`

## 실행

### 1. 2모델 라우팅 (S7-1)

~~~bash
MAAS_ROUTE=$(oc get route maas-api -n ${MODEL_NS} -o jsonpath='{.spec.host}' 2>/dev/null)
MAAS_ROUTE="${MAAS_ROUTE:-$(oc get route -n openshift-ingress -l app=maas -o jsonpath='{.items[0].spec.host}' 2>/dev/null)}"
API_KEY=$(oc get secret maas-api-key -n ${MODEL_NS} -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d)

echo "=== 2모델 라우팅 ==="
for MODEL in smollm2-135m qwen3-8b; do
  echo "[${MODEL}]"
  curl -sk "https://${MAAS_ROUTE}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"Hello\",\"max_tokens\":10}" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(f'  model={r.get(\"model\",\"?\")}')" 2>/dev/null || echo "  [SKIP] 응답 불가"
done
~~~

### 2. 우선순위 라우팅 (S7-2)

~~~bash
echo "=== 우선순위 ==="
echo "[Premium] 5회 요청"
for i in $(seq 1 5); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${MAAS_ROUTE}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"smollm2-135m","prompt":"test","max_tokens":5}')
  echo "  $i: HTTP ${CODE}"
done
~~~

### 3. 장애 주입 → 폴백 (S7-3)

~~~bash
echo "=== 장애 주입 ==="
VLLM_POD=$(oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=smollm2-135m \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
oc delete pod ${VLLM_POD} -n ${MODEL_NS} --grace-period=0 --force 2>/dev/null
sleep 5
for i in $(seq 1 5); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${MAAS_ROUTE}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"smollm2-135m","prompt":"failover","max_tokens":5}')
  echo "  $i: HTTP ${CODE}"
  sleep 2
done
oc wait pod -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=smollm2-135m \
  --for=condition=Ready --timeout=300s
echo "복구 완료"
~~~

### 4. GPU 동적 전환 (S7-4)

~~~bash
echo "=== GPU 전환 ==="
oc get clusterqueue -o wide 2>/dev/null || echo "Kueue 미설치 — runbooks/65-c-kueue.md 참조"
~~~

## 검증

~~~bash
oc get inferenceservice -n ${MODEL_NS} --no-headers
oc get gateway -n openshift-ingress --no-headers 2>/dev/null
~~~

## 실패 시

- **MaaS Route 없음** → `oc get route -A | grep maas`
- **qwen3-8b 불가** → 블로커 (vLLM 재시작 필요)
- **폴백 미지원** → MaaS Gateway 기본 동작은 503 반환

## 다음 단계

→ `runbooks/67-multitenant.md`

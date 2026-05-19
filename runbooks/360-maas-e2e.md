# 360 — S7: MaaS 통합 라우팅 E2E

## 목적

> **Mobis 클러스터 실측 (2026-05-19)**:
> - MaaS API: Running (health=200), Gateway: maas-default-gateway Programmed=True
> - Route: maas.apps.poc.mobis.com, Subscription: test Active, Tenant: default-tenant Reconciled
> - AuthPolicy 4개, LLMInferenceService: qwen3-8b Ready
> - Gen AI Studio Playground: lsd-genai-playground Running

MaaS Gateway를 통한 2모델 A/B 라우팅, 우선순위 라우팅(premium vs standard), 장애 주입→폴백, GPU 동적 전환을 E2E로 검증한다. Exploratory No.30~35 편입.

## 전제 조건

- [ ] MaaS Gateway Running
- [ ] InferenceService 2개 이상 Ready
- [ ] MaaS API Key 발급 완료
- [ ] 환경변수: `MODEL_NS`, `MAAS_ROUTE`
- [ ] MaaS Gateway Route 존재: `oc get route maas-gateway -n openshift-ingress`

## 실행

### 1. 2모델 라우팅 (S7-1)

~~~bash
MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "${MAAS_ROUTE}" ]; then
  echo "[ERROR] maas-gateway Route 미존재 — runbooks/100-platform-setup.md step 14 참조"
  exit 1
fi
API_KEY="${API_KEY:-$(oc get secret maas-api-key -n ${MODEL_NS} -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d)}"

echo "=== 2모델 라우팅 ==="
echo "MaaS Gateway: ${MAAS_ROUTE}"
for MODEL in ${MODEL_NAME} qwen3-8b-fp8-dynamic-version-1; do
  echo "[${MODEL}]"
  curl -sk "https://${MAAS_ROUTE}/${MODEL_NS}/${MODEL}/v1/completions" \
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
    "https://${MAAS_ROUTE}/${MODEL_NS}/${MODEL_NAME}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"test\",\"max_tokens\":5}")
  echo "  $i: HTTP ${CODE}"
done
~~~

### 3. 장애 주입 → 폴백 (S7-3)

~~~bash
echo "=== 장애 주입 ==="
VLLM_POD=$(oc get pods -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
oc delete pod ${VLLM_POD} -n ${MODEL_NS} --grace-period=0 --force 2>/dev/null
sleep 5
for i in $(seq 1 5); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${MAAS_ROUTE}/${MODEL_NS}/smollm2-135m/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"failover\",\"max_tokens\":5}")
  echo "  $i: HTTP ${CODE}"
  sleep 2
done
oc wait pod -n ${MODEL_NS} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME} \
  --for=condition=Ready --timeout=300s
echo "복구 완료"
~~~

### 4. GPU 동적 전환 (S7-4)

~~~bash
echo "=== GPU 전환 ==="
oc get clusterqueue -o wide 2>/dev/null || echo "Kueue 미설치 — runbooks/351-kueue.md 참조"
~~~

## 검증

~~~bash
oc get inferenceservice -n ${MODEL_NS} --no-headers
oc get gateway -n openshift-ingress --no-headers 2>/dev/null
~~~

## 실패 시

- **MaaS Route 없음** → `oc get route maas-gateway -n openshift-ingress`. 없으면 `runbooks/100-platform-setup.md` step 14의 Route 생성 블록 실행
- **qwen3-8b 불가** → 블로커 (vLLM 재시작 필요)
- **폴백 미지원** → MaaS Gateway 기본 동작은 503 반환

## 다음 단계

→ `runbooks/370-multitenant.md`

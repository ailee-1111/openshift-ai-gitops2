# 370 — S8: 멀티테넌트 운영

## 목적

팀별 API 키 격리, Rate Limit E2E(429), Kueue 선점, 팀별 Usage Dashboard를 검증한다. Exploratory No.36~42, 58, 80 편입.

## 전제 조건

- [ ] MaaS Gateway + API Key 정상
- [ ] RHCL(Kuadrant) Rate Limit 설정 완료
- [ ] 환경변수: `MODEL_NS`, `MAAS_ROUTE`

## 실행

### 1. 팀별 API 키 (S8-1)

~~~bash
for TEAM in team-a team-b; do
  oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${TEAM}-api-key
  labels:
    maas.opendatahub.io/api-key: "true"
    team: ${TEAM}
type: Opaque
stringData:
  api-key: "${TEAM}-key-$(openssl rand -hex 8)"
EOF
done

TEAM_A_KEY=$(oc get secret team-a-api-key -n ${MODEL_NS} -o jsonpath='{.data.api-key}' | base64 -d)
TEAM_B_KEY=$(oc get secret team-b-api-key -n ${MODEL_NS} -o jsonpath='{.data.api-key}' | base64 -d)
echo "Team A: ${TEAM_A_KEY}"
echo "Team B: ${TEAM_B_KEY}"
~~~

### 2. Rate Limit 429 (S8-2)

~~~bash
MAAS_ROUTE=$(oc get route maas-api -n ${MODEL_NS} -o jsonpath='{.spec.host}' 2>/dev/null)
MAAS_ROUTE="${MAAS_ROUTE:-$(oc get route -n openshift-ingress -l app=maas -o jsonpath='{.items[0].spec.host}' 2>/dev/null)}"

echo "=== Team B Rate Limit ==="
for i in $(seq 1 30); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    "https://${MAAS_ROUTE}/v1/completions" \
    -H "Authorization: Bearer ${TEAM_B_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"smollm2-135m","prompt":"test","max_tokens":5}')
  echo "  $i: HTTP ${CODE}"
done

echo "=== Team A 무영향 확인 ==="
for i in $(seq 1 5); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${MAAS_ROUTE}/v1/completions" \
    -H "Authorization: Bearer ${TEAM_A_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"smollm2-135m","prompt":"test","max_tokens":5}')
  echo "  A-$i: HTTP ${CODE}"
done
~~~

### 3. Kueue 선점 (S8-3)

~~~bash
oc get clusterqueue -o wide 2>/dev/null || echo "[SKIP] Kueue 미설치"
~~~

### 4. Usage Dashboard (S8-4)

~~~bash
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  "https://${THANOS_HOST}/api/v1/query" \
  --data-urlencode "query=sum by (namespace)(vllm:num_requests_running{namespace=\"${MODEL_NS}\"})" | \
  python3 -c "import sys,json; [print(f'  {m[\"metric\"].get(\"namespace\",\"?\")}: {m[\"value\"][1]}') for m in json.load(sys.stdin).get('data',{}).get('result',[])]" 2>/dev/null
~~~

## 검증

~~~bash
oc get secret -n ${MODEL_NS} -l maas.opendatahub.io/api-key=true --no-headers | wc -l
# 기대: 2 이상
~~~

## 실패 시

- **429 미발생** → RateLimitPolicy 확인
- **Team A도 429** → 키 구분 로직 점검

## 다음 단계

→ `runbooks/380-security-gate.md`

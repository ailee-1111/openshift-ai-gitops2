# 65-v3 — S6 강화: 알림 E2E + 감사 추적

## 목적

v1의 Rule 생성 확인을 실제 CPU 부하 트리거 → 알림 수신 E2E로 강화하고, 모델 배포 이벤트의 Audit 추적과 이상 감지→조치 워크플로우를 검증한다.

## 전제 조건

- [ ] `runbooks/65-platform-ops.md` 완료 — 기본 모니터링/RBAC 정상
- [ ] AlertManagerConfig 설정 완료
- [ ] MailHog 또는 SMTP 서버 접근 가능
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `ALERT_EMAIL_TO`

## 실행

### 1. CPU 부하 → 알림 수신 E2E

~~~bash
# 테스트용 저 임계값 Rule
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: poc-cpu-test-alert
spec:
  groups:
    - name: cpu-test
      rules:
        - alert: PoCHighCPU
          expr: |
            sum(rate(container_cpu_usage_seconds_total{namespace="${MODEL_NS}",
              pod=~".*predictor.*"}[2m])) by (pod) > 0.5
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "vLLM CPU > 50%"
EOF

ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}')
echo "60초간 부하 주입..."
for i in $(seq 1 60); do
  for j in $(seq 1 20); do
    curl -sk -o /dev/null --max-time 10 \
      "https://${ROUTE}/v1/completions" \
      -H "Content-Type: application/json" \
      -d '{"model":"'${MODEL_NAME}'","prompt":"Write a very long essay","max_tokens":500}' &
  done
  sleep 1
done
wait

echo "2분 대기 (alert 조건 충족)..."
sleep 120

THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
echo "=== Alerts ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/alerts" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('data',{}).get('alerts',[]):
    if 'PoC' in a.get('labels',{}).get('alertname',''):
        print(f'  {a[\"labels\"][\"alertname\"]}: {a[\"state\"]}')
" 2>/dev/null

MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS} -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "${MAILHOG_ROUTE}" ]; then
  echo "=== MailHog ==="
  curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=5" | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('items',[]):
    print(f'  {m.get(\"Content\",{}).get(\"Headers\",{}).get(\"Subject\",[\"\"])[0]}')
" 2>/dev/null
fi
~~~

### 2. Audit 추적 E2E

~~~bash
echo "=== K8s Events ==="
oc get events -n ${MODEL_NS} \
  --field-selector involvedObject.kind=InferenceService \
  --sort-by='.lastTimestamp' | tail -10

echo ""
echo "=== ArgoCD Sync ==="
oc get application -n openshift-gitops --no-headers 2>/dev/null | while read APP _; do
  PHASE=$(oc get application ${APP} -n openshift-gitops \
    -o jsonpath='{.status.operationState.phase}' 2>/dev/null)
  echo "  ${APP}: ${PHASE:-N/A}"
done
~~~

### 3. 이상 감지 → 조치 워크플로우

~~~bash
QUEUE=$(curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  "https://${THANOS_HOST}/api/v1/query" \
  --data-urlencode "query=sum(vllm:num_requests_waiting{namespace=\"${MODEL_NS}\"})" \
  | python3 -c "import sys,json; r=json.load(sys.stdin).get('data',{}).get('result',[]); print(r[0]['value'][1] if r else '0')" 2>/dev/null)
echo "큐 깊이: ${QUEUE}"

GPU_TEMP=$(curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_TEMP" \
  | python3 -c "import sys,json; r=json.load(sys.stdin).get('data',{}).get('result',[]); print(r[0]['value'][1] if r else 'N/A')" 2>/dev/null)
echo "GPU 온도: ${GPU_TEMP}°C"

DASH_URL="https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')"
DASH_COUNT=$(curl -sk "${DASH_URL}/perses/api/api/v1/dashboards" 2>/dev/null | \
  python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
echo "Perses 대시보드: ${DASH_COUNT:-0}개"
~~~

### 4. 정리

~~~bash
oc delete prometheusrule poc-cpu-test-alert -n ${MODEL_NS} 2>/dev/null
~~~

## 검증

~~~bash
# 1. Alert 발동 확인
# 2. 메일 수신 확인
# 3. K8s Events 추적
# 4. 이상→조치 워크플로우
# 5. Perses health
curl -sk "${DASH_URL}/perses/api/api/v1/health"
~~~

## 실패 시

- **Alert 미발동** → `for: 1m` 대기. 임계값 확인
- **메일 없음** → AlertManagerConfig smarthost 확인
- **Perses 503** → `data-science-perses-0` Pod 확인

## 다음 단계

→ `runbooks/66-maas-e2e.md` — S7: MaaS 통합 라우팅

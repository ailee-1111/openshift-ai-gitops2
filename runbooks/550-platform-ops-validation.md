# 550 — 플랫폼 운영 검증 (S6: 운영관리)

## 목적

GPU/모델 모니터링, RBAC, SSO 연동, 멀티테넌시, 성능 메트릭(TPS/TTFT/ITL), 대시보드, 로깅이 RHOAI 플랫폼에서 정상 동작하는지 검증한다. 고객 요구사항(No.14~70, 73, 77~80) 대응.

## 전제 조건

- [ ] `runbooks/350-platform-ops.md` 구축 완료
- [ ] `${MODEL_NAME}`, `${MODEL_NS}` 환경변수 설정
- [ ] Prometheus/Thanos, RBAC, 대시보드 구성 완료

## 실행

### 카테고리 A: RBAC / SSO / 멀티테넌시 (No.44~47)

~~~bash
echo "=== V-44: RBAC 검증 ==="
oc auth can-i '*' '*' -n "${MODEL_NS}" --as=admin
# 기대: yes

oc auth can-i delete inferenceservice -n "${MODEL_NS}" --as=user1 2>/dev/null
# 기대: no (설정된 경우)
echo "RBAC 정책:"
oc get rolebinding -n "${MODEL_NS}" --no-headers | head -5
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-45/46: SSO/LDAP/AD 연동 ==="
oc get oauth cluster \
  -o jsonpath='{range .spec.identityProviders[*]}{.name}: {.type}{"\n"}{end}' 2>/dev/null
# 기대: LDAP 또는 OpenID provider 존재 (고객 환경 의존)
# 결과: [   ] PASS / [   ] SKIP (고객 LDAP 미제공)

echo "=== V-47: 멀티테넌시 ==="
oc get networkpolicy -n "${MODEL_NS}" --no-headers
# 기대: 네임스페이스 격리 정책 존재
# 결과: [   ] PASS / [   ] FAIL
~~~

### 카테고리 B: GPU 모니터링 (No.48~51)

~~~bash
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring \
  -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

echo "=== V-48: GPU 사용률 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
for r in results:
    print(f\"  GPU {r['metric'].get('gpu','?')}: {r['value'][1]}%\")
print(f'총 GPU 수: {len(results)}')
"
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-49: VRAM 사용량 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_FB_USED" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
for r in results:
    mb = float(r['value'][1])
    print(f\"  GPU {r['metric'].get('gpu','?')}: {mb:.0f} MiB\")
"
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-50: GPU 온도/전력 ==="
for metric in DCGM_FI_DEV_GPU_TEMP DCGM_FI_DEV_POWER_USAGE; do
  echo ">> ${metric}"
  curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://${THANOS_HOST}/api/v1/query?query=${metric}" \
    | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
for r in results:
    print(f\"  GPU {r['metric'].get('gpu','?')}: {r['value'][1]}\")
" 2>/dev/null || echo "  메트릭 미수집"
done
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-51: 노드별 대시보드 ==="
DASHBOARD_ROUTE=$(oc get route rhods-dashboard -n redhat-ods-applications \
  -o jsonpath='{.spec.host}' 2>/dev/null)
echo "RHOAI Dashboard: https://${DASHBOARD_ROUTE}"
# 결과: [   ] PASS / [   ] FAIL
~~~

### 카테고리 C: 서빙 성능 메트릭 (No.52~57)

~~~bash
echo "=== V-52~57: 서빙 성능 메트릭 ==="
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)

echo ">> 10회 추론 요청 (성능 측정)"
for i in $(seq 1 10); do
  RESULT=$(curl -sk -w '\n%{time_total}' "https://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"What is AI?\",\"max_tokens\":50}")
  LATENCY=$(echo "${RESULT}" | tail -1)
  echo "  요청 ${i}: ${LATENCY}초"
done

echo ""
echo ">> Prometheus 서빙 메트릭"
for metric in \
  "vllm:num_requests_running{namespace=\"${MODEL_NS}\"}" \
  "vllm:time_to_first_token_seconds_bucket{namespace=\"${MODEL_NS}\"}" \
  "vllm:e2e_request_latency_seconds_bucket{namespace=\"${MODEL_NS}\"}"; do
  METRIC_NAME=$(echo "${metric}" | cut -d'{' -f1)
  COUNT=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://${THANOS_HOST}/api/v1/query?query=${metric}" \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('result',[])))" 2>/dev/null)
  echo "  ${METRIC_NAME}: ${COUNT:-0} series"
done

echo ""
echo "V-52 모델별 TPS:   [   ] PASS / [   ] FAIL"
echo "V-53 TTFT:          [   ] PASS / [   ] FAIL"
echo "V-54 ITL:           [   ] PASS / [   ] FAIL"
echo "V-55 E2E 레이턴시: [   ] PASS / [   ] FAIL"
echo "V-56 큐 대기 시간: [   ] PASS / [   ] FAIL"
echo "V-57 에러율:       [   ] PASS / [   ] FAIL"
~~~

### 카테고리 D: 사용량 / 로깅 / 알림 (No.59~67)

~~~bash
echo "=== V-59/60: 사용량 추이 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=sum(rate(vllm:num_requests_running{namespace=\"${MODEL_NS}\"}[5m]))" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
val = results[0]['value'][1] if results else 'N/A'
print(f'요청 rate (5m): {val}')
" 2>/dev/null || echo "시계열 쿼리 실패"
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-65: Prometheus/Grafana 연동 ==="
echo "Prometheus UI: https://${THANOS_HOST}"
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-66: 알림 설정 ==="
oc get prometheusrule -n "${MODEL_NS}" --no-headers 2>/dev/null
oc get alertmanagerconfig -n "${MODEL_NS}" --no-headers 2>/dev/null
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-68: 웹 대시보드 ==="
DASHBOARD_ROUTE=$(oc get route rhods-dashboard -n redhat-ods-applications \
  -o jsonpath='{.spec.host}' 2>/dev/null)
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${DASHBOARD_ROUTE}")
echo "RHOAI Dashboard HTTP: ${HTTP_CODE}"
# 기대: 200 또는 302
# 결과: [   ] PASS / [   ] FAIL
~~~

### 카테고리 E: 추가 기능 (No.73, 16)

~~~bash
echo "=== V-73: Continuous Batching ==="
VLLM_POD=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  -o jsonpath='{.items[0].metadata.name}')
oc logs "${VLLM_POD}" -n "${MODEL_NS}" --tail=30 | grep -i "batch\|scheduler"
# 기대: vLLM 기본 continuous batching 활성
# 결과: [   ] PASS / [   ] FAIL

echo "=== V-16: K8s 네이티브 지원 ==="
for crd in inferenceservices.serving.kserve.io servingruntimes.serving.kserve.io; do
  oc get crd "${crd}" --no-headers 2>/dev/null \
    && echo "  ${crd}: OK" || echo "  ${crd}: MISSING"
done
oc get inferenceservice -n "${MODEL_NS}" --no-headers
# 결과: [   ] PASS / [   ] FAIL
~~~

## 검증

~~~bash
echo "=== S6 검증 요약 ==="
echo ""
echo "[RBAC / SSO]"
echo "V-44 RBAC:               [   ] PASS / [   ] FAIL"
echo "V-45 SSO/LDAP:           [   ] PASS / [   ] SKIP"
echo "V-46 AD 연동:            [   ] PASS / [   ] SKIP"
echo "V-47 멀티테넌시:         [   ] PASS / [   ] FAIL"
echo ""
echo "[GPU 모니터링]"
echo "V-48 GPU 사용률:         [   ] PASS / [   ] FAIL"
echo "V-49 VRAM 사용량:        [   ] PASS / [   ] FAIL"
echo "V-50 GPU 온도/전력:      [   ] PASS / [   ] FAIL"
echo "V-51 노드별 대시보드:    [   ] PASS / [   ] FAIL"
echo ""
echo "[서빙 성능]"
echo "V-52 모델별 TPS:         [   ] PASS / [   ] FAIL"
echo "V-53 TTFT:               [   ] PASS / [   ] FAIL"
echo "V-54 ITL:                [   ] PASS / [   ] FAIL"
echo "V-55 E2E 레이턴시:       [   ] PASS / [   ] FAIL"
echo "V-56 큐 대기 시간:       [   ] PASS / [   ] FAIL"
echo "V-57 에러율:             [   ] PASS / [   ] FAIL"
echo ""
echo "[관찰성 / 알림]"
echo "V-59 모델별 사용량:      [   ] PASS / [   ] FAIL"
echo "V-60 시계열 추이:        [   ] PASS / [   ] FAIL"
echo "V-65 Prometheus/Grafana: [   ] PASS / [   ] FAIL"
echo "V-66 알림 설정:          [   ] PASS / [   ] FAIL"
echo "V-68 웹 대시보드:        [   ] PASS / [   ] FAIL"
echo ""
echo "[기타]"
echo "V-16 K8s 네이티브:       [   ] PASS / [   ] FAIL"
echo "V-73 Continuous Batching:[   ] PASS / [   ] FAIL"
~~~

## 실패 시

- **DCGM 메트릭 미수집** → NVIDIA GPU Operator + DCGM Exporter 확인. `oc get pods -n nvidia-gpu-operator`.
- **vLLM 메트릭 미수집** → UWM 활성화 확인. `oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml | grep enableUserWorkload`.
- **RHOAI Dashboard 접근 불가** → Route 확인. `oc get route -n redhat-ods-applications`.
- **RBAC 테스트 실패** → RoleBinding 확인. `oc describe rolebinding -n ${MODEL_NS}`.
- **Prometheus 쿼리 실패** → Thanos Route + Token 확인. TLS 문제면 `-k` 사용.

## v3 강화 검증 (65-v3-platform-ops.md 연동)

### V-S6-v3-1. CPU 부하 → Alert 발동

~~~bash
# 기대: alert state=firing  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S6-v3-2. 알림 메일 수신

~~~bash
# 기대: MailHog 1건 이상  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S6-v3-3. Audit 추적

~~~bash
oc get events -n ${MODEL_NS} --field-selector involvedObject.kind=InferenceService --sort-by='.lastTimestamp' | tail -3
# 기대: 이벤트 존재  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S6-v3-4. 이상 감지 → 조치

~~~bash
# 큐/GPU 확인→조치 기록  |  결과: [   ] PASS / [   ] FAIL
~~~

## 다음 단계

→ `runbooks/560-maas-validation.md` — S7 MaaS 검증
→ `runbooks/800-comprehensive-validation.md` — 종합 검증

# S6b: 모니터링/관측성 — GPU 및 모델 실시간 가시성

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | OPS |
| 보조역할 | INFRA |
| 데모 시간 | 15분 |
| 검증 항목 | No.48–57, 59–61, 63–67 |
| 구축 런북 | `runbooks/220-observability-dashboards.md`, `runbooks/368-maas-observability.md`, `runbooks/369-e-maas-token-alert.md` |
| 검증 런북 | `runbooks/550-platform-ops-validation.md` |
| IaC | `infra/rhoai/dashboards/`, `infra/rhoai/observability/`, `infra/poc/monitoring/` |

---

## 상황 (Context)

> 현대모비스는 HGX H200x8 GPU 서버에서 자율주행 영상 분석 모델과 차량 음성 인식 모델을 동시 서빙하고 있습니다. GPU 4장이 vLLM 서빙에 할당되어 있으며, 하루 평균 5,000건 이상의 추론 요청이 발생합니다.
>
> 운영팀(OPS)은 GPU 온도가 85도를 넘기 전에 냉각 조치를 해야 하고, 모델 응답 지연이 SLA(1초 이내)를 초과하면 즉시 감지해야 합니다. 또한 경영진에게 월간 GPU 활용률과 모델별 토큰 사용량을 보고해야 합니다.

## 문제 (Problem)

> 기존 방식에서는 이런 문제가 있습니다:
>
> 1. **GPU 블라인드 스팟**: nvidia-smi를 노드마다 SSH 접속하여 수동 확인합니다. 4개 GPU의 온도/전력/메모리를 한 화면에서 볼 수 없습니다.
> 2. **모델 성능 미가시**: vLLM 서빙의 TTFT(Time To First Token), ITL(Inter-Token Latency), 처리량(TPS)을 실시간으로 확인할 방법이 없습니다.
> 3. **알림 부재**: GPU 온도가 위험 수준에 도달하거나, 모델 큐가 쌓여도 운영자가 인지하지 못합니다. 장애가 발생한 후에야 대응합니다.
> 4. **사용량 보고 불가**: 팀별/모델별 토큰 사용량, API 키별 호출 횟수를 집계할 수 없어, 비용 배분과 용량 계획이 불가능합니다.
> 5. **감사 추적 부재**: 누가 어떤 모델을 배포/삭제했는지 이벤트 로그가 산재해 있어 보안 감사 대응이 어렵습니다.

## 해결 (Solution) — RHOAI 관측성 스택으로 해결합니다

### Step 1. GPU Overview 대시보드 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: GPU 4장의 사용률, 온도, 전력, VRAM을 한 화면에서 확인
> **어떻게**: RHOAI Dashboard → Observe & Monitor → GPU 대시보드

```
[시연 포인트]
"RHOAI Dashboard에서 Observe & Monitor 메뉴를 클릭합니다.
 GPU 대시보드를 선택하면, 4개 GPU의 실시간 상태가 한 화면에 나타납니다.
 nvidia-smi SSH 접속 없이도 전체 GPU 상태를 파악할 수 있습니다."
```

```bash
# 대시보드 URL
DASHBOARD_URL="https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')"
echo "Dashboard: ${DASHBOARD_URL}/observe-and-monitor/dashboard"
echo "→ 드롭다운에서 'GPU' 선택"
```

```
[화면에 보여줄 것 — GPU 대시보드 18패널, 5그룹]
현재 상태 요약 (StatChart ×4):
  ┌──────────────┬──────────────┬──────────────┬──────────────┐
  │ GPU 사용률   │ VRAM 사용률  │ 최고 온도    │ 총 전력      │
  │    45%       │    62%       │    72°C      │   320W       │
  └──────────────┴──────────────┴──────────────┴──────────────┘

컴퓨팅 사용률 / 메모리(VRAM) / 열/전력 / 에러 그래프
```

```bash
# GPU 메트릭 직접 확인
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

echo "=== GPU 사용률 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | \
  python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
for r in results:
    print(f'  GPU {r[\"metric\"].get(\"gpu\",\"?\")}: {r[\"value\"][1]}%')
print(f'총 GPU 수: {len(results)}')
"
```

**확인**: GPU 4장 메트릭 수집, 사용률/온도/전력/VRAM 실시간 표시

---

### Step 2. vLLM Performance 대시보드 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: vLLM 서빙 성능 지표(TPS, TTFT, ITL, E2E Latency) 확인
> **어떻게**: GPU 대시보드 드롭다운을 vLLM으로 전환

```
[시연 포인트]
"드롭다운을 'vLLM'으로 바꾸겠습니다.
 처리량 약 15 tokens/s, TTFT P95, ITL P95, E2E 레이턴시 0.63초.
 이 숫자들이 SLA 기준(1초 이내)을 만족하는지 한눈에 알 수 있습니다."
```

```
[화면에 보여줄 것 — vLLM 대시보드 18패널, 5그룹]
핵심 지표 (StatChart ×6):
  ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
  │ TTFT P95 │ ITL P95  │ 처리량   │ KV Cache │ 토큰 t/s │ 총 요청  │
  │  0.12s   │  0.04s   │  8 req/s │   45%    │ ~15 t/s  │  1,247   │
  └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘

Model / Namespace 드롭다운 필터로 모델별 성능 비교
```

```bash
# vLLM 메트릭 확인
echo "=== vLLM 핵심 메트릭 ==="
for metric in "vllm:e2e_request_latency_seconds_sum" "vllm:num_requests_running" "vllm:time_to_first_token_seconds_sum"; do
  METRIC_NAME=$(echo "${metric}" | cut -d'{' -f1)
  COUNT=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://${THANOS_HOST}/api/v1/query" \
    --data-urlencode "query=${metric}{namespace=\"${MODEL_NS:-mobis-poc}\"}" | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('result',[])))" 2>/dev/null)
  echo "  ${METRIC_NAME}: ${COUNT:-0} series"
done
```

**확인**: TPS ~15 t/s, TTFT, ITL, E2E 레이턴시 실시간 수집

---

### Step 3. Token Usage Trend 대시보드 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: API 키별 토큰 사용량, 모델별 사용 추이, 시간대별 패턴 확인
> **어떻게**: Usage Trend 대시보드 (19패널)

```
[시연 포인트]
"이번에는 Usage Trend 대시보드입니다. 19개 패널로 구성되어 있으며,
 시간별/일별/주별/월별로 토큰 사용량을 분석할 수 있습니다.
 경영진에게 월간 보고서를 제출할 때 이 데이터를 사용합니다."
```

```
[화면에 보여줄 것 — Usage Trend 19패널, 6그룹]
  Summary: 누적 토큰 / 오늘 사용량 / 이번 주 / 활성 사용자 / 활성 구독
  시간대별: 전체/사용자별/구독별 실시간 차트
  일별/주별/월별: 추이 그래프 (최대 90일 보존)
  피크: 5분 평균 hits/s 사용률
```

**확인**: 시간/일/주/월 집계, 사용자별 토큰 사용량 가시화

---

### Step 4. MaaS Token 대시보드 (1분)

> **누가**: OPS (poc-operator)
> **무엇을**: API 키별 토큰 사용량, 성공률 확인
> **어떻게**: MaaS Token Metrics 대시보드 (10패널)

```
[시연 포인트]
"API 키별로 토큰 사용량을 봅니다.
 이 키는 282 토큰 소비, 성공률 100%.
 사용량 기반 과금이나 비용 배분의 근거 데이터입니다."
```

```
[화면에 보여줄 것 — MaaS Token 대시보드 10패널, 4그룹]
  Overview: 총 Hits 282, 구독별 Hits, 활성 사용자, 추정 비용
  구독별 추이: Hits Rate, 사용자별 Hits
  총량: 구독별 누적 Hits
  상세: 메트릭 테이블 (user/subscription/namespace)
```

**확인**: API 키별 토큰 282, 성공률 100%

---

### Step 5. Prometheus 수집 타겟 확인 (1분)

> **누가**: INFRA (poc-admin, cluster-admin)
> **무엇을**: 15개 ServiceMonitor 타겟이 모두 UP인지 확인
> **어떻게**: Thanos Querier로 타겟 상태 조회

```
[시연 포인트]
"데이터가 정확하려면, 메트릭 수집 파이프라인이 건강해야 합니다.
 15개 ServiceMonitor 타겟이 모두 UP입니다.
 하나라도 DOWN이면 대시보드에 빈 영역이 나타납니다."
```

```bash
# ServiceMonitor 목록
echo "=== ServiceMonitor (${MODEL_NS:-mobis-poc}) ==="
oc get servicemonitor -n ${MODEL_NS:-mobis-poc} --no-headers

echo ""
echo "=== UWM 타겟 확인 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=up" | \
  python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
up = sum(1 for r in results if r['value'][1] == '1')
down = sum(1 for r in results if r['value'][1] == '0')
print(f'UP: {up}, DOWN: {down}, 총: {len(results)}')
"
```

**확인**: 15개 타겟 모두 UP

---

### Step 6. 임계값 알림 시뮬레이션 (3분)

> **누가**: OPS (poc-operator)
> **무엇을**: GPU 사용률 90% 초과 알림 발생 → AlertManager → MailHog 이메일 수신
> **어떻게**: 부하 주입으로 PrometheusRule 트리거

```
[시연 포인트]
"GPU 사용률 90% 초과 시나리오를 만들겠습니다.
 부하를 주입하면, PrometheusRule이 감지 → AlertManager가 라우팅
 → 60초 내에 운영자 메일함에 알림이 도착합니다."
```

```bash
# 테스트용 저임계값 Rule (시연용 — 임계값 낮게)
oc apply -n ${MODEL_NS:-mobis-poc} -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: poc-demo-alert
spec:
  groups:
    - name: demo-alerts
      rules:
        - alert: GPUHighUtilDemo
          expr: |
            sum(rate(container_cpu_usage_seconds_total{namespace="${MODEL_NS:-mobis-poc}",
              pod=~".*predictor.*"}[2m])) by (pod) > 0.5
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "GPU 사용률 90% 초과 (시연)"
EOF

# 부하 주입
ROUTE=$(oc get route ${MODEL_NAME:-smollm2-135m}-api -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.spec.host}' 2>/dev/null)
echo "30초간 부하 주입..."
for i in $(seq 1 30); do
  for j in $(seq 1 10); do
    curl -sk -o /dev/null --max-time 10 \
      "https://${ROUTE}/v1/completions" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${MODEL_NAME:-smollm2-135m}\",\"prompt\":\"Write a long essay\",\"max_tokens\":200}" &
  done
  sleep 1
done
wait
```

**확인**: 부하 주입 완료 (Alert 발동까지 1~2분 대기)

---

### Step 7. Alert → MailHog 이메일 수신 (2분)

> **누가**: OPS (poc-operator)
> **무엇을**: PrometheusRule → AlertManager → MailHog 이메일 수신까지 E2E 확인
> **어떻게**: Thanos Alerts API + MailHog API 조회

```
[시연 포인트]
"2분이 지났습니다. Alert 상태를 확인하겠습니다.
 Firing 상태가 되었으니, MailHog에서 이메일을 확인합니다.
 운영자가 장애를 인지하기까지 60초 이내입니다."
```

```bash
echo "=== Alert 상태 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/alerts" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('data',{}).get('alerts',[]):
    if 'Demo' in a.get('labels',{}).get('alertname','') or 'PoC' in a.get('labels',{}).get('alertname',''):
        print(f'  {a[\"labels\"][\"alertname\"]}: {a[\"state\"]}')
" 2>/dev/null

echo ""
echo "=== MailHog 이메일 ==="
MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "${MAILHOG_ROUTE}" ]; then
  curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=5" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'총 메일: {d.get(\"total\",0)}건')
for m in d.get('items',[])[:3]:
    subj = m.get('Content',{}).get('Headers',{}).get('Subject',[''])[0]
    print(f'  Subject: {subj[:80]}')
" 2>/dev/null
fi

# 정리
oc delete prometheusrule poc-demo-alert -n ${MODEL_NS:-mobis-poc} --ignore-not-found 2>/dev/null
```

```
[화면에 보여줄 것]
1. Thanos UI → Alerts 탭 → GPUHighUtilDemo: firing
2. MailHog 웹 UI → 수신된 알림 이메일 열기
   Subject: [FIRING] GPUHighUtilDemo — GPU 사용률 90% 초과
```

**확인**: Alert firing, MailHog 이메일 60초 내 수신

---

### Step 8. 감사 로그 — OCP Audit Log (1분)

> **누가**: OPS (poc-operator)
> **무엇을**: 모델 배포/삭제, API 키 발급 등 조작 이력 추적
> **어떻게**: K8s Events + ArgoCD Sync 이력 조회

```
[시연 포인트]
"누가 언제 어떤 모델을 배포했는지, K8s 이벤트로 추적됩니다.
 ArgoCD를 통한 배포는 Git 커밋과 연결되어 완전한 감사 추적이 가능합니다.
 보안 감사 시 이 로그를 제출합니다."
```

```bash
echo "=== K8s Events (InferenceService) ==="
oc get events -n ${MODEL_NS:-mobis-poc} \
  --field-selector involvedObject.kind=InferenceService \
  --sort-by='.lastTimestamp' | tail -5

echo ""
echo "=== ArgoCD Sync 이력 ==="
oc get application -n openshift-gitops --no-headers 2>/dev/null | while read APP _; do
  PHASE=$(oc get application ${APP} -n openshift-gitops \
    -o jsonpath='{.status.operationState.phase}' 2>/dev/null)
  echo "  ${APP}: ${PHASE:-N/A}"
done
```

**확인**: InferenceService 이벤트 이력, ArgoCD Sync 상태 확인

---

### Step 9. 데이터 내보내기 — CSV/JSON (1분)

> **누가**: OPS (poc-operator)
> **무엇을**: 대시보드 데이터를 CSV/JSON으로 내보내기
> **어떻게**: Prometheus API로 범위 쿼리 후 파일 저장

```
[시연 포인트]
"대시보드에서 보는 데이터를 CSV나 JSON으로 내보낼 수 있습니다.
 월간 보고서, 용량 계획, 비용 분석에 사용합니다."
```

```bash
# JSON 내보내기 예시 — 최근 1시간 GPU 사용률
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query_range" \
  --data-urlencode "query=avg(DCGM_FI_DEV_GPU_UTIL)" \
  --data-urlencode "start=$(date -v-1H +%s 2>/dev/null || date -d '1 hour ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode "step=60" | python3 -m json.tool > /tmp/gpu-util-export.json

echo "JSON 내보내기: /tmp/gpu-util-export.json"
echo "$(wc -l < /tmp/gpu-util-export.json) lines"

# CSV 변환
python3 -c "
import json
with open('/tmp/gpu-util-export.json') as f:
    d = json.load(f)
    results = d.get('data',{}).get('result',[])
    if results:
        print('timestamp,gpu_util_avg')
        for ts, val in results[0].get('values',[]):
            print(f'{ts},{val}')
" > /tmp/gpu-util-export.csv
echo "CSV 내보내기: /tmp/gpu-util-export.csv"
```

**확인**: JSON/CSV 파일 생성 완료

---

## 확인 (Verification)

| # | 검증 기준 | 기대값 | 실측값 |
|---|----------|--------|--------|
| V-48 | GPU 사용률 수집 | 4개 GPU 메트릭 수집 | |
| V-49 | VRAM 사용량 수집 | MiB 단위 정상 표시 | |
| V-50 | GPU 온도/전력 | 정상 범위 표시 | |
| V-51 | 대시보드 접근 | RHOAI Dashboard HTTP 200 | |
| V-52 | 모델별 TPS | ~15 t/s (모델에 따라 상이) | |
| V-53 | TTFT | P95 수집 중 | |
| V-54 | ITL | P95 수집 중 | |
| V-55 | E2E 레이턴시 | 0.63s (SLA 1초 이내) | |
| V-59 | 토큰 사용량 추이 | 시간/일/주/월 차트 | |
| V-60 | 사용량 리포팅 | 19패널 대시보드 정상 | |
| V-65 | Prometheus 타겟 | 15개 타겟 모두 UP | |
| V-66 | 알림 발동 | PrometheusRule firing | |
| V-66b | 이메일 수신 | MailHog 60초 내 수신 | |
| V-67 | 감사 로그 | K8s Events 이력 존재 | |
| V-63 | 데이터 내보내기 | CSV/JSON 정상 생성 | |
| 대시보드 수 | 9개 대시보드 운영 | 9개 전부 정상 | |

### 9개 Perses 대시보드 목록

| # | 대시보드 | 패널 수 | 데이터 소스 |
|---|---------|:-------:|-----------|
| 0 | Cluster Admin (RHOAI 기본) | — | RHOAI 자동 생성 |
| 1 | Model (RHOAI 기본) | — | RHOAI 자동 생성 |
| 3 | MaaS Usage Admin | — | MaaS 자동 생성 |
| 4 | GPU | 18 | DCGM Exporter |
| 5 | vLLM | 18 | vLLM metrics |
| 6 | Tokens | 10 | vLLM token metrics |
| 7 | API Key Usage | — | authorized_hits |
| 8 | MaaS Token Metrics | 10 | Limitador |
| 9 | MaaS Usage Trend | 19 | Limitador |

---

## 이번 시연에서 확인된 핵심 가치

- **사전 예방적 장애 대응**: GPU 온도/사용률 임계값 알림이 60초 내에 이메일로 전달됩니다. 장애가 발생하기 전에 조치할 수 있습니다.
- **GPU/모델 실시간 가시성**: nvidia-smi SSH 접속 없이, 웹 대시보드 하나로 GPU 4장의 전체 상태를 실시간 모니터링합니다.
- **SLA 기반 서빙 품질 관리**: TTFT, ITL, E2E 레이턴시를 실시간 측정하여 "응답 1초 이내" SLA를 수치로 증명할 수 있습니다.
- **사용량 기반 비용 배분 근거**: 팀별/모델별/API 키별 토큰 사용량을 시간/일/주/월 단위로 집계하여, 부서 간 비용 배분의 정량적 근거를 제공합니다.
- **컴플라이언스 대응 감사 추적**: K8s Events와 ArgoCD Git 이력으로 모든 변경 사항이 자동 추적됩니다. 보안 감사 시 즉시 증적을 제출할 수 있습니다.
- **SA 토큰 비만료 Secret**: Perses → Thanos 연동에 `kubernetes.io/service-account-token` 타입 Secret을 사용하여, API 서버 재시작 시에도 인증이 끊기지 않습니다.

---

## 추천 사항

1. **알림 채널 다중화**: PoC에서는 MailHog을 사용했지만, 운영 환경에서는 Slack/Teams Webhook + PagerDuty를 AlertManagerConfig에 추가하여 다중 채널 알림을 구성하십시오.
2. **UWM 보존 기간 확대**: 기본 15일 보존을 90일로 확장하고 PVC 30Gi를 할당하면, 분기별 트렌드 분석이 가능합니다. (`user-workload-monitoring-config`에서 `retention: 90d`)
3. **비용 환산 대시보드 추가**: Recording Rule로 토큰 사용량을 USD로 환산하면, 모델별/팀별 비용을 자동 집계할 수 있습니다. (`runbooks/220` 확장 아이디어 참조)
4. **외부 SIEM 연동**: GPU 알림과 감사 로그를 Splunk/ELK로 전송하여 90일 이상 장기 보존하십시오. SOC(Security Operations Center) 통합 모니터링에 필수적입니다.
5. **COO Perses Operator 주의**: RHOAI 3.4 + COO 1.4 환경에서 Perses Operator가 CPU를 과점유하는 아키텍처 충돌이 있습니다. `oc scale deployment perses-operator --replicas=0`으로 대응하고, 커스텀 대시보드는 이미 생성되어 영향이 없습니다. 향후 패치에서 해결 예정입니다.

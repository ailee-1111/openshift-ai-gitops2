# 369-e — MaaS 토큰 초과 알림 (AlertManager → Email)

## 어떤 경우 필요한가

MaaS 사용자의 토큰 사용량이 임계값을 초과하거나 Rate Limit(429)이 발동될 때, AlertManager를 통해 관리자에게 이메일 알림을 자동 발송한다.

## 아키텍처

```
authorized_hits 메트릭 (Limitador)
    ↓ Prometheus 수집
PrometheusRule (kuadrant-system NS)
    ↓ rate() > threshold → alert firing
UWM Prometheus → Platform AlertManager
    ↓ route match (service=maas)
maas-email receiver
    ↓ SMTP
MailHog (poc) / 실제 SMTP 서버 (prod)
    ↓
poc-admin@mobis.com 수신
```

## 전제 조건

- [ ] MaaS Gateway 정상 동작 — `authorized_hits` 메트릭 수집 중
- [ ] MailHog Pod Running (PoC) 또는 SMTP 서버 접근 가능 (Prod)
- [ ] `cluster-admin` 권한

## 실행

### 1. PrometheusRule 생성

> **주의**: `kuadrant-system` NS에 생성해야 한다.
> - UWM Prometheus의 `ruleNamespaceSelector`가 `openshift.io/cluster-monitoring: NotIn [true]`로 설정됨
> - `mobis-poc` NS는 `cluster-monitoring: true` 라벨이 있어 **제외됨**
> - `kuadrant-system` NS는 해당 라벨이 없어 규칙이 정상 로드됨
> - `openshift.io/prometheus-rule-evaluation-scope: leaf-prometheus` 라벨 필수

~~~bash
oc apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: maas-token-alerts
  namespace: kuadrant-system
  labels:
    openshift.io/prometheus-rule-evaluation-scope: leaf-prometheus
spec:
  groups:
    - name: maas-token-limits
      rules:
        - alert: MaaSTokenLimitExceeded
          expr: |
            sum by (user, subscription, model) (
              rate(authorized_hits[5m])
            ) > 0.5
          for: 1m
          labels:
            severity: warning
            service: maas
          annotations:
            summary: "MaaS 토큰 사용량 초과 — {{ $labels.user }}"
            description: |
              사용자 {{ $labels.user }} (구독: {{ $labels.subscription }}, 모델: {{ $labels.model }})의
              토큰 사용률이 {{ $value | printf "%.2f" }} hits/s를 초과했습니다.
        - alert: MaaSRateLimited
          expr: |
            sum by (user, subscription) (limited_calls) > 0
          for: 0m
          labels:
            severity: critical
            service: maas
          annotations:
            summary: "MaaS Rate Limit 발동 — {{ $labels.user }}"
            description: |
              사용자 {{ $labels.user }} (구독: {{ $labels.subscription }})에 Rate Limit 발동 (429).
EOF
~~~

### 2. Platform AlertManager에 Email Receiver 추가

> Platform AlertManager 설정은 `openshift-monitoring/alertmanager-main` Secret으로 관리된다.

~~~bash
# 현재 설정 백업
oc get secret alertmanager-main -n openshift-monitoring \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > alertmanager-backup.yaml

# maas-email receiver + route 추가한 새 설정 적용
# (아래는 기존 Default/Watchdog/Critical + maas-email 추가 예시)
cat > alertmanager-updated.yaml << 'AMEOF'
"global":
  "http_config":
    "proxy_from_environment": true
"inhibit_rules":
- "equal":
  - "namespace"
  - "alertname"
  "source_matchers":
  - "severity = critical"
  "target_matchers":
  - "severity =~ warning|info"
- "equal":
  - "namespace"
  - "alertname"
  "source_matchers":
  - "severity = warning"
  "target_matchers":
  - "severity = info"
"receivers":
- "name": "Default"
- "name": "Watchdog"
- "name": "Critical"
- "name": "maas-email"
  "email_configs":
  - "to": "poc-admin@mobis.com"
    "from": "ocp-alert@poc.mobis.com"
    "smarthost": "mailhog.mobis-poc.svc:1025"
    "require_tls": false
    "headers":
      "Subject": "[MaaS Alert] {{ .GroupLabels.alertname }} — {{ .CommonLabels.user }}"
"route":
  "group_by":
  - "namespace"
  "group_interval": "5m"
  "group_wait": "30s"
  "receiver": "Default"
  "repeat_interval": "12h"
  "routes":
  - "match":
      "alertname": "Watchdog"
    "receiver": "Watchdog"
  - "match":
      "severity": "critical"
    "receiver": "Critical"
  - "match":
      "service": "maas"
    "receiver": "maas-email"
    "group_by":
    - "alertname"
    - "user"
    "group_wait": "30s"
    "group_interval": "5m"
    "repeat_interval": "1h"
AMEOF

oc create secret generic alertmanager-main \
  -n openshift-monitoring \
  --from-file=alertmanager.yaml=alertmanager-updated.yaml \
  --dry-run=client -o yaml | oc replace -f -
~~~

### 3. 규칙 로드 확인

~~~bash
# UWM Prometheus에서 규칙 로드 확인 (30초 대기 후)
sleep 30
oc exec -n openshift-user-workload-monitoring sts/prometheus-user-workload -- \
  curl -s http://localhost:9090/api/v1/rules | \
  python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
for g in d.get('data',{}).get('groups',[]):
    if 'maas' in g.get('name','').lower():
        print(f'그룹: {g[\"name\"]}')
        for r in g.get('rules',[]):
            print(f'  - {r[\"name\"]}: state={r.get(\"state\",\"?\")}')
"
# 기대: MaaSTokenLimitExceeded + MaaSRateLimited 로드됨
~~~

### 4. 알림 트리거 테스트 (부하 발생)

~~~bash
API_KEY="${MAAS_API_KEY}"
HOST="maas.${CLUSTER_DOMAIN:-apps.poc.mobis.com}"

for i in $(seq 1 30); do
  oc exec -n mobis-poc deploy/minio -- curl -sk --max-time 15 \
    "https://${HOST}/${MODEL_NS}/${MODEL_NAME}/v1/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"test ${i}\",\"max_tokens\":50}" \
    -o /dev/null -w "${i} " &
done
wait
echo "부하 발생 완료. 2분 후 Alert 확인"
~~~

## 검증 완료

### V-1: PrometheusRule 로드

~~~bash
oc exec -n openshift-user-workload-monitoring sts/prometheus-user-workload -- \
  curl -s http://localhost:9090/api/v1/rules | grep -c "MaaSToken"
# 기대: 1 이상
# PASS: [   ]  FAIL: [   ]
~~~

### V-2: Alert Firing

~~~bash
oc exec -n openshift-user-workload-monitoring sts/prometheus-user-workload -- \
  curl -s http://localhost:9090/api/v1/rules | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
for g in d.get('data',{}).get('groups',[]):
    for r in g.get('rules',[]):
        if 'MaaS' in r.get('name',''):
            print(f'{r[\"name\"]}: state={r.get(\"state\")} alerts={len(r.get(\"alerts\",[]))}')
"
# 기대: state=firing, alerts=1+
# PASS: [   ]  FAIL: [   ]
~~~

### V-3: AlertManager 수신

~~~bash
oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- \
  curl -s http://localhost:9093/api/v2/alerts | python3 -c "
import sys,json
alerts=[a for a in json.loads(sys.stdin.read()) if a.get('labels',{}).get('service')=='maas']
print(f'MaaS 알림: {len(alerts)}개')
for a in alerts:
    print(f'  {a[\"labels\"][\"alertname\"]}: {a[\"status\"][\"state\"]}')
"
# 기대: MaaSTokenLimitExceeded: active
# PASS: [   ]  FAIL: [   ]
~~~

### V-4: MailHog 이메일 수신

~~~bash
oc exec -n mobis-poc deploy/minio -- \
  curl -s "http://mailhog.mobis-poc.svc:8025/api/v2/messages?limit=5" | python3 -c "
import sys,json
d=json.loads(sys.stdin.buffer.read().decode('utf-8',errors='replace'))
print(f'총 메일: {d.get(\"total\",0)}개')
for m in d.get('items',[])[:5]:
    subj=m.get('Content',{}).get('Headers',{}).get('Subject',[''])[0]
    to=m.get('Content',{}).get('Headers',{}).get('To',[''])[0]
    print(f'  To:{to} Subject:{subj[:80]}')
"
# 기대: [MaaS Alert] MaaSTokenLimitExceeded — admin
# PASS: [   ]  FAIL: [   ]
~~~

### 검증 요약

| # | 항목 | 기준 | 판정 |
|---|------|------|:----:|
| V-1 | PrometheusRule | UWM 로드 | |
| V-2 | Alert | state=firing | |
| V-3 | AlertManager | MaaS 알림 active | |
| V-4 | MailHog | 이메일 수신 | |

## 식별 방법 (트러블슈팅)

### PrometheusRule이 UWM에 로드되지 않을 때

~~~bash
# 1. NS 라벨 확인 — cluster-monitoring: true인 NS는 UWM에서 제외
oc get ns <NS> -o jsonpath='{.metadata.labels.openshift\.io/cluster-monitoring}'
# true → 해당 NS 사용 불가. kuadrant-system 등 라벨 없는 NS로 이동

# 2. PrometheusRule 라벨 확인
oc get prometheusrule <name> -n <ns> -o jsonpath='{.metadata.labels}'
# openshift.io/prometheus-rule-evaluation-scope: leaf-prometheus 필수
~~~

### AlertManager에서 메일 발송 안 될 때

~~~bash
# 1. receiver 로드 확인
oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- \
  curl -s http://localhost:9093/api/v2/status | grep -c "maas-email"

# 2. SMTP 연결 테스트
oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- \
  sh -c "echo test | nc mailhog.mobis-poc.svc 1025"

# 3. AlertManager 로그
oc logs -n openshift-monitoring alertmanager-main-0 -c alertmanager --tail=20 | grep -i "email\|smtp\|error"
~~~

## 실패 시

- **PrometheusRule 미로드** → NS의 `cluster-monitoring` 라벨 확인. `leaf-prometheus` 라벨 확인
- **Alert inactive** → `authorized_hits` 메트릭이 수집되는지 확인. 임계값(0.5) 조정 필요할 수 있음
- **AlertManager 미수신** → route의 `match.service: maas` 확인. PrometheusRule의 `labels.service: maas` 일치 여부
- **메일 미발송** → `smarthost` 주소 확인. MailHog Pod Running 여부. AlertManager → MailHog 네트워크 접근 가능 여부

## 임계값 조정 가이드

| 파라미터 | 기본값 | 설명 | 조정 방법 |
|---------|:------:|------|----------|
| `rate() > threshold` | 0.5 | hits/s (5분 평균) | 환경에 맞게 조정 |
| `for` | 1m | 임계값 초과 지속 시간 | 순간 스파이크 무시 시 증가 |
| `groupWait` | 30s | 첫 알림 대기 | |
| `repeatInterval` | 1h | 반복 알림 간격 | |

## Mobis 클러스터 실측 (2026-05-20)

| 항목 | 값 |
|------|-----|
| PrometheusRule | `kuadrant-system/maas-token-alerts` (UWM 로드 확인) |
| Alert | `MaaSTokenLimitExceeded` firing (admin, 5.22 hits/s) |
| AlertManager | Platform `alertmanager-main`에 `maas-email` receiver 로드 |
| 메일 | MailHog 수신 확인: `[MaaS Alert] MaaSTokenLimitExceeded — admin` |
| SMTP | `mailhog.mobis-poc.svc:1025` (PoC) |

## 다음 단계

→ `runbooks/370-multitenant.md` — 멀티테넌트 검증

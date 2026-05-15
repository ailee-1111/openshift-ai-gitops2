# 65 — 플랫폼 운영: 모니터링 / RBAC / 보안 / 관찰성 (S6)

## 목적

RHOAI 플랫폼의 운영 관리 역량을 종합 구축한다. GPU/모델 모니터링(ServiceMonitor, PrometheusRule, AlertManagerConfig), 역할별 접근 제어(RBAC), 네임스페이스 격리(NetworkPolicy), TrustyAI(Guardrails, LMEval), 그리고 RHOAI 3.4+ Perses 기반 Observability Dashboard를 포함한다.

## 전제 조건

- [ ] `runbooks/61-pipeline.md` 완료 — Pipeline E2E 검증 통과
- [ ] InferenceService Ready=True (`oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS}`)
- [ ] UWM(User Workload Monitoring) 활성화 (`oc get pods -n openshift-user-workload-monitoring`)
- [ ] DCGM Exporter Running (`oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter`)
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `ALERT_EMAIL_TO`, `ALERT_EMAIL_FROM`, `POC_NAMESPACE`

## 실행

### 1. ServiceMonitor 생성

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${MODEL_NAME}-metrics
spec:
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: ${MODEL_NAME}
  endpoints:
    - targetPort: 8080
      path: /metrics
      interval: 15s
EOF
~~~

### 2. PrometheusRule 생성 (GPU + vLLM 알림)

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: poc-gpu-alerts
spec:
  groups:
    - name: gpu-alerts
      rules:
        - alert: GPUHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "GPU temperature above 85°C"
        - alert: GPUHighUtilization
          expr: DCGM_FI_DEV_GPU_UTIL > 95
          for: 10m
          labels:
            severity: info
          annotations:
            summary: "GPU utilization above 95% for 10min"
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vllm-alerts
spec:
  groups:
    - name: vllm-alerts
      rules:
        - alert: VLLMHighQueueWait
          expr: vllm:num_requests_waiting > 10
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "vLLM request queue > 10 for 2min"
EOF
~~~

### 3. AlertManagerConfig 생성

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: monitoring.coreos.com/v1beta1
kind: AlertmanagerConfig
metadata:
  name: poc-alert-routing
spec:
  route:
    receiver: mailhog-webhook
    groupBy: [alertname]
    groupWait: 30s
    groupInterval: 5m
    repeatInterval: 1h
  receivers:
    - name: mailhog-webhook
      emailConfigs:
        - to: "${ALERT_EMAIL_TO:-poc-admin@example.com}"
          from: "${ALERT_EMAIL_FROM:-ocp-alert@example.com}"
          smarthost: "mailhog.${POC_NAMESPACE}.svc.cluster.local:1025"
          requireTLS: false
EOF
~~~

### 4. NetworkPolicy (네임스페이스 격리)

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
spec:
  podSelector: {}
  ingress:
    - from:
        - podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-monitoring
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-user-workload-monitoring
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              network.openshift.io/policy-group: ingress
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-rhoai
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: redhat-ods-applications
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: rhoai-model-registries
  policyTypes: [Ingress]
EOF
~~~

### 5. TrustyAI 서비스 활성화

~~~bash
# DSC에서 LMEval 온라인 평가 허용
oc patch dsc default-dsc --type='merge' \
  -p '{"spec":{"components":{"trustyai":{"eval":{"lmeval":{"permitOnline":"allow"}}}}}}'

# TrustyAI Service 배포
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: trustyai.opendatahub.io/v1
kind: TrustyAIService
metadata:
  name: trustyai-service
spec:
  replicas: 1
  storage:
    format: PVC
    folder: /data
    size: 1Gi
  metrics:
    schedule: "5s"
    batchSize: 5000
  data:
    filename: data.csv
    format: CSV
EOF

oc wait trustyaiservice/trustyai-service -n ${MODEL_NS} \
  --for=jsonpath='{.status.phase}'=Ready \
  --timeout=120s
~~~

### 6. GuardrailsOrchestrator (PII 감지)

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: GuardrailsOrchestrator
metadata:
  name: ${MODEL_NAME}-guardrails
spec:
  replicas: 1
  autoConfig:
    inferenceServiceToGuardrail: ${MODEL_NAME}
  enableBuiltInDetectors: true
  enableGuardrailsGateway: true
  env:
    - name: OPENAI_BASE_URL
      value: http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1
  otelExporter:
    otlpProtocol: grpc
EOF
~~~

### 7. LMEvalJob (모델 평가)

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: ${MODEL_NAME}-eval
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - name: model
      value: ${MODEL_NAME}
    - name: base_url
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/completions"
    - name: tokenizer_backend
      value: huggingface
    - name: tokenized_requests
      value: "false"
    - name: tokenizer
      value: "HuggingFaceTB/SmolLM2-135M"
  taskList:
    taskNames:
      - "hellaswag"
  limit: "3"
  batchSize: "1"
EOF
~~~

### 8. Observability Dashboard (RHOAI 3.4+)

#### 8-1. 전제 Operator 설치 (COO, Tempo, OpenTelemetry)

~~~bash
# Cluster Observability Operator (COO)
oc create namespace openshift-cluster-observability-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: coo-og
  namespace: openshift-cluster-observability-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  channel: stable
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Tempo Operator
oc create namespace openshift-tempo-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: tempo-og
  namespace: openshift-tempo-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: tempo-product
  namespace: openshift-tempo-operator
spec:
  channel: stable
  name: tempo-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Red Hat Build of OpenTelemetry
oc create namespace openshift-opentelemetry-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: otel-og
  namespace: openshift-opentelemetry-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: opentelemetry-product
  namespace: openshift-opentelemetry-operator
spec:
  channel: stable
  name: opentelemetry-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# 설치 확인 (3~5분 소요)
for NS in openshift-cluster-observability-operator openshift-tempo-operator openshift-opentelemetry-operator; do
  echo -n "  ${NS}: "
  oc get csv -n "$NS" --no-headers 2>/dev/null | awk '{print $NF}' | head -1
done
~~~

#### 8-2. DSCI Observability Stack 활성화

~~~bash
oc patch dsci default-dsci --type='merge' -p '{
  "spec": {
    "monitoring": {
      "managementState": "Managed",
      "namespace": "redhat-ods-monitoring",
      "metrics": {},
      "traces": {
        "storage": {
          "backend": "pv",
          "size": "5Gi",
          "retention": "24h"
        }
      }
    }
  }
}'
~~~

#### 8-3. Prometheus Datasource 설정 (Product Gap 우회)

~~~bash
# service-ca ConfigMap 생성
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-web-tls-ca
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF

# PersesDatasource 생성
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: perses.dev/v1alpha2
kind: PersesDatasource
metadata:
  name: prometheus
spec:
  client:
    tls:
      enable: true
      caCert:
        type: configmap
        name: prometheus-web-tls-ca
        certPath: service-ca.crt
  config:
    default: true
    display:
      name: Prometheus (Thanos Querier)
    plugin:
      kind: PrometheusDatasource
      spec:
        proxy:
          kind: HTTPProxy
          spec:
            secret: prometheus-secret
            url: https://thanos-querier.openshift-monitoring.svc:9091
        scrapeInterval: 30s
EOF
~~~

#### 8-4. Perses Operator NetworkPolicy 추가

~~~bash
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-perses-operator
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: perses
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 8080
EOF
~~~

#### 8-5. COO UIPlugin 생성 (선택)

~~~bash
oc apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: monitoring
spec:
  type: Monitoring
  monitoring:
    perses:
      enabled: true
---
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: dashboards
spec:
  type: Dashboards
---
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: troubleshooting-panel
spec:
  type: TroubleshootingPanel
EOF
~~~

#### 8-6. OdhDashboardConfig 활성화

~~~bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications --type=merge \
  -p '{"spec":{"dashboardConfig":{"observabilityDashboard":true}}}'
~~~

## 검증

### 모니터링 검증

~~~bash
# 1) ServiceMonitor 존재
oc get servicemonitor -n ${MODEL_NS}
# 기대: ${MODEL_NAME}-metrics

# 2) Thanos에서 vLLM 메트릭 수집 확인
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query" \
  --data-urlencode "query={__name__=~\"vllm.*\",namespace=\"${MODEL_NS}\"}" | \
  python3 -c "import json,sys; print(f'vLLM 메트릭: {len(json.load(sys.stdin).get(\"data\",{}).get(\"result\",[]))}개')"
# 기대: 1개 이상

# 3) PrometheusRule 존재
oc get prometheusrule -n ${MODEL_NS}
# 기대: poc-gpu-alerts, vllm-alerts

# 4) AlertManagerConfig 존재
oc get alertmanagerconfig poc-alert-routing -n ${MODEL_NS}
~~~

### RBAC / 격리 검증

~~~bash
# 5) NetworkPolicy 4개
oc get networkpolicy -n ${MODEL_NS}
# 기대: deny-from-other-namespaces, allow-monitoring, allow-from-ingress, allow-from-rhoai

# 6) RBAC 역할 분리 (RoleBinding)
oc get rolebinding -n ${MODEL_NS} -o custom-columns=\
'NAME:.metadata.name,ROLE:.roleRef.name,USER:.subjects[0].name'
# 기대: poc-admin→admin, poc-operator→edit, poc-user→view

# 7) 외부 NS 접근 차단
oc run test-curl --rm -it --restart=Never -n default \
  --image=curlimages/curl -- \
  curl -s --max-time 5 \
  "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/models" 2>/dev/null
# 기대: 타임아웃 (차단)
~~~

### TrustyAI 검증

~~~bash
# 8) TrustyAI Service
oc get trustyaiservice -n ${MODEL_NS}
# 기대: phase=Ready

# 9) GuardrailsOrchestrator
oc get guardrailsorchestrator -n ${MODEL_NS}
# 기대: CR 존재

# 10) LMEvalJob 상태
oc get lmevaljob ${MODEL_NAME}-eval -n ${MODEL_NS} \
  -o jsonpath='{.status.state}: {.status.reason}'
echo ""
# 기대: Complete: Succeeded
~~~

### Observability Dashboard 검증

~~~bash
# 11) redhat-ods-monitoring Pod 상태
oc get pods -n redhat-ods-monitoring --no-headers
# 기대: data-science-perses-0, data-science-collector-collector-0, tempo-*-0 모두 Running

# 12) Perses Health
DASH_URL="https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')"
curl -sk "${DASH_URL}/perses/api/api/v1/health"
# 기대: {"database":true}

# 13) Perses Dashboards 목록
curl -sk "${DASH_URL}/perses/api/api/v1/dashboards" | \
  python3 -c "import json,sys; ds=json.load(sys.stdin); print(f'총 {len(ds)}개 대시보드')"
# 기대: 3개 이상

# 14) Prometheus Proxy 동작
TOKEN=$(oc whoami -t)
curl -sk -X POST \
  "${DASH_URL}/perses/api/proxy/projects/redhat-ods-monitoring/datasources/prometheus/api/v1/query" \
  -d 'query=up{namespace="redhat-ods-monitoring"}' \
  -H "Authorization: Bearer ${TOKEN}" | \
  python3 -c "import json,sys; r=json.load(sys.stdin); print(f'status: {r[\"status\"]}, results: {len(r.get(\"data\",{}).get(\"result\",[]))}')"
# 기대: status: success, results: 3+

# 15) PersesDatasource 상태
oc get persesdatasource -n redhat-ods-monitoring
# 기대: prometheus, tempo-datasource 모두 Available=True
~~~

성공 기준:
- ServiceMonitor + PrometheusRule + AlertManagerConfig 정상 생성
- NetworkPolicy 4개 적용, 외부 NS 트래픽 차단
- TrustyAI Service Ready, GuardrailsOrchestrator CR 존재
- Observability Dashboard(Perses) health 정상, 대시보드 3개 이상

## 실패 시

- **vLLM 메트릭 0개** → ServiceMonitor selector가 InferenceService 라벨과 일치하는지 확인. UWM Pod 3개가 Running인지 확인: `oc get pods -n openshift-user-workload-monitoring`
- **NetworkPolicy 적용 후 서빙 접근 불가** → `allow-from-ingress` 정책이 존재하는지 확인. Route를 통한 외부 접근은 ingress 네임스페이스 라벨 필요.
- **TrustyAI phase!=Ready** → TrustyAI Operator Pod 로그 확인. PVC 바인딩 실패 시 StorageClass 확인.
- **Guardrails /info에서 openai=UNHEALTHY** → `OPENAI_BASE_URL`이 `${MODEL_NAME}-metrics` Service를 가리키는지 확인. vLLM headless service가 아닌 metrics ClusterIP service 사용 필수.
- **LMEvalJob Pending** → CPU/Memory 부족 (싱글 노드 한계). Pod events 확인: `oc get events -n ${MODEL_NS} | grep lmeval`
- **redhat-ods-monitoring에 Pod 없음** → DSCI `monitoring.traces` 미설정 또는 3개 Operator(COO, Tempo, OpenTelemetry) 미설치. Step 8-1, 8-2 재확인.
- **Perses health 503** → `data-science-perses` Service/Pod 누락. DSCI에 `traces.storage.backend: pv` 설정 필요.
- **Prometheus proxy TLS 오류** → PersesDatasource `client.tls.caCert` 미설정 (Product Gap). Step 8-3 재수행.
- **PersesDashboard Available=False** → `allow-perses-operator` NetworkPolicy 누락. Step 8-4 재수행.
- **data-science-perses-0 Pending/FailedCreate** → SCC 권한 부족: `oc adm policy add-scc-to-user nonroot-v2 -z perses-sa -n redhat-ods-monitoring`. 또는 LimitRange min 값 과다 시 하향 조정.

## 다음 단계

→ `runbooks/75-platform-ops-validation.md` — 플랫폼 운영 검증 (S6)

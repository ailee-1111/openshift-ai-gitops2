# 110 — GPU 스택 (NFD + NVIDIA GPU Operator)

## 목적

Node Feature Discovery(NFD)와 NVIDIA GPU Operator를 설치하여 GPU 노드의 `nvidia.com/gpu` 리소스를 K8s 스케줄러에 등록하고, DCGM Exporter로 GPU 메트릭 수집을 활성화한다.

## 전제 조건

- [ ] GPU 노드 존재 (예: g6e.12xlarge, p5.48xlarge 등)
- [ ] `cluster-admin` 권한으로 로그인
- [ ] `runbooks/020-rhoai-operator-install.md` 완료

## 실행

### 1. NFD Operator 설치

> **주의**: NFD는 `openshift-operators`가 아닌 **전용 NS(`openshift-nfd`)**에 설치해야 한다.
> AllNamespaces OG에서는 `OwnNamespace InstallModeType not supported` 오류 발생.

~~~bash
oc create namespace openshift-nfd --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nfd-og
  namespace: openshift-nfd
spec:
  targetNamespaces:
    - openshift-nfd
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "NFD Operator 대기 (최대 5분)..."
sleep 30
oc wait csv -n openshift-nfd \
  -l operators.coreos.com/nfd.openshift-nfd \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=300s 2>/dev/null || \
  oc get csv -n openshift-nfd --no-headers | grep nfd
~~~

### 2. NodeFeatureDiscovery CR 생성

~~~bash
oc apply -f - <<'EOF'
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  operand:
    servicePort: 12000
  workerConfig:
    configData: |
      sources:
        pci:
          deviceClassWhitelist:
            - "0200"
            - "03"
            - "12"
          deviceLabelFields:
            - "vendor"
EOF

echo "NFD CR 생성 — 노드 레이블링 대기 (30초)..."
sleep 30
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: pci={.metadata.labels.feature\.node\.kubernetes\.io/pci-10de\.present}{"\n"}{end}'
# 기대: GPU 노드에 pci-10de.present=true 레이블
~~~

### 3. NVIDIA GPU Operator 설치

~~~bash
oc create namespace nvidia-gpu-operator --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
    - nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: v25.3
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "GPU Operator 대기 (최대 5분)..."
sleep 60
oc wait csv -n nvidia-gpu-operator \
  -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=300s 2>/dev/null || \
  oc get csv -n nvidia-gpu-operator --no-headers | grep gpu
~~~

### 4. ClusterPolicy 생성

> **주의**: `spec.daemonsets: {}` 필드가 필수. 없으면 validation 실패.

~~~bash
oc apply -f - <<'EOF'
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
  daemonsets: {}
  dcgmExporter:
    enabled: true
  driver:
    enabled: true
    use_ocp_driver_toolkit: true
  devicePlugin:
    enabled: true
  toolkit:
    enabled: true
  dcgm:
    enabled: true
  gfd:
    enabled: true
  nodeStatusExporter:
    enabled: true
EOF

echo "GPU 드라이버 빌드 대기 (최대 10분)..."
oc wait pod -n nvidia-gpu-operator \
  -l app=nvidia-driver-daemonset \
  --for=condition=Ready \
  --timeout=600s 2>/dev/null || \
  oc get pods -n nvidia-gpu-operator --no-headers | head -10
~~~

### 5. DCGM Exporter ServiceMonitor 생성

GPU Operator가 생성하는 기본 ServiceMonitor는 Operator Pod 메트릭만 수집한다. **DCGM Exporter 메트릭(GPU 사용률/온도/VRAM)은 별도 ServiceMonitor가 필요**하다.

~~~bash
oc apply -n nvidia-gpu-operator -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  labels:
    app: nvidia-dcgm-exporter
spec:
  endpoints:
    - port: gpu-metrics
      interval: 30s
      path: /metrics
  namespaceSelector:
    matchNames:
      - nvidia-gpu-operator
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
EOF

echo "DCGM ServiceMonitor 생성 — Prometheus 수집 시작까지 2~3분 소요"
~~~

### 6. GPU PrometheusRule 생성

~~~bash
oc apply -n "${POC_NAMESPACE:-rhoai-poc}" -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: poc-gpu-alerts
spec:
  groups:
    - name: gpu.alerts
      rules:
        - alert: GPUHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "GPU 온도 80°C 초과 ({{ $labels.gpu }})"
        - alert: GPUMemoryExhaustion
          expr: (DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) > 0.9
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "GPU VRAM 90% 초과 ({{ $labels.gpu }})"
        - alert: GPUHighUtilization
          expr: DCGM_FI_DEV_GPU_UTIL > 95
          for: 10m
          labels:
            severity: info
          annotations:
            summary: "GPU 사용률 95% 초과 지속 ({{ $labels.gpu }})"
EOF
~~~

## 검증

~~~bash
echo "=== 45 — GPU 스택 검증 ==="

# NFD
echo "NFD: $(oc get csv -n openshift-nfd --no-headers 2>/dev/null | grep nfd | awk '{print $1, $NF}')"

# GPU Operator
echo "GPU: $(oc get csv -n nvidia-gpu-operator --no-headers 2>/dev/null | grep gpu | awk '{print $1, $NF}')"

# GPU 리소스 등록
echo "GPU 노드:"
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: gpu={.status.capacity.nvidia\.com/gpu}, type={.metadata.labels.node\.kubernetes\.io/instance-type}{"\n"}{end}' | grep -v "gpu=$"

# DCGM Exporter
DCGM_PODS=$(oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter --no-headers 2>/dev/null | grep -c Running)
echo "DCGM Exporter: ${DCGM_PODS} Running"

# Prometheus DCGM 메트릭 수집
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
DCGM_COUNT=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" 2>/dev/null \
  | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('result',[])))" 2>/dev/null)
echo "Prometheus DCGM 메트릭: ${DCGM_COUNT:-0}개"

# PrometheusRule
echo "PrometheusRule:"
oc get prometheusrule -n "${POC_NAMESPACE:-rhoai-poc}" --no-headers | awk '{print "  "$1}'

echo "=== 검증 완료 ==="
~~~

## 실패 시

- **NFD CSV Failed (`AllNamespaces not supported`)** → 전용 NS(`openshift-nfd`) + OwnNamespace OG로 설치
- **ClusterPolicy validation 실패** → `spec.daemonsets: {}` 필드 필수
- **nvidia-driver-daemonset Init** → 드라이버 빌드 중 (5~10분 소요). `oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset -c openshift-driver-toolkit-ctr`로 진행 확인
- **GPU 미등록** → NFD worker Pod Running 확인: `oc get pods -n openshift-nfd -l app.kubernetes.io/component=worker`
- **DCGM 메트릭 Prometheus 미수집** → DCGM Exporter ServiceMonitor가 `nvidia-gpu-operator` NS에 생성되었는지 확인. Platform Prometheus 수집 시작까지 2~3분 소요. `oc get servicemonitor -n nvidia-gpu-operator` 확인

## 다음 단계

→ `runbooks/100-platform-setup.md` — 플랫폼 사전 구성

# 55 — Observability 대시보드 강화

## 목적

Perses 기반 커스텀 대시보드를 생성하여 GPU 상세 모니터링, vLLM 서빙 성능, 토큰 사용량(IN/OUT)을 시각화한다. RHOAI Dashboard `/observe-and-monitor/dashboard`에서 접근.

## 전제 조건

- [ ] DCGM ServiceMonitor 생성 완료 (runbooks/45 step 5)
- [ ] Perses Pod Running
- [ ] PersesDatasource `prometheus` 존재
- [ ] InferenceService 배포 완료 (vLLM 메트릭 수집 중)

## 실행

### 1. vLLM ServiceMonitor 확인

~~~bash
set -a && source .env && set +a
oc get servicemonitor -n "${MODEL_NS}" --no-headers | grep "${MODEL_NAME}"
# 없으면: InferenceService 배포 시 RHOAI가 자동 생성
~~~

### 2. NVIDIA GPU 상세 대시보드

> GPU별 사용률, VRAM, 온도, 전력, SM Clock, 메모리 대역폭.

~~~bash
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: perses.dev/v1alpha2
kind: PersesDashboard
metadata:
  name: nvidia-gpu-detailed
  labels:
    opendatahub.io/dashboard: "true"
spec:
  config:
    display:
      name: "NVIDIA GPU 상세 모니터링"
    duration: 1h
    refreshInterval: 30s
    variables:
      - kind: ListVariable
        spec:
          display:
            name: GPU
          plugin:
            kind: PrometheusLabelValuesVariable
            spec:
              datasource:
                kind: PrometheusDatasource
                name: prometheus
              labelName: gpu
              matchers:
                - "DCGM_FI_DEV_GPU_UTIL"
          name: gpu
    layouts:
      - kind: Grid
        spec:
          display:
            title: "GPU 개요"
          items:
            - x: 0
              y: 0
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/gpu_util"
            - x: 6
              y: 0
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/vram_used"
            - x: 0
              y: 3
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/gpu_temp"
            - x: 6
              y: 3
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/power_usage"
            - x: 0
              y: 6
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/sm_clock"
            - x: 6
              y: 6
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/mem_copy_util"
    panels:
      gpu_util:
        kind: Panel
        spec:
          display:
            name: "GPU 사용률 (%)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'DCGM_FI_DEV_GPU_UTIL{gpu=~"$gpu"}'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      vram_used:
        kind: Panel
        spec:
          display:
            name: "VRAM 사용량 (MiB)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'DCGM_FI_DEV_FB_USED{gpu=~"$gpu"}'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      gpu_temp:
        kind: Panel
        spec:
          display:
            name: "GPU 온도 (°C)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'DCGM_FI_DEV_GPU_TEMP{gpu=~"$gpu"}'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      power_usage:
        kind: Panel
        spec:
          display:
            name: "전력 소비 (W)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'DCGM_FI_DEV_POWER_USAGE{gpu=~"$gpu"}'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      sm_clock:
        kind: Panel
        spec:
          display:
            name: "SM Clock (MHz)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'DCGM_FI_DEV_SM_CLOCK{gpu=~"$gpu"}'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      mem_copy_util:
        kind: Panel
        spec:
          display:
            name: "메모리 대역폭 사용률 (%)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'DCGM_FI_DEV_MEM_COPY_UTIL{gpu=~"$gpu"}'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
EOF
echo "GPU 대시보드 생성 완료"
~~~

### 3. vLLM 서빙 성능 대시보드

> TTFT, ITL, E2E 레이턴시, TPS, KV Cache, 큐 대기, 에러율.

~~~bash
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: perses.dev/v1alpha2
kind: PersesDashboard
metadata:
  name: vllm-serving-metrics
  labels:
    opendatahub.io/dashboard: "true"
spec:
  config:
    display:
      name: "vLLM 서빙 성능"
    duration: 1h
    refreshInterval: 30s
    layouts:
      - kind: Grid
        spec:
          display:
            title: "레이턴시"
          items:
            - x: 0
              y: 0
              width: 4
              height: 3
              content:
                $ref: "#/spec/panels/ttft"
            - x: 4
              y: 0
              width: 4
              height: 3
              content:
                $ref: "#/spec/panels/itl"
            - x: 8
              y: 0
              width: 4
              height: 3
              content:
                $ref: "#/spec/panels/e2e"
      - kind: Grid
        spec:
          display:
            title: "처리량 및 큐"
          items:
            - x: 0
              y: 0
              width: 4
              height: 3
              content:
                $ref: "#/spec/panels/running"
            - x: 4
              y: 0
              width: 4
              height: 3
              content:
                $ref: "#/spec/panels/waiting"
            - x: 8
              y: 0
              width: 4
              height: 3
              content:
                $ref: "#/spec/panels/success"
      - kind: Grid
        spec:
          display:
            title: "KV Cache 및 토큰"
          items:
            - x: 0
              y: 0
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/kv_cache"
            - x: 6
              y: 0
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/tokens"
    panels:
      ttft:
        kind: Panel
        spec:
          display:
            name: "TTFT P95 (s)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      itl:
        kind: Panel
        spec:
          display:
            name: "ITL P95 (s)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'histogram_quantile(0.95, rate(vllm:inter_token_latency_seconds_bucket{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      e2e:
        kind: Panel
        spec:
          display:
            name: "E2E P95 (s)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'histogram_quantile(0.95, rate(vllm:e2e_request_latency_seconds_bucket{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      running:
        kind: Panel
        spec:
          display:
            name: "활성 요청"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(vllm:num_requests_running{namespace="rhoai-poc"})'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      waiting:
        kind: Panel
        spec:
          display:
            name: "대기 큐"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(vllm:num_requests_waiting{namespace="rhoai-poc"})'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      success:
        kind: Panel
        spec:
          display:
            name: "요청 성공률 (req/s)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(rate(vllm:request_success_total{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      kv_cache:
        kind: Panel
        spec:
          display:
            name: "KV Cache 사용률 (%)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'vllm:kv_cache_usage_perc{namespace="rhoai-poc"} * 100'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      tokens:
        kind: Panel
        spec:
          display:
            name: "토큰 생성률 (tokens/s)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(rate(vllm:generation_tokens_total{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
EOF
echo "vLLM 서빙 대시보드 생성 완료"
~~~

### 4. 토큰 사용량 IN/OUT 대시보드

> 모델별 입력(prompt) / 출력(generation) 토큰 사용량 추이.

~~~bash
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: perses.dev/v1alpha2
kind: PersesDashboard
metadata:
  name: token-usage
  labels:
    opendatahub.io/dashboard: "true"
spec:
  config:
    display:
      name: "토큰 사용량 (IN/OUT)"
    duration: 1h
    refreshInterval: 30s
    layouts:
      - kind: Grid
        spec:
          display:
            title: "토큰 처리량"
          items:
            - x: 0
              y: 0
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/prompt_rate"
            - x: 6
              y: 0
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/gen_rate"
            - x: 0
              y: 3
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/prompt_total"
            - x: 6
              y: 3
              width: 6
              height: 3
              content:
                $ref: "#/spec/panels/gen_total"
            - x: 0
              y: 6
              width: 12
              height: 3
              content:
                $ref: "#/spec/panels/queue_time"
    panels:
      prompt_rate:
        kind: Panel
        spec:
          display:
            name: "입력 토큰 (tokens/s, IN)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(rate(vllm:request_prompt_tokens_sum{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      gen_rate:
        kind: Panel
        spec:
          display:
            name: "출력 토큰 (tokens/s, OUT)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(rate(vllm:generation_tokens_total{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      prompt_total:
        kind: Panel
        spec:
          display:
            name: "입력 토큰 누적 (IN)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(vllm:request_prompt_tokens_sum{namespace="rhoai-poc"})'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      gen_total:
        kind: Panel
        spec:
          display:
            name: "출력 토큰 누적 (OUT)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'sum(vllm:generation_tokens_total{namespace="rhoai-poc"})'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
      queue_time:
        kind: Panel
        spec:
          display:
            name: "큐 대기시간 P95 (s)"
          plugin:
            kind: TimeSeriesChart
            spec: {}
          queries:
            - kind: TimeSeriesQuery
              spec:
                plugin:
                  kind: PrometheusTimeSeriesQuery
                  spec:
                    query: 'histogram_quantile(0.95, rate(vllm:request_queue_time_seconds_bucket{namespace="rhoai-poc"}[5m]))'
                    datasource:
                      kind: PrometheusDatasource
                      name: prometheus
EOF
echo "토큰 사용량 대시보드 생성 완료"
~~~

### 5. llm-d 라우팅 대시보드 (InferencePool 배포 후)

> llm-d InferencePool 메트릭은 InferencePool CR 배포 후 수집 가능. 시나리오 런북(62)에서 배포.

~~~bash
echo "=== llm-d CRD 확인 ==="
oc api-resources | grep -i inferencepool
oc api-resources | grep -i httproute
echo ""
echo "InferencePool 배포 후 아래 메트릭 기반 대시보드 생성 가능:"
echo "  - inference_pool_request_total"
echo "  - inference_pool_request_duration_seconds"
echo "  - inference_pool_active_connections"
~~~

## 검증

~~~bash
echo "=== 55 — 대시보드 검증 ==="
oc get persesdashboard -n redhat-ods-monitoring --no-headers
echo ""
echo "RHOAI Dashboard에서 확인:"
echo "https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')/observe-and-monitor/dashboard"
~~~

## 실패 시

- **PersesDashboard 생성 실패** → Perses Pod Running 확인. CRD 존재: `oc get crd | grep persesdashboard`
- **대시보드에 데이터 없음** → PersesDatasource `prometheus` 확인. ServiceMonitor 존재 확인
- **DCGM 메트릭 0** → `oc get servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator`

## 다음 단계

→ `runbooks/60-model-serving.md` — S1 모델 서빙 구축

# 220 — Observability 대시보드 강화

## 목적

RHOAI Dashboard Observe & Monitor 메뉴에 GPU/vLLM/Tokens 커스텀 Perses 대시보드를 추가하여 GPU 상세 모니터링, 서빙 성능, 모델별 토큰 사용량을 시각화한다.

## 전제 조건

- [ ] `runbooks/110-gpu-stack.md` 완료 — DCGM ServiceMonitor + PrometheusRule 생성
- [ ] Perses Pod Running, PersesDatasource `prometheus` 존재
- [ ] **perses-operator Pod Running** — `oc get pods -n openshift-cluster-observability-operator -l app.kubernetes.io/name=perses-operator`. replicas=0이면 `oc scale deployment perses-operator -n openshift-cluster-observability-operator --replicas=1`로 복구. COO+RHOAI 경합 시 replicas=0으로 축소될 수 있음 (CPU 과점유 방지 목적). 복구 후 CPU 모니터링: `oc adm top pods -n openshift-cluster-observability-operator`
- [ ] InferenceService 배포 완료 (vLLM 메트릭 수집 중)
- [ ] `observabilityDashboard: true` (OdhDashboardConfig)

## RHOAI Dashboard Perses 대시보드 규칙

> 이 규칙을 지키지 않으면 RHOAI Dashboard UI에서 대시보드가 보이지 않는다.

| 항목 | 필수 값 | 비고 |
|------|--------|------|
| CR 이름 | **`dashboard-N-<name>`** | N은 정렬 순서 (0부터) |
| 라벨 | `app.opendatahub.io/dashboard: "true"` | **`opendatahub.io/dashboard`가 아님** |
| 라벨 | `app.kubernetes.io/part-of: dashboard` | |
| 어노테이션 | `opendatahub.io/dashboard-feature-visibility: '[]'` | |
| 스펙 | **`spec.config`** (spec.spec 아님) | |
| 그리드 | **24열** 기준, 높이 **4/8 단위** | RHOAI 기본 대시보드와 동일 |
| Namespace | `redhat-ods-monitoring` | |

## 실행

### 1. vLLM ServiceMonitor 확인

~~~bash
set -a && source .env && set +a
oc get servicemonitor -n "${MODEL_NS}" --no-headers | grep "${MODEL_NAME}"
~~~

### 2. GPU 대시보드 (18패널, 5그룹)

~~~bash
oc apply -f infra/rhoai/dashboards/dashboard-4-gpu.yaml
~~~

패널 구성:

| 그룹 | 패널 | 타입 |
|------|------|------|
| 현재 상태 요약 | GPU 사용률, VRAM 사용률, 최고 온도, 총 전력 | StatChart ×4 |
| 컴퓨팅 사용률 | GPU 사용률, 인코더, 디코더 | TimeSeriesChart ×3 |
| 메모리 (VRAM) | VRAM 사용/여유, 대역폭, Memory Clock | TimeSeriesChart ×3 |
| 열/전력 | GPU 온도, 메모리 온도, 전력, SM Clock | TimeSeriesChart ×4 |
| 에러 | XID, PCIe Replay, NVLink, 에너지 | TimeSeriesChart ×4 |

### 3. vLLM 대시보드 (18패널, 5그룹, Model/Namespace 필터)

~~~bash
oc apply -f infra/rhoai/dashboards/dashboard-5-vllm.yaml
~~~

패널 구성:

| 그룹 | 패널 | 타입 |
|------|------|------|
| 핵심 지표 | TTFT P95, ITL P95, 처리량, KV Cache, 토큰 t/s, 총 요청 | StatChart ×6 |
| Latency | TTFT P50/P95/P99, ITL P50/P95/P99, E2E P50/P95/P99 | TimeSeriesChart ×3 |
| Traffic | 활성/대기 요청, 모델별 req/s, 토큰 IN/OUT | TimeSeriesChart ×3 |
| Saturation | KV Cache, 큐 대기 P50/P95, Prefill P50/P95 | TimeSeriesChart ×3 |
| 분포/연산 | E2E 레이턴시 분포, GPU FLOPS/Read, 토큰당 시간 | BarChart ×1 + TimeSeriesChart ×2 |

변수: **Model** (model_name), **Namespace** 드롭다운 필터

### 4. Tokens 대시보드 (10패널, 4그룹, Model/Namespace 필터)

~~~bash
oc apply -f infra/rhoai/dashboards/dashboard-6-tokens.yaml
~~~

패널 구성:

| 그룹 | 패널 | 타입 |
|------|------|------|
| 요약 | 입력 t/s, 출력 t/s, 총 요청, 총 토큰 (IN+OUT) | StatChart ×4 |
| 모델별 사용량 | 모델별 토큰 Table (IN/OUT/요청 수) | Table ×1 |
| 토큰 추이 | 모델별 Rate IN/OUT, 모델별 누적 IN/OUT | TimeSeriesChart ×2 |
| 요청 분석 | 요청당 입력 토큰 P50/P95, 토큰당 시간 P50/P95, 모델별 성공률 | TimeSeriesChart ×3 |

변수: **Model** (model_name), **Namespace** 드롭다운 필터

### 5. Usage 대시보드 TelemetryPolicy (MaaS 활성화 후)

> MaaS가 `dashboard-3-maas-usage-admin` PersesDashboard를 `redhat-ods-applications`에 자동 생성하지만,
> TelemetryPolicy 없이는 Limitador 메트릭에 `user`/`subscription`/`model` 라벨이 생성되지 않아 대시보드가 빈 화면이다.

~~~bash
oc apply -f infra/rhoai/observability/telemetry-policy.yaml
~~~

적용 후 검증:

~~~bash
# TelemetryPolicy 상태 확인
oc get telemetrypolicy maas-usage-telemetry -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Enforced")].status}'
# 기대값: True

# WasmPlugin에 라벨 주입 확인
oc get wasmplugin kuadrant-maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.pluginConfig.requestData}' | python3 -m json.tool
# 기대값: metrics.labels.user, metrics.labels.subscription, metrics.labels.model 3개 키

# 추론 요청 1회 후 Limitador 메트릭 라벨 확인
LIMITADOR_POD=$(oc get pod -n kuadrant-system -l app=limitador -o name | head -1)
oc exec -n kuadrant-system ${LIMITADOR_POD} -- curl -s http://localhost:8080/metrics | grep authorized_hits
# 기대값: authorized_hits{user="...",subscription="...",model="...",limitador_namespace="..."} > 0
~~~

### 6. llm-d 라우팅 대시보드 (InferencePool 배포 후)

~~~bash
oc api-resources | grep -i inferencepool
# InferencePool 배포 후 메트릭 기반 대시보드 추가 가능
~~~

## 검증

~~~bash
echo "=== 55 — 대시보드 검증 ==="
oc get persesdashboard -n redhat-ods-monitoring --no-headers

echo ""
echo "RHOAI Dashboard:"
echo "https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')/observe-and-monitor/dashboard"
echo ""
echo "드롭다운에 Cluster / Models / GPU / vLLM / Tokens 5개 표시 (redhat-ods-monitoring)"
echo "Usage 대시보드는 redhat-ods-applications NS에 별도 존재 (MaaS 자동 생성)"
echo ""
echo "Usage 대시보드 (MaaS):"
echo "https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')/observe-and-monitor/dashboard"
echo "→ Usage 선택 후 User/Subscription/Model 드롭다운 및 Token Consumption 테이블 확인"
~~~

## 실패 시

- **대시보드 드롭다운에 안 보임** → CR 이름이 `dashboard-N-` 접두사인지 확인. 라벨 `app.opendatahub.io/dashboard: "true"` (NOT `opendatahub.io/dashboard`) 확인
- **패널 비율 쪼그라듦** → 24열 그리드 기준 확인. width 합이 24, height는 4 또는 8
- **데이터 없음 / "No matching datasource found"** → (1) `oc get persesdatasource prometheus -n redhat-ods-monitoring` 없으면 step 16 실행 (2) `prometheus-secret` Secret 없으면 Thanos Querier 인증 실패 — `oc create token default -n redhat-ods-monitoring --duration=87600h`로 SA 토큰 생성 후 Secret 생성 (3) `default` SA에 `cluster-monitoring-view` ClusterRole 부여 필요 (4) Perses Pod 재시작: `oc delete pod data-science-perses-0 -n redhat-ods-monitoring`
- **"tls: certificate signed by unknown authority"** → `prometheus-web-tls-ca` ConfigMap의 `service-ca.crt` 키 확인. 없으면 `service.beta.openshift.io/inject-cabundle: "true"` 어노테이션 확인 후 ConfigMap 재생성
- **DCGM 메트릭 0** → `oc get servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator`
- **Usage 대시보드 빈 화면** → TelemetryPolicy 미적용. `oc apply -f infra/rhoai/observability/telemetry-policy.yaml` 실행 → WasmPlugin에 `requestData` 주입 확인 → 추론 요청 1회 이상 전송 후 30초 대기 (Prometheus 스크래핑 주기). 전제: `kuadrant-prometheus-datasource` Secret + SA + Limitador ServiceMonitor + `kuadrant-system` NS 모니터링 라벨이 이미 설정되어 있어야 함
- **Usage 대시보드 — model 라벨 누락** → TelemetryPolicy에 `model: auth.identity.subscription_info.modelRefs[0].name` 추가. MaaS API subscription-info 응답의 `modelRefs[].name` 필드에서 추출
- **Perses CPU 폭주 (COO + RHOAI 무한 루프)** → COO Perses Operator와 RHOAI Dashboard Controller가 동일한 PersesDashboard CR(`dashboard-0-cluster-admin`, `dashboard-1-model`)을 서로 다르게 정규화하여 초당 3~4회 GET→PUT을 반복. `oc get persesdashboard -n redhat-ods-monitoring -o custom-columns='NAME:.metadata.name,GEN:.metadata.generation'`으로 generation이 수천 이상이면 이 문제. 해결: `oc scale deployment perses-operator -n openshift-cluster-observability-operator --replicas=0` (COO 관리 대시보드는 이미 생성되어 영향 없음). 근본 원인: RHOAI 3.4 + COO 1.4의 아키텍처 충돌 — 두 Operator가 동일 CR을 Watch하고 각자 Perses 인스턴스에 동기화하며 정규화 차이 발생. COO 1.4에는 네임스페이스 제외 설정이 없음
- **trustyai-metrics down** → port `http` → `metrics` 일치, path `/q/metrics` → `/metrics`, `allow-monitoring` NP 필요
- **ds-pipeline-dspa 400** → ServiceMonitor에 `scheme: https` + `tlsConfig.insecureSkipVerify: true` 패치: `oc patch servicemonitor ds-pipeline-dspa -n ${MODEL_NS} --type='json' -p='[{"op":"add","path":"/spec/endpoints/0/scheme","value":"https"},{"op":"add","path":"/spec/endpoints/0/tlsConfig","value":{"insecureSkipVerify":true}}]'`. 주의: DSPA operator가 SM을 관리하므로 operator 업그레이드 시 패치 리셋 가능

## 확장 아이디어

### 토큰 사용량 → 비용 환산 대시보드

토큰 소비량을 금액(USD)으로 환산하여 모델별·사용자별·구독별 비용을 시각화할 수 있다.

**구현 방법:**

1. **PrometheusRule (Recording Rule)** — `kuadrant-system`에 비용 메트릭 사전 계산
   - `maas:token_cost_usd:rate1h = increase(authorized_hits{user!=""}[1h]) * 단가 / 1000`
   - 모델별 단가가 다르면 PromQL 조건 분기 또는 label_replace 활용
   - 알림(Alert) 연동 가능 (예: 일일 비용 임계치 초과 시 알림)

2. **커스텀 Perses 대시보드** — `dashboard-7-cost.yaml`을 `redhat-ods-monitoring`에 배치
   - Recording Rule 메트릭을 참조하여 StatChart(총 비용), Table(사용자별), TimeSeries(추이) 구성
   - MaaS controller 관리 대상이 아니므로 덮어씌워지지 않음

**고려 사항:**
- 모델별 토큰 단가 관리: ConfigMap 또는 PromQL 상수로 정의
- 다중 모델 시 단가 테이블 필요 (모델 추가 시 Recording Rule 업데이트)
- 환율 적용이 필요하면 별도 상수 또는 외부 연동

## 다음 단계

→ `runbooks/300-model-serving.md` — S1 모델 서빙 구축

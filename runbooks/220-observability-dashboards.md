# 220 — Observability 대시보드 강화

## 목적

RHOAI Dashboard Observe & Monitor 메뉴에 GPU/vLLM/Tokens 커스텀 Perses 대시보드를 추가하여 GPU 상세 모니터링, 서빙 성능, 모델별 토큰 사용량을 시각화한다.

## 전제 조건

- [ ] `runbooks/110-gpu-stack.md` 완료 — DCGM ServiceMonitor + PrometheusRule 생성
- [ ] Perses Pod Running, PersesDatasource `prometheus` 존재
- [ ] **perses-operator Pod Running** — `oc get pods -n openshift-cluster-observability-operator -l app.kubernetes.io/name=perses-operator`. replicas=0이면 `oc scale deployment perses-operator -n openshift-cluster-observability-operator --replicas=1`로 복구. **replicas=0으로 두면 안 됨** (OLM CSV unhealthy → DSC DashboardReady=False 연쇄). COO+RHOAI 경합 시 ownerRef 제거로 해결 (아래 트러블슈팅 참조). 복구 후 CPU 모니터링: `oc adm top pods -n openshift-cluster-observability-operator`. dashboard-0/1의 generation이 다시 증가하면 ownerRef 재부착 의심 → `oc get persesdashboard -n redhat-ods-monitoring -o custom-columns='NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind,GEN:.metadata.generation'`
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
- **데이터 없음 / "Forbidden" / 401 Unauthorized** → Perses Datasource SA 토큰 문제. 아래 순서로 해결:
  1. **비만료 SA 토큰 Secret 생성** (단일 Master 환경에서 `oc create token --duration`으로 생성한 토큰은 API 재시작 시 무효화될 수 있음):
     ```bash
     oc apply -f - <<EOF
     apiVersion: v1
     kind: Secret
     metadata:
       name: perses-thanos-token
       namespace: redhat-ods-monitoring
       annotations:
         kubernetes.io/service-account.name: data-science-prometheus-cluster-proxy
     type: kubernetes.io/service-account-token
     EOF
     ```
  2. **SA에 cluster-admin 부여** (cluster-monitoring-view만으로는 부족할 수 있음):
     ```bash
     oc adm policy add-cluster-role-to-user cluster-admin -z data-science-prometheus-cluster-proxy -n redhat-ods-monitoring
     oc adm policy add-cluster-role-to-user cluster-admin -z default -n redhat-ods-monitoring
     ```
  3. **prometheus-secret에 비만료 토큰 동기화**:
     ```bash
     LONG_TOKEN=$(oc get secret perses-thanos-token -n redhat-ods-monitoring -o jsonpath='{.data.token}' | base64 -d)
     oc get secret prometheus-secret -n redhat-ods-monitoring -o json | \
       python3 -c "import sys,json,base64; d=json.load(sys.stdin); d['data']['Authorization']=base64.b64encode(f'Bearer $LONG_TOKEN'.encode()).decode(); d['metadata'].pop('resourceVersion',None); json.dump(d,sys.stdout)" | \
       oc replace -f -
     ```
  4. **Perses Pod 재시작**: `oc delete pod perses-0 -n openshift-cluster-observability-operator`
- **vLLM 메트릭 안 나옴** → `customer-poc` NS에 `openshift.io/cluster-monitoring: true` 라벨이 있으면 UWM에서 제외됨. 라벨 제거: `oc label ns customer-poc openshift.io/cluster-monitoring-`. 제거 후 UWM이 ServiceMonitor를 자동 수집 시작 (1~2분 소요). 주의: DSCI Operator가 이 라벨을 다시 추가할 수 있으므로, 재적용 시 반복 필요
- **vLLM 메트릭 이름 불일치** → vLLM 0.18+에서 메트릭 이름이 `vllm_`(밑줄)가 아닌 `vllm:`(콜론)으로 변경됨. 대시보드 쿼리가 `vllm:num_requests_running` 형식을 사용하는지 확인
- **"tls: certificate signed by unknown authority"** → `prometheus-web-tls-ca` ConfigMap의 `service-ca.crt` 키 확인. 없으면 `service.beta.openshift.io/inject-cabundle: "true"` 어노테이션 확인 후 ConfigMap 재생성
- **DCGM 메트릭 0** → `oc get servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator`
- **Usage 대시보드 빈 화면** → TelemetryPolicy 미적용. `oc apply -f infra/rhoai/observability/telemetry-policy.yaml` 실행 → WasmPlugin에 `requestData` 주입 확인 → 추론 요청 1회 이상 전송 후 30초 대기 (Prometheus 스크래핑 주기). 전제: `kuadrant-prometheus-datasource` Secret + SA + Limitador ServiceMonitor + `kuadrant-system` NS 모니터링 라벨이 이미 설정되어 있어야 함
- **Usage 대시보드 — model 라벨 누락** → TelemetryPolicy에 `model: auth.identity.subscription_info.modelRefs[0].name` 추가. MaaS API subscription-info 응답의 `modelRefs[].name` 필드에서 추출
- **Perses CPU 폭주 (COO + RHOAI 무한 루프)** → RHOAI Dashboard Controller가 `dashboard-0-cluster-admin`, `dashboard-1-model` PersesDashboard CR을 `v1alpha1` API로 PUT → COO conversion webhook이 `v1alpha2`로 변환 → COO perses-operator가 Watch에서 변경 감지하여 Perses 인스턴스에 동기화(PUT) → ownerRef Watch가 RHOAI에 변경 이벤트 전달 → RHOAI가 다시 reconcile → 초당 3~5회 무한 루프. 진단: `oc get persesdashboard -n redhat-ods-monitoring -o custom-columns='NAME:.metadata.name,GEN:.metadata.generation'` (generation 수천 이상이면 확정). **해결: dashboard-0, dashboard-1의 ownerReferences 제거** — `oc get persesdashboard <name> -n redhat-ods-monitoring -o json`으로 export → ownerReferences/managedFields 삭제 → `oc replace -f`로 교체. ownerRef 제거 시 RHOAI Watch 트리거가 해제되어 피드백 루프 차단. perses-operator replicas=0은 사용 금지 (OLM CSV unhealthy → DSC DashboardReady=False 연쇄). IaC `infra/rhoai/dashboards/dashboard-0-cluster-admin.yaml`, `dashboard-1-model.yaml`에서도 ownerReferences 삭제 필수. 근본 원인: RHOAI 3.4가 deprecated v1alpha1 API 사용 (GitHub Issue #3550, RHOAIENG-62730)
- **trustyai-metrics down** → port `http` → `metrics` 일치, path `/q/metrics` → `/metrics`, `allow-monitoring` NP 필요
- **ds-pipeline-dspa 400** → ServiceMonitor에 `scheme: https` + `tlsConfig.insecureSkipVerify: true` 패치: `oc patch servicemonitor ds-pipeline-dspa -n ${MODEL_NS} --type='json' -p='[{"op":"add","path":"/spec/endpoints/0/scheme","value":"https"},{"op":"add","path":"/spec/endpoints/0/tlsConfig","value":{"insecureSkipVerify":true}}]'`. 주의: DSPA operator가 SM을 관리하므로 operator 업그레이드 시 패치 리셋 가능

### 7. MaaS Token Metrics 대시보드 (10패널)

~~~bash
oc apply -f infra/poc/monitoring/perses-maas-token-metrics.yaml
~~~

| 그룹 | 패널 |
|------|------|
| Overview | 총 Hits, 구독별 Hits, 활성 사용자, 추정 비용 |
| 구독별 추이 | Hits Rate, 사용자별 Hits, 시간당 사용량 |
| 총량 | 구독별 누적 Hits |
| 상세 | 메트릭 테이블 (user/subscription/namespace) |

### 8. MaaS Usage Trend 대시보드 (19패널)

~~~bash
oc apply -f infra/poc/monitoring/perses-maas-usage-trend.yaml
~~~

| 그룹 | 패널 | 기간 |
|------|------|:----:|
| Summary | 누적/오늘/이번주/활성사용자/활성구독 | - |
| 시간대별 | 전체/사용자별/구독별 | 실시간 |
| 일별 | 전체/사용자별/모델별 | 최대 90일 |
| 주별 | 전체/사용자별/구독별 | 최대 12주 |
| 월별 | 전체/사용자별/모델별 | 최근 3개월 |
| 피크 | 사용률 (5분 평균 hits/s) | 실시간 |

> UWM Prometheus 보존 기간: 90일 (`user-workload-monitoring-config`에서 `retention: 90d` + PVC 30Gi 설정)

## Customer 클러스터 실측 (2026-05-20)

| 대시보드 | 상태 | 비고 |
|---------|:----:|------|
| dashboard-0-cluster-admin | 정상 | RHOAI 기본 |
| dashboard-1-model | 정상 | RHOAI 기본 |
| dashboard-3-maas-usage-admin | 정상 | MaaS 자동 생성 |
| dashboard-4-gpu | 정상 | DCGM 10 시리즈 |
| dashboard-5-vllm | 정상 | vllm: 메트릭 수집 중 |
| dashboard-6-tokens | 정상 | |
| dashboard-7-apikey-usage | 정상 | authorized_hits 기반 |
| dashboard-8-maas-token-metrics | 정상 | 구독별 사용량 |
| dashboard-9-maas-usage-trend | 정상 | 시간/일/주/월 트렌드 |

### 트러블슈팅 이력

| 날짜 | 이슈 | 원인 | 해결 |
|------|------|------|------|
| 2026-05-20 | Forbidden 에러 | `redhat-ods-monitoring:default` SA 권한 부족 | cluster-admin 부여 |
| 2026-05-20 | Perses→Thanos 401 | SA 토큰 만료 (API 재시작으로 무효화) | 비만료 SA 토큰 Secret 생성 |
| 2026-05-20 | vLLM 메트릭 0 | `cluster-monitoring: true` 라벨로 UWM 제외 | 라벨 제거 |
| 2026-05-20 | vLLM 메트릭 이름 불일치 | vLLM 0.18+ `vllm:` (콜론) 형식 | 대시보드 쿼리 확인 |
| 2026-05-22 | Perses Operator 133회 재시작 | COO 1.4 + RHOAI 3.4 무한 reconcile (dashboard generation 54만+) + CPU 500m 한계 + datasource 충돌 | datasource default 충돌 해소 (IaC prometheus→default:false). operator 0 스케일 시 RHOAI DSC Ready=False 유발 → 스케일 복구 필수 |
| 2026-05-23 | Perses 무한 reconcile 근본 해결 | RHOAI v1alpha1 API PUT → COO v1alpha2 변환 + ownerRef Watch 피드백 루프 (초당 5회, generation 63만+, perses-0 CPU 1,157m) | dashboard-0, dashboard-1의 ownerReferences 제거 (`oc replace`). IaC 반영 완료. perses-0 CPU 1,157m→1m, generation 정지. replicas=0 방식은 OLM 연쇄 unhealthy 유발하므로 사용 금지 |
| 2026-05-22 | Perses datasource 충돌 | IaC `prometheus`와 RHOAI `cluster-prometheus-datasource` 모두 `default:true` | IaC `perses-datasource.yaml`의 `default`를 `false`로 변경. RHOAI 관리 datasource가 default 유지 |
| 2026-05-22 | Perses 대시보드 Unauthorized | `cluster-prometheus-datasource` spec 토큰과 Secret 토큰 불일치 (RHOAI가 Secret 재생성) | CR spec에 최신 Secret 토큰 반영 + operator 일시 스케일업으로 Perses backend 동기화 |
| 2026-05-22 | ds-pipeline-dspa Down | ServiceMonitor HTTP → Service HTTPS 불일치 (serving-cert TLS) | `scheme:https` + `tlsConfig.insecureSkipVerify:true` 패치. DSPA operator가 리셋 가능 |
| 2026-05-22 | istio-pod-monitor Down | PodMonitor port 미지정 + relabeling regex 이중 이스케이프(`\\\\d+`) → 15021(status port)로 fallback, 404 반환 | port를 `metrics`(15020)로 명시 지정 + 이중 이스케이프 relabeling 규칙 제거. Kuadrant operator 재생성 가능 |
| 2026-05-22 | trustyai-metrics Down | TrustyAI 서비스 미배포 (operator만 존재). SM의 `/q/metrics` 경로에 404 | 정상 상태 (TrustyAI 서비스 배포 시 자동 해소). RHOAI 자동생성 SM이므로 삭제 불가 |
| 2026-05-22 | RHOAI Dashboard/MaaS UI 미노출 | perses-operator 0 스케일 → conversion webhook 부재 → DSC DashboardReady=False, ModelsAsServiceReady=False | perses-operator 스케일 복구 + RHOAI operator 재시작으로 전체 reconcile. **주의: replicas=0은 해결책이 아님** — ownerRef 제거 방식으로 전환 (2026-05-23) |
| 2026-05-23 | maas-api-key-cleanup 15분마다 실패 | CronJob이 `http://maas-api:8080`으로 호출하지만 maas-api Pod는 `SECURE=true`로 HTTPS 8443만 리슨 (8080 미오픈). RHOAI operator 버그 | 원본 CronJob suspend + HTTPS 버전 신규 생성 (`maas-api-key-cleanup-https`, `curl -skf https://maas-api:8443`, `restartPolicy:Never`, `activeDeadlineSeconds:120`). operator가 원본 suspend를 해제할 수 있으므로 모니터링 필요 |

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

# 55 — Observability 대시보드 강화

## 목적

RHOAI Dashboard Observe & Monitor 메뉴에 GPU/vLLM/Tokens 커스텀 Perses 대시보드를 추가하여 GPU 상세 모니터링, 서빙 성능, 모델별 토큰 사용량을 시각화한다.

## 전제 조건

- [ ] `runbooks/45-gpu-stack.md` 완료 — DCGM ServiceMonitor + PrometheusRule 생성
- [ ] Perses Pod Running, PersesDatasource `prometheus` 존재
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

### 5. llm-d 라우팅 대시보드 (InferencePool 배포 후)

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
echo "드롭다운에 Cluster / Models / Usage / GPU / vLLM / Tokens 6개 표시되어야 함"
~~~

## 실패 시

- **대시보드 드롭다운에 안 보임** → CR 이름이 `dashboard-N-` 접두사인지 확인. 라벨 `app.opendatahub.io/dashboard: "true"` (NOT `opendatahub.io/dashboard`) 확인
- **패널 비율 쪼그라듦** → 24열 그리드 기준 확인. width 합이 24, height는 4 또는 8
- **데이터 없음** → PersesDatasource `prometheus` 존재 확인. ServiceMonitor 확인
- **DCGM 메트릭 0** → `oc get servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator`

## 다음 단계

→ `runbooks/60-model-serving.md` — S1 모델 서빙 구축

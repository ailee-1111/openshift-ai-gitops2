# 368 — Sprint 8: MaaS Observability 설정 (Kuadrant + Telemetry)

## 목적

MaaS 사용량 모니터링을 위해 Kuadrant Observability와 Tenant Telemetry를 활성화하고, Prometheus에서 MaaS 메트릭이 수집되는지 확인한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.10.2 (Enable Kuadrant observability), §1.10.3 (Enable telemetry)

## 전제 조건

- [ ] `runbooks/367-maas-api-key.md` 완료 — API Key로 추론 성공
- [ ] COO (Cluster Observability Operator) 설치 완료 (`runbooks/100-platform-setup.md` step 5)
- [ ] DSCI observability 설정 완료

## 실행

### 1. Kuadrant Observability 활성화

Limitador PodMonitor를 생성하여 Prometheus가 rate-limiting 메트릭을 수집하도록 한다.

~~~bash
oc patch kuadrant kuadrant -n kuadrant-system \
  --type merge \
  -p '{"spec":{"observability":{"enable":true}}}'

echo "PodMonitor 생성 대기..."
for i in $(seq 1 12); do
  if oc get podmonitor kuadrant-limitador-monitor -n kuadrant-system &>/dev/null; then
    echo "[PASS] kuadrant-limitador-monitor PodMonitor 생성 완료"
    break
  fi
  sleep 5
done
~~~

### 2. Kuadrant Observability 확인

~~~bash
echo "1) Kuadrant observability 설정:"
oc get kuadrant kuadrant -n kuadrant-system \
  -o jsonpath='{.spec.observability.enable}'
echo ""

echo "2) PodMonitor:"
oc get podmonitor kuadrant-limitador-monitor -n kuadrant-system --no-headers
~~~

### 3. Tenant Telemetry 활성화

~~~bash
oc patch tenant default-tenant -n models-as-a-service \
  --type merge \
  -p '{
    "spec": {
      "telemetry": {
        "enabled": true,
        "metrics": {
          "captureOrganization": true,
          "captureUser": false,
          "captureGroup": false,
          "captureModelUsage": true
        }
      }
    }
  }'
echo "[PASS] Tenant telemetry 활성화"
~~~

### 4. Telemetry 설정 확인

~~~bash
echo "=== Telemetry 설정 ==="
oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.spec.telemetry}' | python3 -m json.tool
~~~

### 5. (선택) 사용자별 메트릭 활성화

> 주의: 사용자 수가 많으면 Prometheus 카디널리티가 크게 증가한다.

~~~bash
# oc patch tenant default-tenant -n models-as-a-service \
#   --type merge \
#   -p '{"spec":{"telemetry":{"metrics":{"captureUser":true}}}}'
echo "[INFO] captureUser는 기본 false. 대규모 환경에서는 비권장"
~~~

### 6. 메트릭 수집 트리거 (테스트 요청)

메트릭이 나타나려면 실제 요청이 필요하다.

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
: "${MAAS_API_KEY:?MAAS_API_KEY 미설정 — Sprint 7에서 생성}"
: "${MODEL_NAME:=granite-2b}"

echo "메트릭 트리거 요청 5회..."
for i in $(seq 1 5); do
  CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"ibm-granite/granite-3.1-2b-instruct","messages":[{"role":"user","content":"test"}],"max_tokens":10}')
  echo "  요청 ${i}: HTTP ${CODE}"
  sleep 2
done
~~~

## 검증

~~~bash
echo "=== Sprint 8 검증 ==="

echo "1) Kuadrant observability:"
oc get kuadrant kuadrant -n kuadrant-system \
  -o jsonpath='{.spec.observability.enable}'
echo ""

echo "2) PodMonitor 존재:"
oc get podmonitor kuadrant-limitador-monitor -n kuadrant-system --no-headers

echo "3) Tenant telemetry 설정:"
oc get tenant default-tenant -n models-as-a-service \
  -o jsonpath='{.spec.telemetry.enabled}'
echo ""

echo "4) Prometheus 메트릭 확인 (수동):"
echo "  OpenShift Console → Observe → Metrics"
echo "  쿼리: authorized_calls"
echo "  쿼리: limited_calls"
echo "  쿼리: authorized_hits"
~~~

## 실패 시

- **PodMonitor 미생성** → Kuadrant CR 상태 확인, COO 설치 확인
- **메트릭 미수집** → 요청이 한 번도 발생하지 않으면 메트릭이 나타나지 않음 (정상)
- **Prometheus 타겟 미발견** → `oc get podmonitor -n kuadrant-system -o yaml` 확인, ServiceMonitor selector 매칭 확인

## 다음 단계

→ `runbooks/369-maas-dashboard-export.md`

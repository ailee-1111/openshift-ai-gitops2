# 369 — Sprint 9: MaaS Observability Dashboard 및 CSV Export

## 목적

MaaS Observability Dashboard에서 토큰 소비, 요청 수, Rate Limit 위반을 시각화하고, 비용 귀속을 위한 CSV Export 기능을 검증한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.10.1 (Observability overview), §1.10.4 (View dashboard), §1.10.5 (Export usage data)

## 전제 조건

- [ ] `runbooks/368-maas-observability.md` 완료 — Kuadrant Observability + Telemetry 활성화
- [ ] 테스트 요청이 최소 5회 이상 발생 (메트릭 생성 필수)
- [ ] `cluster-admin` 권한

## 실행

### 1. Observability Dashboard 접근

~~~bash
DASH_URL=$(oc get route rhods-dashboard -n redhat-ods-applications \
  -o jsonpath='{.spec.host}' 2>/dev/null)
echo "RHOAI Dashboard: https://${DASH_URL}"
echo ""
echo "경로: Observe & monitor → Dashboard → Usage 탭"
~~~

### 2. 주요 메트릭 확인 (Prometheus 직접 쿼리)

~~~bash
echo "=== Prometheus 메트릭 쿼리 가이드 ==="
echo ""
echo "OpenShift Console → Observe → Metrics 에서 아래 쿼리 실행:"
echo ""
echo "1) 총 토큰 소비:"
echo '   sum(authorized_hits)'
echo ""
echo "2) 총 요청 수:'
echo '   sum(authorized_calls)'
echo ""
echo "3) Rate Limit 위반 수:'
echo '   sum(limited_calls)'
echo ""
echo "4) Subscription별 토큰:'
echo '   sum by (subscription)(authorized_hits)'
echo ""
echo "5) 인증 지연시간:'
echo '   histogram_quantile(0.95, auth_server_authconfig_duration_seconds_bucket)'
~~~

### 3. Dashboard 개요 메트릭 확인

Dashboard Usage 탭의 Overview 섹션에서 확인할 항목:

| 메트릭 | 설명 |
|---|---|
| Total Tokens | 선택 기간 동안 소비된 총 토큰 수 (입력+출력) |
| Total Requests | API 요청 총 수 |
| Total Errors | 실패 요청 수 |
| Success Rate | 성공률 (%) |
| Active Users | 요청한 고유 사용자 수 |

### 4. Token Consumption by User 테이블 확인

~~~bash
echo "Dashboard Usage 탭 → Token Consumption by User 테이블"
echo ""
echo "확인 항목:"
echo "  - User: API Key 소유자"
echo "  - Subscription: 사용된 구독"
echo "  - Model: 접근한 모델 (<endpoint-name>/<model-id>)"
echo "  - Tokens: 소비된 토큰 수"
echo "  - Requests: 요청 수"
echo "  - Rate Limited: 429 응답 수"
~~~

### 5. CSV Export 테스트

~~~bash
echo "=== CSV Export 절차 ==="
echo ""
echo "1. Dashboard → Observe & monitor → Dashboard → Usage 탭"
echo "2. Time period 드롭다운에서 기간 선택 (예: Last 24 hours)"
echo "3. (선택) User/Subscription/Model 필터 적용"
echo "4. Token Consumption by User 테이블에 마우스 오버"
echo "5. 'Export as CSV' 클릭"
echo "6. CSV 파일이 로컬에 다운로드됨"
echo ""
echo "[주의] CSV는 showback 리포팅용. 빌링급 정밀도 필요 시 Limitador 엔드포인트 직접 사용"
~~~

### 6. Rate Limit 트리거 테스트

dev-subscription의 토큰 제한을 초과하여 429 응답을 확인한다.

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
: "${MAAS_API_KEY:?MAAS_API_KEY 미설정}"
: "${MODEL_NAME:=granite-2b}"

echo "=== Rate Limit 테스트 (15회 연속 요청) ==="
for i in $(seq 1 15); do
  CODE=$(curl -sSk -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST "${MAAS_URL}/llm/${MODEL_NAME}/v1/chat/completions" \
    -H "Authorization: Bearer ${MAAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"ibm-granite/granite-3.1-2b-instruct","messages":[{"role":"user","content":"Generate a long paragraph about cloud computing"}],"max_tokens":200}')
  echo "  요청 ${i}: HTTP ${CODE}"
done
echo ""
echo "200→429 전환이 관찰되면 Rate Limit 정상 동작"
~~~

## 검증

~~~bash
echo "=== Sprint 9 검증 ==="

echo "1) Dashboard URL:"
echo "  https://$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')/observe"

echo "2) Prometheus authorized_calls 존재 확인 (수동):"
echo "  Console → Observe → Metrics → authorized_calls"

echo "3) Rate Limit 검증:"
echo "  위 step 6에서 429 응답 관찰 여부"
~~~

## 실패 시

- **Dashboard Usage 탭 미표시** → `observabilityDashboard: true` 확인 (Sprint 3)
- **메트릭 데이터 없음** → 요청이 발생하지 않으면 메트릭 미생성 (정상). 최소 1회 요청 후 재확인
- **429 미발생** → Subscription 토큰 제한이 너무 높을 수 있음. dev-subscription의 tokens 값 확인
- **CSV Export 버튼 미표시** → 브라우저 호환성 확인, cluster-admin 권한 확인

## 다음 단계

→ `runbooks/369-a-maas-external-oidc.md`

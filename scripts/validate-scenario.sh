#!/bin/bash
set -euo pipefail

# S1~S10 시나리오 검증 스크립트
# 사용법: ./scripts/validate-scenario.sh [S1,S2,...] 또는 전체 (기본 S1~S6)

SCENARIOS="${1:-${SCENARIOS:-S1,S2,S3,S4,S5,S6}}"
MODEL_NS="${MODEL_NS:-rhoai-poc}"
MODEL_NAME="${MODEL_NAME:-smollm2-135m}"

PASS=0; FAIL=0; SKIP=0

check() {
  local name="$1" cmd="$2" expect="$3"
  RESULT=$(eval "${cmd}" 2>/dev/null || echo "ERROR")
  if echo "${RESULT}" | grep -q "${expect}"; then
    echo "  [PASS] ${name}"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] ${name}: got '${RESULT}'"
    FAIL=$((FAIL + 1))
  fi
}

check_min() {
  local name="$1" cmd="$2" min="$3"
  RESULT=$(eval "${cmd}" 2>/dev/null || echo "0")
  RESULT=$(echo "${RESULT}" | tr -d ' ')
  if [ "${RESULT}" -ge "${min}" ] 2>/dev/null; then
    echo "  [PASS] ${name} (${RESULT}개)"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] ${name}: got ${RESULT}, need >=${min}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== PoC 시나리오 검증 (대상: ${SCENARIOS}) ==="
echo ""

if echo "${SCENARIOS}" | grep -q "S1"; then
  echo "[S1] 모델 서빙"
  check "InferenceService Ready" \
    "oc get inferenceservice -A -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}'" "True"
  check "vLLM Pod Running" \
    "oc get pods -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME} --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' '" "1"
  check "Model Registry" \
    "oc get modelregistry -n rhoai-model-registries -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}'" "True"
else echo "[S1] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S2"; then
  echo "[S2] Pipeline"
  check "최근 PipelineRun Succeeded" \
    "oc get pipelinerun -n ${MODEL_NS} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.conditions[0].status}'" "True"
else echo "[S2] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S3"; then
  echo "[S3] Auto-scaling"
  check "ScaledObject Ready" \
    "oc get scaledobject -n ${MODEL_NS} -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}'" "True"
else echo "[S3] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S4"; then
  echo "[S4] 장애복구"
  check "IS Ready" \
    "oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" "True"
else echo "[S4] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S5"; then
  echo "[S5] Scale-to-Zero"
  echo "  [INFO] 수동 검증 필요 (runbooks/74 참조)"; SKIP=$((SKIP+1))
else echo "[S5] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S6"; then
  echo "[S6] 운영관리"
  check_min "ServiceMonitor" "oc get servicemonitor -n ${MODEL_NS} --no-headers | wc -l" 1
  check_min "PrometheusRule" "oc get prometheusrule -n ${MODEL_NS} --no-headers | wc -l" 1
  check_min "NetworkPolicy" "oc get networkpolicy -n ${MODEL_NS} --no-headers | wc -l" 4
else echo "[S6] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S7"; then
  echo "[S7] MaaS 라우팅"
  check_min "MaaS Gateway" "oc get gateway -n openshift-ingress --no-headers 2>/dev/null | wc -l" 1
  check_min "MaaS API Pod" \
    "oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l" 1
else echo "[S7] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S8"; then
  echo "[S8] 멀티테넌트"
  check_min "MaaS API 정상" \
    "oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=maas-api --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l" 1
else echo "[S8] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S9"; then
  echo "[S9] 보안 게이트"
  check "Guardrails CR" \
    "oc get guardrailsorchestrator -n ${MODEL_NS} --no-headers 2>/dev/null | wc -l | tr -d ' '" "1"
  check_min "Guardrails Pod" \
    "oc get pods -n ${MODEL_NS} -l app.kubernetes.io/part-of=trustyai --no-headers 2>/dev/null | grep Running | wc -l" 1
else echo "[S9] SKIP"; SKIP=$((SKIP+1)); fi

if echo "${SCENARIOS}" | grep -q "S10"; then
  echo "[S10] MLOps 루프"
  check "LMEvalJob" "oc get lmevaljob -n ${MODEL_NS} --no-headers 2>/dev/null | wc -l | tr -d ' '" "1"
else echo "[S10] SKIP"; SKIP=$((SKIP+1)); fi

echo ""
echo "=== 결과: PASS=${PASS} FAIL=${FAIL} SKIP=${SKIP} ==="
exit ${FAIL}

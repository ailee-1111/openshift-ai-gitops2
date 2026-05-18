# 366 — Sprint 6: MaaS Authorization Policy 관리

## 목적

MaaS Authorization Policy(MaaSAuthPolicy)를 생성하여 사용자 그룹이 API Gateway를 통해 모델 엔드포인트에 접근할 수 있도록 한다. Subscription은 quota를 정의하고, AuthPolicy는 게이트웨이 접근을 허가한다 — 양쪽 모두 필요하다.

> 출처: RHOAI 3.4 MaaS 문서 §1.8 (Manage authorization policies)

## 전제 조건

- [ ] `runbooks/365-maas-subscription.md` 완료 — Subscription Active
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. AuthPolicy 생성 (dev-team)

~~~bash
: "${MODEL_NS:=llm}"
: "${MODEL_NAME:=granite-2b}"

oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: dev-auth-policy
  namespace: models-as-a-service
spec:
  description: "개발팀 모델 접근 정책"
  groups:
    - dev-team
  models:
    - name: "${MODEL_NAME}"
      namespace: "${MODEL_NS}"
EOF
echo "[PASS] dev-auth-policy 생성"
~~~

### 2. AuthPolicy 생성 (prod-team)

~~~bash
oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: prod-auth-policy
  namespace: models-as-a-service
spec:
  description: "프로덕션팀 전체 모델 접근 정책"
  groups:
    - prod-team
  models:
    - name: "${MODEL_NAME}"
      namespace: "${MODEL_NS}"
EOF
echo "[PASS] prod-auth-policy 생성"
~~~

### 3. AuthPolicy 상태 확인

~~~bash
echo "=== AuthPolicy 목록 ==="
oc get maasauthpolicy -n models-as-a-service

for POLICY in dev-auth-policy prod-auth-policy; do
  PHASE=$(oc get maasauthpolicy "${POLICY}" -n models-as-a-service \
    -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  ${POLICY}: Phase=${PHASE}"
done
~~~

### 4. AuthPolicy 수정 (그룹/모델 추가)

~~~bash
# 예: dev-auth-policy에 추가 모델 포함
# oc patch maasauthpolicy dev-auth-policy -n models-as-a-service \
#   --type=merge \
#   -p '{
#     "spec": {
#       "models": [
#         {"name": "granite-2b", "namespace": "llm"},
#         {"name": "qwen3-06b", "namespace": "llm"}
#       ]
#     }
#   }'
echo "[INFO] 필요 시 위 명령으로 모델 추가"
~~~

### 5. AuthPolicy 삭제 (필요 시)

~~~bash
# 주의: 삭제 즉시 해당 그룹의 API Gateway 접근 차단 (403 반환)
# oc delete maasauthpolicy <name> -n models-as-a-service
echo "[INFO] 삭제가 필요하면 수동 실행. Subscription은 유지되지만 Gateway 접근 불가"
~~~

## 검증

~~~bash
echo "=== Sprint 6 검증 ==="

echo "1) AuthPolicy 목록:"
oc get maasauthpolicy -n models-as-a-service

echo "2) Phase 확인:"
for POLICY in dev-auth-policy prod-auth-policy; do
  PHASE=$(oc get maasauthpolicy "${POLICY}" -n models-as-a-service \
    -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  ${POLICY}: ${PHASE}"
done

echo "3) Subscription + AuthPolicy 정합:"
echo "  Subscriptions:"
oc get maassubscription -n models-as-a-service \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase --no-headers
echo "  AuthPolicies:"
oc get maasauthpolicy -n models-as-a-service \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase --no-headers
~~~

## 실패 시

- **Phase=Failed** → `oc describe maasauthpolicy <name> -n models-as-a-service` 상태 조건 확인
- **403 Forbidden 지속** → Subscription + AuthPolicy 모두 존재하는지 확인 (양쪽 필수)
- **Subscription 변경 후 AuthPolicy 불일치** → Subscription의 "Create matching authorization policy"로 자동 생성한 경우에도 이후 변경은 수동 동기화 필요

## 다음 단계

→ `runbooks/367-maas-api-key.md`

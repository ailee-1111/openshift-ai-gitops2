# 365 — Sprint 5: MaaS Subscription 생성 및 관리

## 목적

MaaS Subscription CR을 생성하여 사용자 그룹에 모델별 토큰 제한(quota)을 부여한다. 우선순위 기반 다중 구독, 토큰 제한 설정, 매칭 AuthPolicy 자동 생성을 포함한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.6 (Subscriptions), §1.7 (Manage subscriptions)

## 전제 조건

- [ ] `runbooks/364-maas-model-deploy.md` 완료 — MaaSModelRef 존재
- [ ] OpenShift 그룹 생성 완료 (또는 OIDC 그룹)
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. OpenShift 그룹 생성

~~~bash
oc adm groups new dev-team 2>/dev/null || echo "INFO: dev-team 그룹 이미 존재"
oc adm groups new prod-team 2>/dev/null || echo "INFO: prod-team 그룹 이미 존재"

CURRENT_USER=$(oc whoami)
oc adm groups add-users dev-team "${CURRENT_USER}" 2>/dev/null
oc adm groups add-users prod-team "${CURRENT_USER}" 2>/dev/null

echo "그룹 확인:"
oc get groups dev-team prod-team
~~~

### 2. Development Subscription 생성 (Priority 0)

~~~bash
: "${MODEL_NS:=llm}"
: "${MODEL_NAME:=granite-2b}"

oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: dev-subscription
  namespace: models-as-a-service
spec:
  description: "개발·실험용 구독 — 낮은 우선순위, 제한된 토큰"
  priority: 0
  groups:
    - dev-team
  models:
    - name: "${MODEL_NAME}"
      namespace: "${MODEL_NS}"
      tokenLimits:
        - tokens: 1000
          duration: 1
          unit: minute
EOF
echo "[PASS] dev-subscription 생성"
~~~

### 3. Production Subscription 생성 (Priority 100)

~~~bash
oc apply -f - <<EOF
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: prod-subscription
  namespace: models-as-a-service
spec:
  description: "프로덕션 워크로드 — 높은 우선순위, 대용량 토큰"
  priority: 100
  groups:
    - prod-team
  models:
    - name: "${MODEL_NAME}"
      namespace: "${MODEL_NS}"
      tokenLimits:
        - tokens: 100000
          duration: 1
          unit: hour
        - tokens: 5000
          duration: 1
          unit: minute
EOF
echo "[PASS] prod-subscription 생성"
~~~

### 4. Subscription 상태 확인

~~~bash
echo "=== Subscription 목록 ==="
oc get maassubscription -n models-as-a-service

echo ""
echo "=== dev-subscription 상세 ==="
oc get maassubscription dev-subscription -n models-as-a-service \
  -o jsonpath='{.status.phase}'
echo ""

echo "=== prod-subscription 상세 ==="
oc get maassubscription prod-subscription -n models-as-a-service \
  -o jsonpath='{.status.phase}'
echo ""
~~~

### 5. Subscription 수정 (토큰 제한 변경 예시)

~~~bash
oc patch maassubscription dev-subscription -n models-as-a-service \
  --type=merge \
  -p '{
    "spec": {
      "models": [{
        "name": "'"${MODEL_NAME}"'",
        "namespace": "'"${MODEL_NS}"'",
        "tokenLimits": [{
          "tokens": 2000,
          "duration": 1,
          "unit": "minute"
        }]
      }]
    }
  }'
echo "[PASS] dev-subscription 토큰 제한 2000/분으로 변경"
~~~

### 6. Subscription 삭제 (필요 시)

~~~bash
# 주의: 삭제하면 해당 그룹의 모든 사용자가 모델 접근 불가
# oc delete maassubscription <name> -n models-as-a-service
echo "[INFO] 삭제가 필요하면 위 명령을 수동 실행"
~~~

## 검증

~~~bash
echo "=== Sprint 5 검증 ==="

echo "1) Subscription 목록:"
oc get maassubscription -n models-as-a-service

echo "2) Phase 확인:"
for SUB in dev-subscription prod-subscription; do
  PHASE=$(oc get maassubscription "${SUB}" -n models-as-a-service \
    -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  ${SUB}: ${PHASE}"
done

echo "3) 그룹 멤버십:"
oc get groups dev-team prod-team -o custom-columns=NAME:.metadata.name,USERS:.users
~~~

## 실패 시

- **Phase=Failed** → `oc describe maassubscription <name> -n models-as-a-service` 상태 조건 메시지 확인
- **모델을 찾을 수 없음** → MaaSModelRef가 해당 네임스페이스에 존재하는지 확인
- **토큰 제한 미적용** → Subscription과 AuthPolicy 모두 필요 — Sprint 6에서 AuthPolicy 생성
- **우선순위 충돌** → 동일 priority 값은 비결정적 동작 유발, 간격을 두고 설정 (0, 10, 50, 100)

## 다음 단계

→ `runbooks/366-maas-auth-policy.md`

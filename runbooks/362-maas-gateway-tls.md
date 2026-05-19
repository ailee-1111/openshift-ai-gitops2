# 362 — Sprint 2: MaaS Gateway 생성 및 TLS 구성

## 목적

MaaS의 인그레스 진입점인 `maas-default-gateway` Gateway 리소스를 생성하고, Authorino ↔ MaaS API 간 TLS 통신을 구성한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.2 (Gateway prerequisites), §1.3 (Configure TLS)

## 전제 조건

- [ ] `runbooks/361-maas-prerequisites.md` 완료 — Kuadrant Ready
- [ ] Connectivity Link Operator CSV Succeeded
- [ ] **On-prem/Restricted 환경**: `runbooks/115-proxy-trusted-ca.md` 완료 — proxy/cluster trustedCA 등록. 미등록 시 Gateway Wasm TLS 실패 → 403
- [ ] 환경변수: `CLUSTER_DOMAIN`

## 실행

### 1. GatewayClass 생성 (OpenShift Gateway Controller)

~~~bash
oc apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-default
spec:
  controllerName: openshift.io/gateway-controller
EOF
echo "[PASS] GatewayClass 생성 완료"
~~~

### 2. maas-default-gateway 생성

~~~bash
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"

oc create namespace openshift-ingress --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
  namespace: openshift-ingress
  annotations:
    # ODH Model Controller가 AuthPolicy를 간섭하지 않도록
    opendatahub.io/managed: "false"
    # Authorino TLS 부트스트랩
    security.opendatahub.io/authorino-tls-bootstrap: "true"
spec:
  gatewayClassName: openshift-default
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "maas.${CLUSTER_DOMAIN}"
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - name: maas-tls-cert
        kind: Secret
EOF
echo "[PASS] maas-default-gateway 생성 완료"
~~~

### 3. Authorino 서비스 TLS 인증서 생성

~~~bash
oc annotate service authorino-authorino-authorization \
  -n kuadrant-system \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  --overwrite

echo "authorino-server-cert Secret 대기..."
for i in $(seq 1 12); do
  if oc get secret authorino-server-cert -n kuadrant-system &>/dev/null; then
    echo "[PASS] authorino-server-cert 생성 완료"
    break
  fi
  sleep 5
done
~~~

### 4. Authorino CR TLS 리스너 활성화

~~~bash
oc patch authorino authorino -n kuadrant-system --type=merge --patch '{
  "spec": {
    "listener": {
      "tls": {
        "enabled": true,
        "certSecretRef": {
          "name": "authorino-server-cert"
        }
      }
    }
  }
}'
echo "[PASS] Authorino TLS 리스너 활성화"
~~~

### 5. Authorino 환경 변수 TLS 인증서 경로 설정

~~~bash
oc -n kuadrant-system set env deployment/authorino \
  SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt

echo "Authorino Pod 재시작 대기..."
oc rollout status deployment/authorino -n kuadrant-system --timeout=120s
echo "[PASS] Authorino TLS 환경변수 설정 완료"
~~~

### 6. Gateway TLS 부트스트랩 어노테이션 확인

~~~bash
TLS_ANNO=$(oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}')
echo "TLS bootstrap 어노테이션: ${TLS_ANNO}"
if [[ "${TLS_ANNO}" != "true" ]]; then
  oc annotate gateway maas-default-gateway -n openshift-ingress \
    security.opendatahub.io/authorino-tls-bootstrap="true" --overwrite
fi
~~~

## 검증

~~~bash
echo "=== Sprint 2 검증 ==="

echo "1) GatewayClass:"
oc get gatewayclass openshift-default --no-headers 2>/dev/null

echo "2) Gateway 상태:"
oc get gateway maas-default-gateway -n openshift-ingress

echo "3) Gateway hostname:"
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.spec.listeners[0].hostname}'
echo ""

echo "4) Authorino TLS 활성화:"
oc get authorino authorino -n kuadrant-system \
  -o jsonpath='{.spec.listener.tls.enabled}'
echo ""

echo "5) authorino-server-cert Secret:"
oc get secret authorino-server-cert -n kuadrant-system --no-headers

echo "6) Authorino SSL_CERT_FILE:"
oc get deployment/authorino -n kuadrant-system \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SSL_CERT_FILE")].value}'
echo ""

echo "7) Gateway TLS bootstrap 어노테이션:"
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.metadata.annotations.security\.opendatahub\.io/authorino-tls-bootstrap}'
echo ""
~~~

## 실패 시

- **GatewayClass 미인식** → OCP 4.19+ Gateway API CRD 확인: `oc get crd gateways.gateway.networking.k8s.io`
- **authorino-server-cert 미생성** → service-ca-operator 동작 확인: `oc get pods -n openshift-service-ca`
- **Authorino Pod CrashLoop** → TLS 인증서 경로 정합 확인: `oc logs deployment/authorino -n kuadrant-system`
- **Gateway Programmed=False** → `oc describe gateway maas-default-gateway -n openshift-ingress` 이벤트 확인

## 다음 단계

→ `runbooks/363-maas-dsc-dashboard.md`

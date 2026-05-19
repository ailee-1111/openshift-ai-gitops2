# 115 — MaaS Gateway 403 트러블슈팅: 클러스터 프록시 Trusted CA 미등록

## 어떤 경우 발생하는 이슈인가

On-premise / Restricted 환경에서 **내부 CA(사설 인증서)**를 사용하는 클러스터에서 MaaS를 구성할 때 발생한다.

Kuadrant WasmPlugin은 Gateway Pod(istio-proxy)가 `registry.access.redhat.com`에서 Wasm 모듈을 OCI pull 해야 한다. 이때 istio-proxy가 내부 CA를 신뢰하지 못하면 TLS 핸드셰이크가 실패하고, Wasm 로드 실패 시 **deny RBAC 필터**가 적용되어 Gateway를 통과하는 **모든 요청이 403으로 거부**된다.

**발생 조건:**
- 클러스터가 사설 CA(기업 ROOT CA 등)를 사용
- `proxy/cluster`에 `trustedCA`가 등록되지 않음
- Gateway Pod에 CA 번들이 마운트되지 않음

**근본 원인 체인:**

```
1. proxy/cluster의 spec.trustedCA.name이 비어있음
2. openshift-ingress NS에 inject-trusted-cabundle ConfigMap이 없음
3. Gateway Pod의 istio-proxy가 내부 CA(HMG Secure ROOT CA 등)를 알지 못함
4. Kuadrant WasmPlugin이 registry.access.redhat.com에서 Wasm 모듈 pull 시 TLS 실패
5. Wasm 로드 실패 → deny RBAC 필터 적용 → 모든 요청 403
```

---

## 이슈 확인 및 재현

### 증상 1: Dashboard "Error loading components"

RHOAI Dashboard → Gen AI Studio → **API Keys** 페이지 접근 시:
```
Error loading components
the server encountered a problem and could not process your request
```

### 증상 2: Gateway 경유 API 호출 시 403

~~~bash
HOST="maas.${CLUSTER_DOMAIN:-apps.poc.mobis.com}"
TOKEN=$(oc whoami -t)

curl -sk -w "\nHTTP: %{http_code}\n" \
  "https://${HOST}/maas-api/health"
# 결과: RBAC: access denied / HTTP: 403
~~~

### 증상 3: istio-proxy 로그에 x509 에러

~~~bash
GW_POD=$(oc get pods -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  --no-headers -o jsonpath='{.items[0].metadata.name}')

oc logs ${GW_POD} -n openshift-ingress -c istio-proxy --tail=10
# 결과:
#   error wasm: ... tls: failed to verify certificate: x509: certificate signed by unknown authority
#   applying deny RBAC filter
#   "GET /maas-api/health HTTP/2" 403 - rbac_access_denied_matched_policy[none]
~~~

---

## 식별 방법

아래 4가지를 순서대로 확인하여 이 이슈인지 판별한다.

### 체크 1: proxy/cluster trustedCA 미설정

~~~bash
oc get proxy/cluster -o jsonpath='{.spec.trustedCA.name}'; echo
# 비어있으면("") → 이 이슈에 해당
# 값이 있으면 → 체크 2로
~~~

### 체크 2: openshift-ingress NS에 CA ConfigMap 부재

~~~bash
oc get configmap -n openshift-ingress \
  -l config.openshift.io/inject-trusted-cabundle=true --no-headers
# "No resources found" → CA 자동 주입 대상 없음
~~~

### 체크 3: Gateway Pod에 CA 마운트 없음

~~~bash
GW_DEPLOY=$(oc get deploy -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  -o jsonpath='{.items[0].metadata.name}')

oc get deploy ${GW_DEPLOY} -n openshift-ingress \
  -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"\n"}{end}' | grep -i ca
# 결과 없으면 → CA 미마운트
~~~

### 체크 4: 내부 CA 번들 존재 확인

~~~bash
oc get configmap user-ca-bundle -n openshift-config \
  -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null | \
  openssl x509 -noout -subject 2>/dev/null || echo "(user-ca-bundle 없음)"
# 있으면: subject=... (예: CN=HMG Secure ROOT CA)
# 없으면: CA 번들을 먼저 생성해야 함 (아래 "사전 준비" 참조)
~~~

**판정**: 체크 1~3 중 하나라도 해당하면 이 런북의 트러블슈팅을 적용한다.

### 참고: 현재 상태 (Mobis 클러스터 2026-05-19 기준)

```
proxy/cluster:           spec.trustedCA.name = ""  (비어있음)
user-ca-bundle:          HMG Secure ROOT CA 1장    (openshift-config에 존재하지만 미연결)
proxy-ca-bundle:         HMG Secure ROOT CA 1장    (openshift-config에 존재하지만 미연결)
DSCInitialization:       customCABundle = ""        (비어있음)
openshift-ingress:       inject CA ConfigMap 없음
Gateway istio-proxy:     CA 미마운트 → x509 실패 → deny RBAC
```

---

## 트러블슈팅 가이드

### 사전 준비: user-ca-bundle이 없는 경우

체크 4에서 `user-ca-bundle`이 없으면 노드에서 CA를 추출하여 생성한다.

~~~bash
# 노드에서 CA 번들 추출
oc debug node/$(oc get nodes -o jsonpath='{.items[0].metadata.name}') -- \
  chroot /host cat /etc/pki/tls/certs/ca-bundle.crt > /tmp/ca-bundle.crt

# user-ca-bundle ConfigMap 생성
oc create configmap user-ca-bundle -n openshift-config \
  --from-file=ca-bundle.crt=/tmp/ca-bundle.crt
~~~

### Step 1: proxy/cluster에 trustedCA 연결

~~~bash
oc patch proxy/cluster --type=merge \
  -p '{"spec":{"trustedCA":{"name":"user-ca-bundle"}}}'

# 확인
oc get proxy/cluster -o jsonpath='{.spec.trustedCA.name}'; echo
# 기대: user-ca-bundle
~~~

> **동작 원리**: OpenShift는 `proxy/cluster`에 지정된 ConfigMap의 CA 인증서를 시스템 CA와 병합하여 `trusted-ca-bundle`이라는 ConfigMap을 자동 생성한다. `config.openshift.io/inject-trusted-cabundle: "true"` 라벨이 붙은 빈 ConfigMap이 있는 NS에 자동 주입된다.

### Step 2: openshift-ingress NS에 자동 주입 ConfigMap 생성

~~~bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: trusted-ca-bundle
  namespace: openshift-ingress
  labels:
    config.openshift.io/inject-trusted-cabundle: "true"
data: {}
EOF
~~~

### Step 3: CA 주입 대기 및 확인

~~~bash
for i in $(seq 1 24); do
  COUNT=$(oc get configmap trusted-ca-bundle -n openshift-ingress \
    -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null | grep -c "BEGIN CERTIFICATE" || echo 0)
  if [ "${COUNT}" -gt 0 ]; then
    echo "CA 주입 완료: ${COUNT}개 인증서"
    break
  fi
  echo "대기 중... (${i}/24)"
  sleep 5
done

# 내부 CA 포함 확인
oc get configmap trusted-ca-bundle -n openshift-ingress \
  -o jsonpath='{.data.ca-bundle\.crt}' | grep -c "BEGIN CERTIFICATE"
# 기대: 시스템 CA + 내부 CA (수십 개)
~~~

### Step 4: Gateway Deployment에 CA 번들 마운트

~~~bash
GW_DEPLOY=$(oc get deploy -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  -o jsonpath='{.items[0].metadata.name}')
echo "Gateway Deployment: ${GW_DEPLOY}"

oc patch deployment ${GW_DEPLOY} -n openshift-ingress \
  --type=json -p='[
    {"op":"add","path":"/spec/template/spec/volumes/-",
     "value":{"name":"trusted-ca","configMap":{"name":"trusted-ca-bundle"}}},
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-",
     "value":{"name":"trusted-ca",
              "mountPath":"/etc/ssl/certs/ca-certificates.crt",
              "subPath":"ca-bundle.crt",
              "readOnly":true}},
    {"op":"add","path":"/spec/template/spec/containers/0/env/-",
     "value":{"name":"SSL_CERT_FILE",
              "value":"/etc/ssl/certs/ca-certificates.crt"}}
  ]'
~~~

### Step 5: 롤아웃 대기

~~~bash
oc rollout status deployment/${GW_DEPLOY} -n openshift-ingress --timeout=120s
~~~

---

## 검증 완료

### V-1: Wasm 로드 성공

~~~bash
oc logs -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  -c istio-proxy --tail=15 2>&1 | grep -E "wasm|error|deny"
# 기대: "x509" 에러 없음, "applying deny RBAC filter" 없음
# PASS: [   ]  FAIL: [   ]
~~~

### V-2: maas-api health 정상

~~~bash
HOST="maas.${CLUSTER_DOMAIN:-apps.poc.mobis.com}"
curl -sk "https://${HOST}/maas-api/health"
# 기대: 200 OK (이전: 403 RBAC denied)
# PASS: [   ]  FAIL: [   ]
~~~

### V-3: API Keys 조회 정상

~~~bash
TOKEN=$(oc whoami -t)
curl -sk -w "\nHTTP: %{http_code}\n" \
  "https://${HOST}/maas-api/v1/api-keys" \
  -H "Authorization: Bearer ${TOKEN}"
# 기대: HTTP 200
# PASS: [   ]  FAIL: [   ]
~~~

### V-4: Dashboard API Keys 페이지

RHOAI Dashboard → Gen AI Studio → API Keys 접속
- 기대: "Error loading components" 해소, API Key 목록 정상 표시
- PASS: [   ]  FAIL: [   ]

### V-5: 모델 추론 (Gateway 경유)

~~~bash
API_KEY="${API_KEY:-$(oc get secret -n ${MODEL_NS:-mobis-poc} \
  -l maas.opendatahub.io/api-key=true \
  -o jsonpath='{.items[0].data.api-key}' 2>/dev/null | base64 -d)}"

curl -sk -w "\nHTTP: %{http_code}\n" \
  "https://${HOST}/${MODEL_NS:-mobis-poc}/${MODEL_NAME:-qwen3-8b}/v1/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME:-qwen3-8b}\",\"prompt\":\"Hello\",\"max_tokens\":10}"
# 기대: HTTP 200 + 추론 응답
# PASS: [   ]  FAIL: [   ]
~~~

### 검증 요약

| # | 항목 | 기준 | 판정 |
|---|------|------|:----:|
| V-1 | Wasm 로드 | x509 에러 없음 | |
| V-2 | maas-api health | 200 OK | |
| V-3 | API Keys 조회 | 200 OK | |
| V-4 | Dashboard API Keys | 페이지 정상 | |
| V-5 | 모델 추론 | 200 + 응답 | |

---

## 실패 시

- **CA 주입 안 됨 (Step 3에서 COUNT=0 유지)** → `proxy/cluster` 패치 반영 확인: `oc get proxy/cluster -o jsonpath='{.spec.trustedCA.name}'`. 비어있으면 Step 1 재실행
- **Gateway 재시작 후에도 403** → volume/env 패치 확인: `oc get deploy ${GW_DEPLOY} -n openshift-ingress -o yaml | grep -A3 trusted-ca`. subPath가 `ca-bundle.crt`인지 확인
- **"already exists" 에러 (patch 재실행 시)** → 이미 volume이 추가된 상태. `oc rollout restart deployment/${GW_DEPLOY} -n openshift-ingress`로 Pod만 재시작
- **다른 Gateway(openshift-ai-inference)도 동일 증상** → 해당 Gateway Deployment에도 Step 4 동일 패치 적용 필요
- **proxy/cluster 패치 후 노드 재부팅 발생?** → 아니오. MCO 롤아웃 없음. trustedCA 변경은 노드 재설정 불필요

## 영향 범위

| 항목 | 영향 |
|------|------|
| proxy/cluster 변경 | 클러스터 전체 — 기존 시스템 CA에 내부 CA를 **추가**. 기존 CA 제거 없음. 부작용 없음 |
| inject-trusted-cabundle | `config.openshift.io/inject-trusted-cabundle: "true"` 라벨이 붙은 ConfigMap에만 자동 주입 |
| MCO 롤아웃 | 발생하지 않음 (노드 재설정 불필요) |
| 기존 Pod | 영향 없음 — 새로 생성/재시작되는 Pod에만 적용 |

## 다음 단계

→ `runbooks/360-maas-e2e.md` — MaaS E2E 검증

# 100 — 플랫폼 사전 구성

## 목적

RHOAI PoC 실행에 필요한 플랫폼 Operator, 보조 서비스, 보안 설정을 배포한다. 이 단계는 시나리오 런북(300~390)의 전제 조건이다. 설치 순서는 poc-factory `dependency-order.md`의 6-Layer 의존성을 따른다.

> **환경별 참고**:
> - **스토리지**: AWS=`gp3-csi` (기본), bare metal=`lvms-vg1` → `.env`의 `STORAGE_CLASS` 참조
> - **이미지**: Restricted 환경에서는 외부 이미지를 사전 미러링 필요 (`MINIO_IMAGE`, `GITEA_IMAGE` 등)
> - **DNS/NTP**: bare metal Restricted 환경에서는 `runbooks/113-dns-troubleshoot-mobis.md` 선행 확인

```
Layer 1: UWM 활성화                    → step 1~2
Layer 2: DSC 컴포넌트 패치 + Dashboard → step 3~4
Layer 2b: COO + Tempo + OpenTelemetry  → step 5
Layer 3: S3(MinIO) + Gitea + MailHog   → step 6~8
Layer 4: CMA + KEDA + Pipelines + MAG  → step 9~12
Layer 5: RHCL + MaaS                   → step 13~14
Layer 6: RBAC + htpasswd               → step 15
Layer 6b: Observability Dashboard      → step 16
```

## 전제 조건

- [ ] `runbooks/031-rhoai-dependency-app-sync.md` 완료 — 의존성 Application `Synced/Healthy`
- [ ] `default-dsc` Ready=True (`oc get dsc default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`)
- [ ] `.env` 에 아래 변수가 정의되어 있음:
  - `CLUSTER_API_URL`, `CLUSTER_DOMAIN`
  - `OCP_ADMIN_USER`, `OCP_ADMIN_PASSWORD`
  - `POC_NAMESPACE` — PoC 전용 네임스페이스 이름
  - `S3_ACCESS_KEY`, `S3_SECRET_KEY` — MinIO 자격 증명 (기본값: `minioadmin`)
  - `S3_BUCKET` — 모델 저장용 S3 버킷 이름
  - `MINIO_IMAGE` — MinIO 컨테이너 이미지 (기본값: `quay.io/minio/minio:RELEASE.2024-06-13T22-53-53Z`)
  - `GITEA_IMAGE` — Gitea 컨테이너 이미지 (기본값: `gitea/gitea:1.21-rootless`)
- [ ] 클러스터에 `cluster-admin` 권한으로 로그인 가능

## 실행

### 0. 환경 변수 로드 및 로그인

~~~bash
set -a && source .env && set +a

# 기본값 설정
: "${POC_NAMESPACE:?POC_NAMESPACE 미정의}"
: "${S3_ACCESS_KEY:=minioadmin}"
: "${S3_SECRET_KEY:=minioadmin}"
: "${S3_BUCKET:=${POC_NAMESPACE}-models}"
: "${MINIO_IMAGE:=quay.io/minio/minio:RELEASE.2024-06-13T22-53-53Z}"
: "${GITEA_IMAGE:=gitea/gitea:1.21-rootless}"

oc login "${CLUSTER_API_URL}" \
  --username="${OCP_ADMIN_USER}" \
  --password="${OCP_ADMIN_PASSWORD}" \
  --insecure-skip-tls-verify=true
~~~

### 1. PoC 네임스페이스 생성 (Layer 1)

~~~bash
oc create namespace "${POC_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc label ns "${POC_NAMESPACE}" opendatahub.io/dashboard=true --overwrite
~~~

### 2. User Workload Monitoring 활성화 (Layer 1)

~~~bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF

oc wait pod --all \
  -n openshift-user-workload-monitoring \
  --for=condition=Ready \
  --timeout=120s 2>/dev/null || \
  echo "INFO: UWM Pod 대기 중 — 최초 활성화 시 최대 2분 소요"
~~~

### 3. OdhDashboardConfig + DSC 컴포넌트 패치 (Layer 2)

~~~bash
oc patch odhdashboardconfig odh-dashboard-config \
  -n redhat-ods-applications \
  --type=merge \
  -p '{
    "spec": {
      "dashboardConfig": {
        "disableKServeMetrics": false,
        "disableLMEval": false,
        "disableModelCatalog": false,
        "disableModelRegistry": false,
        "genAiStudio": true,
        "modelAsService": true,
        "observabilityDashboard": true
      },
      "modelServing": {
        "deploymentStrategy": "rolling",
        "isLLMdDefault": true
      }
    }
  }'

oc patch dsc default-dsc \
  --type=merge \
  -p '{
    "spec": {
      "components": {
        "feastoperator": {"managementState": "Managed"},
        "kserve": {"nim": {"managementState": "Managed"}},
        "ray": {"managementState": "Managed"},
        "trainingoperator": {"managementState": "Managed"}
      }
    }
  }'
~~~

### 4. RHOAI Dashboard Route 확인 (Layer 2)

~~~bash
oc create route passthrough rhods-dashboard \
  -n redhat-ods-applications \
  --service=rhods-dashboard \
  --port=8443 2>/dev/null || echo "INFO: Route 이미 존재"

DASH_URL="$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')"
echo "RHOAI Dashboard: https://${DASH_URL}"
~~~

### 5. COO + Tempo + OpenTelemetry Operator 설치 (Layer 2b)

RHOAI 3.4+ Observability Dashboard(Perses)의 전제 Operator 3개. DSCI traces 활성화 시 Perses/Collector/Tempo Pod가 `redhat-ods-monitoring`에 자동 배포된다.

~~~bash
# a) Cluster Observability Operator (COO)
oc create namespace openshift-cluster-observability-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: coo-og
  namespace: openshift-cluster-observability-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  channel: stable
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# b) Tempo Operator
oc create namespace openshift-tempo-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: tempo-og
  namespace: openshift-tempo-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: tempo-product
  namespace: openshift-tempo-operator
spec:
  channel: stable
  name: tempo-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# c) Red Hat Build of OpenTelemetry
oc create namespace openshift-opentelemetry-operator --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: otel-og
  namespace: openshift-opentelemetry-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: opentelemetry-product
  namespace: openshift-opentelemetry-operator
spec:
  channel: stable
  name: opentelemetry-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "3개 Operator 설치 대기 (최대 5분)..."
sleep 60
for NS in openshift-cluster-observability-operator openshift-tempo-operator openshift-opentelemetry-operator; do
  echo -n "  ${NS}: "
  oc get csv -n "$NS" --no-headers 2>/dev/null | awk '{print $NF}' | head -1
done
~~~

### 6. MinIO S3 스토리지 배포 (Layer 3)

모델 아티팩트·파이프라인 산출물 저장용 S3 호환 스토리지.

#### 6-a. MinIO 자격 증명 Secret

~~~bash
oc apply -n "${POC_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
type: Opaque
stringData:
  MINIO_ROOT_USER: "${S3_ACCESS_KEY}"
  MINIO_ROOT_PASSWORD: "${S3_SECRET_KEY}"
EOF
~~~

#### 6-b. MinIO Deployment + Service + Route

~~~bash
oc apply -n "${POC_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
        - name: minio
          image: "${MINIO_IMAGE}"
          args: ["server", "/data", "--console-address", ":9001"]
          envFrom:
            - secretRef:
                name: minio-credentials
          ports:
            - containerPort: 9000
            - containerPort: 9001
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minio-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  selector:
    app: minio
  ports:
    - name: api
      port: 9000
    - name: console
      port: 9001
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: minio-console
spec:
  to:
    kind: Service
    name: minio
  port:
    targetPort: console
  tls:
    termination: edge
EOF

oc wait deploy/minio \
  -n "${POC_NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s
~~~

#### 6-c. 버킷 초기화

~~~bash
oc exec -n "${POC_NAMESPACE}" deploy/minio -- \
  mkdir -p "/data/${S3_BUCKET}" /data/poc-pipeline-artifacts
~~~

#### 6-d. RHOAI Data Connection Secret

~~~bash
oc apply -n "${POC_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: poc-s3-connection
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/managed: "true"
  annotations:
    opendatahub.io/connection-type: s3
    openshift.io/display-name: "PoC MinIO S3"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "${S3_ACCESS_KEY}"
  AWS_SECRET_ACCESS_KEY: "${S3_SECRET_KEY}"
  AWS_S3_ENDPOINT: "http://minio.${POC_NAMESPACE}.svc.cluster.local:9000"
  AWS_S3_BUCKET: "${S3_BUCKET}"
  AWS_DEFAULT_REGION: "us-east-1"
EOF
~~~

### 7. Gitea 배포 (Layer 3)

~~~bash
oc apply -n "${POC_NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitea-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitea
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitea
  template:
    metadata:
      labels:
        app: gitea
    spec:
      containers:
        - name: gitea
          image: "${GITEA_IMAGE}"
          ports:
            - containerPort: 3000
          env:
            - name: GITEA__database__DB_TYPE
              value: sqlite3
            - name: GITEA_APP_INI
              value: /tmp/gitea/conf/app.ini
            - name: GITEA_WORK_DIR
              value: /tmp/gitea
            - name: GITEA_CUSTOM
              value: /tmp/gitea
            - name: HOME
              value: /tmp/gitea
          volumeMounts:
            - name: data
              mountPath: /tmp/gitea
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: gitea-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: gitea
spec:
  selector:
    app: gitea
  ports:
    - port: 3000
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: gitea
spec:
  to:
    kind: Service
    name: gitea
  port:
    targetPort: 3000
  tls:
    termination: edge
EOF

oc wait deploy/gitea \
  -n "${POC_NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s
~~~

### 8. MailHog 배포 (Layer 3 — 유틸리티)

Pipeline 승인 프로세스(S2)에서 이메일 알림을 수신하기 위한 임시 SMTP 서버.

~~~bash
oc apply -n "${POC_NAMESPACE}" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailhog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mailhog
  template:
    metadata:
      labels:
        app: mailhog
    spec:
      containers:
        - name: mailhog
          image: mailhog/mailhog:v1.0.1
          ports:
            - containerPort: 1025
              name: smtp
            - containerPort: 8025
              name: web
---
apiVersion: v1
kind: Service
metadata:
  name: mailhog
spec:
  selector:
    app: mailhog
  ports:
    - name: smtp
      port: 1025
    - name: web
      port: 8025
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: mailhog
spec:
  to:
    kind: Service
    name: mailhog
  port:
    targetPort: web
  tls:
    termination: edge
EOF

oc wait deploy/mailhog \
  -n "${POC_NAMESPACE}" \
  --for=condition=Available \
  --timeout=60s
~~~

### 9. CMA (Custom Metrics Autoscaler) Operator 설치 (Layer 4)

~~~bash
oc create namespace openshift-keda --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: keda-og
  namespace: openshift-keda
spec:
  targetNamespaces:
    - openshift-keda
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-custom-metrics-autoscaler-operator
  namespace: openshift-keda
spec:
  channel: stable
  name: openshift-custom-metrics-autoscaler-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "CMA 설치 대기 (최대 5분)..."
sleep 30
oc wait csv -n openshift-keda \
  -l operators.coreos.com/openshift-custom-metrics-autoscaler-operator.openshift-keda \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=300s 2>/dev/null || \
  (sleep 60 && oc get csv -n openshift-keda | grep custom-metrics)
~~~

### 10. KedaController CR 생성 (Layer 4)

CMA Operator만 설치하면 KEDA Pod가 배포되지 않는다. KedaController CR이 필수.

~~~bash
oc apply -f - <<'EOF'
apiVersion: keda.sh/v1alpha1
kind: KedaController
metadata:
  name: keda
  namespace: openshift-keda
spec:
  admissionWebhooks:
    logEncoder: console
    logLevel: info
  metricsServer:
    logLevel: "0"
  operator:
    logEncoder: console
    logLevel: info
  watchNamespace: ""
EOF

echo "KEDA Pod 대기 (최대 2분)..."
sleep 30
oc wait pod --all -n openshift-keda \
  --for=condition=Ready --timeout=120s 2>/dev/null || \
  oc get pods -n openshift-keda --no-headers
# 기대: keda-operator, keda-metrics-apiserver, keda-admission Pod Running
~~~

### 11. Pipelines Operator 설치 (Layer 4)

S2 Pipeline 시나리오 전제 조건. RHOAI가 자동 설치하지 않는 클러스터에서는 수동 설치 필요.

~~~bash
oc get csv -n openshift-operators --no-headers 2>/dev/null | grep -q pipelines && \
  echo "Pipelines 이미 설치됨" || \
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "Pipelines Operator 대기 (최대 5분)..."
sleep 60
oc get csv -n openshift-operators --no-headers | grep pipelines
# 기대: Succeeded
~~~

### 12. ManualApprovalGate 설치 (Layer 4)

Tekton Pipeline 승인 게이트(S2) 전제 조건. **Pipelines Operator(step 11) Succeeded 후 실행**.

~~~bash
oc apply -f - <<'EOF'
apiVersion: operator.tekton.dev/v1alpha1
kind: ManualApprovalGate
metadata:
  name: manual-approval-gate
spec:
  targetNamespace: openshift-pipelines
EOF

echo "ManualApprovalGate 대기 (최대 2분)..."
sleep 60
oc get manualapprovalgate
# 기대: Ready=True
oc get pods -n openshift-pipelines | grep manual-approval
# 기대: controller + webhook Running
~~~

### 13. RHCL (Red Hat Connectivity Link) 설치 (Layer 5)

MaaS Rate Limiting과 API 관리(S6)를 위한 Kuadrant 스택.

~~~bash
oc create namespace kuadrant-system --dry-run=client -o yaml | oc apply -f -

## 주의: RHCL 의존성(Authorino/Limitador/DNS)은 AllNamespaces 모드만 지원
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kuadrant-og
  namespace: kuadrant-system
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhcl-operator
  namespace: kuadrant-system
spec:
  channel: stable
  name: rhcl-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "RHCL 설치 대기 (최대 5분)..."
sleep 60
oc wait csv -n kuadrant-system \
  -l operators.coreos.com/rhcl-operator.kuadrant-system \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=300s 2>/dev/null || \
  (sleep 60 && oc get csv -n kuadrant-system | grep rhcl)

oc apply -f - <<'EOF'
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
spec: {}
EOF

sleep 30
oc patch limitador limitador -n kuadrant-system --type='merge' -p '
spec:
  replicas: 1
  resourceRequirements:
    requests:
      cpu: 50m
      memory: 32Mi
    limits:
      cpu: 200m
      memory: 64Mi
'
sleep 30 && oc get pods -n kuadrant-system --no-headers
# 기대: kuadrant-operator, authorino, limitador 모두 Running

# Authorino에 service-ca 신뢰 설정 (MaaS API Key 검증에 필수)
# Authorino → maas-api 내부 호출 시 OpenShift service-serving-signer CA를 신뢰해야 함
# 이 설정 없이는 API Key 사용 시 403 (TLS bad certificate) 발생
oc apply -n kuadrant-system -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: authorino-service-ca
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF

oc patch authorino authorino -n kuadrant-system --type='merge' -p '{
  "spec": {
    "volumes": {
      "items": [
        {
          "name": "service-ca",
          "mountPath": "/etc/ssl/certs",
          "configMaps": ["authorino-service-ca"]
        }
      ]
    }
  }
}'
echo "Authorino service-ca 신뢰 설정 완료"
~~~

### 14. MaaS (Models as a Service) 활성화 (Layer 5)

> **주의**: maas-api는 **PostgreSQL 필수** (SQLite 미지원). PoC용 PostgreSQL을 배포한다.

~~~bash
oc scale deployment rhods-dashboard -n redhat-ods-applications --replicas=1

# MaaS 전제 조건 1: PoC용 PostgreSQL 배포
oc apply -n redhat-ods-applications -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: maas-postgres-secret
type: Opaque
stringData:
  POSTGRES_USER: maasuser
  POSTGRES_PASSWORD: maaspass123
  POSTGRES_DB: maasdb
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: maas-postgres-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: maas-postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: maas-postgres
  template:
    metadata:
      labels:
        app: maas-postgres
    spec:
      containers:
        - name: postgres
          image: docker.io/library/postgres:16-alpine
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: maas-postgres-secret
          env:
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          resources:
            limits:
              cpu: 200m
              memory: 256Mi
            requests:
              cpu: 50m
              memory: 128Mi
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: maas-postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: maas-postgres
spec:
  selector:
    app: maas-postgres
  ports:
    - port: 5432
EOF

oc wait deploy/maas-postgres -n redhat-ods-applications \
  --for=condition=Available --timeout=120s

# MaaS 전제 조건 2: DB Connection Secret
oc apply -n redhat-ods-applications -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: maas-db-config
type: Opaque
stringData:
  DB_CONNECTION_URL: "postgresql://maasuser:maaspass123@maas-postgres.redhat-ods-applications.svc.cluster.local:5432/maasdb?sslmode=disable"
EOF

# MaaS 전제 조건 3: UWM 활성화 (step 2에서 완료)
oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml | grep -q enableUserWorkload || \
  echo "WARNING: UWM 미활성화 — step 2 확인 필요"

# ⚠️ Gateway를 먼저 생성한 후 DSC modelsAsService를 활성화해야 한다.
# 순서가 뒤바뀌면 ModelsAsServiceReady=False로 DSC가 수렴하지 않는다.
# 참조: constraints.md:144, maas-setup.md §2 "Gateway must exist before enabling modelsAsService"

CLUSTER_DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
TLS_SECRET=$(oc get secret -n openshift-ingress -o name 2>/dev/null \
  | grep "cert-manager\|tls" | head -1 | cut -d/ -f2)
if [ -z "${TLS_SECRET}" ]; then
  echo "WARNING: TLS Secret 없음. 자체 서명 인증서 생성..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -subj '/CN=maas' -keyout /tmp/maas.key -out /tmp/maas.crt 2>/dev/null
  oc create secret tls maas-selfsigned-tls \
    --cert=/tmp/maas.crt --key=/tmp/maas.key \
    -n openshift-ingress --dry-run=client -o yaml | oc apply -f -
  rm -f /tmp/maas.key /tmp/maas.crt
  TLS_SECRET="maas-selfsigned-tls"
fi
echo "TLS Secret: ${TLS_SECRET}"

GATEWAY_CLASS=$(oc get gatewayclass -o jsonpath='{.items[0].metadata.name}')
oc apply -n openshift-ingress -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
spec:
  gatewayClassName: ${GATEWAY_CLASS}
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "maas.${CLUSTER_DOMAIN}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: ${TLS_SECRET}
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchExpressions:
              - key: kubernetes.io/metadata.name
                operator: In
                values:
                  - openshift-ingress
                  - redhat-ods-applications
                  - ${POC_NAMESPACE}
EOF

# MaaS Gateway Route 생성 (maas-ui → MaaS API 외부 접근 경로)
# Gateway Service는 Istio proxy이므로 passthrough로 TLS를 직접 전달
MAAS_GW_SVC=$(oc get svc -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  -o jsonpath='{.items[0].metadata.name}')
if [ -n "${MAAS_GW_SVC}" ]; then
  oc get route maas-gateway -n openshift-ingress &>/dev/null || \
  oc apply -n openshift-ingress -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: maas-gateway
  labels:
    app.kubernetes.io/part-of: rhoai
    app.kubernetes.io/component: models-as-service
spec:
  host: "maas.${CLUSTER_DOMAIN}"
  port:
    targetPort: 443
  tls:
    termination: passthrough
  to:
    kind: Service
    name: ${MAAS_GW_SVC}
    weight: 100
  wildcardPolicy: None
EOF
  echo "MaaS Gateway Route: maas.${CLUSTER_DOMAIN}"
else
  echo "[WARN] maas-default-gateway Service 미발견 — Route 생성 생략"
fi

# Gateway 생성 완료 후 DSC modelsAsService 활성화
oc patch dsc default-dsc --type='merge' \
  -p '{"spec":{"components":{"kserve":{"modelsAsService":{"managementState":"Managed"}}}}}'

echo "MaaS 활성화 대기 (최대 3분)..."
sleep 120
oc get dsc default-dsc -o jsonpath='{.status.conditions}' \
  | python3 -c "
import json, sys
for c in json.loads(sys.stdin.read()):
    if 'ModelsAsService' in c.get('type',''):
        print(f\"{c['type']}: {c['status']}\")
" 2>/dev/null || echo "ModelsAsService 상태 확인 필요"

# MaaS 전제 조건 4: Tier-to-Group 매핑 (API Key 발급에 필수)
# 이 ConfigMap 없이는 Dashboard에서 API Key 생성 불가
oc apply -n redhat-ods-applications -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tier-to-group-mapping
data:
  config.yaml: |
    tiers:
      - name: enterprise
        level: 3
        groups:
          - rhods-admins
          - system:cluster-admins
        rateLimit:
          requestsPerMinute: 100
          tokensPerMinute: 100000
      - name: premium
        level: 2
        groups:
          - rhods-admins
        rateLimit:
          requestsPerMinute: 50
          tokensPerMinute: 50000
      - name: free
        level: 1
        groups:
          - system:authenticated
        rateLimit:
          requestsPerMinute: 10
          tokensPerMinute: 10000
EOF

# admin 사용자를 rhods-admins 그룹에 추가
oc adm groups add-users rhods-admins "${OCP_ADMIN_USER}" 2>/dev/null || echo "이미 추가됨"

# maas-api 재시작 (ConfigMap 반영)
oc delete pod -n redhat-ods-applications -l app.kubernetes.io/name=maas-api
echo "tier-to-group-mapping + 그룹 설정 완료"
~~~

### 15. htpasswd IdP + RBAC 테스트 사용자 (Layer 6)

~~~bash
: "${POC_ADMIN_PASS:=admin123}"
: "${POC_OPERATOR_PASS:=operator123}"
: "${POC_USER_PASS:=user123}"

htpasswd -c -B -b /tmp/htpasswd poc-admin "${POC_ADMIN_PASS}"
htpasswd -B -b /tmp/htpasswd poc-operator "${POC_OPERATOR_PASS}"
htpasswd -B -b /tmp/htpasswd poc-user "${POC_USER_PASS}"

oc create secret generic htpasswd-poc \
  --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config \
  --dry-run=client -o yaml | oc apply -f -
rm -f /tmp/htpasswd

oc patch oauth cluster --type='json' \
  -p '[{"op":"add","path":"/spec/identityProviders/-","value":{"name":"htpasswd-poc","type":"HTPasswd","htpasswd":{"fileData":{"name":"htpasswd-poc"}}}}]' 2>/dev/null || \
  echo "WARNING: IdP 추가 실패. 'oc edit oauth cluster'로 수동 추가하세요."

oc adm policy add-role-to-user admin poc-admin -n "${POC_NAMESPACE}"
oc adm policy add-role-to-user edit poc-operator -n "${POC_NAMESPACE}"
oc adm policy add-role-to-user view poc-user -n "${POC_NAMESPACE}"
~~~

### 16. Observability Dashboard 구성 (Layer 6b)

DSCI traces를 활성화하고 PersesDatasource + UIPlugin을 생성한다. RHOAI 3.4+ 전용.

~~~bash
# DSCI Observability Stack 활성화
oc patch dsci default-dsci --type='merge' -p '{
  "spec": {
    "monitoring": {
      "managementState": "Managed",
      "namespace": "redhat-ods-monitoring",
      "metrics": {},
      "traces": {
        "storage": {
          "backend": "pv",
          "size": "5Gi",
          "retention": "24h"
        }
      }
    }
  }
}'

echo "Observability Pod 배포 대기 (최대 5분)..."
sleep 180
oc get pods -n redhat-ods-monitoring --no-headers
# 기대: data-science-perses-0, data-science-collector-collector-0, tempo-*-0 모두 Running

# service-ca ConfigMap (TLS 워크어라운드)
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-web-tls-ca
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
data: {}
EOF

# prometheus-secret (Thanos Querier SA 토큰 인증)
# RHOAI Operator는 PersesDatasource를 자동 생성하지 않음.
# Perses HTTPProxy가 Thanos Querier에 접근할 때 SA 토큰이 필수이며,
# 이 Secret이 없으면 대시보드에서 "No matching datasource found" 또는
# "tls: certificate signed by unknown authority" 에러 발생.
oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  -z default -n redhat-ods-monitoring
PERSES_SA_TOKEN=$(oc create token default -n redhat-ods-monitoring --duration=87600h)
oc apply -n redhat-ods-monitoring -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: prometheus-secret
type: Opaque
stringData:
  Authorization: "Bearer ${PERSES_SA_TOKEN}"
EOF

# PersesDatasource (Product Gap 우회)
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: perses.dev/v1alpha2
kind: PersesDatasource
metadata:
  name: prometheus
spec:
  client:
    tls:
      enable: true
      caCert:
        type: configmap
        name: prometheus-web-tls-ca
        certPath: service-ca.crt
  config:
    default: true
    display:
      name: Prometheus (Thanos Querier)
    plugin:
      kind: PrometheusDatasource
      spec:
        proxy:
          kind: HTTPProxy
          spec:
            secret: prometheus-secret
            url: https://thanos-querier.openshift-monitoring.svc:9091
        scrapeInterval: 30s
EOF

# NetworkPolicy (Perses Operator 접근 허용)
oc apply -n redhat-ods-monitoring -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-perses-operator
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: perses
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 8080
EOF

# COO UIPlugin (OCP Console 대시보드 메뉴)
oc apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: monitoring
spec:
  type: Monitoring
  monitoring:
    perses:
      enabled: true
---
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: dashboards
spec:
  type: Dashboards
---
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: troubleshooting-panel
spec:
  type: TroubleshootingPanel
EOF
~~~

## 검증

~~~bash
echo "=== 40 — 플랫폼 사전 구성 검증 ==="

# [Layer 1] 네임스페이스
NS_PHASE="$(oc get ns "${POC_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)"
echo "1. 네임스페이스 (${POC_NAMESPACE}): ${NS_PHASE}"

# [Layer 1] UWM
UWM_COUNT="$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | grep -c Running)"
echo "2. UWM Pod 수: ${UWM_COUNT}"

# [Layer 2] Dashboard config
GEN_AI="$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null)"
echo "3. genAiStudio: ${GEN_AI}"

# [Layer 2] Dashboard Route
DASH_HOST="$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null)"
echo "4. Dashboard: https://${DASH_HOST}"

# [Layer 2b] COO/Tempo/OTel
for NS in openshift-cluster-observability-operator openshift-tempo-operator openshift-opentelemetry-operator; do
  CSV_STATUS=$(oc get csv -n "$NS" --no-headers 2>/dev/null | awk '{print $NF}' | head -1)
  echo "5. ${NS}: ${CSV_STATUS:-미설치}"
done

# [Layer 3] MinIO
MINIO_STATUS="$(oc get pods -n "${POC_NAMESPACE}" -l app=minio -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "6. MinIO: ${MINIO_STATUS}"

# [Layer 3] Data Connection
oc get secret poc-s3-connection -n "${POC_NAMESPACE}" -o jsonpath='{.metadata.annotations.opendatahub\.io/connection-type}' 2>/dev/null | grep -q s3 && echo "6d. Data Connection: OK" || echo "6d. Data Connection: MISSING"

# [Layer 3] Gitea
GITEA_STATUS="$(oc get pods -n "${POC_NAMESPACE}" -l app=gitea -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "7. Gitea: ${GITEA_STATUS}"

# [Layer 3] MailHog
MAILHOG_STATUS="$(oc get pods -n "${POC_NAMESPACE}" -l app=mailhog -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "8. MailHog: ${MAILHOG_STATUS}"

# [Layer 4] CMA / KEDA
CMA_PHASE="$(oc get csv -n openshift-keda --no-headers 2>/dev/null | grep custom-metrics | awk '{print $NF}')"
KEDA_PODS="$(oc get pods -n openshift-keda --no-headers 2>/dev/null | grep -c Running)"
echo "9-10. CMA: ${CMA_PHASE}, KEDA Pods: ${KEDA_PODS}"

# [Layer 4] ManualApprovalGate
MAG_PODS="$(oc get pods -n openshift-pipelines --no-headers 2>/dev/null | grep -c manual-approval)"
echo "11. ManualApprovalGate Pods: ${MAG_PODS}"

# [Layer 5] RHCL / Kuadrant
KUADRANT_PODS="$(oc get pods -n kuadrant-system --no-headers 2>/dev/null | grep -c Running)"
echo "12. Kuadrant Pods: ${KUADRANT_PODS}"

# [Layer 5] MaaS Gateway + Route
MAAS_GW="$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.name}' 2>/dev/null)"
MAAS_RT="$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null)"
echo "13. MaaS Gateway: ${MAAS_GW:-미존재}, Route: ${MAAS_RT:-미존재}"

# [Layer 6] htpasswd IdP
IDP_LIST="$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' 2>/dev/null)"
echo "14. Identity Providers: ${IDP_LIST}"

# [Layer 6b] Observability Dashboard
PERSES_STATUS="$(oc get pods -n redhat-ods-monitoring -l app.kubernetes.io/name=perses -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "15. Perses: ${PERSES_STATUS:-미배포}"
DATASOURCE="$(oc get persesdatasource prometheus -n redhat-ods-monitoring -o jsonpath='{.metadata.name}' 2>/dev/null)"
echo "15. PersesDatasource: ${DATASOURCE:-미존재}"

echo "=== 검증 완료 ==="
~~~

## 실패 시

- **MinIO Pod CrashLoopBackOff** → `oc logs -n ${POC_NAMESPACE} deploy/minio` 확인. PVC 바인딩 실패가 흔한 원인
- **Gitea Pod Pending** → PVC 할당 부족. `oc describe pvc gitea-pvc -n ${POC_NAMESPACE}` 확인
- **UWM Pod 미생성** → `oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml` 확인
- **OdhDashboardConfig 패치 실패** → RHOAI Operator `Succeeded` 확인 후 재시도
- **DSC 컴포넌트 Degraded** → GPU 없는 환경에서 `ray` 활성화 시 리소스 부족 가능 — `Removed`로 복원
- **COO/Tempo/OTel CSV 미설치** → `oc get packagemanifest -n openshift-marketplace | grep -E 'observability|tempo|opentelemetry'`로 카탈로그 확인
- **COO Perses Operator 무한 루프 (RHOAI 3.4 + COO 1.4)** → RHOAI Dashboard Controller가 `dashboard-0-cluster-admin`, `dashboard-1-model`을 deprecated `v1alpha1` API로 PUT → COO conversion webhook이 `v1alpha2`로 변환 → perses-operator Watch 감지 → Perses 동기화 → ownerRef Watch가 RHOAI에 이벤트 전달 → 무한 반복 (초당 5회, generation 63만+). 진단: `oc get persesdashboard -n redhat-ods-monitoring -o custom-columns='NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind,GEN:.metadata.generation'`. **해결: dashboard-0, dashboard-1의 ownerReferences 제거** — `oc get persesdashboard <name> -n redhat-ods-monitoring -o json` → python3로 ownerReferences/managedFields 삭제 → `oc replace -f`. IaC에서도 ownerReferences 삭제 (`infra/rhoai/dashboards/`). **replicas=0은 사용 금지** (OLM CSV unhealthy → DSC Ready=False 연쇄). 근본 원인: GitHub Issue #3550 (RHOAIENG-62730)
- **CMA CSV 미설치** → `oc get packagemanifest -n openshift-marketplace | grep custom-metrics` 확인
- **KedaController Pod 미생성** → CMA Operator `Succeeded` 확인. `oc describe kedacontroller keda -n openshift-keda`
- **RHCL 설치 실패** → `oc get csv -n kuadrant-system` 확인. Authorino/Limitador/DNS가 함께 필요
- **MaaS Gateway 미생성** → GatewayClass 확인: `oc get gatewayclass` (OCP 4.20: `openshift-ai-inference`, 4.21: `data-science-gateway-class`)
- **maas-api CrashLoopBackOff (invalid database URL)** → maas-api는 **PostgreSQL 필수** (SQLite 미지원). `maas-db-config` Secret의 `DB_CONNECTION_URL`이 `postgresql://user:pass@host:5432/db` 형식인지 확인. PoC용 PostgreSQL 배포 필요 (step 14 참조)
- **maas-api Deployment selector immutable** → 기존 Deployment 삭제 후 Operator가 재생성: `oc delete deploy maas-api -n redhat-ods-applications`
- **MaaS API Key 403 (PERMISSION_DENIED)** → Authorino → maas-api 호출 시 TLS 인증서 미신뢰. step 13의 `authorino-service-ca` ConfigMap + Authorino CR volumes 설정 확인
- **MaaS API Key 발급 안됨 (Dashboard)** → `tier-to-group-mapping` ConfigMap 없음. step 14의 전제 조건 4 실행. 사용자가 `rhods-admins` 그룹에 속해야 함
- **Dashboard API Keys 페이지 "Error loading components"** → 아래 순서로 점검:
  1. **Route 누락**: `oc get route maas-gateway -n openshift-ingress`. 없으면 step 14의 Route 생성 블록 재실행. maas-ui가 `maas.${CLUSTER_DOMAIN}`으로 MaaS API를 호출하므로 이 Route가 필수
  2. **Gateway allowedRoutes 설정 오류**: `oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.from}'`이 `All`이면 `Selector`로 변경 필요. `from: All`이면 `odh-model-controller`가 `maas-default-gateway-authn` AuthPolicy를 삭제함. 수정: `oc patch gateway maas-default-gateway -n openshift-ingress --type=merge -p '{"spec":{"listeners":[{"name":"https","port":443,"protocol":"HTTPS","allowedRoutes":{"namespaces":{"from":"Selector","selector":{"matchExpressions":[{"key":"kubernetes.io/metadata.name","operator":"In","values":["openshift-ingress","redhat-ods-applications","${POC_NAMESPACE}"]}]}}}}]}}'`
  3. **`maas-default-gateway-authn` AuthPolicy 미생성**: `oc get authpolicy maas-default-gateway-authn -n openshift-ingress`. 이 AuthPolicy는 `odh-model-controller`가 MaaS Gateway에 연결된 `LLMInferenceService`가 있을 때만 자동 생성. RawDeployment 모드의 InferenceService만 있으면 생성 안 됨. MaaS Dashboard에서 모델을 subscription에 등록하면 LLMInferenceService CR이 자동 생성되고, 이후 authn AuthPolicy도 생성됨
  4. **MaaS API `X-MaaS-Username` 헤더 누락**: Gateway를 우회하여 maas-api를 직접 호출하면 발생. Authorino가 인증 후 이 헤더를 주입하므로 반드시 Gateway 경로를 사용해야 함
- **Gen AI Studio Playground 응답 없음** → (1) LlamaStack config의 `base_url`이 HTTP인데 llm-d vLLM이 HTTPS를 사용하는 경우. `oc get configmap llama-stack-config -n rhoai-poc`에서 `base_url`을 `https://`로 변경 후 Pod 삭제로 재시작 (2) 구독에 해당 모델이 없는 경우 403. `oc get maassubscription -n models-as-a-service`에서 모델 추가
- **Usage 대시보드 데이터 없음 / 드롭다운 비어있음** → (1) Limitador ServiceMonitor 생성 필요 (`kuadrant-system` NS) (2) NS에 `openshift.io/cluster-monitoring: true` 라벨 (3) `kuadrant-prometheus-datasource` Perses Secret에 SA 토큰 + CA 번들 — Perses API로 설정 (4) SA에 `cluster-admin` ClusterRole (5) user/subscription/model 레이블은 MaaS TP 제한
- **trustyai-metrics ServiceMonitor down** → (1) port `http` → Service 포트 이름 `metrics`로 일치 (2) path `/q/metrics` → Operator는 `/metrics` (3) `allow-monitoring` NetworkPolicy 필요
- **ds-pipeline-dspa 400 Bad Request** → `scheme: https` + `tlsConfig.insecureSkipVerify: true` 추가
- **ManualApprovalGate 미동작** → Tekton Pipelines 1.22+ 필수
- **htpasswd IdP 추가 실패** → `oc edit oauth cluster`로 수동 추가
- **Perses Pod Pending/FailedCreate** → SCC 부족: `oc adm policy add-scc-to-user nonroot-v2 -z perses-sa -n redhat-ods-monitoring`. LimitRange min 과다 시 하향 조정
- **Perses Prometheus 데이터 없음** → PersesDatasource `config.default: true` 확인. TLS CA ConfigMap 주입 확인
- **DSC DashboardReady=False / ModelsAsServiceReady=False "conversion webhook for PersesDashboard failed: no endpoints"** → `perses-operator` Deployment가 replicas=0으로 축소되어 있음. 복구: `oc scale deployment perses-operator -n openshift-cluster-observability-operator --replicas=1`. **근본 원인이 COO+RHOAI 무한 루프였다면 replicas 복구만으로 재발** — 반드시 dashboard-0/1의 ownerReferences 제거까지 완료할 것 (위 항목 참조). CPU 모니터링: `oc adm top pods -n openshift-cluster-observability-operator`
- **MaaS Gateway 403 `rbac_access_denied_matched_policy[none]` (모든 요청 거부)** → on-prem 사설 CA 환경에서 Kuadrant WasmPlugin TLS 검증 실패. **`runbooks/115-proxy-trusted-ca.md`** 실행 (proxy/cluster trustedCA 등록 + Gateway CA 마운트). Dashboard "Error loading components" (API Keys 페이지)도 동일 원인
- **vLLM "ValueError: aimv2 is already used by a Transformers config"** → vLLM 이미지의 transformers 버전 충돌. RHOAI template의 기본 이미지 digest가 최신 transformers(4.58+)를 포함하면 발생. 해결: sandbox에서 실제 동작 중인 이미지 digest 확인 후 교체: `oc get pods -n <ns> -l serving.kserve.io/inferenceservice=<model> -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="kserve-container")].imageID}'`

## 다음 단계

→ `runbooks/110-gpu-stack.md` (GPU 스택 필요 시) 또는 `runbooks/300-model-serving.md` (시나리오 구축 시작)

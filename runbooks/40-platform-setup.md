# 40 — 플랫폼 사전 구성

## 목적

RHOAI PoC 실행에 필요한 플랫폼 보조 서비스(MinIO S3, Gitea, User Workload Monitoring)를 배포하고, PoC 네임스페이스와 RHOAI Dashboard/DSC 설정을 구성한다. 이 단계는 시나리오 런북(60~65)의 전제 조건이다.

## 전제 조건

- [ ] `runbooks/31-rhoai-dependency-app-sync.md` 완료 — 의존성 Application `Synced/Healthy`
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

### 1. PoC 네임스페이스 생성

~~~bash
oc create namespace "${POC_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc label ns "${POC_NAMESPACE}" opendatahub.io/dashboard=true --overwrite
~~~

### 2. User Workload Monitoring 활성화

PoC 시나리오에서 커스텀 메트릭 수집(Prometheus, TrustyAI 등)을 위해 필수.

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

### 3. MinIO S3 스토리지 배포

모델 아티팩트·파이프라인 산출물 저장용 S3 호환 스토리지.

#### 3-a. MinIO 자격 증명 Secret

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

#### 3-b. MinIO Deployment + Service + Route

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

#### 3-c. 버킷 초기화

~~~bash
oc exec -n "${POC_NAMESPACE}" deploy/minio -- \
  mkdir -p "/data/${S3_BUCKET}" /data/poc-pipeline-artifacts
~~~

#### 3-d. RHOAI Data Connection Secret

RHOAI Dashboard에서 S3 연결을 인식하기 위한 라벨·어노테이션 포함.

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

### 4. Gitea 배포

PoC 전용 Git 리포지토리. GitOps 모드에서 ArgoCD 원격 저장소로 사용.

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

### 5. OdhDashboardConfig + DSC 컴포넌트 패치

RHOAI Dashboard에서 Gen AI Studio, MaaS 메뉴, 모델 카탈로그 등을 활성화한다.

~~~bash
# Dashboard 기능 활성화
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
        "modelAsService": true
      },
      "modelServing": {
        "deploymentStrategy": "rolling",
        "isLLMdDefault": true
      }
    }
  }'

# DSC 컴포넌트 활성화 (기본 Removed인 항목)
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

### 6. RHOAI Dashboard Route 확인

~~~bash
oc create route passthrough rhods-dashboard \
  -n redhat-ods-applications \
  --service=rhods-dashboard \
  --port=8443 2>/dev/null || echo "INFO: Route 이미 존재"

DASH_URL="$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')"
echo "RHOAI Dashboard: https://${DASH_URL}"
~~~

## 검증

~~~bash
echo "=== 40 — 플랫폼 사전 구성 검증 ==="

# 네임스페이스
NS_PHASE="$(oc get ns "${POC_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)"
echo "네임스페이스 (${POC_NAMESPACE}): ${NS_PHASE}"
test "${NS_PHASE}" = "Active"

# MinIO
MINIO_STATUS="$(oc get pods -n "${POC_NAMESPACE}" -l app=minio -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "MinIO: ${MINIO_STATUS}"
test "${MINIO_STATUS}" = "Running"

# Data Connection Secret
oc get secret poc-s3-connection -n "${POC_NAMESPACE}" -o jsonpath='{.metadata.annotations.opendatahub\.io/connection-type}' | grep -q s3
echo "Data Connection: OK"

# Gitea
GITEA_STATUS="$(oc get pods -n "${POC_NAMESPACE}" -l app=gitea -o jsonpath='{.items[0].status.phase}' 2>/dev/null)"
echo "Gitea: ${GITEA_STATUS}"
test "${GITEA_STATUS}" = "Running"

# User Workload Monitoring
UWM_COUNT="$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | grep -c Running)"
echo "UWM Pod 수: ${UWM_COUNT}"
test "${UWM_COUNT}" -ge 3

# Dashboard config
GEN_AI="$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null)"
echo "genAiStudio: ${GEN_AI}"
test "${GEN_AI}" = "true"

# Dashboard Route
DASH_HOST="$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null)"
echo "Dashboard: https://${DASH_HOST}"
test -n "${DASH_HOST}"

echo "=== 검증 완료 ==="
~~~

## 실패 시

- **MinIO Pod CrashLoopBackOff** → `oc logs -n ${POC_NAMESPACE} deploy/minio` 확인. PVC 바인딩 실패가 흔한 원인. `oc get pvc -n ${POC_NAMESPACE}` 로 PVC 상태 확인 후 StorageClass 존재 여부 점검
- **Gitea Pod Pending** → PVC 할당 부족. `oc describe pvc gitea-pvc -n ${POC_NAMESPACE}` 로 이벤트 확인. 기본 StorageClass가 없으면 `oc get sc` 후 PVC에 `storageClassName` 명시
- **UWM Pod 미생성** → `cluster-monitoring-config` ConfigMap이 `openshift-monitoring` 네임스페이스에 존재하는지 확인. `oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml`
- **OdhDashboardConfig 패치 실패** → RHOAI Operator가 아직 준비되지 않음. `oc get csv -n redhat-ods-operator --no-headers` 로 `Succeeded` 확인 후 재시도
- **DSC 패치 후 컴포넌트 Degraded** → `oc get dsc default-dsc -o jsonpath='{.status.conditions}'` 로 어떤 컴포넌트가 실패했는지 확인. GPU 없는 환경에서 `ray` 활성화 시 리소스 부족 가능 — 해당 컴포넌트를 `Removed`로 복원

## 다음 단계

→ `runbooks/45-gpu-stack.md` (GPU 스택 필요 시) 또는 `runbooks/50-rhoai-topology.md` (RHOAI 토폴로지 정합화)

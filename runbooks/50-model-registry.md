# 50 — Model Registry 인스턴스 구성

## 목적

PoC 전용 Model Registry 인스턴스(PostgreSQL 백엔드)를 생성하여 모델 등록/버전 관리/메타데이터 CRUD를 제공한다.

## 전제 조건

- [ ] `runbooks/40-platform-setup.md` 완료
- [ ] `default-dsc` Ready=True, ModelRegistryReady=True
- [ ] `${MODEL_REGISTRY_NS}` 환경변수 설정

## 실행

### 1. Model Registry 네임스페이스

~~~bash
set -a && source .env && set +a
: "${MODEL_REGISTRY_NS:=rhoai-model-registries}"

oc create namespace "${MODEL_REGISTRY_NS}" --dry-run=client -o yaml | oc apply -f -
oc label ns "${MODEL_REGISTRY_NS}" opendatahub.io/dashboard=true --overwrite
~~~

### 2. PostgreSQL 배포 (Model Registry 백엔드)

~~~bash
oc apply -n "${MODEL_REGISTRY_NS}" -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: mr-postgres-secret
type: Opaque
stringData:
  database-password: mrpassword123
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mr-postgres-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mr-postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mr-postgres
  template:
    metadata:
      labels:
        app: mr-postgres
    spec:
      containers:
        - name: postgres
          image: docker.io/library/postgres:16-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: mruser
            - name: POSTGRES_PASSWORD
              value: mrpassword123
            - name: POSTGRES_DB
              value: modelregistry
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
            claimName: mr-postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mr-postgres
spec:
  selector:
    app: mr-postgres
  ports:
    - port: 5432
EOF

oc wait deploy/mr-postgres -n "${MODEL_REGISTRY_NS}" \
  --for=condition=Available --timeout=120s
~~~

### 3. ModelRegistry CR 생성

~~~bash
oc apply -n "${MODEL_REGISTRY_NS}" -f - <<EOF
apiVersion: modelregistry.opendatahub.io/v1beta1
kind: ModelRegistry
metadata:
  name: poc-model-registry
spec:
  grpc:
    port: 9090
  rest:
    port: 8080
    serviceRoute: enabled
  postgres:
    host: mr-postgres.${MODEL_REGISTRY_NS}.svc.cluster.local
    database: modelregistry
    username: mruser
    passwordSecret:
      name: mr-postgres-secret
      key: database-password
    port: 5432
    sslMode: disable
    skipDBCreation: false
EOF

echo "ModelRegistry CR 대기 (최대 2분)..."
sleep 30
oc get modelregistry -n "${MODEL_REGISTRY_NS}"
# 기대: poc-model-registry Available=True
~~~

## 검증

~~~bash
echo "=== 50 — Model Registry 검증 ==="
echo "Postgres: $(oc get pods -n ${MODEL_REGISTRY_NS} -l app=mr-postgres -o jsonpath='{.items[0].status.phase}')"
MR_AVAILABLE=$(oc get modelregistry poc-model-registry -n "${MODEL_REGISTRY_NS}" \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
echo "ModelRegistry: Available=${MR_AVAILABLE}"
MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers 2>/dev/null | awk '{print $2}' | head -1)
echo "Route: ${MR_ROUTE}"
~~~

## 실패 시

- **Postgres ErrImagePull** → Red Hat 이미지 대신 `docker.io/library/postgres:16-alpine` 사용
- **ModelRegistry Available=False** → Postgres 연결 확인: `oc logs deploy/poc-model-registry -n ${MODEL_REGISTRY_NS}`

## 다음 단계

→ `runbooks/51-serving-runtime.md` — vLLM ServingRuntime 구성

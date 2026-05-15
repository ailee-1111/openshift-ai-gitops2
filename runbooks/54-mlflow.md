# 54 — MLflow Server 구성

## 목적

MLflow Tracking Server를 배포하여 실험 추적, 메트릭 기록, 아티팩트 저장을 활성화한다. RHOAI Dashboard Experiment Tracking 메뉴의 전제 조건.

## 전제 조건

- [ ] `runbooks/53-trustyai.md` 완료
- [ ] DSC `mlflowoperator.managementState: Managed`
- [ ] PostgreSQL 접근 가능
- [ ] `poc-s3-connection` Secret 존재

## 실행

### 1. DSC MLflow 확인

~~~bash
set -a && source .env && set +a
echo "MLflow DSC: $(oc get dsc default-dsc -o jsonpath='{.spec.components.mlflowoperator.managementState}')"
~~~

### 2. MLflow Server 생성

> **주의**: `backendStoreUri`에 PostgreSQL 사용 시 **`?sslmode=disable`** 필수.
> SQLite는 미지원.

~~~bash
oc apply -n "${MODEL_NS}" -f - <<'EOF'
apiVersion: mlflow.opendatahub.io/v1
kind: MLflow
metadata:
  name: mlflow
spec:
  backendStoreUri: "postgresql://maasuser:maaspass123@maas-postgres.redhat-ods-applications.svc.cluster.local:5432/maasdb?sslmode=disable"
  serveArtifacts: true
  objectStorage:
    objectStorageSecretName: poc-s3-connection
EOF

echo "MLflow 배포 대기 (최대 2분)..."
sleep 60
oc get mlflow -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: available={.status.conditions[?(@.type=="Available")].status}{"\n"}{end}'
~~~

## 검증

~~~bash
echo "=== 54 — MLflow 검증 ==="
echo "MLflow URL: $(oc get mlflow mlflow -n ${MODEL_NS} -o jsonpath='{.status.url}' 2>/dev/null)"
echo "Pod: $(oc get pods -n redhat-ods-applications --no-headers | grep mlflow | grep -v operator | awk '{print $1, $3}')"
~~~

## 실패 시

- **`SSL was required` (db-migration)** → URI에 `?sslmode=disable` 추가
- **`storage must be configured`** → SQLite 미지원. PostgreSQL URI 사용
- **Pod ImagePullBackOff** → `registry.redhat.io` pull-secret 확인

## 다음 단계

→ `runbooks/60-model-serving.md` — S1 모델 서빙 구축

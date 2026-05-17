# 210 — DataSciencePipelinesApplication 구성

## 목적

PoC 네임스페이스에 DSPA를 생성하여 Tekton 기반 ML 파이프라인 실행 환경을 구성한다. S2 Pipeline 시나리오의 전제 조건.

## 전제 조건

- [ ] `runbooks/201-serving-runtime.md` 완료
- [ ] Pipelines Operator Succeeded
- [ ] MinIO + `poc-s3-connection` Secret 존재
- [ ] `${MODEL_NS}` 환경변수 설정

## 실행

### 1. DSPA CR 생성

~~~bash
set -a && source .env && set +a

oc apply -n "${MODEL_NS}" -f - <<EOF
# 주의: RHOAI 3.4에서는 v1 (v1alpha1 아님)
apiVersion: datasciencepipelinesapplications.opendatahub.io/v1
kind: DataSciencePipelinesApplication
metadata:
  name: dspa
spec:
  apiServer:
    cABundle:
      configMapName: odh-trusted-ca-bundle
      configMapKey: ca-bundle.crt
    enableSamplePipeline: false
  database:
    mariaDB:
      deploy: true
      pipelineDBName: mlpipeline
      pvcSize: 10Gi
  objectStorage:
    externalStorage:
      bucket: poc-pipeline-artifacts
      host: "minio.${MODEL_NS}.svc.cluster.local:9000"
      port: ""
      scheme: http
      s3CredentialsSecret:
        accessKey: AWS_ACCESS_KEY_ID
        secretKey: AWS_SECRET_ACCESS_KEY
        secretName: poc-s3-connection
EOF

echo "DSPA 배포 대기 (최대 3분)..."
sleep 60
oc get dspa -n "${MODEL_NS}"
oc get pods -n "${MODEL_NS}" --no-headers | grep -E "ds-pipeline|mariadb"
~~~

## 검증

~~~bash
echo "=== 52 — DSPA 검증 ==="
DSPA_READY=$(oc get dspa dspa -n "${MODEL_NS}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
echo "DSPA Ready: ${DSPA_READY}"
echo "Pods:"
oc get pods -n "${MODEL_NS}" --no-headers | grep -E "ds-pipeline|mariadb" | awk '{print "  "$1, $3}'
~~~

## 실패 시

- **DSPA CrashLoop** → S3 연결 확인. `poc-s3-connection` Secret endpoint가 MinIO Service와 일치하는지
- **MariaDB Pending** → PVC 할당: `oc get pvc -n ${MODEL_NS} | grep mariadb`
- **CA bundle 오류** → `odh-trusted-ca-bundle` ConfigMap 없으면 DSPA spec에서 `cABundle` 섹션 제거

## 다음 단계

→ `runbooks/211-trustyai.md` — TrustyAI + Guardrails 구성

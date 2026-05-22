# 300 — 모델 서빙 (Model Registry + vLLM InferenceService)

## 목적

> **Mobis 클러스터 실측 (2026-05-19)**:
> - smollm2-135m InferenceService Ready=True (vllm-cuda-runtime), Route: smollm2-135m-api
> - Model Registry: default-modelregistry Ready=True, S3: poc-s3-connection Secret 존재
> - HardwareProfile 5개 (cpu-small, default, gpu-small/medium/large), gpu-xlarge-h200 미생성
> - qwen3-8b는 MaaS(LLMInferenceService) 경유로 별도 관리

S3 호환 스토리지에 모델 아티팩트를 저장하고, RHOAI Model Registry에 등록한 뒤, vLLM 기반 GPU 서빙을 배포하여 OpenAI 호환 API로 추론 응답을 확인한다. 모델 라이프사이클(저장 → 등록 → 서빙 → 추론)의 전체 경로가 RHOAI 플랫폼 위에서 K8s 네이티브하게 동작하는지 검증하는 것이 핵심 목적이다.

## 전제 조건

- [ ] `runbooks/030-argocd-app-sync.md` 완료 -- `default-dsc` Ready=True
- [ ] `runbooks/031-rhoai-dependency-app-sync.md` 완료
- [ ] GPU 노드 1개 이상 가용 (`oc get nodes -l nvidia.com/gpu.present=true`)
- [ ] PoC 네임스페이스 생성 완료 (`oc get ns ${POC_NAMESPACE}`)
- [ ] S3 Data Connection Secret `poc-s3-connection` 생성 완료 (`oc get secret poc-s3-connection -n ${POC_NAMESPACE}`)
- [ ] 환경변수 설정 완료 (아래 참조)

필수 환경변수:

~~~bash
# .env 또는 셸에서 export
POC_NAMESPACE="${POC_NAMESPACE:-rhoai-poc}"
MODEL_NS="${POC_NAMESPACE}"
MODEL_REGISTRY_NS="${MODEL_REGISTRY_NS:-rhoai-model-registries}"
MODEL_NAME="${MODEL_NAME:-smollm2-135m}"
S3_BUCKET="${S3_BUCKET:-models}"
S3_MODEL_PATH="${S3_MODEL_PATH:-smollm2-135m/v1}"
MR_DB_PASSWORD="${MR_DB_PASSWORD:-$(openssl rand -base64 12)}"
~~~

## 실행

### 1. Model Registry 용 Postgres 배포

Model Registry의 메타데이터 저장소로 사용할 전용 PostgreSQL을 배포한다.

~~~bash
oc apply -n "${MODEL_REGISTRY_NS}" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mr-postgres-secret
type: Opaque
stringData:
  database-password: "${MR_DB_PASSWORD}"
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
          image: registry.redhat.io/rhel9/postgresql-16:16
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRESQL_USER
              value: mruser
            - name: POSTGRESQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mr-postgres-secret
                  key: database-password
            - name: POSTGRESQL_DATABASE
              value: modelregistry
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          volumeMounts:
            - name: data
              mountPath: /var/lib/pgsql/data
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

oc wait -n "${MODEL_REGISTRY_NS}" deployment/mr-postgres \
  --for=condition=Available --timeout=120s
~~~

### 2. ModelRegistry CR 생성

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
    host: "mr-postgres.${MODEL_REGISTRY_NS}.svc.cluster.local"
    database: modelregistry
    username: mruser
    passwordSecret:
      name: mr-postgres-secret
      key: database-password
    port: 5432
    sslMode: disable
    skipDBCreation: false
EOF

# ModelRegistry Ready 대기
oc wait -n "${MODEL_REGISTRY_NS}" modelregistry/poc-model-registry \
  --for=condition=Available --timeout=180s
~~~

### 3. 모델 다운로드 및 S3 업로드

로컬에서 HuggingFace 모델을 다운로드하고 MinIO S3에 업로드한다.

~~~bash
# HuggingFace 모델 다운로드
pip install huggingface-hub 2>/dev/null
# 모델 HF 경로는 .env의 TOKENIZER_MODEL 참조 (기본: HuggingFaceTB/SmolLM2-135M)
huggingface-cli download "${TOKENIZER_MODEL:-HuggingFaceTB/SmolLM2-135M}" \
  --local-dir "/tmp/${MODEL_NAME}"

# MinIO S3 디렉토리 생성
oc exec -n "${MODEL_NS}" deploy/minio -- \
  mkdir -p "/data/${S3_BUCKET}/${S3_MODEL_PATH}"

# port-forward로 S3 API 업로드
oc port-forward svc/minio -n "${MODEL_NS}" 9000:9000 &
PF_PID=$!
sleep 3

python3 -c "
from minio import Minio
import os

client = Minio('localhost:9000',
    access_key='${MINIO_ACCESS_KEY:-minioadmin}',
    secret_key='${MINIO_SECRET_KEY:-minioadmin}',
    secure=False)
model_dir = '/tmp/${MODEL_NAME}'
for f in os.listdir(model_dir):
    fpath = os.path.join(model_dir, f)
    if os.path.isfile(fpath):
        client.fput_object('${S3_BUCKET}', '${S3_MODEL_PATH}/' + f, fpath)
        print(f'Uploaded: {f}')
"

kill "${PF_PID}" 2>/dev/null
~~~

### 4. Model Registry에 모델 등록

~~~bash
MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" \
  -l app=poc-model-registry \
  -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
# Route가 없으면 fallback: 첫 번째 Route 사용
MR_ROUTE="${MR_ROUTE:-$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers | awk '{print $2}' | head -1)}"
TOKEN=$(oc whoami -t)

# RegisteredModel 생성 (이미 존재하면 409 -- 정상)
curl -sk -X POST \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"name\":\"${MODEL_NAME}\",\"description\":\"${MODEL_NAME} PoC 검증용 모델\"}"

# Model ID 추출
MODEL_ID=$(curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
items = json.load(sys.stdin).get('items', [])
for m in items:
    if m.get('name') == '${MODEL_NAME}':
        print(m['id']); break
")
echo "Model ID: ${MODEL_ID}"

# v1 버전 등록
curl -sk -X POST \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"name\":\"v1\",\"description\":\"s3://${S3_BUCKET}/${S3_MODEL_PATH}\"}"
~~~

### 5. vLLM ServingRuntime + InferenceService 배포

~~~bash
# vLLM CUDA ServingRuntime 생성 (이미 존재하면 무시)
oc process -n redhat-ods-applications vllm-cuda-runtime-template \
  | oc apply -n "${MODEL_NS}" -f - 2>/dev/null || true

# InferenceService 배포
oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: ${MODEL_NAME}
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    minReplicas: 1
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-cuda-runtime
      storage:
        key: poc-s3-connection
        path: ${S3_MODEL_PATH}
      args:
        - --dtype=float16
        - --max-model-len=2048
      # 리소스: .env의 GPU_MEMORY_REQUEST/LIMIT로 조정 (H200 대형 모델은 확대 필요)
      resources:
        requests:
          cpu: "2"
          memory: ${GPU_MEMORY_REQUEST:-4Gi}
          nvidia.com/gpu: "1"
        limits:
          cpu: "4"
          memory: ${GPU_MEMORY_LIMIT:-8Gi}
          nvidia.com/gpu: "1"
      env:
        - name: HF_HUB_OFFLINE
          value: "1"
EOF

# vLLM 모델 로딩에 2~5분 소요
oc wait inferenceservice/"${MODEL_NAME}" -n "${MODEL_NS}" \
  --for=condition=Ready --timeout=600s
~~~

### 6. 추론 테스트

~~~bash
# RawDeployment 모드에서는 Route가 자동 생성되지 않으므로 수동 생성
oc create route edge "${MODEL_NAME}-api" \
  --service="${MODEL_NAME}-metrics" \
  --port=8080 \
  -n "${MODEL_NS}" 2>/dev/null || true

ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}')
echo "Inference Route: https://${ROUTE}"

# /v1/models 확인
curl -sk "https://${ROUTE}/v1/models" | python3 -m json.tool

# /v1/completions 추론
curl -sk "https://${ROUTE}/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"prompt\": \"What is 2+2? Answer:\",
    \"max_tokens\": 20
  }" | python3 -m json.tool
~~~

## 검증

~~~bash
# 1. Postgres Pod Running
oc get pods -n "${MODEL_REGISTRY_NS}" -l app=mr-postgres \
  -o jsonpath='{.items[0].status.phase}'
# 기대: Running

# 2. ModelRegistry Available
oc get modelregistry poc-model-registry -n "${MODEL_REGISTRY_NS}" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
# 기대: Available=True

# 3. S3에 모델 아티팩트 존재
oc exec -n "${MODEL_NS}" deploy/minio -- \
  ls "/data/${S3_BUCKET}/${S3_MODEL_PATH}/"
# 기대: config.json, tokenizer.json, *.safetensors 등

# 4. Model Registry에 모델 등록 확인
MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers | awk '{print $2}' | head -1)
curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('items', []):
    print(f\"{m['name']}: state={m.get('state','?')}\")
"
# 기대: smollm2-135m: state=LIVE

# 5. InferenceService Ready
oc get inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'
# 기대: Ready=True

# 6. vLLM Pod Running + GPU 할당
VLLM_POD=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  -o jsonpath='{.items[0].metadata.name}')
oc get pod "${VLLM_POD}" -n "${MODEL_NS}" \
  -o jsonpath='phase={.status.phase} gpu={.spec.containers[0].resources.limits.nvidia\.com/gpu}'
# 기대: phase=Running gpu=1

# 7. OpenAI 호환 API 응답
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" -o jsonpath='{.spec.host}')
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${ROUTE}/v1/models")
echo "/v1/models HTTP: ${HTTP_CODE}"
# 기대: 200
~~~

## 실패 시

- **Postgres Pod CrashLoopBackOff** → `oc logs -n ${MODEL_REGISTRY_NS} deploy/mr-postgres` 확인. PVC 권한 문제면 `oc get pvc mr-postgres-pvc -n ${MODEL_REGISTRY_NS}` 상태 점검. `Pending`이면 StorageClass 확인.

- **ModelRegistry Available=False** → `oc describe modelregistry poc-model-registry -n ${MODEL_REGISTRY_NS}` 이벤트 확인. Postgres 연결 실패가 흔한 원인 -- Secret의 password와 Deployment의 env가 일치하는지 점검.

- **S3 업로드 실패 (port-forward)** → `pip install minio`가 선행되어야 함. MinIO Pod가 Running인지 확인. `oc get pods -n ${MODEL_NS} -l app=minio`.

- **InferenceService Ready 타임아웃** → `oc describe inferenceservice ${MODEL_NAME} -n ${MODEL_NS}` 이벤트와 `oc logs -l serving.kserve.io/inferenceservice=${MODEL_NAME} -n ${MODEL_NS}` 확인. GPU 부족이면 `Insufficient nvidia.com/gpu` 이벤트 발생. `oc describe node <gpu-node>` 에서 Allocatable gpu 수량 점검.

- **vLLM OOMKilled** → `--max-model-len` 값을 줄이거나 memory limit을 늘림. 경량 모델(135M)은 4Gi로 충분하지만, 대형 모델(7B+)은 GPU_MEMORY_LIMIT 확대 필요. H200(141GB VRAM)에서는 70B도 단일 GPU 가능.

- **`/v1/completions` 응답 없음 / 타임아웃** → vLLM이 모델 로딩 중일 수 있음. `oc logs ${VLLM_POD} -n ${MODEL_NS}` 에서 `Uvicorn running` 메시지 확인 후 재시도.

- **Route 생성 실패** → Service 이름이 `${MODEL_NAME}-metrics`(ClusterIP)를 사용. `${MODEL_NAME}-predictor`(Headless)는 Route로 노출 불가.

- **`/v1/chat/completions` 400 에러 (chat template 없음)** → base 모델(SmolLM2-135M 등 경량 모델)은 `tokenizer_config.json`에 `chat_template` 필드가 없음. S3의 `tokenizer_config.json`에 chat_template을 추가하거나, Instruct 모델을 사용. Gen AI Studio Playground는 `/v1/chat/completions`를 사용하므로 chat_template 필수.

## Mobis 클러스터 실측 (2026-05-23)

S1 시나리오 — Model Registry 등록/버전/메타데이터/MR 연동 배포/철수 7 Step 전체 PASS.

| 항목 | 결과 |
|------|------|
| S3 아티팩트 업로드 | PASS — 9개 파일 (config.json, tokenizer.json, model.safetensors 등) |
| Model Registry 등록 | PASS — id=10, state=LIVE |
| v1/v2 버전 공존 | PASS — v1(id=11), v2(id=12) 조회 확인 |
| customProperties CRUD | PASS — 6개 필드 (framework, task, team, dataset, accuracy, owner) |
| MR 연동 배포 (원클릭) | PASS — 145초 (GPU 할당 포함), IS Ready=True, Registry 라벨 확인 |
| 원클릭 철수 | PASS — 15초 (IS minReplicas=0 + KEDA ScaledObject minReplicaCount=0) |
| /v1/models API 응답 | PASS — HTTP 200 |

## 다음 단계

→ `runbooks/302-guardrails.md` — GuardrailsOrchestrator + LMEval 구성

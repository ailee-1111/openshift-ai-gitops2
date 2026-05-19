# 390 — S10: MLOps 루프

## 목적

TrainJob → LMEvalJob → Registry v2 → RollingUpdate 배포의 MLOps 전체 루프를 검증한다. Exploratory No.77~78, 7, 4~6, 10~12 편입.

> **참고**: KServe canary(`canaryTrafficPercent`)는 **Serverless 모드에서만** 동작한다. Standard/RawDeployment 모드에서는 RollingUpdate + storage.path 변경으로 버전을 전환한다.

## 전제 조건

- [ ] LMEvalJob 경험 (`runbooks/302-guardrails.md`)
- [ ] Model Registry Available=True
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `MODEL_REGISTRY_NS`

## 실행

### 1. TrainJob (S10-1)

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: kubeflow.org/v2alpha1
kind: TrainJob
metadata:
  name: poc-finetune-cpu
spec:
  runtimeRef:
    name: torch-tune
  trainerConfig:
    image: "quay.io/modh/training:py311-pt210-20250422"
    command: ["python3", "-c", "import torch; m=torch.nn.Linear(128,64); o=torch.optim.SGD(m.parameters(),lr=0.01); l=torch.nn.MSELoss(); [print(f'epoch {e}: loss={l(m(torch.randn(32,128)),torch.randn(32,64)).item():.4f}') or (o.zero_grad(),l(m(torch.randn(32,128)),torch.randn(32,64)).backward(),o.step()) for e in range(5)]; torch.save(m.state_dict(),'/tmp/model.pt'); print('Done')"]
    resources:
      requests: {cpu: "1", memory: 1Gi}
      limits: {cpu: "2", memory: 2Gi}
  numNodes: 1
EOF

for i in $(seq 1 30); do
  STATE=$(oc get trainjob poc-finetune-cpu -n ${MODEL_NS} -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
  echo "$(date '+%H:%M:%S') Complete=${STATE:-Pending}"
  [ "${STATE}" = "True" ] && break; sleep 10
done
~~~

### 2. LMEvalJob (S10-2)

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: poc-v2-eval
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - {name: model, value: ${MODEL_NAME}}
    - {name: base_url, value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/completions"}
    - {name: tokenizer_backend, value: huggingface}
    - {name: tokenized_requests, value: "false"}
    - {name: tokenizer, value: "HuggingFaceTB/SmolLM2-135M"}
  taskList:
    taskNames: ["hellaswag"]
  limit: "5"
  batchSize: "1"
EOF

for i in $(seq 1 30); do
  STATE=$(oc get lmevaljob poc-v2-eval -n ${MODEL_NS} -o jsonpath='{.status.state}' 2>/dev/null)
  echo "$(date '+%H:%M:%S') state=${STATE:-Pending}"
  [ "${STATE}" = "Complete" ] && break; sleep 20
done
~~~

### 3. Registry v2 (S10-3)

~~~bash
MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers | awk '{print $2}' | head -1)
TOKEN=$(oc whoami -t)
MODEL_ID=$(curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "
import sys,json
for m in json.load(sys.stdin).get('items',[]):
    if m.get('name')=='${MODEL_NAME}': print(m['id']); break")

curl -sk -X POST "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN}" \
  -d '{"name":"v2-finetuned","description":"Fine-tuned + eval passed"}'
echo "v2-finetuned 등록 완료"
~~~

### 4. RollingUpdate 버전 전환 (S10-4)

> KServe canary(`canaryTrafficPercent`)는 Serverless 모드 전용. Standard/RawDeployment에서는 storage.path 변경 + RollingUpdate로 전환한다.

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}')

# 배포 전 상태 확인
echo "=== 전환 전 ==="
CURRENT_PATH=$(oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='{.spec.predictor.model.storage.path}')
echo "  현재 경로: ${CURRENT_PATH}"

# v2 경로로 전환 (RollingUpdate)
oc patch inferenceservice ${MODEL_NAME} -n ${MODEL_NS} --type=merge \
  -p '{"spec":{"predictor":{"model":{"storage":{"path":"'${MODEL_NAME}'/v2'"}}}}}'
echo "v2 전환 요청"

# Ready 대기
oc wait inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  --for=condition=Ready --timeout=300s

# 서빙 검증
echo "=== 전환 후 검증 ==="
for i in $(seq 1 5); do
  curl -sk -o /dev/null -w "  $i: HTTP %{http_code}\n" --max-time 10 \
    "https://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"'${MODEL_NAME}'","prompt":"test","max_tokens":5}'
done

# 원복 (필요 시)
# oc patch inferenceservice ${MODEL_NAME} -n ${MODEL_NS} --type=merge \
#   -p '{"spec":{"predictor":{"model":{"storage":{"path":"'${CURRENT_PATH}'"}}}}}'
echo "전환 완료"
~~~

## 검증

~~~bash
oc get trainjob poc-finetune-cpu -n ${MODEL_NS} -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null; echo ""
oc get lmevaljob poc-v2-eval -n ${MODEL_NS} -o jsonpath='{.status.state}' 2>/dev/null; echo ""
oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'; echo ""
~~~

## 실패 시

- **TrainJob CRD 없음** → `oc get crd trainjobs.kubeflow.org`
- **버전 전환 후 Ready=False** → S3 경로에 v2 모델이 존재하는지 확인. storage.path 오타 점검. `oc describe inferenceservice` 이벤트에서 원인 확인
- **KServe Canary 사용 시** → Serverless 모드(`serving.kserve.io/deploymentMode: Serverless`)로 전환 필요. Standard/RawDeployment에서는 `canaryTrafficPercent` 미지원

## 다음 단계

→ `runbooks/500-model-serving-validation.md`

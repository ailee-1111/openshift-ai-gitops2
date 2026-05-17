# 390 — S10: MLOps 루프

## 목적

TrainJob → LMEvalJob → Registry v2 → Canary 배포의 MLOps 전체 루프를 검증한다. Exploratory No.77~78, 7, 4~6, 10~12 편입.

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

### 4. Canary → 전환 (S10-4)

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}')

# Canary 10%
oc annotate inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  serving.kserve.io/canaryTrafficPercent="10" --overwrite 2>/dev/null
echo "Canary 10%"
sleep 10

for i in $(seq 1 10); do
  curl -sk -o /dev/null -w "  $i: HTTP %{http_code}\n" --max-time 10 \
    "https://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"'${MODEL_NAME}'","prompt":"test","max_tokens":5}'
done

# 전환
oc annotate inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  serving.kserve.io/canaryTrafficPercent- --overwrite 2>/dev/null
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
- **Canary 미동작** → RawDeployment 모드 제한

## 다음 단계

→ `runbooks/500-model-serving-validation.md`

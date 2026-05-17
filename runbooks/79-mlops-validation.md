# 79 — MLOps 루프 검증 (S10)

## 목적

TrainJob → LMEvalJob → Registry → Canary 루프를 검증한다. 구축: `69-mlops-loop.md`.

## 검증 항목

### V-S10-1. TrainJob Complete

~~~bash
oc get trainjob poc-finetune-cpu -n rhoai-poc \
  -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null; echo ""
# 기대: True  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S10-2. LMEvalJob Complete

~~~bash
oc get lmevaljob -n rhoai-poc -o jsonpath='{.items[-1].status.state}' 2>/dev/null; echo ""
# 기대: Complete  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S10-3. Registry 모델 존재

~~~bash
MR_ROUTE=$(oc get route -n rhoai-model-registries --no-headers | awk '{print $2}' | head -1)
curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer $(oc whoami -t)" | python3 -c "import sys,json; print(f'{json.load(sys.stdin).get(\"size\",0)}개')"
# 기대: 1+  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S10-4. IS Ready

~~~bash
oc get inferenceservice smollm2-135m -n rhoai-poc \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'; echo ""
# 기대: True  |  결과: [   ] PASS / [   ] FAIL
~~~

## 다음 단계

→ `runbooks/80-comprehensive-validation.md`

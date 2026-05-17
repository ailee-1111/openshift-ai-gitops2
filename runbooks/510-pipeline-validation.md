# 510 — Pipeline E2E 검증 (S2: Pipeline)

## 목적

Tekton Pipeline 기반 모델 배포 자동화(S3 검증 → 승인 게이트 → 서빙 검증)와 vLLM OpenAI 호환 API가 고객 요구사항(No.1,2,3,10,11,12,43)을 충족하는지 검증한다.

## 전제 조건

- [ ] `runbooks/310-pipeline.md` 구축 완료 (Task, Pipeline, PipelineRun 정상)
- [ ] `${MODEL_NAME}`, `${MODEL_NS}` 환경변수 설정
- [ ] ManualApprovalGate controller 정상 동작

## 실행

### V-1. vLLM 지원 (No.1)

~~~bash
echo "=== V-1: vLLM 서빙 엔진 확인 ==="
oc get servingruntime -n "${MODEL_NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.containers[0].image}{"\n"}{end}'
# 기대: vLLM 기반 이미지

oc get inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" \
  -o jsonpath='modelFormat={.spec.predictor.model.modelFormat.name}, runtime={.spec.predictor.model.runtime}'
echo ""
# 기대: modelFormat=vLLM
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-3. 엔진 버전 관리 (No.3)

~~~bash
echo "=== V-3: 서빙 엔진 버전 확인 ==="
VLLM_POD=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  -o jsonpath='{.items[0].metadata.name}')
oc exec "${VLLM_POD}" -n "${MODEL_NS}" -- \
  python3 -c "import vllm; print(f'vLLM version: {vllm.__version__}')" 2>/dev/null \
  || oc logs "${VLLM_POD}" -n "${MODEL_NS}" --tail=50 | grep -i "vllm version\|version:"
# 기대: vLLM 버전 출력
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-10. 모델 배포 자동화 파이프라인 (No.10)

~~~bash
echo "=== V-10: E2E Pipeline 실행 ==="
oc create -n "${MODEL_NS}" -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: validation-e2e-
spec:
  pipelineRef:
    name: model-serving-e2e-pipeline
EOF

sleep 15

LATEST_RUN=$(oc get pipelinerun -n "${MODEL_NS}" \
  --sort-by='.metadata.creationTimestamp' \
  -o jsonpath='{.items[-1].metadata.name}')
echo "PipelineRun: ${LATEST_RUN}"
oc get pipelinerun "${LATEST_RUN}" -n "${MODEL_NS}" \
  -o jsonpath='{range .status.childReferences[*]}{.name}: {.kind}{"\n"}{end}'
# 기대: validate-artifact(TaskRun) 완료, request-approval(CustomRun) 대기 중
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-11/12. 승인 프로세스 (No.11, No.12)

~~~bash
echo "=== V-11/12: 승인 게이트 검증 ==="

# 승인 전 차단 확인
echo ">> 승인 전 차단 확인"
oc get pipelinerun "${LATEST_RUN}" -n "${MODEL_NS}" \
  -o jsonpath='상태: {.status.conditions[0].reason}'
echo ""
# 기대: Running (승인 대기)

AT_NAME=$(oc get approvaltask -n "${MODEL_NS}" \
  --sort-by='.metadata.creationTimestamp' \
  -o jsonpath='{.items[-1].metadata.name}')
echo "ApprovalTask: ${AT_NAME}"
oc get approvaltask "${AT_NAME}" -n "${MODEL_NS}" \
  -o jsonpath='state={.status.state}, approvals={.status.approvalsReceived}'
echo ""
# 기대: state=pending

# 승인 수행
echo ">> 승인 수행"
oc patch approvaltask "${AT_NAME}" -n "${MODEL_NS}" \
  --type='merge' -p '{"spec":{"approvers":[{"name":"admin","input":"approve"}]}}'

sleep 30
oc get pipelinerun "${LATEST_RUN}" -n "${MODEL_NS}" \
  -o jsonpath='최종상태: {.status.conditions[0].reason}'
echo ""
# 기대: Succeeded
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-43. OpenAI 호환 API (No.43)

~~~bash
echo "=== V-43: OpenAI 호환 API 검증 ==="
ROUTE=$(oc get route "${MODEL_NAME}-api" -n "${MODEL_NS}" \
  -o jsonpath='{.spec.host}' 2>/dev/null)

# /v1/models
echo ">> GET /v1/models"
curl -sk "https://${ROUTE}/v1/models" | python3 -m json.tool | head -10
# 기대: HTTP 200, data 배열에 모델 정보

# /v1/completions
echo ">> POST /v1/completions"
curl -sk "https://${ROUTE}/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"What is 2+2? Answer:\",\"max_tokens\":20}" \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(f\"model: {r.get('model')}\")
print(f\"choices: {len(r.get('choices', []))}\")
if r.get('choices'):
    print(f\"text: {r['choices'][0].get('text','')[:100]}\")
"
# 기대: choices 1개 이상, 텍스트 생성

# /v1/chat/completions
echo ">> POST /v1/chat/completions"
curl -sk "https://${ROUTE}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":20}" \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(f\"choices: {len(r.get('choices', []))}\")
if r.get('choices'):
    msg = r['choices'][0].get('message', {})
    print(f\"role: {msg.get('role')}, content: {msg.get('content','')[:100]}\")
"
# 기대: chat completions 응답 정상
# 결과: [   ] PASS / [   ] FAIL
~~~

## 검증

~~~bash
echo "=== S2 검증 요약 ==="
echo "V-1   vLLM 지원:                  [   ] PASS / [   ] FAIL"
echo "V-3   엔진 버전 관리:             [   ] PASS / [   ] FAIL"
echo "V-10  모델 배포 자동화:           [   ] PASS / [   ] FAIL"
echo "V-11  모델 등록 프로세스(승인):   [   ] PASS / [   ] FAIL"
echo "V-12  모델 승인 프로세스(배포):   [   ] PASS / [   ] FAIL"
echo "V-43  OpenAI 호환 API:            [   ] PASS / [   ] FAIL"
echo ""
echo "V-2   TGI/TRT-LLM 대체 엔진:     [   ] SKIP (Advanced)"
~~~

## 실패 시

- **PipelineRun 즉시 실패** → `oc describe pipelinerun ${LATEST_RUN} -n ${MODEL_NS}` 이벤트 확인. Task 참조 오류가 가장 흔한 원인.
- **ManualApprovalGate 미동작** → `oc get pods -n openshift-pipelines | grep manual-approval` controller 로그 확인. Tekton Pipelines 1.22+ 필수.
- **승인 후 verify-serving 실패** → InferenceService Ready 재확인. Service 엔드포인트 DNS 해석 가능 여부 확인.
- **OpenAI API 응답 없음** → vLLM Pod 로그에서 `Uvicorn running` 확인. 모델 로딩 완료 전이면 503 응답.
- **/v1/chat/completions 미지원** → vLLM 버전에 따라 chat endpoint가 없을 수 있음. `--served-model-name` 설정 확인.

## v3 강화 검증 (61-v3-pipeline.md 연동)

### V-S2-v3-1. 7단계 Pipeline 존재

~~~bash
oc get pipeline model-e2e-7stage-pipeline -n ${MODEL_NS}
# 기대: 존재  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S2-v3-2. 승인/반려 시나리오

~~~bash
oc get pipelinerun -n ${MODEL_NS} -l tekton.dev/pipeline=model-e2e-7stage-pipeline \
  -o custom-columns='NAME:.metadata.name,SUCCEEDED:.status.conditions[0].status' --no-headers
# 기대: approve→True, reject→False  |  결과: [   ] PASS / [   ] FAIL
~~~

### V-S2-v3-3. RBAC 분리 + 그룹 승인

~~~bash
oc auth can-i create pipelinerun -n ${MODEL_NS} --as=poc-operator
# 기대: yes  |  결과: [   ] PASS / [   ] FAIL
# 그룹 승인: approvers에 group:rhods-admins 포함 확인
~~~

### V-S2-v3-4. 메일 알림

~~~bash
MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS} -o jsonpath='{.spec.host}')
curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=3" | python3 -c "import sys,json; print(f'{len(json.load(sys.stdin).get(\"items\",[]))}건')"
# 기대: 1건 이상  |  결과: [   ] PASS / [   ] FAIL
~~~

## 다음 단계

→ `runbooks/520-autoscaling-validation.md` — 오토스케일링 검증

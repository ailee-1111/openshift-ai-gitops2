# 302 — GuardrailsOrchestrator 구성

## 목적

> **Customer 클러스터 실측 (2026-05-19)**:
> - GuardrailsOrchestrator: CR 미생성 (customer-poc NS에 없음) -- 배포 필요
> - TrustyAIService: Running 상태 정상

InferenceService 배포 완료 후, GuardrailsOrchestrator(PII 감지/콘텐츠 필터링)를 배포한다. TrustyAI Operator와 TrustyAIService는 `runbooks/211-trustyai.md`에서 사전 구성 완료.

> **EvalHub + LMEvalJob**은 `runbooks/303-evalhub.md`로 분리됨.

## 전제 조건

- [ ] `runbooks/211-trustyai.md` 완료 (TrustyAIService Running)
- [ ] `runbooks/300-model-serving.md` 완료 (InferenceService Ready=True)
- [ ] `${MODEL_NS}`, `${MODEL_NAME}` 환경변수 설정

## 실행

### 1. GuardrailsOrchestrator CR 생성

~~~bash
set -a && source .env && set +a

oc get inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" 2>/dev/null || {
  echo "ERROR: InferenceService 미배포. runbooks/300 완료 후 실행하세요."
  exit 1
}

oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: GuardrailsOrchestrator
metadata:
  name: ${MODEL_NAME}-guardrails
spec:
  replicas: 1
  autoConfig:
    inferenceServiceToGuardrail: ${MODEL_NAME}
  enableBuiltInDetectors: true
  enableGuardrailsGateway: true
  env:
    - name: OPENAI_BASE_URL
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1"
  otelExporter:
    otlpProtocol: grpc
EOF

echo "GuardrailsOrchestrator 대기 (최대 2분)..."
oc wait pod -n "${MODEL_NS}" \
  -l app="${MODEL_NAME}-guardrails" \
  --for=condition=Ready --timeout=120s 2>/dev/null \
  || echo "WARNING: Pod Ready 대기 타임아웃"
oc get pods -n "${MODEL_NS}" -l app="${MODEL_NAME}-guardrails" --no-headers
~~~

### 2. LMEvalJob 실행 (모델 평가)

~~~bash
oc apply -n "${MODEL_NS}" -f - <<EOF
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: ${MODEL_NAME}-eval
spec:
  model: local-completions
  allowOnline: true
  modelArgs:
    - name: model
      value: ${MODEL_NAME}
    - name: base_url
      value: "http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/completions"
    - name: tokenizer_backend
      value: huggingface
    - name: tokenized_requests
      value: "false"
    - name: tokenizer
      value: "${TOKENIZER_MODEL:-HuggingFaceTB/SmolLM2-135M}"
  taskList:
    taskNames:
      - "hellaswag"
  limit: "3"
  batchSize: "1"
EOF

echo "LMEvalJob 대기 (최대 5분)..."
for i in $(seq 1 10); do
  STATE=$(oc get lmevaljob "${MODEL_NAME}-eval" -n "${MODEL_NS}" \
    -o jsonpath='{.status.state}' 2>/dev/null)
  echo "  ${i}0초: state=${STATE}"
  [ "${STATE}" = "Complete" ] && break
  sleep 30
done
~~~

### 3. EvalHub CR 생성 (Dashboard Evaluations 탭)

> **주의**: EvalHub CR은 `redhat-ods-applications` 네임스페이스에 생성해야 한다. 다른 NS에 생성하면 Dashboard가 인식하지 못한다.

~~~bash
oc apply -n redhat-ods-applications -f - <<'EOF'
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: EvalHub
metadata:
  name: evalhub
  namespace: redhat-ods-applications
spec:
  database:
    type: sqlite
  replicas: 1
  providers:
    - garak
    - garak-kfp
    - lm-evaluation-harness
    - guidellm
    - lighteval
  env:
    - name: MLFLOW_TRACKING_URI
      value: "https://mlflow.redhat-ods-applications.svc:8443"
    - name: MLFLOW_INSECURE_SKIP_VERIFY
      value: "true"
    - name: MLFLOW_WORKSPACE
      value: "${MODEL_NS}"
EOF

oc wait pod -n redhat-ods-applications \
  -l app.kubernetes.io/name=evalhub \
  --for=condition=Ready --timeout=120s 2>/dev/null \
  || echo "WARNING: EvalHub Ready 타임아웃"
oc get evalhub -n redhat-ods-applications
~~~

### 4. EvalHub RBAC — 대상 네임스페이스 권한 부여

> **주의**: EvalHub이 evaluation job을 실행할 모든 네임스페이스에 아래 RBAC를 생성해야 한다.

~~~bash
# ServiceAccount
oc create sa evalhub-redhat-ods-applications-job -n "${MODEL_NS}" 2>/dev/null || true

# CA ConfigMap 복사
oc get configmap evalhub-service-ca -n redhat-ods-applications -o json \
  | python3 -c "
import sys, json
cm = json.load(sys.stdin)
cm['metadata'] = {'name': 'evalhub-service-ca', 'namespace': '${MODEL_NS}'}
json.dump(cm, sys.stdout)
" | oc apply -f -

# MLflow 접근 권한
oc create rolebinding evalhub-mlflow-access-rb \
  --clusterrole=trustyai-service-operator-evalhub-mlflow-access \
  --serviceaccount=redhat-ods-applications:evalhub-service \
  -n "${MODEL_NS}" 2>/dev/null || true

oc create rolebinding evalhub-mlflow-jobs-access-rb \
  --clusterrole=trustyai-service-operator-evalhub-mlflow-jobs-access \
  --serviceaccount=redhat-ods-applications:evalhub-service \
  -n "${MODEL_NS}" 2>/dev/null || true

# Job 실행 권한
oc apply -n "${MODEL_NS}" -f - <<ROLE_EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: evalhub-job-access-role
  namespace: ${MODEL_NS}
rules:
- apiGroups: [""]
  resources: [configmaps, pods, pods/log, serviceaccounts, secrets, events]
  verbs: ["*"]
- apiGroups: [batch]
  resources: [jobs]
  verbs: ["*"]
- apiGroups: [trustyai.opendatahub.io]
  resources: [status-events]
  verbs: [create]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: evalhub-job-access-rb
  namespace: ${MODEL_NS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: evalhub-job-access-role
subjects:
- kind: ServiceAccount
  name: evalhub-service
  namespace: redhat-ods-applications
ROLE_EOF

echo "RBAC 설정 완료"
~~~

### 5. Dashboard Pod 재시작 (MLflow 인식)

> **주의**: MLflow CR 생성 후 Dashboard Pod를 재시작해야 `mlflow-ui` 컨테이너가 MLflow를 인식한다.

~~~bash
oc rollout restart deploy/rhods-dashboard -n redhat-ods-applications
oc rollout status deploy/rhods-dashboard -n redhat-ods-applications --timeout=120s
~~~

## 검증

~~~bash
echo "=== 60-b — 전체 검증 ==="
echo "Guardrails Pod: $(oc get pods -n ${MODEL_NS} -l app=${MODEL_NAME}-guardrails -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo '미배포')"
echo "LMEvalJob: $(oc get lmevaljob ${MODEL_NAME}-eval -n ${MODEL_NS} -o jsonpath='{.status.state}' 2>/dev/null || echo '미실행')"
echo "EvalHub: $(oc get evalhub evalhub -n redhat-ods-applications -o jsonpath='phase={.status.phase}, ready={.status.ready}' 2>/dev/null || echo '미배포')"
echo "MLflow: $(oc get mlflow mlflow -o jsonpath='available={.status.conditions[?(@.type==\"Available\")].status}' 2>/dev/null)"
~~~

## 실패 시

- **Guardrails CrashLoop** → InferenceService Ready 확인. `OPENAI_BASE_URL` 엔드포인트 접근 가능 여부: `oc exec -n ${MODEL_NS} deploy/trustyai-service -- curl -s http://${MODEL_NAME}-metrics.${MODEL_NS}.svc.cluster.local:8080/v1/models`
- **LMEvalJob 실패** → vLLM 모델 로딩 완료 상태 필요. `oc logs -l serving.kserve.io/inferenceservice=${MODEL_NAME} -n ${MODEL_NS} --tail=20`
- **"Evaluations unavailable"** → EvalHub CR이 `redhat-ods-applications`에 있는지 확인. 다른 NS에 만들면 Dashboard가 인식 못함
- **"MLflow is not configured"** → Dashboard Pod 재시작 필요. `oc rollout restart deploy/rhods-dashboard -n redhat-ods-applications`
- **"Error loading experiments"** → `mlflow-ui` 컨테이너 로그 확인: `oc logs <dashboard-pod> -n redhat-ods-applications -c mlflow-ui --tail=10`. "not configured" 메시지면 Dashboard 재시작
- **MLflow 403 PERMISSION_DENIED** → `MLFLOW_WORKSPACE` 환경변수가 대상 네임스페이스와 일치하는지 확인. EvalHub에 해당 NS의 MLflow RoleBinding 존재 여부 확인
- **eval job Pod FailedCreate "SA not found"** → 대상 NS에 `evalhub-redhat-ods-applications-job` SA 생성 필요
- **eval job Pod FailedMount "configmap not found"** → 대상 NS에 `evalhub-service-ca` ConfigMap 복사 필요
- **GuideLLM "starting benchmarks..." 이후 멈춤** → 자가서명 인증서 환경에서 HTTPS Route 접근 시 TLS 검증 실패. 내부 svc URL 사용 또는 `--insecure` 옵션 필요 (Product Gap)

## Customer 클러스터 실측 (2026-05-23)

| 항목 | 결과 | 판정 |
|------|------|:----:|
| Granite Guardian CPU IS | S3에 Guardian 모델 미업로드 — 미배포 | 미검증 |
| GuardrailsOrchestrator | Guardian 의존 — 미배포 | 미검증 |
| NemoGuardrails CR | nemo-quickstart Ready, Pod 2/2 Running | PASS |
| NemoGuardrails 정상 텍스트 | status=success | PASS |
| NemoGuardrails 이메일 (Presidio) | kim@customer.com → blocked (detect sensitive data on input) | PASS |
| NemoGuardrails 한국 주민번호 (regex) | 901215-1234567 → blocked (regex check input) | PASS |
| NemoGuardrails 한국 전화번호 (regex) | 010-9876-5432 → blocked (regex check input) | PASS |
| 한국어 PII 감지기 v3 | Pod Running, 9개 패턴, 오버랩 제거 정상 | PASS |

> 소스: `scenarios/S09-security-gate.md` 검증 테이블 — NemoGuardrails + korean-pii-detector 실증 완료. GuardrailsOrchestrator는 Guardian 모델 업로드 후 배포 예정.

## 다음 단계

→ `runbooks/500-model-serving-validation.md` — S1 모델 서빙 검증

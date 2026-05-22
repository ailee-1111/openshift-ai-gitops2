# 310 — Tekton Pipeline E2E (S2)

## 목적

> **Mobis 클러스터 실측 (2026-05-19)**:
> - DSPA: Ready=True, PipelineRun 3건 Succeeded (e2e-7stage v1/v2, e2e-pipeline)
> - ds-pipeline Pod 6개 Running, MariaDB/Gitea/MailHog Running
> - ManualApprovalGate: TektonConfig에 미설정 -- 별도 설치 필요

모델 등록 요청부터 ManualApprovalGate 승인 게이트를 거쳐 서빙 엔드포인트 검증까지의 E2E 파이프라인을 Tekton Pipeline으로 구현한다. 승인 없이는 배포가 차단되고, 승인 후에만 후속 Task가 진행되는 프로세스를 검증한다.

## 전제 조건

- [ ] `runbooks/301-llm-cpu.md` 완료 — InferenceService Ready=True
- [ ] OpenShift Pipelines(Tekton) 1.22+ 설치 (`oc get csv -A | grep pipelines`)
- [ ] ManualApprovalGate v0.8.0+ 설치 완료 (`oc get manualapprovalgate`)
- [ ] S3 Data Connection Secret 존재 (`oc get secret poc-s3-connection -n ${MODEL_NS}`)
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `S3_BUCKET`

## 실행

### 1. ManualApprovalGate 설치 확인

~~~bash
# ManualApprovalGate CR 상태
oc get manualapprovalgate
# 기대: Ready=True

# controller + webhook Pod 확인
oc get pods -n openshift-pipelines | grep manual-approval
# 기대: controller Running, webhook Running

# ApprovalTask CRD 존재 확인
oc get crd approvaltasks.openshift-pipelines.org
~~~

미설치 시:

~~~bash
oc apply -f - <<'EOF'
apiVersion: operator.tekton.dev/v1alpha1
kind: ManualApprovalGate
metadata:
  name: manual-approval-gate
spec:
  targetNamespace: openshift-pipelines
EOF

oc wait manualapprovalgate/manual-approval-gate \
  --for=jsonpath='{.status.conditions[0].status}'=True \
  --timeout=120s
~~~

### 2. Tekton Task 생성

~~~bash
# S3 아티팩트 검증 Task
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: validate-model-artifact
spec:
  params:
    - name: model-path
    - name: s3-bucket
    - name: s3-endpoint
  results:
    - name: model-uri
  steps:
    - name: check-artifact
      image: amazon/aws-cli:latest
      env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: poc-s3-connection
              key: AWS_ACCESS_KEY_ID
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: poc-s3-connection
              key: AWS_SECRET_ACCESS_KEY
      script: |
        #!/bin/bash
        set -e
        echo "S3 모델 아티팩트 검증: $(params.model-path)"
        COUNT=$(aws s3 ls "s3://$(params.s3-bucket)/$(params.model-path)" \
          --endpoint-url "$(params.s3-endpoint)" --recursive | wc -l)
        if [ "$COUNT" -eq 0 ]; then echo "ERROR: 모델 미발견"; exit 1; fi
        echo "OK: ${COUNT}개 파일"
        echo -n "s3://$(params.s3-bucket)/$(params.model-path)" > $(results.model-uri.path)
EOF

# 서빙 엔드포인트 검증 Task
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: verify-serving-endpoint
spec:
  params:
    - name: isvc-name
    - name: namespace
  steps:
    - name: verify
      image: curlimages/curl:latest
      script: |
        #!/bin/sh
        set -e
        echo "서빙 엔드포인트 검증: $(params.isvc-name)"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 \
          "http://$(params.isvc-name)-predictor.$(params.namespace).svc.cluster.local:8080/v1/models")
        echo "HTTP: ${HTTP_CODE}"
        [ "${HTTP_CODE}" = "200" ] || { echo "WARNING: 응답 ${HTTP_CODE}"; exit 1; }
EOF
~~~

### 3. E2E Pipeline 생성 (S3 검증 -> 승인 -> 서빙 검증)

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: model-serving-e2e-pipeline
spec:
  params:
    - name: model-name
      default: ${MODEL_NAME}
    - name: s3-path
      default: ${MODEL_NAME}/v1
  tasks:
    - name: validate-artifact
      taskRef:
        name: validate-model-artifact
      params:
        - name: model-path
          value: \$(params.s3-path)
        - name: s3-bucket
          value: ${S3_BUCKET}
        - name: s3-endpoint
          value: http://minio.${MODEL_NS}.svc.cluster.local:9000
    - name: request-approval
      runAfter: [validate-artifact]
      taskRef:
        apiVersion: openshift-pipelines.org/v1alpha1
        kind: ApprovalTask
      params:
        - name: approvers
          value: [admin]
        - name: numberOfApprovalsRequired
          value: "1"
        - name: description
          value: "모델 배포 승인 요청"
    - name: verify-serving
      runAfter: [request-approval]
      taskRef:
        name: verify-serving-endpoint
      params:
        - name: isvc-name
          value: \$(params.model-name)
        - name: namespace
          value: ${MODEL_NS}
EOF
~~~

### 4. PipelineRun 실행

~~~bash
oc create -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: e2e-pipeline-
spec:
  pipelineRef:
    name: model-serving-e2e-pipeline
EOF
~~~

### 5. 승인 처리

~~~bash
# 승인 대기 중인 ApprovalTask 조회
AT_NAME=$(oc get approvaltask -n ${MODEL_NS} \
  -o jsonpath='{.items[-1].metadata.name}')
echo "ApprovalTask: ${AT_NAME}"

# admin으로 승인
oc patch approvaltask ${AT_NAME} -n ${MODEL_NS} \
  --type='merge' \
  -p '{"spec":{"approvers":[{"name":"admin","input":"approve"}]}}'
~~~

### 6. (선택) 승인 거부 시나리오 검증

~~~bash
# 별도 PipelineRun 생성
oc create -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: e2e-reject-test-
spec:
  pipelineRef:
    name: model-serving-e2e-pipeline
EOF

# 30초 후 승인 거부
sleep 30
AT_NAME=$(oc get approvaltask -n ${MODEL_NS} \
  -o jsonpath='{.items[-1].metadata.name}')
oc patch approvaltask ${AT_NAME} -n ${MODEL_NS} \
  --type='merge' \
  -p '{"spec":{"approvers":[{"name":"admin","input":"reject"}]}}'

# 기대: PipelineRun SUCCEEDED=False (거부로 인한 Pipeline 실패)
sleep 15
oc get pipelinerun -n ${MODEL_NS} --sort-by='.metadata.creationTimestamp' | tail -1
~~~

## 검증

~~~bash
# 1) Task 생성 확인
oc get task -n ${MODEL_NS}
# 기대: validate-model-artifact, verify-serving-endpoint

# 2) Pipeline 존재 확인
oc get pipeline -n ${MODEL_NS}
# 기대: model-serving-e2e-pipeline

# 3) 승인 전 — verify-serving 차단 확인
LATEST_RUN=$(oc get pipelinerun -n ${MODEL_NS} \
  --sort-by='.metadata.creationTimestamp' \
  -o jsonpath='{.items[-1].metadata.name}')
oc get pipelinerun ${LATEST_RUN} -n ${MODEL_NS} \
  -o jsonpath='{range .status.childReferences[*]}{.name}: {.kind}{"\n"}{end}'
# 기대: validate-artifact(TaskRun), request-approval(CustomRun)만 존재

# 4) ApprovalTask 상태
oc get approvaltask -n ${MODEL_NS}
# 승인 전: state=pending / 승인 후: state=approved, approvalsReceived=1

# 5) PipelineRun 최종 상태 (승인 후)
oc get pipelinerun -n ${MODEL_NS} --sort-by='.metadata.creationTimestamp' | tail -1
# 기대: SUCCEEDED=True

# 6) 서빙 엔드포인트 추론 테스트
oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
  "http://${MODEL_NAME}-predictor.${MODEL_NS}.svc.cluster.local:8080/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"Hello\",\"max_tokens\":5}"
# 기대: HTTP 200, choices 배열에 생성된 텍스트
~~~

성공 기준:
- Tekton Task 2개 + Pipeline 1개 정상 생성
- 승인 전 verify-serving Task 미실행 (차단)
- 승인 후 PipelineRun Succeeded=True (3개 Task 모두 성공)
- 서빙 엔드포인트 `/v1/completions` HTTP 200

## 실패 시

- **ManualApprovalGate Ready=False** → `oc get pods -n openshift-pipelines | grep manual-approval`로 controller/webhook 로그 확인. Tekton Pipelines 1.22+ 필수.
- **validate-artifact Task 실패** → S3 Secret(`poc-s3-connection`)의 키 확인. MinIO 엔드포인트 접근 가능 여부 확인: `oc exec deploy/minio -n ${MODEL_NS} -- curl -s http://localhost:9000/minio/health/ready`
- **승인 후에도 verify-serving 미실행** → CustomRun 상태 확인: `oc get customrun -n ${MODEL_NS}`. ApprovalTask의 `approvalsReceived`와 `numberOfApprovalsRequired` 일치 여부 확인.
- **verify-serving Task 실패 (HTTP != 200)** → InferenceService Ready 상태 재확인: `oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS}`. Pod가 Running인지, Service 엔드포인트가 존재하는지 확인.

## Mobis 클러스터 실측 (2026-05-23)

S2 시나리오 — 7단계 파이프라인 v1→v2 버전 전환, 이중 승인, HTML 메일 알림, PipelineRun Succeeded.

| 항목 | 결과 |
|------|------|
| vLLM ServingRuntime | PASS — vllm-cuda-runtime (quay.io/modh/vllm:rhoai-2.22-cuda) |
| Pipeline 7 Stage 완료 | PASS — e2e-7stage Succeeded (4s+4s+승인+5s+4s+승인+4s) |
| 등록 승인 (Stage 3) | PASS — ApprovalTask approved, approvalsReceived=1 |
| 배포 승인 (Stage 6) | PASS — ApprovalTask approved, approvalsReceived=1 |
| 거부 시 차단 | PASS — PipelineRun Succeeded=False, Stage 7 미실행 |
| 메일 알림 (MailHog) | PASS — 5건 수신 확인 (등록 요청 + 배포 완료 등) |
| /v1/models | PASS — HTTP 200 |
| /v1/completions | PASS — 텍스트 생성 정상 |
| /v1/chat/completions | PASS — 채팅 응답 정상 |
| 파라미터 전달 | PASS — model-name, s3-path가 Stage 7 IS patch에 정확 반영 |

## 다음 단계

→ `runbooks/350-platform-ops.md` — 모니터링/RBAC/보안/관찰성 플랫폼 운영

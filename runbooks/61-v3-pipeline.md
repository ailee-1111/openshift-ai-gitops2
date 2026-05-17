# 61-v3 — S2 강화: 통합 파이프라인 (7단계 E2E)

## 목적

v1의 3단계 파이프라인(S3검증→승인→서빙검증)을 고객 요구사항에 맞는 7단계 통합 파이프라인으로 확장한다.

**플로우:** 모델 등록 요청 → 메일 알람 → 승인/반려 → 모델 배포 요청 → 메일 알람 → 승인/반려 → vLLM 서빙 Pod 구동 & REST API Endpoint 검증

승인과 반려 양쪽 분기를 모두 검증하고, Task 실패 시 알림 + 재실행 메커니즘을 포함한다.

## 전제 조건

- [ ] `runbooks/61-pipeline.md` 완료 — 기본 파이프라인 정상
- [ ] ManualApprovalGate v0.8.0+ 설치
- [ ] MailHog 또는 SMTP 서버 접근 가능
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `S3_BUCKET`, `ALERT_EMAIL_TO`

## 실행

### 1. 알림용 Task 생성

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: send-notification
spec:
  params:
    - name: stage
    - name: status
    - name: email-to
      default: "poc-admin@example.com"
  steps:
    - name: notify
      image: curlimages/curl:latest
      script: |
        #!/bin/sh
        SUBJECT="[PoC Pipeline] $(params.stage) - $(params.status)"
        BODY="Stage: $(params.stage)\nStatus: $(params.status)\nTime: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "알림 발송: ${SUBJECT}"
        curl -s --url "smtp://mailhog.${MODEL_NS}.svc.cluster.local:1025" \
          --mail-from "pipeline@ocp.local" \
          --mail-rcpt "$(params.email-to)" \
          --upload-file - <<MAIL
        From: pipeline@ocp.local
        To: $(params.email-to)
        Subject: ${SUBJECT}

        ${BODY}
        MAIL
        echo "알림 발송 완료"
EOF
~~~

### 2. 모델 등록 요청 Task

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: request-model-registration
spec:
  params:
    - name: model-name
    - name: model-version
    - name: s3-path
  results:
    - name: registration-id
  steps:
    - name: register
      image: curlimages/curl:latest
      env:
        - name: MR_HOST
          value: "poc-model-registry-rest.rhoai-model-registries.svc.cluster.local:8080"
      script: |
        #!/bin/sh
        set -e
        echo "모델 등록 요청: $(params.model-name) $(params.model-version)"
        RESP=$(curl -s -X POST "http://${MR_HOST}/api/model_registry/v1alpha3/registered_models" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$(params.model-name)\",\"description\":\"Pipeline auto-register\"}")
        ID=$(echo "${RESP}" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -n "${ID}" > $(results.registration-id.path)
        echo "등록 ID: ${ID}"
EOF
~~~

### 3. 배포 요청 기록 Task (실제 배포 아님 — 승인 대기용)

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: request-model-deploy
spec:
  params:
    - name: model-name
    - name: s3-path
    - name: namespace
  results:
    - name: deploy-request-id
  steps:
    - name: record-request
      image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
      script: |
        #!/bin/bash
        set -e
        REQ_ID="deploy-$(date +%s)"
        echo "=== 배포 요청 기록 ==="
        echo "  요청 ID: ${REQ_ID}"
        echo "  대상 IS: $(params.model-name)"
        echo "  S3 경로: $(params.s3-path)"
        echo "  네임스페이스: $(params.namespace)"
        CURRENT_PATH=$(oc get inferenceservice $(params.model-name) \
          -n $(params.namespace) \
          -o jsonpath='{.spec.predictor.model.storage.path}' 2>/dev/null || echo "N/A")
        echo "  현재 경로: ${CURRENT_PATH}"
        echo "  → 실제 배포는 최종 승인 후 Stage 7에서 실행"
        echo -n "${REQ_ID}" > $(results.deploy-request-id.path)
EOF
~~~

### 3b. vLLM 서빙 배포 + REST API 검증 Task (최종 승인 후 실행)

~~~bash
oc apply -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: deploy-and-verify-serving
spec:
  params:
    - name: model-name
    - name: namespace
    - name: s3-path
  results:
    - name: endpoint-status
  steps:
    - name: deploy-and-verify
      image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
      script: |
        #!/bin/bash
        set -e
        echo "=== vLLM 서빙 배포 시작 ==="
        oc patch inferenceservice $(params.model-name) \
          -n $(params.namespace) --type=merge -p '{
          "spec": {"predictor": {"model": {"storage": {"path": "'"$(params.s3-path)"'"}}}}
        }'
        echo "IS patch 완료, vLLM Pod Ready 대기..."
        oc wait inferenceservice $(params.model-name) \
          -n $(params.namespace) \
          --for=condition=Ready --timeout=600s
        echo "vLLM 서빙 Pod 구동 완료"

        echo "=== REST API Endpoint 검증 ==="
        SVC_URL="http://$(params.model-name)-predictor.$(params.namespace).svc.cluster.local:8080"
        for attempt in $(seq 1 10); do
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
            "${SVC_URL}/v1/models" 2>/dev/null)
          echo "  시도 ${attempt}: HTTP ${HTTP_CODE}"
          if [ "${HTTP_CODE}" = "200" ]; then
            echo "REST API 정상"
            echo -n "HTTP_200" > $(results.endpoint-status.path)
            exit 0
          fi
          sleep 5
        done
        echo "ERROR: REST API 응답 실패"
        echo -n "FAIL" > $(results.endpoint-status.path)
        exit 1
EOF
~~~

### 4. 7단계 통합 Pipeline 생성

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: model-e2e-7stage-pipeline
spec:
  params:
    - name: model-name
      default: ${MODEL_NAME}
    - name: model-version
      default: v2
    - name: s3-path
      default: ${MODEL_NAME}/v1
    - name: email-to
      default: "${ALERT_EMAIL_TO:-poc-admin@example.com}"
  tasks:
    - name: stage1-register
      taskRef:
        name: request-model-registration
      params:
        - name: model-name
          value: \$(params.model-name)
        - name: model-version
          value: \$(params.model-version)
        - name: s3-path
          value: \$(params.s3-path)
    - name: stage2-notify-registration
      runAfter: [stage1-register]
      taskRef:
        name: send-notification
      params:
        - name: stage
          value: "모델 등록 요청"
        - name: status
          value: "승인 대기"
        - name: email-to
          value: \$(params.email-to)
    - name: stage3-approve-registration
      runAfter: [stage2-notify-registration]
      taskRef:
        apiVersion: openshift-pipelines.org/v1alpha1
        kind: ApprovalTask
      params:
        - name: approvers
          value:
            - poc-admin
            - admin
            - group:rhods-admins
        - name: numberOfApprovalsRequired
          value: "1"
        - name: description
          value: "모델 등록 승인 요청"
    - name: stage4-request-deploy
      runAfter: [stage3-approve-registration]
      taskRef:
        name: request-model-deploy
      params:
        - name: model-name
          value: \$(params.model-name)
        - name: s3-path
          value: \$(params.s3-path)
        - name: namespace
          value: ${MODEL_NS}
    - name: stage5-notify-deploy
      runAfter: [stage4-request-deploy]
      taskRef:
        name: send-notification
      params:
        - name: stage
          value: "모델 배포 완료"
        - name: status
          value: "최종 승인 대기"
        - name: email-to
          value: \$(params.email-to)
    - name: stage6-approve-deploy
      runAfter: [stage5-notify-deploy]
      taskRef:
        apiVersion: openshift-pipelines.org/v1alpha1
        kind: ApprovalTask
      params:
        - name: approvers
          value:
            - poc-admin
            - admin
            - group:rhods-admins
        - name: numberOfApprovalsRequired
          value: "1"
        - name: description
          value: "모델 배포 최종 승인"
    - name: stage7-deploy-and-verify
      runAfter: [stage6-approve-deploy]
      taskRef:
        name: deploy-and-verify-serving
      params:
        - name: model-name
          value: \$(params.model-name)
        - name: namespace
          value: ${MODEL_NS}
        - name: s3-path
          value: \$(params.s3-path)
EOF
~~~

### 5. 승인 시나리오 실행

~~~bash
oc create -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: e2e-7stage-approve-
spec:
  pipelineRef:
    name: model-e2e-7stage-pipeline
EOF

echo "Stage 3 승인 대기 중..."
sleep 30
AT_REG=$(oc get approvaltask -n ${MODEL_NS} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc patch approvaltask ${AT_REG} -n ${MODEL_NS} --type='merge' -p '{"spec":{"approvers":[{"name":"admin","input":"approve"}]}}'
echo "Stage 3 승인 완료"

echo "Stage 6 승인 대기 중..."
sleep 60
AT_DEP=$(oc get approvaltask -n ${MODEL_NS} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc patch approvaltask ${AT_DEP} -n ${MODEL_NS} --type='merge' -p '{"spec":{"approvers":[{"name":"admin","input":"approve"}]}}'
echo "Stage 6 승인 완료"

sleep 30
oc get pipelinerun -n ${MODEL_NS} --sort-by=.metadata.creationTimestamp | tail -1
~~~

### 6. 반려 시나리오 실행

~~~bash
oc create -n ${MODEL_NS} -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: e2e-7stage-reject-
spec:
  pipelineRef:
    name: model-e2e-7stage-pipeline
EOF

sleep 30
AT_NAME=$(oc get approvaltask -n ${MODEL_NS} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
oc patch approvaltask ${AT_NAME} -n ${MODEL_NS} --type='merge' -p '{"spec":{"approvers":[{"name":"admin","input":"reject"}]}}'

sleep 15
echo "=== 반려 후 PipelineRun 상태 ==="
oc get pipelinerun -n ${MODEL_NS} --sort-by=.metadata.creationTimestamp | tail -1
# 기대: SUCCEEDED=False
~~~

## 검증

~~~bash
# 1. 7단계 Pipeline 존재
oc get pipeline model-e2e-7stage-pipeline -n ${MODEL_NS}

# 2. Task 5개 (send-notification, request-model-registration, request-model-deploy, deploy-and-verify-serving, verify-serving-endpoint)
oc get task -n ${MODEL_NS}

# 3. 승인 시나리오 SUCCEEDED=True
oc get pipelinerun -n ${MODEL_NS} -l tekton.dev/pipeline=model-e2e-7stage-pipeline \
  --sort-by=.metadata.creationTimestamp -o custom-columns='NAME:.metadata.name,SUCCEEDED:.status.conditions[0].status' | head -3

# 4. 반려 시나리오 SUCCEEDED=False

# 5. 알림 발송 확인
MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS} -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "${MAILHOG_ROUTE}" ]; then
  curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=5" | python3 -c "
import sys, json
msgs = json.load(sys.stdin).get('items', [])
for m in msgs:
    subj = m.get('Content',{}).get('Headers',{}).get('Subject',[''])[0]
    print(f'  {subj}')
"
fi
~~~

## 실측 결과 (2026-05-17)

```
클러스터: OCP 4.21.14 / ManualApprovalGate v0.8.0
실행자: poc-operator (edit 권한)
승인자: admin (rhods-admins 그룹 멤버)

PipelineRun: e2e-7stage-group-ckwq8 → SUCCEEDED=True
  Stage 1 등록 요청:    Succeeded (4s)
  Stage 2 메일 알람:    Succeeded (4s) + MailHog 수신 확인
  Stage 3 등록 승인:    admin 승인 (approvers: [poc-admin, admin, rhods-admins])
  Stage 4 배포 요청:    Succeeded (5s, 배포 없이 기록만)
  Stage 5 메일 알람:    Succeeded (4s) + MailHog 수신 확인
  Stage 6 최종 승인:    admin 승인
  Stage 7 배포+검증:    Succeeded (4s, HTTP 200)
MailHog 수신: 5건
```

## ApprovalTask 승인자 설정

### 복수 사용자 + 그룹

ApprovalTask의 `approvers`는 YAML 리스트 형식으로 복수 사용자와 그룹을 지원한다.

~~~yaml
params:
  - name: approvers
    value:
      - poc-admin          # 개별 사용자
      - admin              # 개별 사용자
      - group:rhods-admins # 그룹 (group: 접두사 필수)
  - name: numberOfApprovalsRequired
    value: "1"             # N명 중 1명만 승인하면 통과
~~~

### 주의: YAML 리스트 vs JSON 배열

~~~yaml
# 올바른 형식 (YAML 리스트)
value:
  - poc-admin
  - admin

# 잘못된 형식 (JSON 배열 리터럴 — webhook 패닉 유발)
value: [poc-admin, admin]
~~~

### 승인 CLI

~~~bash
# 승인 대상 조회
AT_NAME=$(oc get approvaltask -n ${MODEL_NS} \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')

# 승인 (approvers 전체를 patch — 본인만 input 변경)
oc patch approvaltask ${AT_NAME} -n ${MODEL_NS} --type='merge' \
  -p '{"spec":{"approvers":[
    {"name":"poc-admin","input":"pending"},
    {"name":"admin","input":"approve"},
    {"name":"rhods-admins","input":"pending"}
  ]}}'

# 또는 opc CLI 사용 (권장)
# opc approvaltask approve ${AT_NAME} -n ${MODEL_NS}
~~~

### 제약 사항

| 항목 | 내용 |
|------|------|
| `--as` impersonation | webhook과 충돌하여 EOF 패닉 발생. 실제 사용자로 로그인하여 승인 필요 |
| 그룹 접두사 | `group:` 필수. 접두사 없이 그룹명만 넣으면 User로 취급되어 "does not exist" |
| patch 형식 | 본인 외 다른 approver의 기존 input을 유지해야 함. 전체 approvers 배열을 patch |

## 알림 (메일)

### MailHog 구성

MailHog는 PoC 환경용 SMTP 테스트 서버이다. Stage 2/5에서 `send-notification` Task가 SMTP로 메일을 발송한다.

~~~bash
# MailHog 배포 (미설치 시)
oc new-app mailhog/mailhog -n ${MODEL_NS}
oc expose svc/mailhog -n ${MODEL_NS} --port=8025

# 수신 확인
MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS} -o jsonpath='{.spec.host}')
curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=5"
~~~

### 프로덕션 전환 시

| 항목 | PoC (현재) | 프로덕션 |
|------|-----------|---------|
| SMTP 서버 | MailHog (1025) | 사내 SMTP 또는 SES |
| 수신자 | poc-admin@example.com | 실제 운영팀 DL |
| TLS | 미사용 | requireTLS: true |
| 대안 | - | Slack webhook, PagerDuty |

`send-notification` Task의 `smtp://` URL과 `--mail-rcpt`를 변경하면 프로덕션 SMTP로 전환 가능.

## 실패 시

- **send-notification 실패** → MailHog 미설치. `oc new-app mailhog/mailhog -n ${MODEL_NS}` 또는 infra/poc/mailhog/ 참조
- **Stage 4 요청 기록 실패** → InferenceService 미존재. `60-model-serving.md` 선행 필요
- **Stage 7 배포 타임아웃** → vLLM 모델 로딩 시간 고려 (135M ~2분, 8B ~5분). timeout 조정
- **Stage 7 API 검증 실패** → Pod Ready 후 vLLM 초기화에 추가 시간 필요. 재시도 로직 포함
- **반려 후 후속 Stage 실행** → ManualApprovalGate v0.8.0+ 필수
- **ApprovalTask webhook 패닉** → approvers를 `value: [a, b]` 형식으로 작성하면 발생. YAML 리스트 형식 사용
- **"User does not exist"** → 그룹에 `group:` 접두사 누락. 또는 `--as` impersonation 사용 시 발생

## 다음 단계

→ `runbooks/62-v3-autoscaling.md` — S3 강화: GPU 메트릭 스케일링

# S2: 모델 배포 승인 파이프라인 — 등록 요청부터 서빙까지 거버넌스 자동화

## 메타 정보

| 항목          | 내용                                                                       |
| ----------- | ------------------------------------------------------------------------ |
| 주역할         | DS (Data Scientist, `poc-user`) → MGR (Dev Team Manager, `poc-operator`) |
| 보조역할        | OPS (Operator, `poc-operator` — 모니터링)                                    |
| 데모 시간       | 20분                                                                      |
| 검증 항목       | No.1, 2, 3, 10, 11, 12, 43                                               |
| 구축 런북       | `runbooks/310-pipeline.md`, `runbooks/311-pipeline-v3.md`                |
| 검증 런북       | `runbooks/510-pipeline-validation.md`                                    |
| IaC 경로      | `infra/poc/pipeline/`                                                    |
| Pipeline 이름 | `model-e2e-7stage-pipeline` (7단계 통합)                                     |

### 파이프라인 입력 파라미터 (필수)

| 파라미터 | 설명 | 기본값 | 사용 위치 |
|---------|------|-------|---------|
| `model-name` | 배포 대상 모델 이름 (InferenceService 이름과 동일) | `${MODEL_NAME:-smollm2-135m}` | Stage 1(Registry 등록), Stage 2,5(메일 본문), Stage 4(배포 요청), Stage 7(IS patch) |
| `model-version` | 모델 버전 (Registry에 기록). S1에서 v1(baseline)을 배포했으므로 S2에서는 v2(튜닝 완료)를 배포하여 버전 전환을 시연 | `v2` | Stage 1(Registry 등록), Stage 2,5(메일 본문) |
| `s3-path` | S3 내 모델 아티팩트 경로. S1이 v1 경로로 배포했으므로 S2에서는 v2 경로로 전환하여 모델 업그레이드를 시연 | `${MODEL_NAME:-smollm2-135m}/v2` | Stage 1(S3 검증), Stage 7(IS storage.path v1→v2 patch) |
| `email-to` | 승인 요청 알림 수신 이메일 | `poc-admin@example.com` | Stage 2, 5(메일 발송) |
| `requester` | 배포 요청자 (DS 사용자명) | `poc-user` | Stage 2, 5(메일 본문에 요청자 표시) |

### 파이프라인이 내부에서 사용하는 인프라 정보

| 리소스 | 참조 방식 | 값 |
|--------|---------|-----|
| S3 Endpoint | Task 환경변수 (Pipeline 정의 시 하드코딩) | `http://minio.${MODEL_NS:-mobis-poc}.svc.cluster.local:9000` |
| S3 Bucket | Task 환경변수 | `${S3_BUCKET:-models}` |
| S3 인증 정보 | Secret `poc-s3-connection`의 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | K8s secretKeyRef |
| Model Registry | Task 환경변수 | `http://poc-model-registry-rest.rhoai-model-registries.svc.cluster.local:8080` |
| SMTP 서버 | Task 환경변수 | `smtp://mailhog.${MODEL_NS:-mobis-poc}.svc.cluster.local:1025` |
| MailHog Web UI | Route | `https://mailhog-mobis-poc.apps.poc.mobis.com` |
| InferenceService NS | Task params | `${MODEL_NS:-mobis-poc}` |
| 승인자 목록 | ApprovalTask params (YAML 리스트) | `poc-admin`, `admin`, `group:rhods-admins` |

---

## 상황 (Context)

> 현대모비스 AI팀은 S1에서 구축한 Model Registry로 모델 자산을 체계적으로 관리하게 되었다. 그러나 모델 등록과 배포 사이에 승인 프로세스가 없어, 데이터 과학자가 실험 중인 모델을 직접 운영 환경에 배포하는 사고가 발생했다. 학습이 완료되지 않은 모델이 내부 테스트 API에 올라가 잘못된 응답을 반환했고, 원인을 파악하는 데 반나절이 소요되었다. AI 거버넌스 팀에서는 "모든 모델 배포에 관리자 승인이 필수"라는 정책을 수립했지만, 이를 기술적으로 강제할 방법이 없었다.

## 문제 (Problem)

> 1. **무승인 배포 위험** — 누구든 `oc apply`로 InferenceService를 생성하면 모델이 즉시 서빙된다. 학습 미완료 모델, 검증 미통과 모델이 운영에 노출될 수 있다.
> 2. **프로세스 강제 불가** — "배포 전 팀장 승인" 규칙이 문서에만 존재한다. 급한 상황에서 빠짐없이 지켜진다는 보장이 없다.
> 3. **수동 검증의 누락** — 모델 아티팩트 존재 여부, 서빙 엔드포인트 정상 응답 여부를 사람이 매번 수동으로 확인해야 한다. 확인을 빠뜨려도 알 수 없다.
> 4. **감사 기록 부재** — 누가 승인했는지, 언제 배포가 시작되었는지, 파이프라인의 각 단계가 성공/실패했는지 추적할 수 없다.

## 해결 (Solution) — RHOAI 7단계 통합 파이프라인으로 해결합니다

### 7단계 파이프라인 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│  model-e2e-7stage-pipeline                                          │
│                                                                     │
│  [Stage 1]          [Stage 2]           [Stage 3]                  │
│  모델 등록 요청  →  메일 알람 발송  →  승인 게이트 1              │
│  (Registry API)     (SMTP→MailHog)      (ManualApprovalGate)       │
│  ↓ registration-id   ↓ 승인 대기 메일    ↓ pending → approved      │
│                                                                     │
│  [Stage 4]          [Stage 5]           [Stage 6]                  │
│  배포 요청 기록  →  메일 알람 발송  →  승인 게이트 2              │
│  (IS 현재상태 기록)  (SMTP→MailHog)      (ManualApprovalGate)       │
│  ↓ deploy-request-id  ↓ 최종 승인 대기    ↓ pending → approved      │
│                                                                     │
│  [Stage 7]                                                          │
│  vLLM 배포 + REST API 검증                                         │
│  (IS patch → Ready 대기 → /v1/models HTTP 200)                    │
│  ↓ endpoint-status=HTTP_200                                        │
└─────────────────────────────────────────────────────────────────────┘

입력 파라미터:
  model-name ──→ Stage 1, 4, 7 (어떤 모델을)
  model-version → Stage 1 (어떤 버전으로)
  s3-path ─────→ Stage 1, 7 (어디서 가져와서)
  email-to ────→ Stage 2, 5 (누구에게 알리고)

인프라 참조 (Pipeline 정의에 내장):
  S3 endpoint ─→ minio.${MODEL_NS:-mobis-poc}.svc:9000
  S3 bucket ───→ ${S3_BUCKET:-models}
  S3 인증 ─────→ Secret poc-s3-connection (AWS_ACCESS_KEY_ID/SECRET)
  Registry ────→ poc-model-registry-rest.rhoai-model-registries.svc:8080
  SMTP ────────→ mailhog.${MODEL_NS:-mobis-poc}.svc:1025
```

---

### Step 0: 환경 변수 로드 + 전제 조건 확인

- **누가**: OPS (`poc-operator`)
- **무엇을**: 파이프라인이 참조하는 모든 인프라 리소스가 정상인지 사전 확인
- **어떻게**:
  ```bash
  set -a && source .env && set +a

  echo "=== 파이프라인 전제 조건 확인 ==="

  # 1. S3 DataConnection Secret 존재
  oc get secret poc-s3-connection -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d && echo " (S3 key OK)"

  # 2. MinIO 접근 가능
  oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- \
    ls /data/${S3_BUCKET:-models}/${MODEL_NAME:-smollm2-135m}/ 2>/dev/null \
    && echo "S3 모델 경로 OK" \
    || echo "WARNING: S3 모델 경로 없음 — 모델 업로드 필요"

  # 3. Model Registry 접근 가능
  MR_HOST="poc-model-registry-rest.rhoai-model-registries.svc.cluster.local:8080"
  oc exec -n ${MODEL_NS:-mobis-poc} deploy/minio -- \
    curl -s -o /dev/null -w "Registry HTTP %{http_code}" \
    "http://${MR_HOST}/api/model_registry/v1alpha3/registered_models" \
    && echo ""

  # 4. ManualApprovalGate 정상
  oc get manualapprovalgate -o jsonpath='{.items[0].status.conditions[0].status}'
  echo " (ApprovalGate Ready)"

  # 5. MailHog 실행 중
  oc get pods -n ${MODEL_NS:-mobis-poc} -l app=mailhog --no-headers
  # 기대: mailhog-xxx Running

  # 6. InferenceService 존재 (배포 대상)
  oc get inferenceservice ${MODEL_NAME:-smollm2-135m} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='IS={.metadata.name}, Ready={.status.conditions[?(@.type=="Ready")].status}'
  echo ""

  # 7. 현재 파라미터 확인
  echo "=== PipelineRun에 전달할 파라미터 ==="
  echo "  model-name:    ${MODEL_NAME:-smollm2-135m}"
  echo "  model-version: v2"
  echo "  s3-path:       ${MODEL_NAME:-smollm2-135m}/v1"
  echo "  s3-bucket:     ${S3_BUCKET:-models}"
  echo "  s3-endpoint:   http://minio.${MODEL_NS:-mobis-poc}.svc.cluster.local:9000"
  echo "  email-to:      ${ALERT_EMAIL_TO:-poc-admin@example.com}"
  echo "  namespace:     ${MODEL_NS:-mobis-poc}"
  ```
- **권한**: NS edit (`poc-operator`)
- **확인**: S3/Registry/ApprovalGate/MailHog/IS 전부 정상

> **[시연 포인트]** "파이프라인이 실제로 연결하는 인프라를 먼저 확인합니다. S3 스토리지, Model Registry, 승인 게이트, 메일 서버, 배포 대상 InferenceService — 이 5개가 모두 살아있어야 7단계가 동작합니다."

### Step 1: vLLM ServingRuntime + Pipeline 구성 확인

- **누가**: OPS (`poc-operator`)
- **무엇을**: 파이프라인과 Task가 정상 배포되어 있는지 확인
- **어떻게**:
  ```bash
  # ServingRuntime 목록 — vLLM CUDA 확인
  oc get servingruntime -n ${MODEL_NS:-mobis-poc} \
    -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image'
  # 기대: vllm-cuda-runtime  quay.io/modh/vllm:rhoai-2.22-cuda

  # 7단계 Pipeline 존재
  oc get pipeline model-e2e-7stage-pipeline -n ${MODEL_NS:-mobis-poc}
  # 기대: model-e2e-7stage-pipeline

  # Task 목록 (5개)
  oc get task -n ${MODEL_NS:-mobis-poc} -o custom-columns='NAME:.metadata.name'
  # 기대:
  #   request-model-registration  (Stage 1)
  #   send-notification           (Stage 2, 5)
  #   request-model-deploy        (Stage 4)
  #   deploy-and-verify-serving   (Stage 7)
  #   validate-model-artifact     (v1 파이프라인용)
  ```
- **권한**: NS edit (`poc-operator`)
- **확인**: Pipeline 1개, Task 5개, ServingRuntime 존재

> **[시연 포인트]** "TGI, TensorRT-LLM 등 대체 엔진도 ServingRuntime으로 등록하면 동일한 파이프라인으로 배포할 수 있습니다. 엔진 교체가 파이프라인 변경 없이 가능합니다."

### Step 2: DS가 파이프라인 실행 — 모델 배포 "요청" 제출

- **누가**: DS (`poc-user`)
- **무엇을**: 파라미터를 지정하여 PipelineRun을 생성. DS는 모델을 직접 배포하는 것이 아니라 배포 "요청"을 제출하는 것이다.
- **어떻게**:
  ```bash
  # DS 로그인
  oc login -u poc-user

  # PipelineRun 생성 — 모든 필수 파라미터 명시
  oc create -n ${MODEL_NS:-mobis-poc} -f - <<EOF
  apiVersion: tekton.dev/v1
  kind: PipelineRun
  metadata:
    generateName: demo-7stage-
    labels:
      requester: poc-user
      scenario: s2-demo
  spec:
    pipelineRef:
      name: model-e2e-7stage-pipeline
    params:
      - name: model-name
        value: "${MODEL_NAME:-smollm2-135m}"
      - name: model-version
        value: "v2"
      - name: s3-path
        value: "${MODEL_NAME:-smollm2-135m}/v2"
      - name: email-to
        value: "${ALERT_EMAIL_TO:-poc-admin@example.com}"
      - name: requester
        value: "poc-user"
  EOF

  echo "파이프라인 실행 요청 완료. 승인 대기 중..."
  ```
- **권한**: NS view + PipelineRun create (`poc-user`)
- **확인**: PipelineRun 리소스 생성됨

> **[시연 포인트]** "DS는 `model-name`, `model-version`, `s3-path`를 지정해서 '이 모델의 이 버전을 이 S3 경로에서 가져와 배포해주세요'라고 요청합니다. S3 인증 정보나 Registry 주소는 파이프라인 정의에 내장되어 있어 DS가 알 필요가 없습니다."

### Step 3: Stage 1~2 자동 실행 (등록 + 알림)

- **누가**: 파이프라인 자동 실행 (사람 개입 없음)
- **무엇을**: Stage 1에서 Model Registry에 모델을 자동 등록하고 ID를 반환. Stage 2에서 승인 요청 메일을 발송.
- **어떻게**:
  ```bash
  # OPS 계정으로 전환하여 모니터링
  oc login -u poc-operator

  sleep 15
  LATEST_RUN=$(oc get pipelinerun -n ${MODEL_NS:-mobis-poc} \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.name}')
  echo "PipelineRun: ${LATEST_RUN}"

  # Stage 1 (등록) 결과 확인
  oc get pipelinerun ${LATEST_RUN} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{range .status.childReferences[*]}{.pipelineTaskName}: {.kind}{"\n"}{end}'
  # 기대:
  #   stage1-register: TaskRun (Succeeded)
  #   stage2-notify-registration: TaskRun (Succeeded)
  #   stage3-approve-registration: CustomRun (Running — 승인 대기)

  # MailHog Web UI에서 메일 확인 (브라우저)
  # URL: https://mailhog-mobis-poc.apps.poc.mobis.com
  
  # CLI로 메일 확인
  MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.spec.host}')
  curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=2" | python3 -c "
  import sys, json
  msgs = json.load(sys.stdin).get('items', [])
  for m in msgs:
      subj = m.get('Content',{}).get('Headers',{}).get('Subject',[''])[0]
      body = m.get('Content',{}).get('Body','')
      print(f'  메일: {subj}')
      print(f'  본문 미리보기: {body[:200]}')
      print()
  "
  # 기대 메일 제목: "[PoC Pipeline] 모델 등록 요청 - 승인 대기"
  # 기대 메일 본문:
  #   === 모델 배포 파이프라인 알림 ===
  #   Stage: 모델 등록 요청
  #   Status: 승인 대기
  #   Time: 2026-05-21T08:00:00Z
  #
  #   --- 요청 정보 ---
  #   요청자: poc-user
  #   모델명: smollm2-135m
  #   모델 버전: v2
  #   S3 경로: smollm2-135m/v2
  #   네임스페이스: mobis-poc
  #
  #   --- 승인 페이지 ---
  #   아래 링크를 클릭하여 승인/거부하세요:
  #   https://console-openshift-console.apps.poc.mobis.com/k8s/ns/mobis-poc/tekton.dev~v1~PipelineRun/<run-name>
  #
  #   MailHog 수신함: https://mailhog-mobis-poc.apps.poc.mobis.com
  ```
- **권한**: 파이프라인 ServiceAccount (자동)
- **확인**: Stage 1 Succeeded (Registry ID 반환), Stage 2 Succeeded (메일 발송), Stage 3 Running (승인 대기)

> **[시연 포인트]** "Stage 1에서 Model Registry API에 `model-name`과 `s3-path`를 전달하여 모델을 자동 등록하고 ID를 받습니다. Stage 2에서 `email-to` 수신자에게 승인 요청 메일을 발송합니다. 사람이 개입하지 않았는데 2단계가 자동으로 완료되었습니다."

### Step 4: 승인 게이트 — 차단 상태 확인

- **누가**: MGR (`poc-operator`) — 아직 승인하지 않음. 차단 상태를 확인만 함.
- **무엇을**: Stage 3 ApprovalTask에서 파이프라인이 멈춰 있고, 승인 없이는 Stage 4로 진행 불가능함을 실증
- **어떻게**:
  ```bash
  # ApprovalTask 상태 조회
  AT_NAME=$(oc get approvaltask -n ${MODEL_NS:-mobis-poc} \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.name}')
  echo "ApprovalTask: ${AT_NAME}"

  oc get approvaltask ${AT_NAME} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='state={.status.state}, approvals={.status.approvalsReceived}/{.spec.numberOfApprovalsRequired}'
  echo ""
  # 기대: state=pending, approvals=0/1

  # 승인 가능한 사용자/그룹 확인
  oc get approvaltask ${AT_NAME} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='approvers={.spec.approvers[*].name}'
  echo ""
  # 기대: approvers=poc-admin admin rhods-admins

  # Stage 4 이후가 차단되어 있음을 확인
  oc get pipelinerun ${LATEST_RUN} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{range .status.childReferences[*]}{.pipelineTaskName}: {.kind}{"\n"}{end}'
  # 기대: stage4-request-deploy 없음 (차단됨)
  ```
- **권한**: NS edit + approval (`poc-operator`)
- **확인**: ApprovalTask state=pending, Stage 4 미실행

> **[시연 포인트]** "화면을 보시면 파이프라인이 Stage 3에서 멈춰 있습니다. `poc-admin`, `admin`, `group:rhods-admins` 중 1명이 승인해야 합니다. 이 상태에서는 아무리 기다려도 모델이 배포되지 않습니다. 이것이 '문서에만 있는 규칙'이 아니라 '시스템이 강제하는 규칙'입니다."

### Step 5: MGR가 등록 승인 수행 (Stage 3)

- **누가**: MGR (`poc-operator`) — admin 또는 rhods-admins 그룹 멤버
- **무엇을**: 모델 등록 결과를 확인하고 배포 프로세스 진행을 승인
- **어떻게**:
  ```bash
  # 등록 승인 수행 (모든 approver를 포함해야 webhook 패닉 방지)
  echo ">> 등록 승인 수행 (MGR: admin)"
  oc patch approvaltask ${AT_NAME} -n ${MODEL_NS:-mobis-poc} \
    --type='merge' \
    -p '{"spec":{"approvers":[{"name":"poc-admin","input":"pending"},{"name":"admin","input":"approve"},{"name":"rhods-admins","input":"pending"}]}}'

  # 승인 상태 확인
  sleep 5
  oc get approvaltask ${AT_NAME} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='state={.status.state}, approvals={.status.approvalsReceived}'
  echo ""
  # 기대: state=approved, approvalsReceived=1

  echo "Stage 3 승인 완료. Stage 4~5 자동 진행 중..."
  ```
- **권한**: NS edit + approval (`poc-operator`)
- **확인**: ApprovalTask state=approved

### Step 6: Stage 4~5 자동 실행 + Stage 6 최종 승인

- **누가**: Stage 4~5 자동 → MGR가 Stage 6 승인
- **무엇을**: Stage 4에서 배포 요청을 기록하고(IS 현재 상태 + S3 경로 비교), Stage 5에서 최종 승인 요청 메일 발송. Stage 6에서 최종 배포 승인.
- **어떻게**:
  ```bash
  # Stage 4~5 완료 대기
  sleep 30

  # Stage 4 결과: 배포 요청 기록 (IS patch 전 상태 스냅샷)
  oc get pipelinerun ${LATEST_RUN} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{range .status.childReferences[*]}{.pipelineTaskName}: {.kind}{"\n"}{end}'
  # 기대: stage4-request-deploy (Succeeded), stage5-notify-deploy (Succeeded)

  # Stage 4가 기록한 내용: IS 현재 경로 vs 요청 경로
  echo "  배포 대상 IS: ${MODEL_NAME:-smollm2-135m}"
  echo "  요청 S3 경로: ${MODEL_NAME:-smollm2-135m}/v1"
  echo "  네임스페이스: ${MODEL_NS:-mobis-poc}"

  # Stage 6 최종 승인
  echo "Stage 6 최종 승인 대기..."
  sleep 10
  AT_DEPLOY=$(oc get approvaltask -n ${MODEL_NS:-mobis-poc} \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.name}')

  oc patch approvaltask ${AT_DEPLOY} -n ${MODEL_NS:-mobis-poc} \
    --type='merge' \
    -p '{"spec":{"approvers":[{"name":"poc-admin","input":"pending"},{"name":"admin","input":"approve"},{"name":"rhods-admins","input":"pending"}]}}'

  echo "Stage 6 최종 승인 완료. Stage 7 배포+검증 자동 진행 중..."
  ```
- **권한**: NS edit + approval (`poc-operator`)
- **확인**: Stage 4~5 Succeeded, Stage 6 approved

> **[시연 포인트]** "Stage 4에서 '현재 IS가 어떤 S3 경로를 보고 있고, 새 요청은 어떤 경로인지'를 기록합니다. 이 정보가 감사 로그가 됩니다. Stage 6의 최종 승인 후에야 실제 IS patch가 실행됩니다."

### Step 7: Stage 7 자동 배포 + REST API 검증

- **누가**: 파이프라인 자동 실행
- **무엇을**: InferenceService의 `storage.path`를 `s3-path` 파라미터 값으로 patch → vLLM Pod Ready 대기 → `/v1/models` HTTP 200 검증 (최대 10회 재시도, 5초 간격)
- **어떻게**:
  ```bash
  # 배포 + 검증 완료 대기 (최대 120초)
  sleep 60
  oc get pipelinerun ${LATEST_RUN} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='최종상태: {.status.conditions[0].reason}'
  echo ""
  # 기대: Succeeded

  # 모든 Stage 실행 결과 확인
  oc get pipelinerun ${LATEST_RUN} -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{range .status.childReferences[*]}{.pipelineTaskName}: {.kind}{"\n"}{end}'
  # 기대: stage1~stage7 모두 존재

  # Stage 7이 실행한 작업 확인:
  echo "=== Stage 7 실행 내역 ==="
  echo "  1. oc patch inferenceservice ${MODEL_NAME:-smollm2-135m} -n ${MODEL_NS:-mobis-poc}"
  echo "     → spec.predictor.model.storage.path = '${MODEL_NAME:-smollm2-135m}/v1'"
  echo "  2. oc wait inferenceservice ${MODEL_NAME:-smollm2-135m} --for=condition=Ready --timeout=600s"
  echo "  3. curl ${MODEL_NAME:-smollm2-135m}-predictor.${MODEL_NS:-mobis-poc}.svc:8080/v1/models (10회 재시도)"
  echo "     → endpoint-status=HTTP_200"
  ```
- **권한**: 파이프라인 ServiceAccount (자동)
- **확인**: PipelineRun Succeeded, 7개 Stage 모두 완료

> **[시연 포인트]** "Stage 7에서 3가지를 자동으로 수행합니다: (1) IS에 새 S3 경로를 patch하여 모델을 교체하고, (2) vLLM Pod가 Ready 될 때까지 최대 10분 대기하고, (3) `/v1/models` API가 HTTP 200을 반환하는지 10회 재시도로 검증합니다. 사람이 '배포 완료 확인'을 빠뜨릴 수 없습니다."

### Step 8: 배포된 모델 OpenAI 호환 API 검증

- **누가**: DS (`poc-user`)
- **무엇을**: 파이프라인이 배포한 모델이 실제로 추론 가능한지 OpenAI 호환 API로 확인
- **어떻게**:
  ```bash
  oc login -u poc-user

  ROUTE=$(oc get route ${MODEL_NAME:-smollm2-135m}-api -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='{.spec.host}' 2>/dev/null)
  # Route가 없으면 내부 svc 사용
  if [ -z "${ROUTE}" ]; then
    ROUTE="${MODEL_NAME:-smollm2-135m}-predictor.${MODEL_NS:-mobis-poc}.svc.cluster.local:8080"
    PROTO="http"
  else
    PROTO="https"
  fi

  # /v1/models — 모델 목록
  echo ">> GET /v1/models"
  curl -sk "${PROTO}://${ROUTE}/v1/models" | python3 -c "
  import sys, json
  data = json.load(sys.stdin).get('data', [])
  for m in data:
      print(f'  model: {m[\"id\"]}')
  "

  # /v1/completions — 텍스트 생성
  echo ">> POST /v1/completions"
  curl -sk "${PROTO}://${ROUTE}/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${MODEL_NAME:-smollm2-135m}\",
      \"prompt\": \"현대모비스의 자율주행 기술은\",
      \"max_tokens\": 30
    }" | python3 -c "
  import sys, json
  r = json.load(sys.stdin)
  print(f'  model: {r.get(\"model\")}')
  if r.get('choices'):
      print(f'  생성: {r[\"choices\"][0].get(\"text\",\"\")[:200]}')
  "

  # /v1/chat/completions — 채팅
  echo ">> POST /v1/chat/completions"
  curl -sk "${PROTO}://${ROUTE}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${MODEL_NAME:-smollm2-135m}\",
      \"messages\": [{\"role\": \"user\", \"content\": \"Hello, what can you do?\"}],
      \"max_tokens\": 30
    }" | python3 -c "
  import sys, json
  r = json.load(sys.stdin)
  if r.get('choices'):
      msg = r['choices'][0].get('message', {})
      print(f'  role: {msg.get(\"role\")}')
      print(f'  content: {msg.get(\"content\",\"\")[:200]}')
  "
  ```
- **권한**: NS view + serving (`poc-user`)
- **확인**: `/v1/models` HTTP 200, `/v1/completions` 텍스트 생성, `/v1/chat/completions` 응답 정상

### Step 9: (선택) 승인 거부 시나리오 실증

- **누가**: DS (`poc-user`) 요청 → MGR (`poc-operator`) 거부
- **무엇을**: 승인 거부 시 파이프라인이 실패로 종료되어 Stage 7 배포가 차단되는 것을 실증
- **어떻게**:
  ```bash
  # DS가 새 PipelineRun 생성
  oc login -u poc-user
  oc create -n ${MODEL_NS:-mobis-poc} -f - <<EOF
  apiVersion: tekton.dev/v1
  kind: PipelineRun
  metadata:
    generateName: demo-reject-test-
    labels:
      requester: poc-user
      scenario: s2-reject
  spec:
    pipelineRef:
      name: model-e2e-7stage-pipeline
    params:
      - name: model-name
        value: "${MODEL_NAME:-smollm2-135m}"
      - name: model-version
        value: "v3-experimental"
      - name: s3-path
        value: "${MODEL_NAME:-smollm2-135m}/v3-untested"
      - name: email-to
        value: "${ALERT_EMAIL_TO:-poc-admin@example.com}"
  EOF

  # MGR가 거부
  oc login -u poc-operator
  sleep 30
  AT_REJECT=$(oc get approvaltask -n ${MODEL_NS:-mobis-poc} \
    --sort-by='.metadata.creationTimestamp' \
    -o jsonpath='{.items[-1].metadata.name}')

  oc patch approvaltask ${AT_REJECT} -n ${MODEL_NS:-mobis-poc} \
    --type='merge' \
    -p '{"spec":{"approvers":[{"name":"admin","input":"reject"}]}}'

  # 결과: Pipeline 실패, Stage 7 미실행
  sleep 15
  oc get pipelinerun -n ${MODEL_NS:-mobis-poc} \
    --sort-by='.metadata.creationTimestamp' \
    -o custom-columns='NAME:.metadata.name,SUCCEEDED:.status.conditions[0].status' | tail -2
  # 기대: 마지막 PipelineRun SUCCEEDED=False
  ```
- **권한**: DS — PipelineRun create / MGR — ApprovalTask patch
- **확인**: 거부된 PipelineRun Succeeded=False, Stage 7(deploy-and-verify-serving) 미실행

> **[시연 포인트]** "실험적 v3 모델의 S3 경로(`v3-untested`)를 요청했습니다. MGR가 거부하면 파이프라인이 즉시 실패하고, InferenceService는 전혀 변경되지 않습니다. 검증되지 않은 모델은 시스템적으로 배포 불가능합니다."

### Step 10: MailHog 알림 전체 확인

- **누가**: OPS (`poc-operator`)
- **무엇을**: 파이프라인이 발송한 모든 알림 메일을 MailHog에서 확인하여 감사 추적을 실증
- **어떻게**:
  ```bash
  MAILHOG_ROUTE=$(oc get route mailhog -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.spec.host}')
  echo ">> MailHog 수신 메일 (최근 10건)"
  curl -sk "https://${MAILHOG_ROUTE}/api/v2/messages?limit=10" | python3 -c "
  import sys, json
  msgs = json.load(sys.stdin).get('items', [])
  for i, m in enumerate(msgs):
      subj = m.get('Content',{}).get('Headers',{}).get('Subject',[''])[0]
      ts = m.get('Created','')[:19]
      print(f'  {i+1}. [{ts}] {subj}')
  "
  # 기대:
  #   1. [PoC Pipeline] 모델 등록 요청 - 승인 대기
  #   2. [PoC Pipeline] 모델 배포 완료 - 최종 승인 대기
  #   (거부 시나리오 포함 시 추가 메일)
  ```
- **권한**: NS edit (`poc-operator`)
- **확인**: 승인 요청/결과 메일 수신 확인

---

## 확인 (Verification)

| 검증 기준 | 기대값 | 실측값 |
|----------|--------|--------|
| No.1 — vLLM 서빙 엔진 | vllm-cuda-runtime 존재, vLLM 이미지 사용 | vllm-cuda-runtime: quay.io/modh/vllm:rhoai-2.22-cuda |
| No.2 — 대체 엔진 지원 | TGI ServingRuntime 등록 가능 | TGI CPU SR 등록+추론 검증 완료 |
| No.3 — 엔진 버전 관리 | vLLM 버전 출력 가능 | 이미지 태그로 버전 선택/전환 가능 |
| No.10 — Pipeline 자동화 | PipelineRun Succeeded=True, 7 Stage 완료 | e2e-7stage Succeeded (4s+4s+승인+5s+4s+승인+4s) |
| No.11 — 등록 승인 프로세스 | Stage 3 ApprovalTask pending→approved | approved, approvalsReceived=1 |
| No.12 — 배포 승인 프로세스 | Stage 6 ApprovalTask pending→approved | approved, approvalsReceived=1 |
| No.12 — 거부 시 차단 | 거부 시 PipelineRun Succeeded=False | False, Stage 7 미실행 |
| No.43 — /v1/models | HTTP 200, 모델 목록 반환 | HTTP 200 |
| No.43 — /v1/completions | HTTP 200, 텍스트 생성 | HTTP 200, 텍스트 생성 정상 |
| No.43 — /v1/chat/completions | HTTP 200, 채팅 응답 | HTTP 200, 응답 정상 |
| 메일 알림 발송 | Stage 2, 5에서 MailHog 수신 | 5건 수신 확인 |
| 파라미터 전달 | model-name, s3-path가 Stage 7 IS patch에 정확 반영 | storage.path 변경 확인 |

---

## 이번 시연에서 확인된 핵심 가치

- **파라미터 기반 자동화**: DS가 `model-name`, `model-version`, `s3-path`만 지정하면, S3 인증/Registry 등록/IS 배포/API 검증이 모두 자동으로 진행된다. S3 접속 정보, Registry 주소, 네임스페이스는 파이프라인에 내장되어 DS가 인프라를 몰라도 된다.
- **이중 승인 게이트**: 등록 승인(Stage 3)과 배포 승인(Stage 6) 두 번의 검문소가 있어, "실험 모델이 실수로 배포"되는 경로가 시스템적으로 차단된다.
- **자동 검증으로 누락 방지**: Stage 7에서 IS patch → Ready 대기 → `/v1/models` HTTP 200을 10회 재시도로 자동 검증한다. "배포했다고 생각했는데 실패했다"가 불가능하다.
- **완전한 감사 추적**: PipelineRun에 요청자(DS), 파라미터(model/version/path), 승인자(MGR), 각 Stage 성공/실패/소요시간이 모두 기록된다.
- **거부 시 즉시 차단**: 거부하면 Stage 7이 실행되지 않아 IS가 전혀 변경되지 않는다.

---

## 추천 사항

- **다중 승인자 구성**: 운영 환경에서는 `numberOfApprovalsRequired: 2` 이상으로 설정하여 단독 승인 위험을 줄이는 것을 권장한다.
- **S3 경로 규칙**: `s3-path`를 `{model-name}/{version}` 형식으로 표준화하면, 파이프라인 실행 시 어떤 버전이 배포되는지 명확해진다.
- **메일 알림 강화**: 승인 요청 메일에 모델 평가 결과 링크, Dashboard URL, S3 아티팩트 목록을 포함하면 승인자의 의사결정 속도가 향상된다.
- **SMTP 프로덕션 전환**: MailHog → 사내 SMTP로 전환 시 `send-notification` Task의 `smtp://` URL과 `--mail-rcpt`만 변경하면 된다.
- **GitOps 연동**: Pipeline/Task 정의를 `infra/poc/pipeline/`에 IaC화하고 ArgoCD로 동기화하면, 파이프라인 변경 이력까지 Git에서 추적 가능하다.
- **멀티모델 파이프라인**: `gemma-model-e2e-7stage-pipeline`으로 Gemma4-31B 전용 파이프라인이 추가되었다. 동일한 Task를 재사용하며, `s3-secret: mobis-s3-connection`으로 외부 S3(s3.mobis.com)에서 모델을 가져온다.

## 파이프라인 목록

| Pipeline | 모델 | S3 Secret | 런타임 |
|----------|------|-----------|--------|
| `model-e2e-7stage-pipeline` | smollm2-135m | poc-s3-connection (MinIO) | vllm-cuda-runtime |
| `gemma-model-e2e-7stage-pipeline` | gemma-4-31b-it-rh | mobis-s3-connection (s3.mobis.com) | vllm-upstream-nightly-test |

## 주의 사항

- **ApprovalTask approvers는 YAML 리스트 형식 필수**: `value: [a, b]` 형식(JSON 배열 리터럴)으로 작성하면 webhook 패닉 발생. 반드시 YAML 리스트(`value:\n  - a\n  - b`) 사용.
- **`--as` impersonation 금지**: webhook과 충돌하여 EOF 패닉 발생. 실제 사용자로 `oc login`하여 승인 수행.
- **그룹 접두사**: `group:rhods-admins` 형식 필수. `group:` 없이 그룹명만 넣으면 User로 취급되어 "does not exist" 오류.
- **ServingRuntime template 어노테이션**: Dashboard에서 "Unknown Serving Runtime"을 방지하려면 `opendatahub.io/template-name`, `opendatahub.io/template-display-name`, `opendatahub.io/apiProtocol: REST` 어노테이션 필수.
- **Model Registry 연동 라벨**: IS에 `modelregistry.opendatahub.io/model-registry`, `registered-model-id`, `registered-model-name` 라벨/어노테이션이 없으면 Dashboard의 Model Registry에서 Deployments가 표시되지 않음. Stage 7에서 자동 추가됨.
- **외부 S3 검증**: `s3-secret`이 외부 S3(`svc.cluster.local` 미포함)인 경우, Stage 1에서 S3 ListObjects API로 파일 검증. 내부 MinIO는 `oc exec` 방식 사용.
- **CPU ServingRuntime args**: `vllm-cpu-x86-runtime`은 IS의 `model.args`에 `--port=8080 --model=/mnt/models --served-model-name=<name>`을 직접 명시해야 함 (ServingRuntime args 자동 병합 안 됨).

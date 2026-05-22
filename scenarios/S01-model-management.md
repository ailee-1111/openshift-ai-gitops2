# S1: 모델 라이프사이클 관리 — 등록, 버전 관리, 배포/철수

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | DS (Data Scientist, `poc-user`) |
| 보조역할 | MGR (Dev Team Manager, `poc-operator`) |
| 데모 시간 | 15분 |
| 검증 항목 | No.4, 5, 6, 8, 9, 13 |
| 구축 런북 | `runbooks/200-model-registry.md`, `runbooks/300-model-serving.md` |
| 검증 런북 | `runbooks/500-model-serving-validation.md` |
| IaC 경로 | `infra/poc/model-serving/` |

---

## 상황 (Context)

> 현대모비스 자율주행 AI팀은 차량 비전 모델과 LLM 기반 매뉴얼 검색 모델을 동시에 개발하고 있다. 데이터 과학자 3명이 각자 실험한 모델을 팀 공유 스토리지에 올리고, Slack으로 "v2 올렸어요, 테스트해보세요"라고 알린 뒤, 운영 담당자가 수동으로 서버에 배포하는 방식이다. 모델 파일은 팀 NAS의 `/shared/models/` 디렉토리에 날짜별 폴더로 관리되고 있다.

## 문제 (Problem)

> 1. **버전 추적 불가** — `model_v2_final`, `model_v2_final_real`, `model_v2_진짜최종` 같은 파일명이 난립한다. 어떤 버전이 현재 운영 중인지 아무도 확신하지 못한다.
> 2. **메타데이터 유실** — 모델의 학습 데이터, 하이퍼파라미터, 성능 지표가 개인 노트북에만 존재한다. 담당자 퇴사 시 맥락이 사라진다.
> 3. **배포 리드타임** — 모델 교체에 운영팀 티켓 발행 → 수동 배포 → 검증까지 평균 2~3일이 소요된다.
> 4. **감사 추적 부재** — 누가, 언제, 어떤 모델을 배포했는지 기록이 없어 AI 거버넌스 감사에 대응할 수 없다.

## 해결 (Solution) — RHOAI

### 시나리오 플로우 : 모델 카탈로그 (등록/허깅페이스/yaml)-> 인증된 모델을 사용 -> 레지스트리 버전관리(등록) -> vLLM 추론 모델 배포 -> 자원 회수/삭제 
- 사용하지 않는 모델 버전의 경우 아카이빙 처러

### Step 1: S3 모델 아티팩트 업로드 확인

- **누가**: DS (`poc-user`)
- **무엇을**: MinIO(S3 호환 스토리지)에 모델 아티팩트가 정상 저장되었는지 확인
- **어떻게**:
  ```bash
  # 환경변수 로드
  set -a && source .env && set +a

  # S3에 업로드된 모델 파일 목록 확인
  oc exec -n "${MODEL_NS:-mobis-poc}" deploy/minio -- \
    ls -lh "/data/${S3_BUCKET:-models}/${S3_MODEL_PATH}/"

  # 핵심 파일 존재 여부
  for FILE in config.json tokenizer.json model.safetensors; do
    oc exec -n "${MODEL_NS:-mobis-poc}" deploy/minio -- \
      test -f "/data/${S3_BUCKET:-models}/${S3_MODEL_PATH}/${FILE}" \
      && echo "  ${FILE}: OK" \
      || echo "  ${FILE}: MISSING"
  done
  ```
- **권한**: NS view (`poc-user`는 네임스페이스 내 리소스 조회 가능)
- **확인**: `config.json`, `tokenizer.json`, `*.safetensors` 파일이 모두 존재

### Step 2: Model Registry에 모델 v1 등록

- **누가**: DS (`poc-user`)
- **무엇을**: RHOAI Model Registry REST API로 모델을 공식 등록
- **어떻게**:
  ```bash
  # Model Registry Pod 및 토큰 획득
  MR_POD=$(oc get pods -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" \
    -l app=mobis-registry --no-headers -o name | head -1)
  TOKEN=$(oc whoami -t)

  # 모델 등록 (Pod 내부 REST API 호출)
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s -X POST \
      "http://localhost:8080/api/model_registry/v1alpha3/registered_models" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"${MODEL_NAME:-smollm2-135m}"'",
        "description": "PoC 검증용 sLLM 모델",
        "customProperties": {
          "team": {"string_value": "autonomous-driving", "metadataType": "MetadataStringValue"},
          "framework": {"string_value": "vLLM", "metadataType": "MetadataStringValue"},
          "task": {"string_value": "text-generation", "metadataType": "MetadataStringValue"}
        }
      }'
  ```
- **권한**: NS view + serving (`poc-user`는 Model Registry API 호출 가능)
- **확인**: HTTP 200 응답, 유효한 `id` 반환

### Step 3: v1 버전 등록 및 확인

- **누가**: DS (`poc-user`)
- **무엇을**: 등록된 모델에 v1 버전을 생성하고 버전 목록 조회
- **어떻게**:
  ```bash
  # 모델 ID 조회
  MODEL_ID=$(oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models" \
    | python3 -c "
  import sys, json
  for m in json.load(sys.stdin).get('items', []):
      if m['name'] == '${MODEL_NAME:-smollm2-135m}':
          print(m['id']); break
  ")

  # v1 버전 등록 (registeredModelId 필수)
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s -X POST \
      "http://localhost:8080/api/model_registry/v1alpha3/model_versions" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"v1\", \"description\": \"초기 학습 모델 (baseline)\", \"registeredModelId\": \"${MODEL_ID}\"}"

  # v1 버전에 Model Artifact 연결 (S3 URI)
  VERSION_ID=$(oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
    | python3 -c "
  import sys, json
  for v in json.load(sys.stdin).get('items', []):
      if v['name'] == 'v1': print(v['id']); break
  ")
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s -X POST \
      "http://localhost:8080/api/model_registry/v1alpha3/model_versions/${VERSION_ID}/artifacts" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"${MODEL_NAME:-smollm2-135m}"'-v1-artifact",
        "uri": "s3://'"${S3_BUCKET:-mobis-poc-models}"'/'"${S3_MODEL_PATH:-smollm2-135m/v1}"'",
        "modelFormatName": "vLLM",
        "artifactType": "model-artifact"
      }'

  # 버전 목록 확인
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
    | python3 -c "
  import sys, json
  for v in json.load(sys.stdin).get('items', []):
      print(f'  - {v[\"name\"]}: id={v[\"id\"]}')
  "
  ```
- **권한**: NS view + serving (`poc-user`)
- **확인**: v1 버전이 정상 생성되고 목록에 표시됨

### Step 4: v2 버전 재등록 및 버전 전환 확인

- **누가**: DS (`poc-user`)
- **무엇을**: 개선된 모델을 v2로 등록하고, v1/v2 양 버전이 공존하는지 확인
- **어떻게**:
  ```bash
  # v2 버전 등록
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s -X POST \
      "http://localhost:8080/api/model_registry/v1alpha3/model_versions" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"v2\", \"description\": \"하이퍼파라미터 튜닝 완료, F1 0.92→0.95\", \"registeredModelId\": \"${MODEL_ID}\"}"

  # 버전 목록 재확인 — v1, v2 모두 존재
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
    | python3 -c "
  import sys, json
  versions = json.load(sys.stdin).get('items', [])
  print(f'총 버전 수: {len(versions)}')
  for v in versions:
      print(f'  - {v[\"name\"]}: {v.get(\"description\",\"\")}')
  "
  ```
- **권한**: NS view + serving (`poc-user`)
- **확인**: v1, v2 두 버전이 모두 조회됨. 각 버전에 고유 ID 부여

> **[시연 포인트]** "NAS 폴더명 대신 API 기반 버전 관리가 되므로, '진짜최종' 같은 파일명 혼란이 사라집니다."

### Step 5: 메타데이터 CRUD (조회 → 수정 → 재조회)

- **누가**: DS (`poc-user`)
- **무엇을**: 모델에 부착된 메타데이터(customProperties)를 조회/수정하여 감사 추적 가능성 입증
- **어떻게**:
  ```bash
  # 현재 메타데이터 조회
  echo ">> 수정 전 메타데이터:"
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models/${MODEL_ID}" \
    | python3 -c "
  import sys, json
  m = json.load(sys.stdin)
  print(f'  name: {m[\"name\"]}')
  print(f'  description: {m[\"description\"]}')
  for k, v in m.get('customProperties', {}).items():
      print(f'  {k}: {v.get(\"string_value\", \"?\")}')
  "

  # 메타데이터 업데이트 — 학습 정보 추가
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s -X PATCH \
      "http://localhost:8080/api/model_registry/v1alpha3/registered_models/${MODEL_ID}" \
      -H "Content-Type: application/json" \
      -d '{
        "customProperties": {
          "framework": {"string_value": "vLLM", "metadataType": "MetadataStringValue"},
          "task": {"string_value": "text-generation", "metadataType": "MetadataStringValue"},
          "dataset": {"string_value": "internal-manual-corpus-v3", "metadataType": "MetadataStringValue"},
          "accuracy": {"string_value": "0.95", "metadataType": "MetadataStringValue"},
          "owner": {"string_value": "ds-team-kim", "metadataType": "MetadataStringValue"}
        }
      }'

  # 수정 결과 확인
  echo ">> 수정 후 메타데이터:"
  oc exec -n "${MODEL_REGISTRY_NS:-rhoai-model-registries}" ${MR_POD} -c rest-container -- \
    curl -s "http://localhost:8080/api/model_registry/v1alpha3/registered_models/${MODEL_ID}" \
    | python3 -c "
  import sys, json
  for k, v in sorted(json.load(sys.stdin).get('customProperties', {}).items()):
      print(f'  {k}: {v.get(\"string_value\", \"?\")}')
  "
  ```
- **권한**: NS view + serving (`poc-user`)
- **확인**: `dataset`, `accuracy`, `owner` 필드가 추가되고 정상 조회됨

> **[시연 포인트]** "모델에 학습 데이터셋, 정확도, 담당자 정보가 API로 기록됩니다. 담당자가 변경되어도 모델의 맥락이 보존됩니다."

### Step 6: 원클릭 배포 (Model Registry 연동 InferenceService 생성)

- **누가**: MGR (`poc-operator`) — 배포 승인 권한 보유
- **무엇을**: Model Registry에 등록된 모델을 참조하는 InferenceService를 생성하여 GPU 서빙 Pod 배포
- **어떻게**:
  ```bash
  START_DEPLOY=$(date +%s)

  # Model Registry 연동 InferenceService 생성
  cat <<EOF | oc apply -f -
  apiVersion: serving.kserve.io/v1beta1
  kind: InferenceService
  metadata:
    name: ${MODEL_NAME:-smollm2-135m}
    namespace: ${MODEL_NS:-mobis-poc}
    labels:
      opendatahub.io/dashboard: "true"
      modelregistry.opendatahub.io/registered-model-id: "${MODEL_ID}"
      modelregistry.opendatahub.io/model-version-id: "${VERSION_ID}"
    annotations:
      serving.kserve.io/deploymentMode: RawDeployment
      modelregistry.opendatahub.io/registered-model-name: ${MODEL_NAME:-smollm2-135m}
      modelregistry.opendatahub.io/model-version-name: v1
      modelregistry.opendatahub.io/model-registry: ${MODEL_REGISTRY_NAME:-mobis-registry}
  spec:
    predictor:
      minReplicas: 1
      maxReplicas: 1
      model:
        modelFormat:
          name: vLLM
        runtime: vllm-cuda-runtime
        storage:
          key: poc-s3-connection
          path: ${S3_MODEL_PATH:-smollm2-135m/v1}
        args:
          - --dtype=float16
          - --max-model-len=2048
        env:
          - name: HF_HUB_OFFLINE
            value: "1"
        resources:
          limits:
            cpu: "4"
            memory: 8Gi
            nvidia.com/gpu: "1"
          requests:
            cpu: "2"
            memory: 4Gi
            nvidia.com/gpu: "1"
  EOF

  # Ready 대기
  oc wait inferenceservice "${MODEL_NAME:-smollm2-135m}" -n "${MODEL_NS:-mobis-poc}" \
    --for=condition=Ready --timeout=600s
  END_DEPLOY=$(date +%s)
  echo "배포 소요: $((END_DEPLOY - START_DEPLOY))초"

  # Model Registry 연동 확인
  oc get inferenceservice "${MODEL_NAME:-smollm2-135m}" -n "${MODEL_NS:-mobis-poc}" \
    -o jsonpath='{.metadata.labels}' | python3 -m json.tool

  # 서빙 엔드포인트 동작 확인
  POD=$(oc get pods -n "${MODEL_NS:-mobis-poc}" \
    -l "serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m}" \
    -o jsonpath='{.items[0].metadata.name}')
  oc exec -n "${MODEL_NS:-mobis-poc}" ${POD} -c kserve-container -- \
    curl -s http://localhost:8080/v1/models | python3 -m json.tool | head -10
  ```
- **권한**: NS edit + approval (`poc-operator`). 권한 없는 사용자(`poc-view`)는 확인만 가능, 배포 불가
- **확인**: InferenceService Ready=True, `/v1/models` HTTP 200, Model Registry 라벨(registered-model-id, model-version-id) 존재

> **[시연 포인트]** "Model Registry에 등록된 모델 v1이 IS에 연결되어 배포되었습니다. 누가 어떤 모델 버전을 배포했는지 라벨로 추적 가능합니다."

### Step 7: 원클릭 철수 (서빙 중단)

- **누가**: MGR (`poc-operator`)
- **무엇을**: 운영 중인 모델 서빙을 즉시 중단하여 GPU 자원 반환
- **어떻게**:
  ```bash
  START_STOP=$(date +%s)

  # 서빙 철수 (minReplicas=0)
  oc patch inferenceservice "${MODEL_NAME:-smollm2-135m}" -n "${MODEL_NS:-mobis-poc}" --type=merge \
    -p '{"spec":{"predictor":{"minReplicas":0,"maxReplicas":0}}}'

  # KEDA ScaledObject가 있는 경우 함께 패치 (ScaledObject가 Deployment을 관리하므로)
  oc patch scaledobject vllm-autoscaler -n "${MODEL_NS:-mobis-poc}" --type=merge \
    -p '{"spec":{"minReplicaCount":0}}' 2>/dev/null || true

  # Pod 종료 대기
  oc wait pods -n "${MODEL_NS:-mobis-poc}" \
    -l "serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m}" \
    --for=delete --timeout=120s 2>/dev/null || true
  END_STOP=$(date +%s)

  PODS_REMAINING=$(oc get pods -n "${MODEL_NS:-mobis-poc}" \
    -l "serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m}" \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "철수 소요: $((END_STOP - START_STOP))초, 잔여 Pod: ${PODS_REMAINING}"
  ```
- **권한**: NS edit (`poc-operator`)
- **확인**: 서빙 Pod 0개, GPU 자원 반환 완료
- **참고**: KEDA ScaledObject가 Deployment을 관리하는 경우, IS 패치 외에 ScaledObject의 `minReplicaCount`도 함께 0으로 패치해야 Pod가 실제로 종료됨

> **[시연 포인트]** "배포와 철수가 단일 명령으로 수행됩니다. 티켓 발행 없이 즉시 GPU 자원을 회수할 수 있습니다."

---

## 확인 (Verification)

| 검증 기준 | 기대값 | 실측값 |
|----------|--------|--------|
| No.4 — Model Registry에 모델 등록 | HTTP 200, 모델 ID 반환 | PASS — id=10, state=LIVE |
| No.5 — S3 아티팩트 업로드 정상 | config.json + tokenizer.json + safetensors 존재 | PASS — 9개 파일 확인 (config.json, tokenizer.json, model.safetensors 등) |
| No.6 — v1/v2 버전 공존 | 2개 버전 조회 가능 | PASS — v1(id=11), v2(id=12) 공존 확인 |
| No.8 — 원클릭 배포 소요 시간 | InferenceService Ready, ___초 | PASS — 145초 (Model Registry 연동 배포, GPU 할당 포함) |
| No.8 — 원클릭 철수 소요 시간 | Pod 0개, ___초 | PASS — 15초 (IS minReplicas=0 + KEDA ScaledObject minReplicaCount=0) |
| No.9 — customProperties CRUD | 5개 필드 조회/수정/재조회 성공 | PASS — 6개 필드 CRUD 성공 (framework, task, team, dataset, accuracy, owner) |
| No.13 — 모델 아티팩트 S3 저장 | safetensors 1개 이상 | PASS — model.safetensors 존재 (경로: /data/mobis-poc-models/smollm2-135m/v1/) |

---

## 이번 시연에서 확인된 핵심 가치

- **체계적 버전 관리**: NAS 폴더 + Slack 알림 대신, Model Registry API가 모든 모델 버전을 고유 ID로 추적한다. `v2_final_real` 같은 혼란이 원천 차단된다.
- **메타데이터 영속성**: 학습 데이터셋, 성능 지표, 담당자 정보가 모델에 직접 부착되어, 인사 이동과 무관하게 AI 자산의 맥락이 보존된다.
- **즉시 배포/철수**: 운영팀 티켓 2~3일 대기 대신, 권한이 있는 관리자가 단일 명령으로 배포와 철수를 수행한다. GPU 비용 낭비를 방지한다.
- **감사 추적 기반 확보**: 모든 등록/수정 이력이 API 수준에서 기록되므로, AI 거버넌스 감사 요구에 대응할 수 있다.
- **코드처럼 관리되는 모델**: Git이 소스코드를 관리하듯, Model Registry가 모델 자산을 관리한다. 버전 비교, 롤백, 이력 조회가 가능하다.

---

## 추천 사항

- **모델 명명 규칙 확립**: 팀 내 모델 이름 규칙(예: `{프로젝트}-{용도}-{크기}`)을 사전 합의하면 Registry가 한눈에 읽힌다.
- **customProperties 표준화**: `framework`, `task`, `dataset`, `accuracy`, `owner` 를 팀 표준 메타데이터 필드로 정의하면 모델 검색과 비교가 효율적이다.
- **배포 권한 분리**: 모델 등록은 DS가, 배포 승인은 MGR가 수행하도록 RBAC을 구성하면 무단 배포를 방지할 수 있다. (S2 파이프라인과 연계)
- **모델 카탈로그 연동**: RHOAI Model Catalog에 검증 완료된 모델을 등록하면, 다른 프로젝트에서 재사용할 수 있는 내부 AI 자산 허브를 구축할 수 있다.
- **버전 전환 시 무중단 전략**: 운영 환경에서는 v1→v2 전환 시 Gateway API HTTPRoute weight 기반 카나리 배포 또는 blue-green 전략을 적용하여 다운타임 없는 모델 교체를 구현하는 것을 권장한다. (S7 Step 12 참조, `infra/poc/maas-routing/httproute-canary.yaml`)

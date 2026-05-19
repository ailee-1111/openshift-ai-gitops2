# 202 — 모델 카탈로그 소스 구성 (에어갭 환경 포함)

## 어떤 경우 필요한가

RHOAI Dashboard의 모델 카탈로그에 표시되는 모델 목록을 확장하거나, 에어갭(Restricted) 환경에서 HuggingFace 접근 없이 카탈로그 데이터를 수동 구성해야 할 때 사용한다.

**참조:**
- [opendatahub-io/model-metadata-collection](https://github.com/opendatahub-io/model-metadata-collection) — 카탈로그 YAML 생성 도구
- [RHOAI 3.3 Working with the model catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/pdf/working_with_the_model_catalog/)

## 아키텍처

```
┌─ Connected 클러스터 (Sandbox) ──────────────────┐
│  odh-model-metadata-collection 이미지            │
│  └─ /app/data/validated-models-catalog.yaml     │
│     (74개 모델, RedHatAI HuggingFace 기반)       │
└───────────────────┬─────────────────────────────┘
                    │ yaml 파일 추출 + 전송
┌───────────────────▼─────────────────────────────┐
│  Restricted 클러스터 (Mobis)                     │
│  model-catalog-sources ConfigMap                │
│  └─ sources.yaml에 카탈로그 추가                 │
│  model-catalog Pod → Dashboard 모델 카탈로그     │
└─────────────────────────────────────────────────┘
```

## 전제 조건

- [ ] `cluster-admin` 권한으로 로그인
- [ ] `rhoai-model-registries` NS에 `model-catalog` Pod Running
- [ ] 에어갭 환경: 카탈로그 YAML 파일을 사전 확보 (Connected 클러스터에서 추출)

## 실행

### 1. 현재 카탈로그 소스 확인

~~~bash
oc get configmap model-catalog-sources -n rhoai-model-registries \
  -o jsonpath='{.data.sources\.yaml}'
~~~

### 2. 카탈로그 YAML 추출 (Connected 클러스터에서)

> 에어갭 환경에서는 인터넷 연결된 클러스터에서 먼저 추출하여 파일로 전송한다.

#### 방법 A: 실행 중인 model-catalog Pod에서 추출

~~~bash
oc exec -n rhoai-model-registries deploy/model-catalog -c catalog -- \
  cat /shared-data/validated-models-catalog.yaml > validated-models-catalog.yaml

oc exec -n rhoai-model-registries deploy/model-catalog -c catalog -- \
  cat /shared-data/models-catalog.yaml > models-catalog.yaml

oc exec -n rhoai-model-registries deploy/model-catalog -c catalog -- \
  cat /shared-data/other-models-catalog.yaml > other-models-catalog.yaml

echo "추출 완료: $(wc -l validated-models-catalog.yaml models-catalog.yaml other-models-catalog.yaml)"
~~~

#### 방법 B: OCI 이미지에서 직접 추출

~~~bash
INIT_IMAGE=$(oc get deploy model-catalog -n rhoai-model-registries \
  -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="catalog-data-init")].image}')

podman create --name catalog-extract ${INIT_IMAGE} true
podman cp catalog-extract:/app/data/ ./catalog-data/
podman rm catalog-extract

ls -la catalog-data/
~~~

### 3. 카탈로그 YAML 형식 확인

추출한 YAML의 구조:

```yaml
source: Red Hat
models:
    - name: RedHatAI/Llama-3.3-70B-Instruct-FP8-dynamic
      provider: Meta
      description: "..."
      language: [en]
      license: llama3.3
      tasks:
        - text-generation
      customProperties:
        model_type:
            metadataType: MetadataStringValue
            string_value: "generative"
        validated_on:
            metadataType: MetadataStringValue
            string_value: '["RHOAI 3.2","vLLM 0.11.2"]'
      artifacts:
        - uri: oci://registry.redhat.io/rhai/modelcar-llama-3-3-70b-instruct-fp8-dynamic:3.0
          customProperties:
            source:
                metadataType: MetadataStringValue
                string_value: registry.redhat.io
            type:
                metadataType: MetadataStringValue
                string_value: modelcar
```

### 4. Restricted 클러스터에 카탈로그 소스 추가

> ConfigMap의 `sources.yaml`에 새 카탈로그 항목을 추가한다. `type: yaml`과 `url` 필드로 로컬 파일을 참조하거나, ConfigMap에 직접 데이터를 포함한다.

#### 방법 A: model-catalog-sources ConfigMap에 카탈로그 추가

~~~bash
# 현재 sources.yaml 백업
oc get configmap model-catalog-sources -n rhoai-model-registries \
  -o jsonpath='{.data.sources\.yaml}' > sources-backup.yaml

# 새 카탈로그 항목 추가 (Red Hat AI Validated)
cat > sources-updated.yaml <<'SOURCES_EOF'
catalogs:
    - enabled: true
      id: red_hat_ai_recent
      includedModels:
        - Qwen3.6-35B-A3B-NVFP4
        - Qwen3.6-35B-A3B-FP8-dynamic
        - Qwen3.6-35B-A3B-FP8
        - Qwen3.6-27B-FP8
        - gemma-4-31B-it-FP8-block
        - gemma-4-31B-it-NVFP4
        - gemma-4-26B-A4B-it-NVFP4
        - gemma-4-31B-it-FP8-Dynamic
        - gemma-4-31B-it-speculator.eagle3
        - gemma-4-26B-A4B-it-FP8-Dynamic
        - gemma-4-26B-A4B-it-speculator.eagle3
        - gemma-4-31B-it-speculator.dflash
      name: Red Hat AI Recent
      properties:
        allowedOrganization: RedHatAI
        apiKey: ""
      type: hf
    - enabled: true
      id: red_hat_ai_validated
      name: Red Hat AI Validated (Offline)
      type: hf
      properties:
        allowedOrganization: RedHatAI
        apiKey: ""
SOURCES_EOF

oc create configmap model-catalog-sources \
  -n rhoai-model-registries \
  --from-file=sources.yaml=sources-updated.yaml \
  --dry-run=client -o yaml | oc apply -f -
~~~

#### 방법 B: validated-models-catalog.yaml을 별도 ConfigMap으로 등록

~~~bash
# 카탈로그 데이터를 ConfigMap으로 생성
oc create configmap validated-models-data \
  -n rhoai-model-registries \
  --from-file=validated-models-catalog.yaml \
  --dry-run=client -o yaml | oc apply -f -
~~~

### 5. model-catalog Pod 재시작 (데이터 갱신)

~~~bash
oc delete pod -l component=model-catalog -n rhoai-model-registries
oc wait pod -l component=model-catalog -n rhoai-model-registries \
  --for=condition=Ready --timeout=120s
~~~

## 검증 완료

### V-1: ConfigMap 업데이트 확인

~~~bash
oc get configmap model-catalog-sources -n rhoai-model-registries \
  -o jsonpath='{.data.sources\.yaml}' | grep -c "id:"
# 기대: 2 이상 (기존 + 추가)
# PASS: [   ]  FAIL: [   ]
~~~

### V-2: model-catalog Pod Ready

~~~bash
oc get pods -n rhoai-model-registries -l component=model-catalog --no-headers
# 기대: 1/1 Running (또는 2/2)
# PASS: [   ]  FAIL: [   ]
~~~

### V-3: Dashboard 모델 카탈로그

RHOAI Dashboard → Model Catalog 페이지
- 기대: 추가된 카탈로그의 모델이 표시됨
- PASS: [   ]  FAIL: [   ]

## 사용 가능한 카탈로그 YAML 파일

init 컨테이너(`odh-model-metadata-collection`)에 포함된 카탈로그:

| 파일 | 모델 수 | 설명 |
|------|:------:|------|
| `validated-models-catalog.yaml` | 74 | RedHatAI 검증 모델 (Llama, Mistral, Qwen, Gemma 등) |
| `models-catalog.yaml` | ~50 | 기본 모델 카탈로그 |
| `other-models-catalog.yaml` | ~30 | 추가 모델 |

## 실패 시

- **Dashboard에 모델 미표시** → model-catalog Pod 재시작: `oc delete pod -l component=model-catalog -n rhoai-model-registries`
- **"Request access to model catalog" 에러** → ConfigMap 삭제 후 재생성: `oc delete configmap model-catalog-sources -n rhoai-model-registries`
- **에어갭에서 HF 접근 실패** → `type: hf`는 HuggingFace API를 호출. 오프라인에서는 카탈로그 데이터를 사전 추출하여 수동 적용
- **ConfigMap 용량 초과** → 1MB 제한. 큰 카탈로그는 여러 ConfigMap으로 분리

## Mobis 클러스터 실측 (2026-05-20)

| 항목 | 값 |
|------|-----|
| 현재 카탈로그 | Red Hat AI Recent (12 모델) |
| init 이미지 | `odh-model-metadata-collection-rhel9` |
| /shared-data/ | 12 파일 (validated 74개, models ~50개, other ~30개) |
| model-catalog Pod | 2/2 Running |

## 다음 단계

→ `runbooks/210-dspa.md` — Data Science Pipeline 구성

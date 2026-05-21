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

### 4. HuggingFace에서 모델 메타데이터 수집 (Connected 환경에서 실행)

> 에어갭 클러스터에 모델을 추가하려면 **인터넷 연결된 환경에서** HuggingFace API + README를 수집하여 YAML로 변환해야 한다.

#### 4-1. HuggingFace API + README 수집

~~~bash
MODELS=(
  "RedHatAI/Qwen3.6-35B-A3B-NVFP4"
  "mistralai/Mistral-7B-Instruct-v0.3"
)
mkdir -p hf-metadata hf-readme

for MODEL in "${MODELS[@]}"; do
  SAFE=$(echo "${MODEL}" | tr '/' '_')
  curl -sL "https://huggingface.co/api/models/${MODEL}" > "hf-metadata/${SAFE}.json"
  curl -sL "https://huggingface.co/${MODEL}/raw/main/README.md" > "hf-readme/${SAFE}.md"
  echo "${MODEL}: api=$(wc -c < hf-metadata/${SAFE}.json)B readme=$(wc -l < hf-readme/${SAFE}.md)lines"
done
~~~

#### 4-2. YAML 변환 — 필드별 출처

| YAML 필드 | HuggingFace 출처 | 필수 | 비고 |
|-----------|------------------|:----:|------|
| `name` | `modelId` (API) | O | `org/model-name` 형식 |
| `provider` | `author` (API) 또는 모델명에서 추론 | O | |
| `description` | `cardData.description` (API) | O | |
| `readme` | `README.md` 파일 전문 | **권장** | 없으면 Dashboard 모델 카드 빈 페이지 |
| `language` | `cardData.language` (API) | O | |
| `license` | `cardData.license` (API) | O | |
| `licenseLink` | 라이선스별 URL 매핑 | - | |
| `libraryName` | `library_name` (API) | - | |
| `tasks` | `pipeline_tag` (API) | O | |
| `customProperties` | `tags` (API)에서 추출 | O | `model_type: generative` 필수 |
| `artifacts[].uri` | HuggingFace 모델 URL | O | |

#### 4-3. 등록용 YAML 형식 (전체 예시)

```yaml
source: Hugging Face
models:
    - name: mistralai/Mistral-7B-Instruct-v0.3
      provider: Mistral AI
      description: "Mistral-7B-Instruct-v0.3 - instruct fine-tuned version of Mistral-7B-v0.3"
      readme: |-
        # Mistral-7B-Instruct-v0.3
        The Mistral-7B-Instruct-v0.3 Large Language Model (LLM) is an
        instruct fine-tuned version of the Mistral-7B-v0.3.

        ## Changes compared to v0.2
        - Extended vocabulary to 32768
        - Supports v3 Tokenizer
        - Supports function calling
        ... (전체 README.md 내용을 여기에 포함)
      language: [en]
      license: apache-2.0
      licenseLink: https://www.apache.org/licenses/LICENSE-2.0
      libraryName: transformers
      tasks:
        - text-generation
      customProperties:
        model_type:
            metadataType: MetadataStringValue
            string_value: "generative"
      artifacts:
        - uri: https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3
          customProperties:
            source:
                metadataType: MetadataStringValue
                string_value: huggingface
            type:
                metadataType: MetadataStringValue
                string_value: model
```

#### 4-4. 일괄 변환 스크립트

~~~bash
python3 << 'PYEOF'
import json, os, glob

metadata_dir, readme_dir = "hf-metadata", "hf-readme"
print("source: Hugging Face")
print("models:")

for jf in sorted(glob.glob(f"{metadata_dir}/*.json")):
    with open(jf) as f:
        data = json.load(f)
    model_id = data.get("modelId", "")
    safe = model_id.replace("/", "_")
    card = data.get("cardData", {}) or {}

    readme_path = f"{readme_dir}/{safe}.md"
    readme = ""
    if os.path.exists(readme_path):
        with open(readme_path) as f:
            readme = f.read().strip()

    nl = model_id.lower()
    provider = data.get("author", "Unknown")
    if "qwen" in nl: provider = "Alibaba"
    elif "gemma" in nl: provider = "Google"
    elif "mistral" in nl: provider = "Mistral AI"
    elif "llama" in nl: provider = "Meta"
    elif "granite" in nl: provider = "IBM"

    desc = card.get("description", f"{model_id.split('/')[-1]} - {data.get('pipeline_tag','text-generation')}")
    license_val = card.get("license", data.get("license", "apache-2.0")) or "apache-2.0"
    language = card.get("language", ["en"])
    if isinstance(language, str): language = [language]
    pipeline = data.get("pipeline_tag", "text-generation")
    library = data.get("library_name", "")

    print(f'    - name: {model_id}')
    print(f'      provider: {provider}')
    print(f'      description: "{desc}"')
    if readme:
        print(f'      readme: |-')
        for line in readme.split("\n"):
            print(f'        {line}')
    print(f'      language: [{", ".join(language)}]')
    print(f'      license: {license_val}')
    if library:
        print(f'      libraryName: {library}')
    print(f'      tasks:')
    print(f'        - {pipeline}')
    print(f'      customProperties:')
    print(f'        model_type:')
    print(f'            metadataType: MetadataStringValue')
    print(f'            string_value: "generative"')
    print(f'      artifacts:')
    print(f'        - uri: https://huggingface.co/{model_id}')
    print(f'          customProperties:')
    print(f'            source:')
    print(f'                metadataType: MetadataStringValue')
    print(f'                string_value: huggingface')
    print(f'            type:')
    print(f'                metadataType: MetadataStringValue')
    print(f'                string_value: model')
PYEOF
# 출력을 custom-models.yaml로 저장하여 Restricted 클러스터로 전송
~~~

### 5. Restricted 클러스터에 카탈로그 적용

> **핵심**: `model-catalog-default-sources` ConfigMap이 `type: yaml`로 `/shared-data/models-catalog.yaml`을 참조한다. `type: hf`는 에어갭에서 동작하지 않는다. 추가 모델은 기존 파일에 **병합** 후 init 컨테이너로 주입해야 한다.

#### 5-1. 기존 카탈로그에 커스텀 모델 병합

~~~bash
# 기존 models-catalog.yaml 추출
oc exec -n rhoai-model-registries deploy/model-catalog -c catalog -- \
  cat /shared-data/models-catalog.yaml > models-catalog-original.yaml

# 커스텀 모델 YAML의 models: 하위만 추출하여 병합
grep -A9999 '^models:' custom-models.yaml | tail -n +2 >> models-catalog-original.yaml

# 병합 결과 확인
echo "모델 수: $(grep '    - name:' models-catalog-original.yaml | wc -l)"
~~~

#### 5-2. ConfigMap 생성 + init 컨테이너 추가

~~~bash
# override ConfigMap 생성 (400KB+ 시 replace 사용 — annotation 크기 제한 회피)
oc create configmap models-catalog-override \
  -n rhoai-model-registries \
  --from-file=models-catalog.yaml=models-catalog-original.yaml \
  --dry-run=client -o yaml | oc replace -f -

# Deployment에 override init 컨테이너 추가
# (catalog-data-init 이후 실행되어 /shared-data/ 파일을 덮어씀)
oc patch deployment model-catalog -n rhoai-model-registries \
  --type=json -p='[
    {"op":"add","path":"/spec/template/spec/volumes/-",
     "value":{"name":"models-override","configMap":{"name":"models-catalog-override"}}},
    {"op":"add","path":"/spec/template/spec/initContainers/-",
     "value":{
       "name":"custom-catalog-inject",
       "image":"registry.access.redhat.com/ubi9/ubi-minimal:latest",
       "command":["/bin/sh","-c",
         "cp /override/models-catalog.yaml /shared-data/models-catalog.yaml && echo injected"],
       "volumeMounts":[
         {"name":"models-override","mountPath":"/override","readOnly":true},
         {"name":"catalog-data","mountPath":"/shared-data"}
       ]
     }}
  ]'
~~~

#### 5-3. 롤아웃 대기 및 검증

~~~bash
oc rollout status deployment/model-catalog -n rhoai-model-registries --timeout=120s

# 주입 확인
oc exec -n rhoai-model-registries deploy/model-catalog -c catalog -- \
  grep '    - name:' /shared-data/models-catalog.yaml | wc -l
~~~

### 6. Dashboard에서 모델 카탈로그 확인

RHOAI Dashboard → **Model Catalog** 페이지:

1. "Red Hat AI" 라벨 아래 기존 + 추가 모델이 함께 표시
2. 모델 클릭 → **모델 카드(readme)** 전문 표시
3. Description, Provider, License 정보 표시

> **주의**: `type: hf`는 에어갭에서 동작하지 않는다. `model-catalog-default-sources`의 기본 구성이 `type: yaml` + `/shared-data/` 파일 경로이므로, 기존 파일에 모델을 병합하는 방식이 가장 확실하다.

### 참고: Dashboard UI에서 카탈로그 소스 추가 (Connected 환경)

인터넷 연결된 환경에서는 Dashboard UI에서 직접 추가 가능:

1. OpenShift Console → **Workloads → ConfigMaps**
2. Project: `rhoai-model-registries`
3. `model-catalog-sources` ConfigMap 클릭 → YAML 탭
4. `data.sources.yaml`의 `catalogs:` 배열에 항목 추가
5. 저장 후 model-catalog Pod 재시작: `oc delete pod -l component=model-catalog -n rhoai-model-registries`

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
| `models-catalog.yaml` | 10 | 기본 모델 카탈로그 |
| `other-models-catalog.yaml` | 5 | 추가 모델 |

### validated-models-catalog.yaml 모델 전체 목록 (74개)

<details>
<summary>모델 목록 펼치기</summary>

| # | 모델 | 제공자 | 양자화 |
|---|------|--------|--------|
| 1 | Apertus-8B-Instruct-2509-FP8-dynamic | Swiss AI | FP8 |
| 2 | DeepSeek-R1-0528-quantized.w4a16 | DeepSeek | W4A16 |
| 3 | Devstral-Small-2-24B-Instruct-2512 | Mistral | - |
| 4 | Kimi-K2-Instruct-quantized.w4a16 | Moonshot | W4A16 |
| 5 | Llama-3.1-8B-Instruct | Meta | - |
| 6 | Llama-3.1-Nemotron-70B-Instruct-HF | NVIDIA | - |
| 7 | Llama-3.1-Nemotron-70B-Instruct-HF-FP8-dynamic | NVIDIA | FP8 |
| 8 | Llama-3.3-70B-Instruct | Meta | - |
| 9 | Llama-3.3-70B-Instruct-FP8-dynamic | Meta | FP8 |
| 10 | Llama-3.3-70B-Instruct-quantized.w4a16 | Meta | W4A16 |
| 11 | Llama-3.3-70B-Instruct-quantized.w8a8 | Meta | W8A8 |
| 12 | Llama-4-Maverick-17B-128E-Instruct | Meta | - |
| 13 | Llama-4-Maverick-17B-128E-Instruct-FP8 | Meta | FP8 |
| 14 | Llama-4-Scout-17B-16E-Instruct | Meta | - |
| 15 | Llama-4-Scout-17B-16E-Instruct-FP8-dynamic | Meta | FP8 |
| 16 | Llama-4-Scout-17B-16E-Instruct-quantized.w4a16 | Meta | W4A16 |
| 17 | Meta-Llama-3.1-8B-Instruct-FP8-dynamic | Meta | FP8 |
| 18 | Meta-Llama-3.1-8B-Instruct-quantized.w4a16 | Meta | W4A16 |
| 19 | Meta-Llama-3.1-8B-Instruct-quantized.w8a8 | Meta | W8A8 |
| 20 | MiniMax-M2.5 | MiniMax | - |
| 21 | Ministral-3-14B-Instruct-2512 | Mistral | - |
| 22 | Ministral-3-3B-Instruct-2512 | Mistral | - |
| 23 | Mistral-Large-3-675B-Instruct-2512 | Mistral | - |
| 24 | Mistral-Large-3-675B-Instruct-2512-NVFP4 | Mistral | NVFP4 |
| 25 | Mistral-Small-24B-Instruct-2501 | Mistral | - |
| 26 | Mistral-Small-24B-Instruct-2501-FP8-dynamic | Mistral | FP8 |
| 27 | Mistral-Small-24B-Instruct-2501-quantized.w4a16 | Mistral | W4A16 |
| 28 | Mistral-Small-24B-Instruct-2501-quantized.w8a8 | Mistral | W8A8 |
| 29 | Mistral-Small-3.1-24B-Instruct-2503 | Mistral | - |
| 30 | Mistral-Small-3.1-24B-Instruct-2503-FP8-dynamic | Mistral | FP8 |
| 31 | Mistral-Small-3.1-24B-Instruct-2503-quantized.w4a16 | Mistral | W4A16 |
| 32 | Mistral-Small-3.1-24B-Instruct-2503-quantized.w8a8 | Mistral | W8A8 |
| 33 | Mistral-Small-4-119B-2603 | Mistral | - |
| 34 | Mistral-Small-4-119B-2603-NVFP4 | Mistral | NVFP4 |
| 35 | Mixtral-8x7B-Instruct-v0.1 | Mistral | - |
| 36 | NVIDIA-Nemotron-3-Nano-30B-A3B-FP8 | NVIDIA | FP8 |
| 37 | NVIDIA-Nemotron-3-Super-120B-A12B-BF16 | NVIDIA | BF16 |
| 38 | NVIDIA-Nemotron-3-Super-120B-A12B-FP8 | NVIDIA | FP8 |
| 39 | NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4 | NVIDIA | NVFP4 |
| 40 | NVIDIA-Nemotron-Nano-9B-v2-FP8-dynamic | NVIDIA | FP8 |
| 41 | Phi-4-mini-instruct-FP8-dynamic | Microsoft | FP8 |
| 42 | Phi-4-reasoning-FP8-dynamic | Microsoft | FP8 |
| 43 | Qwen2.5-7B-Instruct | Alibaba | - |
| 44 | Qwen2.5-7B-Instruct-FP8-dynamic | Alibaba | FP8 |
| 45 | Qwen2.5-7B-Instruct-quantized.w4a16 | Alibaba | W4A16 |
| 46 | Qwen2.5-7B-Instruct-quantized.w8a8 | Alibaba | W8A8 |
| 47 | Qwen3-8B-FP8-dynamic | Alibaba | FP8 |
| 48 | Qwen3-Coder-480B-A35B-Instruct-FP8 | Alibaba | FP8 |
| 49 | Qwen3-Coder-Next-NVFP4 | Alibaba | NVFP4 |
| 50 | Qwen3-Next-80B-A3B-Instruct-quantized.w4a16 | Alibaba | W4A16 |
| 51 | Qwen3-VL-235B-A22B-Instruct-NVFP4 | Alibaba | NVFP4 |
| 52 | Qwen3.5-122B-A10B-FP8-dynamic | Alibaba | FP8 |
| 53 | Qwen3.5-35B-A3B-FP8-dynamic | Alibaba | FP8 |
| 54 | Qwen3.5-397B-A17B-FP8-dynamic | Alibaba | FP8 |
| 55 | Voxtral-Mini-3B-2507-FP8-dynamic | Mistral | FP8 |
| 56 | gemma-2-9b-it | Google | - |
| 57 | gemma-2-9b-it-FP8 | Google | FP8 |
| 58 | gemma-3n-E4B-it-FP8-dynamic | Google | FP8 |
| 59 | gpt-oss-120b | Red Hat | - |
| 60 | gpt-oss-20b | Red Hat | - |
| 61 | granite-3.1-8b-base-quantized.w4a16 | IBM | W4A16 |
| 62 | granite-3.1-8b-instruct | IBM | - |
| 63 | granite-3.1-8b-instruct-FP8-dynamic | IBM | FP8 |
| 64 | granite-3.1-8b-instruct-quantized.w4a16 | IBM | W4A16 |
| 65 | granite-3.1-8b-instruct-quantized.w8a8 | IBM | W8A8 |
| 66 | granite-4.0-h-small-FP8-dynamic | IBM | FP8 |
| 67 | granite-4.0-h-tiny-FP8-dynamic | IBM | FP8 |
| 68 | phi-4 | Microsoft | - |
| 69 | phi-4-FP8-dynamic | Microsoft | FP8 |
| 70 | phi-4-quantized.w4a16 | Microsoft | W4A16 |
| 71 | phi-4-quantized.w8a8 | Microsoft | W8A8 |
| 72 | sarvam-105b-FP8-dynamic | Sarvam | FP8 |
| 73 | sarvam-30b-FP8-dynamic | Sarvam | FP8 |
| 74 | whisper-large-v3-turbo-quantized.w4a16 | OpenAI | W4A16 |

</details>

## 실패 시

- **Dashboard에 모델 미표시** → model-catalog Pod 재시작: `oc delete pod -l component=model-catalog -n rhoai-model-registries`
- **"Request access to model catalog" 에러** → ConfigMap 삭제 후 재생성: `oc delete configmap model-catalog-sources -n rhoai-model-registries`
- **에어갭에서 HF 접근 실패** → `type: hf`는 HuggingFace API를 호출. 오프라인에서는 카탈로그 데이터를 사전 추출하여 수동 적용
- **ConfigMap 용량 초과** → 1MB 제한. 큰 카탈로그는 여러 ConfigMap으로 분리
- **카탈로그 변경 후 미반영** → model-catalog Pod + model-catalog-postgres Pod 모두 재시작 필요

## Mobis 클러스터 실측 (2026-05-20)

| 항목 | 값 |
|------|-----|
| 카탈로그 소스 | Red Hat AI Recent (12 모델) + **Red Hat AI Validated (74 모델)** |
| init 이미지 | `odh-model-metadata-collection-rhel9` |
| /shared-data/ | 12 파일 (validated 74개, models 10개, other 5개) |
| model-catalog Pod | 2/2 Running |
| 적용 절차 | Pod에서 YAML 추출 → ConfigMap 업데이트 → Pod 재시작 |

## 트러블슈팅 이력

| 날짜 | 이슈 | 해결 |
|------|------|------|
| 2026-05-20 | 에어갭 환경에서 HF 접근 불가 → 카탈로그 미표시 | model-catalog Pod 내부 `/shared-data/`에서 YAML 추출 → ConfigMap 적용 |

## 다음 단계

→ `runbooks/210-dspa.md` — Data Science Pipeline 구성



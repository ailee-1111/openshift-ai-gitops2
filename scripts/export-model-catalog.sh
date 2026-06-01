#!/bin/bash
set -e

MODEL_NAME="${1:-smollm2-135m}"
REGISTRY_NAME="${2:-mobis-registry}"
MR_NS="rhoai-model-registries"
MR_API="http://localhost:8080/api/model_registry/v1alpha3"
OUTPUT_DIR="reports/model-catalog"

mkdir -p "${OUTPUT_DIR}"

MR_POD=$(oc get pods -n ${MR_NS} -l app=${REGISTRY_NAME} --no-headers -o name | head -1)
if [ -z "${MR_POD}" ]; then
  echo "ERROR: Model Registry Pod 없음"
  exit 1
fi

echo "=== Model Registry → Catalog YAML 변환 ==="

# Step 1: 모델 정보
MODEL_JSON=$(oc exec -n ${MR_NS} ${MR_POD} -c rest-container -- \
  curl -s "${MR_API}/registered_models" | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('items', []):
    if m['name'] == '${MODEL_NAME}':
        print(json.dumps(m)); break
")

MODEL_ID=$(echo "${MODEL_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Step 2: 버전 정보
VERSIONS_JSON=$(oc exec -n ${MR_NS} ${MR_POD} -c rest-container -- \
  curl -s "${MR_API}/registered_models/${MODEL_ID}/versions")

# Step 3: 각 LIVE 버전의 artifact
ARTIFACTS_JSON="["
FIRST=true
for VID in $(echo "${VERSIONS_JSON}" | python3 -c "
import sys, json
for v in json.load(sys.stdin).get('items', []):
    if v.get('state') == 'LIVE':
        print(v['id'])
"); do
  ART=$(oc exec -n ${MR_NS} ${MR_POD} -c rest-container -- \
    curl -s "${MR_API}/model_versions/${VID}/artifacts")
  if [ "${FIRST}" = "true" ]; then
    FIRST=false
  else
    ARTIFACTS_JSON="${ARTIFACTS_JSON},"
  fi
  ARTIFACTS_JSON="${ARTIFACTS_JSON}{\"versionId\":\"${VID}\",\"artifacts\":${ART}}"
done
ARTIFACTS_JSON="${ARTIFACTS_JSON}]"

# Step 4: Python으로 YAML 생성
python3 -c "
import json, sys

model = json.loads('''${MODEL_JSON}''')
versions = json.loads('''${VERSIONS_JSON}''')
artifacts = json.loads('''${ARTIFACTS_JSON}''')

props = model.get('customProperties', {})
get = lambda k: props.get(k, {}).get('string_value', 'N/A')

live = [v for v in versions.get('items', []) if v.get('state') == 'LIVE']

# artifact URI map
art_map = {}
for a in artifacts:
    vid = a['versionId']
    for item in a.get('artifacts', {}).get('items', []):
        art_map[vid] = item.get('uri', '')

yaml = f'''source: Model Registry
models:
- name: {model['name']}
  description: {model.get('description', '')}
  license: proprietary
  licenseLink: \"\"
  libraryName: transformers
  provider: {get('team')}
  artifacts:'''

for v in live:
    uri = art_map.get(v['id'], f\"s3://mobis-poc-models/{model['name']}/{v['name']}\")
    yaml += f'''
    - uri: {uri}
      customProperties:
        version:
            metadataType: MetadataStringValue
            string_value: {v['name']}
        framework:
            metadataType: MetadataStringValue
            string_value: {get('framework')}
        task:
            metadataType: MetadataStringValue
            string_value: {get('task')}
        source:
            metadataType: MetadataStringValue
            string_value: model-registry'''

yaml += f'''
  readme: |-
    # {model['name']}

    ## Model Overview
    - **Framework:** {get('framework')}
    - **Task:** {get('task')}
    - **Team:** {get('team')}
    - **Owner:** {get('owner')}
    - **Accuracy:** {get('accuracy')}
    - **Dataset:** {get('dataset')}
    - **Description:** {model.get('description', '')}

    ## Versions (LIVE)'''

for v in live:
    uri = art_map.get(v['id'], '')
    yaml += f'''
    | {v['name']} | id={v['id']} | {v.get('description','')} | {uri} |'''

yaml += f'''

    ## Deployment

    vLLM 기반 InferenceService로 배포:

    \\\`\\\`\\\`bash
    oc create -n mobis-poc -f - <<EOF
    apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: deploy-{model['name']}-
    spec:
      pipelineRef:
        name: model-e2e-7stage-pipeline
      params:
        - name: model-name
          value: \"{model['name']}\"
        - name: model-version
          value: \"v1\"
        - name: s3-path
          value: \"{model['name']}/v1\"
        - name: s3-secret
          value: \"poc-s3-connection\"
    EOF
    \\\`\\\`\\\`
'''

print(yaml)
" > "${OUTPUT_DIR}/${MODEL_NAME}-catalog.yaml"

echo "  파일: ${OUTPUT_DIR}/${MODEL_NAME}-catalog.yaml"
echo ""
cat "${OUTPUT_DIR}/${MODEL_NAME}-catalog.yaml"

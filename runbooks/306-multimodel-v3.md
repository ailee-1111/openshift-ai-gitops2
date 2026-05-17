# 306 — S1 강화: 멀티모델 운영

## 목적

단일 모델 검증(v1)을 넘어 3개 이상 모델을 동시 등록·서빙하고, 모델 버전 전환(v1→v2) 시 추론 연속성(다운타임 0)을 검증한다. 라벨/태그 기반 검색·필터 기능으로 모델 디스커버리를 확인한다.

## 전제 조건

- [ ] `runbooks/300-model-serving.md` 완료 — 단일 모델 서빙 정상
- [ ] Model Registry Available=True
- [ ] GPU 노드 가용 (L40S × 4 또는 동등)
- [ ] S3(MinIO) 접근 가능
- [ ] 환경변수: `MODEL_NS`, `MODEL_REGISTRY_NS`, `S3_BUCKET`

## 실행

### 1. 멀티모델 동시 등록 (3개)

~~~bash
MODELS=("smollm2-135m" "qwen3-8b" "smollm2-135m-chat")
TAGS=("small" "large" "small-chat")

MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" \
  -l app=poc-model-registry \
  -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
MR_ROUTE="${MR_ROUTE:-$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers | awk '{print $2}' | head -1)}"
TOKEN=$(oc whoami -t)

for i in "${!MODELS[@]}"; do
  MODEL="${MODELS[$i]}"
  TAG="${TAGS[$i]}"

  echo "=== 모델 등록: ${MODEL} (tag: ${TAG}) ==="
  curl -sk -X POST \
    "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "{
      \"name\": \"${MODEL}\",
      \"description\": \"v3 멀티모델 검증\",
      \"customProperties\": {
        \"tier\": {\"stringValue\": \"${TAG}\"},
        \"framework\": {\"stringValue\": \"vLLM\"},
        \"gpu_required\": {\"stringValue\": \"true\"}
      }
    }" 2>/dev/null | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    print(f'  ID: {r.get(\"id\", \"already exists\")}')
except: print('  등록 완료 또는 이미 존재')
"
done
~~~

### 2. 등록 모델 목록 조회 + 필터

~~~bash
echo "=== 전체 등록 모델 ==="
curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('items', []):
    props = m.get('customProperties', {})
    tier = props.get('tier', {}).get('stringValue', '-')
    print(f'  {m[\"name\"]}: state={m.get(\"state\",\"?\")} tier={tier}')
print(f'총 {data.get(\"size\", 0)}개')
"

echo ""
echo "=== tier=small 필터 ==="
curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('items', []):
    tier = m.get('customProperties', {}).get('tier', {}).get('stringValue', '')
    if 'small' in tier:
        print(f'  {m[\"name\"]}: tier={tier}')
"
~~~

### 3. 모델 버전 v2 등록

~~~bash
MODEL_NAME="smollm2-135m"

MODEL_ID=$(curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('items', []):
    if m.get('name') == '${MODEL_NAME}':
        print(m['id']); break
")
echo "Model ID: ${MODEL_ID}"

# v2 버전 등록
curl -sk -X POST \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"name":"v2","description":"s3://models/smollm2-135m/v2"}'

echo ""
echo "=== ${MODEL_NAME} 버전 목록 ==="
curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
for v in json.load(sys.stdin).get('items', []):
    print(f'  {v[\"name\"]}: state={v.get(\"state\",\"?\")}')
"
~~~

### 4. InferenceService v1→v2 전환 (다운타임 0 검증)

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} \
  -o jsonpath='{.spec.host}')

# 연속 요청 (백그라운드 90초)
echo "=== 연속 요청 시작 (90초) ==="
FAIL_COUNT=0
TOTAL=0
for i in $(seq 1 90); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    "https://${ROUTE}/v1/models" 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  if [ "${CODE}" != "200" ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$(date '+%H:%M:%S') HTTP ${CODE} [FAIL]"
  fi
  sleep 1
done &
REQ_PID=$!

# 10초 후 storage.path 전환
sleep 10
echo "=== storage.path 전환: v1 → v2 ==="
oc patch inferenceservice ${MODEL_NAME} -n ${MODEL_NS} --type=merge -p '{
  "spec": {
    "predictor": {
      "model": {
        "storage": {
          "path": "smollm2-135m/v2"
        }
      }
    }
  }
}'

oc rollout status deployment/${MODEL_NAME}-predictor -n ${MODEL_NS} --timeout=300s

wait $REQ_PID
echo ""
echo "=== 결과: 총 ${TOTAL}건, 실패 ${FAIL_COUNT}건 ==="
if [ "${FAIL_COUNT}" -eq 0 ]; then
  echo "PASS: 다운타임 0"
else
  echo "FAIL: 다운타임 발생 (${FAIL_COUNT}건)"
fi
~~~

### 5. 원복 (v2→v1)

~~~bash
oc patch inferenceservice ${MODEL_NAME} -n ${MODEL_NS} --type=merge -p '{
  "spec": {
    "predictor": {
      "model": {
        "storage": {
          "path": "smollm2-135m/v1"
        }
      }
    }
  }
}'

oc wait inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  --for=condition=Ready --timeout=300s
echo "원복 완료"
~~~

## 검증

~~~bash
# 1. 등록 모델 3개 이상
MODEL_COUNT=$(curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('size',0))")
echo "등록 모델: ${MODEL_COUNT}개"
# 기대: 3 이상

# 2. customProperties 필터 동작
curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for m in data.get('items',[])
  if 'small' in m.get('customProperties',{}).get('tier',{}).get('stringValue',''))
print(f'tier=small 매칭: {count}개')
"
# 기대: 2개

# 3. 버전 2개 이상
curl -sk \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import sys,json; print(f'버전: {json.load(sys.stdin).get(\"size\",0)}개')"
# 기대: 2 이상

# 4. v1→v2 전환 다운타임 0 — Step 4 결과 확인

# 5. InferenceService Ready
oc get inferenceservice ${MODEL_NAME} -n ${MODEL_NS} \
  -o jsonpath='Ready={.status.conditions[?(@.type=="Ready")].status}'
echo ""
# 기대: Ready=True
~~~

## 실패 시

- **customProperties 미반영** → Model Registry API v1alpha3에서 `stringValue` 키 필수
- **v1→v2 전환 시 다운타임** → replica=1에서 RollingUpdate 시 잠시 다운타임 가능. `maxSurge: 1` 설정으로 새 Pod 선기동 후 전환
- **v2 경로에 모델 없음** → S3에 `smollm2-135m/v2` 존재 확인. 없으면 v1 복사: `oc exec deploy/minio -n ${MODEL_NS} -- cp -r /data/models/smollm2-135m/v1 /data/models/smollm2-135m/v2`
- **GPU 부족으로 3개 동시 서빙 불가** → 135M × 2 + 8B × 1은 L40S 4기 기준 가능. 부족 시 등록만 하고 서빙은 스킵

## 다음 단계

→ `runbooks/311-pipeline-v3.md` — S2 강화: 통합 파이프라인

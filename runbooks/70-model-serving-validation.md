# 70 — 모델 서빙 검증 (S1: 모델 관리)

## 목적

모델 라이프사이클(등록 → 버전 관리 → 원클릭 배포/철수 → 메타데이터 관리)이 RHOAI 플랫폼 위에서 고객 요구사항(No.4,5,6,8,9,13)을 충족하는지 기능 검증한다.

## 전제 조건

- [ ] `runbooks/60-model-serving.md` 구축 완료 (MinIO + Model Registry + InferenceService 정상)
- [ ] `${MODEL_NAME}`, `${MODEL_NS}`, `${MODEL_REGISTRY_NS}` 환경변수 설정
- [ ] Model Registry Route 접근 가능

## 실행

### V-4. 모델 등록 기능 (No.4)

~~~bash
# Model Registry REST API로 모델 조회
MR_ROUTE=$(oc get route -n "${MODEL_REGISTRY_NS}" --no-headers \
  | awk '{print $2}' | head -1)
TOKEN=$(oc whoami -t)

echo "=== V-4: 모델 등록 확인 ==="
RESULT=$(curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}")
MODEL_COUNT=$(echo "${RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('size',0))")
echo "등록된 모델 수: ${MODEL_COUNT}"
echo "${RESULT}" | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('items', []):
    print(f\"  - {m['name']}: id={m['id']}, state={m.get('state','?')}\")
"
# 기대: 1개 이상의 모델 등록, state=LIVE
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-5. 모델 등록/업로드 (No.5)

~~~bash
echo "=== V-5: 신규 모델 등록 테스트 ==="
# 새 모델을 등록하고 성공 여부 확인
REGISTER_RESULT=$(curl -sk -X POST \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"validation-test-model","description":"검증용 테스트 모델"}')
NEW_MODEL_ID=$(echo "${REGISTER_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','FAIL'))")
echo "신규 모델 ID: ${NEW_MODEL_ID}"
# 기대: 유효한 ID 반환
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-6. 모델 버전 관리 (No.6)

~~~bash
echo "=== V-6: 모델 버전 관리 ==="
MODEL_ID=$(curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
items = json.load(sys.stdin).get('items', [])
for m in items:
    if m['name'] == '${MODEL_NAME}':
        print(m['id']); break
else:
    print('NOT_FOUND')
")

# v2 버전 등록
V2_RESULT=$(curl -sk -X POST \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"v2","description":"검증용 버전 2"}')
echo "v2 등록: $(echo ${V2_RESULT} | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"id={d.get('id','?')}, name={d.get('name','?')}\")")"

# 버전 목록 조회
curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}/versions" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
for v in json.load(sys.stdin).get('items', []):
    print(f\"  - {v['name']}: id={v['id']}\")
"
# 기대: v1, v2 두 버전 존재
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-8. 원클릭 배포/철수 (No.8)

~~~bash
echo "=== V-8: 원클릭 배포/철수 ==="

# 철수: replicas=0
echo ">> 서빙 철수 (replicas=0)"
START_STOP=$(date +%s)
oc patch inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" --type=merge \
  -p '{"spec":{"predictor":{"minReplicas":0,"maxReplicas":0}}}'
oc wait pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" \
  --for=delete --timeout=120s 2>/dev/null || true
END_STOP=$(date +%s)
PODS_AFTER=$(oc get pods -n "${MODEL_NS}" \
  -l "serving.kserve.io/inferenceservice=${MODEL_NAME}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "철수 소요: $((END_STOP - START_STOP))초, 잔여 Pod: ${PODS_AFTER}"
# 기대: Pod 0개

# 재배포: replicas=1
echo ">> 서빙 재배포 (replicas=1)"
START_DEPLOY=$(date +%s)
oc patch inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" --type=merge \
  -p '{"spec":{"predictor":{"minReplicas":1,"maxReplicas":1}}}'
oc wait inferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" \
  --for=condition=Ready --timeout=600s
END_DEPLOY=$(date +%s)
echo "재배포 소요: $((END_DEPLOY - START_DEPLOY))초"
# 기대: InferenceService Ready=True
# 결과: [   ] PASS / [   ] FAIL
# 실측값: 철수 ___초, 재배포 ___초
~~~

### V-9. 모델 메타데이터 관리 (No.9)

~~~bash
echo "=== V-9: 메타데이터 CRUD ==="
curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
m = json.load(sys.stdin)
print(f\"name={m.get('name')}\")
print(f\"description={m.get('description')}\")
print(f\"customProperties={json.dumps(m.get('customProperties', {}), indent=2)}\")
"

# 메타데이터 업데이트
curl -sk -X PATCH \
  "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"customProperties":{"framework":{"stringValue":"vLLM"},"task":{"stringValue":"text-generation"}}}'
echo "메타데이터 업데이트 완료"

# 업데이트 확인
curl -sk "https://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models/${MODEL_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
cp = json.load(sys.stdin).get('customProperties', {})
print(f\"framework={cp.get('framework',{}).get('stringValue','?')}\")
print(f\"task={cp.get('task',{}).get('stringValue','?')}\")
"
# 기대: framework=vLLM, task=text-generation
# 결과: [   ] PASS / [   ] FAIL
~~~

### V-13. 모델 아티팩트 저장 (No.13)

~~~bash
echo "=== V-13: S3 모델 아티팩트 저장 확인 ==="
oc exec -n "${MODEL_NS}" deploy/minio -- \
  ls -lh "/data/${S3_BUCKET}/${S3_MODEL_PATH}/" 2>/dev/null \
  || echo "MinIO에 모델 경로 없음"

for FILE in config.json tokenizer.json tokenizer_config.json; do
  oc exec -n "${MODEL_NS}" deploy/minio -- \
    test -f "/data/${S3_BUCKET}/${S3_MODEL_PATH}/${FILE}" \
    && echo "  ${FILE}: OK" \
    || echo "  ${FILE}: MISSING"
done

SAFETENSOR_COUNT=$(oc exec -n "${MODEL_NS}" deploy/minio -- \
  ls "/data/${S3_BUCKET}/${S3_MODEL_PATH}/" 2>/dev/null \
  | grep -c safetensors)
echo "safetensors 파일 수: ${SAFETENSOR_COUNT}"
# 기대: config.json + tokenizer.json + safetensors 1개 이상
# 결과: [   ] PASS / [   ] FAIL
~~~

## 검증

~~~bash
echo "=== S1 검증 요약 ==="
echo "V-4  모델 등록 기능:       [   ] PASS / [   ] FAIL"
echo "V-5  모델 등록/업로드:     [   ] PASS / [   ] FAIL"
echo "V-6  모델 버전 관리:       [   ] PASS / [   ] FAIL"
echo "V-8  원클릭 배포/철수:     [   ] PASS / [   ] FAIL"
echo "V-9  모델 메타데이터 관리: [   ] PASS / [   ] FAIL"
echo "V-13 모델 아티팩트 저장:   [   ] PASS / [   ] FAIL"
echo ""
echo "실측값:"
echo "  철수 소요 시간: ___초"
echo "  재배포 소요 시간: ___초"
~~~

## 실패 시

- **Model Registry Route 접근 불가** → `oc get route -n ${MODEL_REGISTRY_NS}`로 Route 존재 확인. TLS 인증서 문제면 `-k` 옵션 사용.
- **모델 등록 API 401/403** → `oc whoami -t` 토큰 만료 여부 확인. `oc login` 재수행.
- **버전 등록 실패 (409 Conflict)** → 동일 이름의 버전이 이미 존재. 다른 이름으로 재시도.
- **철수 후 Pod 미삭제** → `oc get replicaset -n ${MODEL_NS}`로 RS 상태 확인. Finalizer가 걸려 있으면 수동 정리 필요.
- **재배포 후 Ready 타임아웃** → 모델 로딩 시간이 GPU/모델 크기에 따라 다름. `oc logs` 확인.

## 다음 단계

→ `runbooks/71-pipeline-validation.md` — Pipeline E2E 검증

# 60-c — TGI 대체 엔진 검증 (No.2)

## 목적

vLLM 외 TGI(Text Generation Inference) CPU 모드를 커스텀 ServingRuntime으로 등록하고 추론을 검증. RHOAI가 다양한 엔진을 지원함을 실증.

## 전제 조건

- [ ] KServe Managed
- [ ] GPU 불필요 (CPU 모드)

## 실행

### 1. TGI CPU ServingRuntime

~~~bash
oc apply -n ${POC_NAMESPACE} -f - <<'EOF'
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: tgi-cpu-runtime
  annotations:
    openshift.io/display-name: "TGI CPU Runtime"
spec:
  supportedModelFormats:
    - name: pytorch
      version: "1"
      autoSelect: true
  multiModel: false
  containers:
    - name: kserve-container
      image: ghcr.io/huggingface/text-generation-inference:latest-intel-cpu
      args: ["--model-id","/mnt/models","--port","3000"]
      ports:
        - containerPort: 3000
          protocol: TCP
      resources:
        requests:
          cpu: "2"
          memory: "4Gi"
        limits:
          cpu: "4"
          memory: "8Gi"
EOF
~~~

### 2. InferenceService 배포

~~~bash
oc apply -n ${POC_NAMESPACE} -f - <<'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: tgi-cpu-test
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: pytorch
      runtime: tgi-cpu-runtime
      storageUri: "s3://${S3_BUCKET}/smollm2-135m"
EOF
~~~

### 3. Ready 확인 및 추론

~~~bash
oc wait inferenceservice tgi-cpu-test -n ${POC_NAMESPACE} --for=condition=Ready --timeout=300s

TGI_URL=$(oc get inferenceservice tgi-cpu-test -n ${POC_NAMESPACE} -o jsonpath='{.status.url}')
curl -sk "${TGI_URL}/generate" \
  -H "Content-Type: application/json" \
  -d '{"inputs":"Hello","parameters":{"max_new_tokens":20}}'
~~~

## 실측 결과 (2026-05-16)

| 항목 | 결과 |
|------|------|
| 이미지 | 2.4.1-intel-cpu (latest 호환 문제) |
| S3 인증 | storage.key 방식 필수 |
| 환경변수 | HOME=/tmp, OUTLINES_CACHE_DIR=/tmp/outlines |
| Warmup | CPU 5~7분 |
| InferenceService | **Ready=True** |
| /generate | 정상 텍스트 반환 |

## 검증

| 항목 | 기준 | 판정 |
|------|------|------|
| ServingRuntime | 등록 | **PASS** |
| InferenceService | Ready | **PASS** |
| /generate | 텍스트 반환 | **PASS** |

## 트러블슈팅

- **transformers.masking_utils 없음** → 2.4.1-intel-cpu 사용
- **S3 인증 실패** → storage.key로 Secret 참조
- **Cache 권한 거부** → HOME=/tmp env 추가

## 정리

~~~bash
oc delete inferenceservice tgi-cpu-test -n ${POC_NAMESPACE} --ignore-not-found
oc delete servingruntime tgi-cpu-runtime -n ${POC_NAMESPACE} --ignore-not-found
~~~

## 다음 단계
→ `runbooks/70-model-serving-validation.md`

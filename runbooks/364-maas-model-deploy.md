# 364 — Sprint 4: MaaS 모델 배포 (LLMInferenceService)

## 목적

MaaS Gateway를 통해 서빙할 LLM 모델을 `LLMInferenceService` CR로 배포하고, MaaS 모델로 퍼블리시한다. llm-d 분산 추론 또는 vLLM 런타임 중 선택한다.

> 출처: RHOAI 3.4 MaaS 문서 §1.5 (Publish models with MaaS), ODH MaaS Model Setup 문서

## 전제 조건

- [ ] `runbooks/363-maas-dsc-dashboard.md` 완료 — Tenant Ready
- [ ] GPU 노드 1개 이상 가용 (`oc get nodes -l nvidia.com/gpu.present=true`)
- [ ] 모델 아티팩트가 S3 또는 HuggingFace에 접근 가능
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`, `MODEL_URI`

## 실행

### 1. 모델 네임스페이스 준비

~~~bash
: "${MODEL_NS:=llm}"
oc create namespace "${MODEL_NS}" --dry-run=client -o yaml | oc apply -f -
oc label ns "${MODEL_NS}" opendatahub.io/dashboard=true --overwrite
~~~

### 2-A. LLMInferenceService 배포 (llm-d 분산 추론)

~~~bash
: "${MODEL_NAME:=granite-2b}"
: "${MODEL_URI:=hf://ibm-granite/granite-3.1-2b-instruct}"

oc apply -f - <<EOF
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: ${MODEL_NAME}
  namespace: ${MODEL_NS}
  annotations:
    alpha.maas.opendatahub.io/tiers: '[]'
spec:
  model:
    uri: "${MODEL_URI}"
    name: "$(echo ${MODEL_URI} | sed 's|hf://||')"
  replicas: 1
  router:
    route: {}
    gateway:
      refs:
        - name: maas-default-gateway
          namespace: openshift-ingress
  template:
    containers:
      - name: main
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: 12Gi
          requests:
            nvidia.com/gpu: "1"
            memory: 8Gi
EOF

echo "LLMInferenceService ${MODEL_NAME} 배포 대기..."
~~~

### 2-B. LLMInferenceService 배포 (vLLM 런타임 — Technology Preview)

> vLLMDeploymentOnMaaS가 true일 때만 사용 가능

~~~bash
: "${MODEL_NAME:=qwen3-06b}"
: "${MODEL_URI:=hf://Qwen/Qwen3-0.6B}"

oc apply -f - <<EOF
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: ${MODEL_NAME}
  namespace: ${MODEL_NS}
  annotations:
    alpha.maas.opendatahub.io/tiers: '[]'
spec:
  model:
    uri: "${MODEL_URI}"
    name: "$(echo ${MODEL_URI} | sed 's|hf://||')"
  replicas: 1
  router:
    route: {}
    gateway:
      refs:
        - name: maas-default-gateway
          namespace: openshift-ingress
  template:
    containers:
      - name: main
        image: "vllm/vllm-openai:latest"
        resources:
          limits:
            nvidia.com/gpu: "1"
            memory: 12Gi
          requests:
            nvidia.com/gpu: "1"
            memory: 8Gi
EOF

echo "vLLM LLMInferenceService ${MODEL_NAME} 배포 대기..."
~~~

### 3. 배포 상태 대기

~~~bash
echo "Pod Ready 대기 (최대 10분)..."
for i in $(seq 1 60); do
  READY=$(oc get llminferenceservice "${MODEL_NAME}" -n "${MODEL_NS}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "${READY}" == "True" ]]; then
    echo "[PASS] ${MODEL_NAME} Ready"
    break
  fi
  echo "  대기 중... (${i}/60)"
  sleep 10
done

oc get pods -n "${MODEL_NS}" --no-headers
~~~

### 4. MaaSModelRef 확인

모델을 MaaS로 퍼블리시하면 `MaaSModelRef` 오브젝트가 자동 생성된다.

~~~bash
echo "=== MaaSModelRef 확인 ==="
oc get maasmodelref -n "${MODEL_NS}" --no-headers
~~~

### 5. 자동 생성된 RBAC 확인

`alpha.maas.opendatahub.io/tiers: '[]'` 어노테이션이 있으면 ODH Controller가 Role/RoleBinding을 자동 생성한다.

~~~bash
echo "=== 자동 RBAC 확인 ==="
oc get roles,rolebindings -n "${MODEL_NS}" | grep "${MODEL_NAME}"
~~~

## 검증

~~~bash
echo "=== Sprint 4 검증 ==="

echo "1) LLMInferenceService:"
oc get llminferenceservice -n "${MODEL_NS}"

echo "2) 모델 Pod:"
oc get pods -n "${MODEL_NS}" --no-headers

echo "3) MaaSModelRef:"
oc get maasmodelref -n "${MODEL_NS}" --no-headers

echo "4) 자동 RBAC:"
oc get roles -n "${MODEL_NS}" --no-headers | grep -c "${MODEL_NAME}" || echo "0"
echo "roles found"
~~~

## 실패 시

- **Pod ImagePullBackOff** → 이미지 레지스트리 접근 확인, `oc describe pod -n ${MODEL_NS}`
- **GPU 할당 실패** → `oc describe node <gpu-node>` 에서 allocatable GPU 확인
- **MaaSModelRef 미생성** → `alpha.maas.opendatahub.io/tiers` 어노테이션 존재 + Gateway refs 정확성 확인
- **LLMInferenceService Not Ready** → `oc describe llminferenceservice ${MODEL_NAME} -n ${MODEL_NS}` 이벤트 확인

## 다음 단계

→ `runbooks/365-maas-subscription.md`

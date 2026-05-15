# 62 — CMA/KEDA 오토스케일링 (S3)

## 목적

부하 트래픽 증가 시 CMA(Custom Metrics Autoscaler) 기반 ScaledObject가 vLLM 메트릭(활성 요청 수 + 대기 요청 수)을 감지하여 replica를 자동 증가시키는 과정을 검증한다. GPU 메트릭 수집 파이프라인과 스케일링 정책 커스터마이징도 함께 확인한다.

## 전제 조건

- [ ] `runbooks/61-pipeline.md` 완료 — Tekton Pipeline E2E 검증 통과
- [ ] CMA Operator v2.18.1 Succeeded (`oc get csv -A | grep custom-metrics`)
- [ ] KEDA Pod Running (`oc get pods -n openshift-keda`)
- [ ] Prometheus (UWM) 활성화 (`oc get pods -n openshift-user-workload-monitoring`)
- [ ] DCGM Exporter Running (`oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter`)
- [ ] 환경변수 설정: `MODEL_NS`, `MODEL_NAME`
- [ ] GPU 2기 이상 가용 (스케일업 실증 시 필요, 1기 환경은 조건부 PASS)

## 실행

### 1. CMA Operator 및 KEDA 환경 확인

~~~bash
# CMA Operator 상태
oc get csv -n openshift-keda | grep custom-metrics
# 기대: custom-metrics-autoscaler.v2.18.1 ... Succeeded

# KEDA Pod 상태
oc get pods -n openshift-keda
# 기대: keda-operator, keda-metrics-apiserver 등 Running

# KEDA CRD 확인
oc api-resources | grep scaledobjects
# 기대: scaledobjects keda.sh/v1alpha1
~~~

### 2. TriggerAuthentication 및 HPA 충돌 해소

~~~bash
# TriggerAuthentication 확인 (없으면 SA 기반 인증 설정)
oc get triggerauthentication keda-prometheus-creds -n ${MODEL_NS} 2>/dev/null || \
  bash scripts/keda-sa-auth-setup.sh ${MODEL_NS}

# KServe 자동 생성 HPA 삭제 (ScaledObject와 충돌 방지)
oc delete hpa ${MODEL_NAME}-predictor -n ${MODEL_NS} 2>/dev/null || true

# IS의 maxReplicas를 GPU 수에 맞게 설정
oc patch inferenceservice ${MODEL_NAME} -n ${MODEL_NS} --type=merge \
  -p '{"spec":{"predictor":{"maxReplicas":3}}}'
~~~

### 3. ScaledObject 생성

~~~bash
oc apply -n ${MODEL_NS} -f - <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: vllm-autoscaler
spec:
  scaleTargetRef:
    name: ${MODEL_NAME}-predictor
  minReplicaCount: 1
  maxReplicaCount: 3
  cooldownPeriod: 60
  pollingInterval: 10
  triggers:
    - type: prometheus
      metadata:
        serverAddress: "https://thanos-querier.openshift-monitoring.svc.cluster.local:9091"
        query: |
          sum(vllm:num_requests_running{namespace="${MODEL_NS}"}) +
          sum(vllm:num_requests_waiting{namespace="${MODEL_NS}"})
        threshold: "2"
        unsafeSsl: "true"
      authenticationRef:
        name: keda-prometheus-creds
EOF
~~~

> GitOps 환경에서는 ArgoCD가 ScaledObject를 관리한다. 수동 생성 대신 sync 상태만 확인할 것.

### 4. 부하 트래픽 발생 및 스케일업 관찰

~~~bash
# 동시 요청 10건 발생 (threshold=2 초과 목표)
for i in $(seq 1 10); do
  oc exec -n ${MODEL_NS} deploy/minio -- curl -s \
    http://${MODEL_NAME}-predictor.${MODEL_NS}.svc.cluster.local:8080/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"'${MODEL_NAME}'","prompt":"Write a long essay about AI","max_tokens":200}' &
done
wait
echo "부하 발생 완료"
~~~

## 검증

~~~bash
# ScaledObject 상태 확인
oc get scaledobject vllm-autoscaler -n ${MODEL_NS}
# 기대: READY=True

# KEDA가 자동 생성한 HPA 확인
oc get hpa -n ${MODEL_NS} | grep keda-hpa
# 기대: keda-hpa-vllm-autoscaler 존재, MIN=1, MAX=3

# 스케일링 정책 상세 확인
oc get scaledobject vllm-autoscaler -n ${MODEL_NS} \
  -o jsonpath='{.spec}' | python3 -m json.tool
# 기대: cooldownPeriod=60, pollingInterval=10, threshold="2"

# HPA 메트릭 및 replica 변화 관찰 (30초 간격, 3분간)
for i in $(seq 1 6); do
  echo "--- $(date '+%H:%M:%S') ---"
  oc get hpa keda-hpa-vllm-autoscaler -n ${MODEL_NS}
  oc get pods -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME} --no-headers
  sleep 30
done
# 기대 (GPU 2+): REPLICAS 1 -> 2 또는 3 증가

# DCGM GPU 메트릭 Prometheus 수집 확인
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | jq '.data.result | length'
# 기대: result >= 1
~~~

## 실패 시

- **ScaledObject Ready=False** → TriggerAuthentication의 SA 토큰 설정 확인. `oc describe scaledobject vllm-autoscaler -n ${MODEL_NS}`로 이벤트 조회. Prometheus 인증 경고가 원인인 경우 `scripts/keda-sa-auth-setup.sh` 재실행.
- **HPA 미생성** → KServe 기본 HPA가 남아 있는지 확인. `oc get hpa -n ${MODEL_NS}`로 충돌 여부 점검 후 KServe HPA 삭제.
- **스케일업 미발생 (GPU 1기)** → GPU 부족으로 Pending은 정상(조건부 PASS). HPA의 desiredReplicas가 증가했는지 확인하여 메트릭 폴링 동작은 검증.
- **Prometheus 메트릭 미수집** → UWM(User Workload Monitoring) Pod 상태 확인. ServiceMonitor/PodMonitor가 vLLM 메트릭을 수집하도록 구성되었는지 확인.
- **KEDA 인증 만료** → `oc create token --duration=24h` 방식은 24시간 후 만료. ServiceAccount 기반 인증(`scripts/keda-sa-auth-setup.sh`)으로 전환.

## 다음 단계

→ `runbooks/63-recovery.md` — 장애복구 / 이중화 검증

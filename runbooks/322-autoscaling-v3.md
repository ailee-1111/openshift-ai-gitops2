# 322 — S3 강화: GPU 메트릭 실 스케일링

## 목적

v1의 CPU 기반 HPA를 GPU VRAM/큐 깊이 기반 KEDA 트리거로 강화하고, 1→3→1 전체 사이클을 계단형 부하(10→50→100 RPS)로 검증한다.

## 전제 조건

- [ ] `runbooks/320-autoscaling.md` 완료 — 기본 ScaledObject READY=True
- [ ] GPU 2기 이상 가용
- [ ] DCGM Exporter Running
- [ ] TriggerAuthentication 설정 완료
- [ ] 환경변수: `MODEL_NS`, `MODEL_NAME`

## 실행

### 1. GPU 메트릭 기반 ScaledObject 업데이트

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
  cooldownPeriod: 120
  pollingInterval: 10
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 30
          policies:
            - type: Pods
              value: 1
              periodSeconds: 30
        scaleDown:
          stabilizationWindowSeconds: 120
          policies:
            - type: Pods
              value: 1
              periodSeconds: 60
  triggers:
    - type: prometheus
      metadata:
        serverAddress: "https://thanos-querier.openshift-monitoring.svc.cluster.local:9091"
        query: |
          sum(vllm:num_requests_running{namespace="${MODEL_NS}"}) +
          sum(vllm:num_requests_waiting{namespace="${MODEL_NS}"})
        threshold: "2"
        unsafeSsl: "true"
        authModes: "bearer"
      authenticationRef:
        name: keda-prometheus-creds
    - type: prometheus
      metadata:
        serverAddress: "https://thanos-querier.openshift-monitoring.svc.cluster.local:9091"
        query: |
          avg(DCGM_FI_DEV_FB_USED{namespace="nvidia-gpu-operator"})
          / avg(DCGM_FI_DEV_FB_FREE{namespace="nvidia-gpu-operator"} + DCGM_FI_DEV_FB_USED{namespace="nvidia-gpu-operator"})
          * 100
        threshold: "80"
        unsafeSsl: "true"
        authModes: "bearer"
      authenticationRef:
        name: keda-prometheus-creds
EOF
~~~

### 2. 계단형 부하 테스트 (10→50→100 RPS)

~~~bash
ROUTE=$(oc get route ${MODEL_NAME}-api -n ${MODEL_NS} -o jsonpath='{.spec.host}')

echo "=== 계단형 부하 시작 ==="
for STEP_RPS in 10 50 100; do
  echo ""
  echo "=== [Step] ${STEP_RPS} RPS (30초) ==="
  for round in $(seq 1 30); do
    for i in $(seq 1 ${STEP_RPS}); do
      curl -sk -o /dev/null --max-time 10 \
        "https://${ROUTE}/v1/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"'${MODEL_NAME}'","prompt":"Write a detailed essay","max_tokens":200}' &
    done
    sleep 1
  done
  wait
  echo "$(date '+%H:%M:%S') ${STEP_RPS} RPS 완료"
  oc get hpa -n ${MODEL_NS} --no-headers
  oc get pods -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME} --no-headers | wc -l | xargs echo "  Pods:"
done
~~~

### 3. 스케일다운 관찰

~~~bash
echo "=== 스케일다운 관찰 (5분, 30초 간격) ==="
for i in $(seq 1 10); do
  echo "--- $(date '+%H:%M:%S') ---"
  oc get hpa -n ${MODEL_NS} --no-headers
  oc get pods -n ${MODEL_NS} -l serving.kserve.io/inferenceservice=${MODEL_NAME} --no-headers | wc -l | xargs echo "  Pods:"
  sleep 30
done
~~~

## 검증

~~~bash
# 1. ScaledObject GPU 트리거 포함
oc get scaledobject vllm-autoscaler -n ${MODEL_NS} -o jsonpath='{.spec.triggers}' | python3 -c "
import sys, json
for t in json.load(sys.stdin):
    q = t.get('metadata',{}).get('query','')
    label = 'VRAM' if 'DCGM' in q else 'Queue'
    print(f'  {label}: threshold={t[\"metadata\"][\"threshold\"]}')
"

# 2. HPA 스케일업 이벤트
oc describe hpa keda-hpa-vllm-autoscaler -n ${MODEL_NS} | grep -A5 "Events"

# 3. 최종 replica=1 복귀
oc get deployment ${MODEL_NAME}-predictor -n ${MODEL_NS} -o jsonpath='replicas={.spec.replicas}'
echo ""
~~~

## 실패 시

- **VRAM 트리거 미동작** → DCGM 메트릭 네임스페이스 확인
- **스케일업 미발생** → 경량 모델은 큐 미발생. 8B 모델 또는 `max_tokens=500+` 사용
- **스케일다운 지연** → cooldown + stabilization으로 최소 4분 소요

## 다음 단계

→ `runbooks/332-recovery-v3.md` — S4 강화: Chaos Engineering

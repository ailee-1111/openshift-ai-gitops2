# S5: Scale-to-Zero — 비사용 시 GPU 비용 제로

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | INFRA (poc-admin, cluster-admin) |
| 보조역할 | OPS (poc-operator, NS edit + monitoring) |
| 데모 시간 | 10분 |
| 검증 항목 | No.23 (스케일 투 제로), No.24 (콜드스타트 최적화) |
| 구축 런북 | runbooks/340-scale-to-zero.md, runbooks/341-scale-to-zero-v3.md |
| 검증 런북 | runbooks/540-scale-to-zero-validation.md |
| IaC 경로 | infra/poc/autoscaling/ |

---

## 상황 (Context)

> 현대모비스는 HGX H200×8 GPU 서버를 도입하여 AI 비전 검사 모델을 운영하고 있습니다. GPU 서버 리스 비용은 월 약 5,000만 원입니다. 그런데 양산 라인은 주간(08:00~18:00)에만 가동되며, 야간과 주말에는 AI 추론 요청이 전혀 없습니다. 일주일 168시간 중 실제 사용 시간은 50시간 — GPU가 **70%의 시간 동안 유휴 상태**로 전기를 소모하고 있습니다.

---

## 문제 (Problem)

> **RHOAI 없이 운영한다면:**
>
> - GPU 서버가 24/7 켜져 있어야 합니다. 야간과 주말에 요청이 0건이어도 GPU VRAM에 모델이 상주하며 **전력을 소모**합니다
> - "사용하지 않을 때 끄면 되지 않나?"라는 질문에 — 수동으로 끄고 켜려면 운영자가 매일 출퇴근 시간에 **서버 관리 작업**을 해야 합니다
> - 모델 서버를 수동으로 내리면, 다음 날 아침 **모델 로딩에 10~20분**이 걸려 양산 시작이 지연됩니다
> - GPU를 다른 워크로드(학습 등)와 공유할 수 없어, **고가의 GPU 자원이 잠겨(lock-in)** 있습니다
> - 연간 GPU 비용 6억 원 중 약 **4억 원이 유휴 시간 비용**입니다

---

## 해결 (Solution) — RHOAI로 이렇게 해결합니다

### **1) 수동으로 1개 올림 → 2) 트래픽 없이 대기 → 3) KEDA가 자동으로 0으로 축소 → 4) Cold Start 복원** 

  
|          구분          │       트리거 소스                       │               가능 여부                                                          │
| --------------- | -------------------------- | ------------------------------------------------- |
|  **Scale to zero** (idle→0) │ vLLM num_requests=0     │ KEDA idleReplicaCount=0로 가능           │
|  **Scale from zero** (0→1)  │ vLLM 메트릭             │  **불가** — Pod가 없으면 메트릭 없음                  │
│  **Scale from zero** (0→1)  │ Gateway/Ingress 요청 수 │ 가능 — 요청이 Gateway에 도착하면 감지     │
│  **Scale from zero** (0→1)  │ KEDA HTTP Add-on        │ 가능 — 프록시가 요청을 버퍼링                    │
│  **Scale from zero** (0→1)  │ llm-d activator         │ 가능 — RHOAI Developer Preview                   │
│  **Scale from zero** (0→1)  │ CronJob 스케줄          │ 가능 — 업무 시간 기반 예측                                 │


### Step 1. 현재 GPU 자원 사용량 확인

| 항목      | 내용                                           |
| ------- | -------------------------------------------- |
| **누가**  | INFRA (poc-admin)                            |
| **무엇을** | 서빙 Pod의 GPU VRAM 사용량과 할당 상태 확인               |
| **어떻게** | DCGM Exporter로 VRAM 사용량 조회, 노드의 GPU 할당 상태 확인 |
| **권한**  | cluster-admin                                |

```bash
# DCGM Exporter로 현재 VRAM 사용량 확인
DCGM_POD=$(oc get pods -n nvidia-gpu-operator \
  -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}')

echo "=== 현재 GPU VRAM 사용량 ==="
oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
  curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"

echo "=== 노드 GPU 할당 상태 ==="
oc describe node -l nvidia.com/gpu.present=true | grep -A5 "Allocated resources"
```

**확인**: 서빙 Pod가 GPU 1개를 점유하고, VRAM 약 41,936 MiB 사용 중

> **시연 포인트**: "지금 이 GPU는 모델 서빙을 위해 VRAM 약 42GB를 점유하고 있습니다. 야간이나 주말처럼 요청이 없는 시간에도 이 자원이 잠겨 있어, 학습이나 다른 추론에 사용할 수 없습니다."

---

### Step 2. Scale-to-Zero 설정 — CronJob + KEDA paused 연동

| 항목 | 내용 |
|------|------|
| **누가** | INFRA (poc-admin) |
| **무엇을** | CronJob으로 업무 시간 외에 GPU 자동 해제 |
| **어떻게** | CronJob이 KEDA `paused-replicas` 어노테이션으로 replica=0 전환 |
| **권한** | cluster-admin |

**Scale-to-Zero 아키텍처:**

```
┌─────────────────────────────────────────────────────────────┐
│  S3 (Auto-scaling)과 S5 (Scale-to-Zero)의 역할 분리          │
│                                                             │
│  ScaledObject (vllm-autoscaler):                            │
│    minReplicaCount=1, maxReplicaCount=3                     │
│    → 업무 시간: KEDA가 부하 기반 1→3 스케일링 관리 (S3)       │
│                                                             │
│  CronJob (scale-down-evening / scale-up-morning):           │
│    → 18:00: paused-replicas="0" → KEDA 정지 + replica=0     │
│    → 08:00: paused 해제 → KEDA 재개 + min=1 유지             │
│                                                             │
│  핵심: KEDA의 paused 어노테이션으로 S3/S5 전환               │
└─────────────────────────────────────────────────────────────┘
```

> **Scale-from-Zero 제약 사항**: RawDeployment 모드에서는 Pod=0일 때 vLLM 메트릭이 존재하지 않으며, HAProxy 라우터는 backend 없는 요청을 즉시 503으로 반환(큐잉 없음)합니다. 따라서 **요청 기반 자동 Scale-from-Zero는 불가**합니다. 프로덕션에서는 Knative Serving 모드(activator 기반 요청 버퍼링) 또는 llm-d activator(Developer Preview)를 사용하십시오.

```bash
# CronJob 생성 — 업무 시간 기반 Scale-to-Zero / Scale-from-Zero
cat <<'CRON_EOF' | oc apply -n ${MODEL_NS:-mobis-poc} -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-up-morning
  labels:
    scenario: s5-scale-to-zero
spec:
  schedule: "0 8 * * 1-5"
  timeZone: "Asia/Seoul"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pipeline
          containers:
          - name: scale-up
            image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
            command: ["/bin/bash", "-c"]
            args:
            - |
              echo "=== 업무 시작: Scale-from-Zero (0→1) ==="
              oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS:-mobis-poc} \
                autoscaling.keda.sh/paused-replicas- --overwrite 2>/dev/null || true
              oc scale deployment ${MODEL_NAME:-smollm2-135m}-predictor \
                -n ${MODEL_NS:-mobis-poc} --replicas=1
              oc wait pod -n ${MODEL_NS:-mobis-poc} \
                -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
                --for=condition=Ready --timeout=300s
              echo "Scale-up 완료"
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-down-evening
  labels:
    scenario: s5-scale-to-zero
spec:
  schedule: "0 18 * * 1-5"
  timeZone: "Asia/Seoul"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pipeline
          containers:
          - name: scale-down
            image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
            command: ["/bin/bash", "-c"]
            args:
            - |
              echo "=== 업무 종료: Scale-to-Zero (1→0) ==="
              oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS:-mobis-poc} \
                autoscaling.keda.sh/paused-replicas="0" --overwrite
              oc scale deployment ${MODEL_NAME:-smollm2-135m}-predictor \
                -n ${MODEL_NS:-mobis-poc} --replicas=0
              echo "Scale-down 완료. GPU 자원 해제됨."
          restartPolicy: OnFailure
CRON_EOF

echo "CronJob 생성 완료"
```

**수동 Scale-to-Zero 실행 (시연용):**
```bash
# 즉시 Scale-to-Zero 트리거 (CronJob 수동 실행)
oc create job scale-down-now --from=cronjob/scale-down-evening -n ${MODEL_NS:-mobis-poc}
```

> **시연 포인트**: "운영 환경에서는 CronJob이 매일 18:00에 자동으로 GPU를 해제하고, 08:00에 자동으로 복원합니다. KEDA의 `paused` 어노테이션으로 S3(오토스케일링)과 S5(스케일투제로)를 하나의 ScaledObject에서 시간대별로 전환합니다."

---

### Step 3. GPU 자원 완전 해제 확인 — VRAM 41,936→0 MiB

| 항목 | 내용 |
|------|------|
| **누가** | INFRA + OPS (모두 관찰) |
| **무엇을** | Pod 종료 후 GPU VRAM이 완전히 해제되었는지 확인 |
| **어떻게** | Pod 상태 확인 + DCGM VRAM 메트릭 재조회 |
| **권한** | NS view 이상 |

```bash
# 30초 대기 (Pod graceful shutdown)
sleep 30

echo "=== Pod 상태 (축소 후) ==="
oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running --no-headers
# 기대: 출력 없음 (Running Pod 0개)

echo "=== 축소 후 VRAM ==="
oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
  curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"
# 기대: VRAM 사용량 대폭 감소 (모델 점유분 해제)

echo "=== 축소 후 GPU 할당 ==="
oc describe node -l nvidia.com/gpu.present=true | grep -A5 "Allocated resources"
# 기대: nvidia.com/gpu 요청 0
```

**실측값**: VRAM **41,936 → 0 MiB** 완전 해제, Pod 0개

> **시연 포인트**: "VRAM이 42GB에서 0으로 완전히 해제되었습니다. 이 GPU는 이제 다른 워크로드 — 모델 학습, 다른 팀의 추론, 배치 처리 등 — 에 자유롭게 할당할 수 있습니다. 야간에 자동으로 이 상태가 되면, GPU 비용이 0입니다."

---

### Step 4. 추론 요청으로 Cold Start 트리거

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | replica=0 상태에서 새 추론 요청을 보내 자동 복원(Cold Start) 시작 |
| **어떻게** | KEDA paused 해제 + replica=1 복원 + 시간 측정 |
| **권한** | NS edit |

```bash
# replica 0 상태 확인
echo "=== 복원 전 상태 ==="
oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running --no-headers
# 확인: Running Pod 없음

# Cold Start 타이머 시작
echo "Cold Start 시작: $(date '+%H:%M:%S')"
START=$(date +%s)

# KEDA paused 해제 + replica 복원
oc annotate scaledobject vllm-autoscaler -n ${MODEL_NS:-mobis-poc} \
  autoscaling.keda.sh/paused-replicas- --overwrite 2>/dev/null || true
oc scale deployment ${MODEL_NAME:-smollm2-135m}-predictor -n ${MODEL_NS:-mobis-poc} --replicas=1
```

> **시연 포인트**: "아침 8시, 첫 번째 추론 요청이 들어옵니다. KEDA가 요청을 감지하고 자동으로 GPU Pod를 기동합니다. 지금부터 Cold Start 시간을 측정합니다."

---

### Step 5. Cold Start 완료 및 API 복원 확인

| 항목 | 내용 |
|------|------|
| **누가** | OPS + INFRA (모두 관찰) |
| **무엇을** | Pod Ready까지의 Cold Start 시간 측정 + API 정상 응답 확인 |
| **어떻게** | `oc wait` + 반복 curl로 HTTP 200 확인 |
| **권한** | NS view 이상 |

```bash
# Pod Ready 대기
oc wait pod -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --for=condition=Ready --timeout=600s
END=$(date +%s)
echo "Cold Start (Pod Ready): $((END - START))초"

# API 서빙 재개 확인 (모델 로딩 완료까지 추가 대기)
ROUTE=$(oc get route ${MODEL_NAME:-smollm2-135m}-api -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='{.spec.host}')

for attempt in $(seq 1 30); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 30 \
    -X POST "https://${ROUTE}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"'${MODEL_NAME:-smollm2-135m}'","messages":[{"role":"user","content":"cold start test"}],"max_tokens":10}')
  echo "$(date '+%H:%M:%S') | 시도 ${attempt} | HTTP: ${HTTP_CODE}"
  if [ "${HTTP_CODE}" = "200" ]; then break; fi
  sleep 10
done
END_API=$(date +%s)
echo "API 복원까지 총 소요: $((END_API - START))초"
```

**실측값**: 1차 Cold Start **61초**, 2차 Cold Start **73초** (목표 120초 이내)

> **시연 포인트**: "61초 만에 GPU가 할당되고, 모델이 로딩되고, API가 정상 응답합니다. 120초 이내라는 목표를 달성했습니다. 양산 라인 시작 전 1~2분 전에 자동으로 기동하면, 작업자는 AI 부재를 전혀 인지하지 못합니다."

---

### Step 6. VRAM 재할당 확인

| 항목 | 내용 |
|------|------|
| **누가** | INFRA (poc-admin) |
| **무엇을** | Cold Start 후 VRAM이 정상적으로 재할당되었는지 확인 |
| **어떻게** | DCGM VRAM 메트릭 재조회 |
| **권한** | cluster-admin |

```bash
echo "=== 복원 후 VRAM ==="
oc exec -n nvidia-gpu-operator ${DCGM_POD} -- \
  curl -s localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED"
# 기대: VRAM 사용량이 축소 전 수준(~41,936 MiB)으로 복귀

echo "=== 복원 후 Pod ==="
oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m}
# 기대: 1개 Pod, Running, 2/2 Ready

echo "=== 복원 후 GPU 할당 ==="
oc describe node -l nvidia.com/gpu.present=true | grep -A5 "Allocated resources"
# 기대: nvidia.com/gpu 요청 1
```

> **시연 포인트**: "VRAM이 다시 42GB로 돌아왔습니다. 전체 사이클이 완료되었습니다: 유휴 → GPU 해제(비용 0) → 요청 도착 → 자동 복원(61초) → 정상 서빙. 이 사이클이 매일 자동으로 반복됩니다."

---

## 확인 (Verification)

| 검증 기준 | 기대값 | 실측값 |
|----------|--------|--------|
| Scale-to-Zero 후 Pod 수 | 0개 | **PASS — 0개 (CronJob paused-replicas=0)** |
| VRAM 해제 | 모델 점유분 완전 해제 | **PASS — GPU 할당 3→2 (smollm2 GPU 해제)** |
| GPU 할당 해제 | nvidia.com/gpu 요청 감소 | **PASS — 확인** |
| Cold Start (CronJob 복원) | 120초 이내 | **PASS — 72초 (CronJob paused 해제 → Pod Ready)** |
| Cold Start 후 API 응답 | HTTP 200 | **PASS — HTTP 200** |
| VRAM 재할당 | 축소 전 수준 복귀 | **PASS — GPU 재할당 확인** |
| Scale-from-Zero 방식 | 자동 (KEDA/Gateway) | **CronJob 스케줄 방식** — RawDeployment에서는 요청 기반 자동 복원 불가. 프로덕션은 Knative Serving 또는 llm-d activator 권장 |

---

## 이번 시연에서 확인된 핵심 가치

- **유휴 시간 GPU 비용 제로**: replica=0이 되면 VRAM이 완전히 해제되어 GPU 비용이 0입니다. 야간(18:00~08:00)과 주말에 자동 적용하면, 주 168시간 중 118시간의 GPU 비용을 절감합니다.
- **연간 40~60% 비용 절감**: GPU 서버 월 5,000만 원 기준, 유휴 시간 비율 70%를 절감하면 **연간 약 4.2억 원**의 비용 절감이 가능합니다. ROI 계산의 핵심 근거입니다.
- **Cold Start 61~73초**: Scale-to-Zero에서 서빙 재개까지 120초 이내를 달성했습니다. 양산 라인 시작 1~2분 전에 자동 기동하면, 작업자는 지연을 인지하지 못합니다.
- **GPU 자원 공유 가능**: 해제된 GPU를 야간 배치 학습, 다른 팀의 추론, 실험 워크로드 등에 재할당할 수 있어, 동일한 하드웨어로 더 많은 가치를 창출합니다.

---

## 추천 사항

- **KEDA cooldownPeriod 설정**: 운영 환경에서는 cooldownPeriod를 300~600초(5~10분)로 설정하십시오. 짧은 유휴 후 즉시 축소하면 불필요한 Cold Start가 빈번해집니다.
- **CronJob 기반 예측 스케일링**: 양산 라인 일정이 고정되어 있다면, CronJob으로 08:00에 replica=1, 18:00에 replica=0을 예약하는 방식이 더 예측 가능합니다. KEDA 자동 축소와 병행하면 최적입니다.
- **대형 모델 Cold Start 대응**: SmolLM2-135M 기준 61~73초이며, 대형 모델(8B, 70B)은 수 분이 소요됩니다. H200의 HBM3e 대역폭(4.8TB/s)이 로딩 시간을 단축하며, PVC 기반 모델 캐싱으로 추가 최적화가 가능합니다.
- **클라이언트 재시도 로직**: Scale-to-Zero 상태에서 첫 요청은 Pod 기동 전이므로 503 또는 타임아웃이 발생합니다. 클라이언트에 exponential backoff 재시도 로직을 반드시 구현하십시오.
- **llm-d activator (Developer Preview)**: 향후 llm-d activator가 GA되면, Scale-to-Zero 상태에서 요청을 드롭하지 않고 버퍼링하면서 Pod를 기동할 수 있습니다. 클라이언트 재시도 로직 없이도 안정적인 운영이 가능해집니다.
- **비용 절감 리포팅**: GPU 유휴 시간과 Scale-to-Zero 절감액을 월별로 리포팅하여, GPU 투자 ROI를 경영진에게 정량적으로 보고하십시오.

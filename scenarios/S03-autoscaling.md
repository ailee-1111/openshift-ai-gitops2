# S3: Auto-scaling — 트래픽 급증 시 GPU 자동 확장

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | OPS (poc-operator, NS edit + monitoring) |
| 보조역할 | INFRA (poc-admin, cluster-admin) |
| 데모 시간 | 15분 |
| 검증 항목 | No.21 (수평 오토스케일링), No.22 (GPU 메트릭), No.25 (스케일링 정책 커스터마이징) |
| 구축 런북 | runbooks/320-autoscaling.md, runbooks/321-cpu-hpa.md, runbooks/322-autoscaling-v3.md |
| 검증 런북 | runbooks/520-autoscaling-validation.md |
| IaC 경로 | infra/poc/autoscaling/ |

---

## 상황 (Context)

> 현대모비스 AI 비전 검사 서비스가 양산 라인에 투입된 지 3개월째입니다. 평상시 초당 10건의 추론 요청을 안정적으로 처리하고 있었습니다. 그런데 오늘 마케팅팀이 신규 AI 품질관리 시스템 홍보 캠페인을 시작하면서, 협력사 5곳이 동시에 API 연동 테스트를 시작했습니다. 트래픽이 10배 급증하여 초당 100건의 요청이 몰리고 있습니다.

---

## 문제 (Problem)

> **RHOAI 없이 운영한다면:**
>
> - 운영자가 트래픽 급증을 **수동으로 모니터링**하다가 알림을 놓칩니다
> - GPU 서버 증설을 위해 인프라팀에 요청 → 승인 → 프로비저닝까지 **수 시간~수 일** 소요
> - 그 사이 요청 큐가 넘쳐 **타임아웃과 오류**가 발생하고, 협력사 연동 테스트가 실패합니다
> - 트래픽이 줄어든 후에도 증설된 GPU가 **유휴 상태로 방치**되어 비용이 낭비됩니다
> - "GPU를 몇 대 준비해야 하는가?"라는 질문에 대한 답이 없어 항상 **과잉 프로비저닝**하게 됩니다

---

## 해결 (Solution) — RHOAI로 이렇게 해결합니다

### Step 1. 현재 서빙 상태 확인

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | 현재 모델 서빙 replica 수와 Pod 상태 확인 |
| **어떻게** | `oc` CLI로 Deployment 및 Pod 조회 |
| **권한** | NS edit + monitoring |

```bash
# 현재 replica 수 확인
oc get deployment ${MODEL_NAME:-smollm2-135m}-predictor -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='replicas={.spec.replicas}'
echo ""

# 서빙 Pod 상태
oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running
```

**확인**: replica=1, Pod 1개 Running (2/2 Ready)

> **시연 포인트**: "현재 GPU 1개로 서빙 중입니다. 이 상태에서 트래픽이 10배 급증하면 어떻게 되는지 보겠습니다."

---

### Step 2. KEDA ScaledObject 구성 확인

| 항목 | 내용 |
|------|------|
| **누가** | INFRA (poc-admin) |
| **무엇을** | CMA/KEDA 기반 오토스케일링 정책 설명 |
| **어떻게** | ScaledObject YAML과 실행 상태 조회 |
| **권한** | cluster-admin |

```bash
# ScaledObject 상태 확인
oc get scaledobject vllm-autoscaler -n ${MODEL_NS:-mobis-poc}
# 기대: READY=True

# 스케일링 정책 상세
oc get scaledobject vllm-autoscaler -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='{.spec}' | python3 -m json.tool
```

**확인**: 다음 정책이 설정되어 있음을 보여줍니다:

| 파라미터 | 값 | 의미 |
|---------|-----|------|
| `minReplicaCount` | 1 | 최소 1개 replica 유지 |
| `maxReplicaCount` | 3 | 최대 3개까지 확장 |
| `cooldownPeriod` | 60초 | 부하 해소 후 60초 대기 후 축소 |
| `pollingInterval` | 10초 | 10초마다 메트릭 폴링 |
| `threshold` | 2 | 활성+대기 요청 합이 2 초과 시 스케일업 |

> **시연 포인트**: "KEDA가 vLLM의 실시간 요청 큐 깊이를 10초마다 감시합니다. 요청이 threshold를 초과하면 자동으로 GPU replica를 추가합니다. 인프라팀의 수동 개입이 전혀 필요 없습니다."

**IaC 참조**: `infra/poc/autoscaling/scaledobject.yaml`

```yaml
# ScaledObject 핵심 설정 (GitOps로 관리)
triggers:
  - type: prometheus
    metadata:
      query: |
        sum(vllm:num_requests_running{namespace="${MODEL_NS:-mobis-poc}"}) +
        sum(vllm:num_requests_waiting{namespace="${MODEL_NS:-mobis-poc}"})
      threshold: "2"
```

---

### Step 3. 부하 트래픽 발생 (트래픽 급증 시뮬레이션)

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | 클러스터 내부 Job으로 동시 요청 250건 발생하여 트래픽 급증 시뮬레이션 |
| **어떻게** | Kubernetes Job (parallelism=5) → vLLM `/v1/completions` API 호출 |
| **권한** | NS edit |

#### 부하 테스트 방법: Kubernetes Job 기반

**왜 Job을 사용하는가?**

| 방법 | 장점 | 단점 |
|------|------|------|
| `oc exec` + `curl &` | 간단 | 로컬 → 클러스터 네트워크 지연, 경량 모델은 요청이 너무 빨리 처리되어 Prometheus 스크래핑(15~30초) 사이에 사라짐 |
| **Job (parallelism)** | 클러스터 내부에서 직접 호출, 지속적 부하 유지 | Job YAML 작성 필요 |
| 외부 도구 (k6, locust) | 정밀한 RPS 제어 | 별도 설치 필요, 클러스터 외부 네트워크 경유 |

**Job 파라미터 가이드:**

| 파라미터 | 설명 | 권장값 |
|---------|------|--------|
| `parallelism` | 동시 실행 Pod 수 (= 동시 클라이언트 수) | 5~10 |
| `completions` | 총 완료 Pod 수 (= parallelism과 동일) | parallelism과 동일 |
| `max_tokens` | 응답 길이 (클수록 요청 처리 시간 증가) | 500~1000 |
| 반복 횟수 (`seq 1 N`) | Pod당 요청 수 | 30~50 |
| `restartPolicy` | Job 실패 시 동작 | `Never` |
| `backoffLimit` | 재시도 횟수 | `0` (재시도 안함) |

> **핵심**: `parallelism × 반복횟수 = 총 요청 수`. 경량 모델(135M)은 `parallelism=5 × 50건 = 250건`, 대형 모델(7B+)은 `parallelism=3 × 10건 = 30건`이면 충분합니다. `max_tokens`를 높이면 요청 처리 시간이 길어져 `num_requests_running` 메트릭이 더 오래 유지됩니다.

```bash
# 부하 테스트 Job 생성
cat <<'LOADEOF' | oc apply -n ${MODEL_NS:-mobis-poc} -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test-s3
spec:
  parallelism: 5       # 동시 5개 클라이언트
  completions: 5       # 5개 Pod 모두 완료 시 Job 종료
  template:
    spec:
      containers:
      - name: load
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          SVC="http://${MODEL_NAME:-smollm2-135m}-predictor.${MODEL_NS:-mobis-poc}.svc.cluster.local:8080"
          for i in $(seq 1 50); do
            curl -s "${SVC}/v1/completions" \
              -H "Content-Type: application/json" \
              -d '{"model":"${MODEL_NAME:-smollm2-135m}","prompt":"Write a very long detailed essay about the complete history of artificial intelligence","max_tokens":1000}' > /dev/null
          done
      restartPolicy: Never
  backoffLimit: 0
LOADEOF

echo "부하 테스트 시작: $(date '+%H:%M:%S')"
echo "5개 Pod × 50건 = 250건 동시 요청"
```

**부하 진행 모니터링:**
```bash
# Job Pod 상태 확인
oc get pods -n ${MODEL_NS:-mobis-poc} -l job-name=load-test-s3 --no-headers

# Job 완료 여부
oc get job load-test-s3 -n ${MODEL_NS:-mobis-poc}
```

**부하 테스트 정리:**
```bash
# 테스트 완료 후 Job 삭제
oc delete job load-test-s3 -n ${MODEL_NS:-mobis-poc}
```

> **시연 포인트**: "마케팅 캠페인으로 협력사 5곳이 동시 접속한 상황을 시뮬레이션합니다. 5개 클라이언트가 클러스터 내부에서 직접 vLLM API를 호출하므로, 외부 네트워크 지연 없이 순수한 모델 서빙 부하를 발생시킵니다."

---

### Step 4. HPA 대시보드 관찰 — 스케일업 1→2→3

| 항목 | 내용 |
|------|------|
| **누가** | OPS + INFRA (모두 관찰) |
| **무엇을** | KEDA가 자동 생성한 HPA의 replica 변화 실시간 관찰 |
| **어떻게** | 30초 간격으로 HPA 및 Pod 상태 모니터링 |
| **권한** | NS view 이상 |

```bash
# HPA 메트릭 및 replica 변화 관찰 (30초 간격, 3분간)
for i in $(seq 1 6); do
  echo "--- $(date '+%H:%M:%S') ---"
  oc get hpa keda-hpa-vllm-autoscaler -n ${MODEL_NS:-mobis-poc}
  oc get pods -n ${MODEL_NS:-mobis-poc} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} --no-headers
  sleep 30
done
```

**기대 결과**: replica가 1 → 2 → 3으로 단계적으로 증가

> **시연 포인트**: "보시는 것처럼, 운영자가 아무것도 하지 않았는데 GPU replica가 자동으로 늘어나고 있습니다. KEDA가 10초마다 Prometheus에서 vLLM 요청 큐 깊이를 읽고, threshold=2를 초과하면 HPA에 스케일업을 지시합니다."

---

### Step 5. 부하 해소 후 자동 스케일다운

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | 부하 해소 후 cooldown 경과 시 자동 축소 관찰 |
| **어떻게** | 부하 중단 후 60초 대기, replica 변화 확인 |
| **권한** | NS monitoring |

```bash
# 부하 완전 해소 확인
echo "부하 해소 대기 (cooldownPeriod=60초)..."
sleep 60

# 스케일다운 관찰 (30초 간격, 2분간)
for i in $(seq 1 4); do
  echo "--- $(date '+%H:%M:%S') ---"
  oc get hpa keda-hpa-vllm-autoscaler -n ${MODEL_NS:-mobis-poc} \
    -o jsonpath='desired={.status.desiredReplicas}, current={.status.currentReplicas}'
  echo ""
  sleep 30
done
```

**기대 결과**: replica가 3 → 2 → 1로 자동 축소 (minReplicaCount=1까지)

> **시연 포인트**: "캠페인이 끝나고 트래픽이 줄자, 60초 쿨다운 후 불필요한 GPU replica가 자동으로 반환됩니다. GPU를 과잉 보유하여 비용을 낭비하는 일이 없습니다."

---

### Step 6. GPU 메트릭 모니터링 확인

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | DCGM GPU 사용률 및 vLLM 요청 메트릭 Prometheus 수집 확인 |
| **어떻게** | Thanos Querier API로 실시간 메트릭 조회 |
| **권한** | NS monitoring |

```bash
# DCGM GPU 사용률 확인
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring \
  -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

echo "=== DCGM GPU 사용률 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
print(f'GPU 메트릭 타겟 수: {len(results)}')
for r in results:
    gpu = r['metric'].get('gpu', '?')
    val = r['value'][1]
    print(f'  GPU {gpu}: {val}%')
"

echo "=== vLLM 활성 요청 수 ==="
curl -sk -H "Authorization: Bearer ${TOKEN}" \
  "https://${THANOS_HOST}/api/v1/query?query=sum(vllm:num_requests_running{namespace=\"${MODEL_NS:-mobis-poc}\"})" \
  | python3 -c "
import sys, json
results = json.load(sys.stdin).get('data', {}).get('result', [])
val = results[0]['value'][1] if results else 'N/A'
print(f'활성 요청 수: {val}')
"
```

> **시연 포인트**: "GPU 사용률(DCGM_FI_DEV_GPU_UTIL)과 vLLM 요청 큐(num_requests_running, num_requests_waiting) 두 가지 메트릭이 Prometheus에 실시간 수집되고 있습니다. 이 메트릭이 스케일링 판단의 근거입니다."

---

## 확인 (Verification)

| 검증 기준 | 기대값 | 실측값 |
|----------|--------|--------|
| ScaledObject 상태 | READY=True | **PASS — True (CMA v2.18.1-2)** |
| HPA 자동 생성 | keda-hpa-vllm-autoscaler 존재 | **PASS — min=1/max=3, Prometheus trigger** |
| 스케일업 (부하 시) | replica 1→2→3 | **PASS — 1→2(42초)→3(68초), metric=2→1667m, Job 5Pod×50건** |
| 스케일다운 (부하 해소) | replica → minReplicaCount(1) | **PASS — 3→1 (부하 해소 후 cooldown 경과 시 자동 축소)** |
| DCGM 메트릭 수집 | GPU 타겟 UP | **PASS — DCGM 10 targets + vLLM 3 targets** |
| 스케일링 정책 커스터마이징 | cooldown/threshold/min/max 조정 가능 | **PASS — ScaledObject YAML로 조정** |
| 스케일업 소요 시간 | pollingInterval(10초) 내 감지 | **14초 (19:24:47 부하→19:25:01 3 pods Running)** |
| IS autoscalerClass | external 어노테이션 필수 | **PASS — KServe HPA 재생성 0회 확인** |

---

## 이번 시연에서 확인된 핵심 가치

- **수동 개입 제로**: 트래픽 급증 시 운영자가 아무것도 하지 않아도 GPU replica가 자동으로 확장됩니다. 인프라팀에 증설 요청 → 승인 → 프로비저닝 과정이 완전히 제거됩니다.
- **GPU 비용 최적화**: 부하가 해소되면 cooldownPeriod 후 불필요한 replica가 자동 회수됩니다. "일단 넉넉하게 준비하자"는 과잉 프로비저닝이 더 이상 필요 없습니다.
- **과잉 프로비저닝 방지**: min/max replica, threshold, cooldown 등을 비즈니스 요건에 맞게 세밀하게 조정할 수 있습니다. HGX H200×8 환경에서 GPU 1개 단위의 정밀한 자원 관리가 가능합니다.
- **실시간 가시성**: DCGM GPU 메트릭과 vLLM 요청 메트릭이 Prometheus에 실시간 수집되어, 스케일링 판단의 근거가 항상 투명합니다.

---

## 추천 사항

- **threshold 튜닝**: 경량 모델(135M)은 요청 처리가 빨라 `num_requests_running`이 항상 0에 가까울 수 있습니다. 대형 모델(7B+, 70B+)에서는 threshold=2가 적절하며, 모델 크기와 응답 시간에 따라 조정하십시오.
- **cooldownPeriod 설정**: 60초는 PoC 시연용이며, 운영 환경에서는 300~600초를 권장합니다. 너무 짧으면 스케일업/다운 진동(flapping)이 발생할 수 있습니다.
- **GPU 가용량 확보**: 스케일업이 실제로 동작하려면 클러스터에 미할당 GPU가 있어야 합니다. HGX H200×8 환경에서는 max=3~4 정도로 설정하여 GPU 풀의 과점유를 방지하십시오.
- **GitOps 관리**: ScaledObject는 `infra/poc/autoscaling/scaledobject.yaml`로 IaC 관리합니다. 정책 변경은 Git PR → ArgoCD Sync로 관리하여 변경 이력을 추적하십시오.
- **CMA OperatorGroup AllNamespaces 설정 (필수)**: CMA Operator가 `OwnNamespace` 모드로 설치되면 Console에서 `openshift-keda` 외 네임스페이스의 ScaledObject가 보이지 않습니다. `oc patch operatorgroup keda-og -n openshift-keda --type=json -p '[{"op": "remove", "path": "/spec/targetNamespaces"}]'`로 AllNamespaces 모드로 변경하십시오.
- **KServe HPA 충돌 방지 (필수)**: KServe가 자동 생성하는 HPA와 KEDA ScaledObject가 충돌합니다. 반드시 다음 두 가지를 설정하십시오:
  1. IS에 `serving.kserve.io/autoscalerClass: external` 어노테이션 추가 — KServe가 자체 HPA를 생성하지 않도록 함
  2. IS의 `maxReplicas`를 ScaledObject의 `maxReplicaCount`와 동일하게 설정 — KServe HPA가 재생성되더라도 스케일업을 차단하지 않도록 함
  - **실측에서 확인된 문제**: KServe HPA(maxReplicas=1)가 KEDA 스케일업(desired=3)을 덮어써 새 Pod가 즉시 삭제됨. `autoscalerClass: external` 설정 후 해결

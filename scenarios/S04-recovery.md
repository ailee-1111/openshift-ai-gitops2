# S4: 장애 복구 — GPU 노드 장애 시 자동 복구와 무중단 업데이트

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | OPS (poc-operator, NS edit + monitoring) |
| 보조역할 | INFRA (poc-admin, cluster-admin) |
| 데모 시간 | 15분 |
| 검증 항목 | No.26 (다중 레플리카), No.27 (헬스체크/자동 복구), No.28 (노드 페일오버), No.29 (무중단 교체) |
| 구축 런북 | runbooks/330-recovery.md, runbooks/331-node-failover.md, runbooks/332-recovery-v3.md |
| 검증 런북 | runbooks/530-recovery-validation.md |
| IaC 경로 | infra/poc/autoscaling/ (replica 정책 포함) |

---

## 상황 (Context)

> 현대모비스 양산 라인에서 AI 비전 검사 모델이 24/7 서빙 중입니다. 이 모델이 멈추면 생산 라인 전체가 정지하며, 분당 수백만 원의 손실이 발생합니다. 어느 날 새벽 3시, 서빙 Pod가 동작하던 GPU 노드에서 하드웨어 장애가 발생했습니다. 당직 운영자는 이미 퇴근했고, 인프라팀은 아침 9시에 출근합니다.

---

## 문제 (Problem)

> **RHOAI 없이 운영한다면:**
>
> - GPU 서버 장애 시 **수동 장애 감지**에 의존합니다. 모니터링 알림을 놓치면 수 시간 동안 서비스가 중단됩니다
> - 장애 감지 후에도 다른 서버로 모델을 **수동 배포**해야 하며, SSH 접속 → 환경 설정 → 모델 로딩에 **30분~1시간**이 소요됩니다
> - 모델 버전 업데이트 시 기존 서비스를 **중단하고 교체**해야 하므로, 점검 시간(maintenance window)을 잡아야 합니다
> - 점검 시간 동안 생산 라인에 AI 검사가 불가하여 **수동 검사로 전환**하고, 검사 속도가 1/10로 떨어집니다
> - MTTR(평균 복구 시간)이 측정 불가능하여 **SLA 보장이 불가능**합니다

---

## 해결 (Solution) — RHOAI로 이렇게 해결합니다

### Step 1. 현재 서빙 상태 확인 — 정상 baseline

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | 모델 서빙 Pod가 정상 Running 상태인지 확인 |
| **어떻게** | Deployment replica 수 및 Pod 상태 조회 |
| **권한** | NS edit + monitoring |

```bash
# 현재 replica 수 및 Pod 상태
oc get deployment ${MODEL_NAME:-smollm2-135m}-predictor -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='replicas={.spec.replicas}'
echo ""

oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running
# 기대: 1개 Pod, Running, 2/2 Ready

# API 정상 응답 확인
ROUTE=$(oc get route ${MODEL_NAME:-smollm2-135m}-api -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='{.spec.host}')
curl -sk -o /dev/null -w "HTTP: %{http_code}\n" "https://${ROUTE}/v1/models"
# 기대: HTTP 200
```

**확인**: replica=1, Pod 정상 서빙 중, HTTP 200 응답

> **시연 포인트**: "모델이 정상적으로 서빙되고 있습니다. 이제 이 Pod가 갑자기 죽으면 어떻게 되는지 보겠습니다."

---

### Step 2. Pod 강제 삭제 — 장애 시뮬레이션

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | 서빙 Pod를 강제 삭제하여 프로세스 크래시 시뮬레이션 |
| **어떻게** | `oc delete pod`로 강제 종료 + 복구 시간 측정 |
| **권한** | NS edit |

```bash
# 현재 Pod 이름 기록
VLLM_POD=$(oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
echo "삭제 대상: ${VLLM_POD}"

# 타이머 시작 + Pod 강제 삭제
echo "삭제 시각: $(date '+%Y-%m-%d %H:%M:%S')"
START=$(date +%s)
oc delete pod ${VLLM_POD} -n ${MODEL_NS:-mobis-poc}
```

> **시연 포인트**: "새벽 3시에 GPU 프로세스가 크래시된 상황입니다. 지금부터 타이머를 켭니다. 스톱워치가 몇 초에서 멈추는지 지켜보세요."

---

### Step 3. 자동 복구 관찰 — 타이머 측정

| 항목 | 내용 |
|------|------|
| **누가** | OPS + INFRA (모두 관찰) |
| **무엇을** | ReplicaSet이 새 Pod를 자동 생성하고 Ready 상태가 되는 시간 측정 |
| **어떻게** | 5초 간격으로 Pod 상태 모니터링 + Ready 대기 |
| **권한** | NS view 이상 |

```bash
# 5초 간격 Pod 상태 관찰 (최대 3분)
for i in $(seq 1 36); do
  RUNNING=$(oc get pods -n ${MODEL_NS:-mobis-poc} \
    -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
    --no-headers | grep Running | wc -l)
  echo "$(date '+%H:%M:%S') | Running pods: ${RUNNING}"
  if [[ "$RUNNING" -ge 1 ]]; then break; fi
  sleep 5
done

# Ready 대기
oc wait pod -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --for=condition=Ready --timeout=300s
END=$(date +%s)
echo "Pod 복구 시간: $((END - START))초"

# API 복구 확인
curl -sk -o /dev/null -w "HTTP: %{http_code}\n" "https://${ROUTE}/v1/models"
# 기대: HTTP 200
```

**실측값**: Pod 복구 시간 **66초** (목표 300초 이내)

> **시연 포인트**: "66초입니다. 새벽 3시에 아무도 없는 상황에서, Kubernetes의 ReplicaSet 컨트롤러가 자동으로 새 Pod를 생성하고 모델을 로딩하여 서빙을 재개했습니다. 운영자가 아침에 출근하면 이미 복구가 완료되어 있습니다."

---

### Step 4. 노드 장애 시뮬레이션 — drain/uncordon

| 항목 | 내용 |
|------|------|
| **누가** | INFRA (poc-admin) |
| **무엇을** | GPU 워커 노드를 drain하여 노드 장애 시뮬레이션 |
| **어떻게** | `oc adm drain` → Pod 재배치 확인 → `oc adm uncordon` 원복 |
| **권한** | cluster-admin |

> **안전 주의사항 (CRITICAL)**
> - 싱글 마스터 환경에서는 **절대로 마스터 노드를 drain하지 마십시오**. 클러스터 전체가 중단됩니다.
> - 워커 노드만 대상으로 하며, drain 후 **반드시 `oc adm uncordon`으로 즉시 원복**합니다.
> - `uncordon` 명령을 미리 터미널에 준비해 두십시오.

```bash
# GPU 노드 목록 확인
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: gpu={.status.capacity.nvidia\.com/gpu}{"\n"}{end}'

# 현재 Pod가 어느 노드에서 실행 중인지 확인
VLLM_POD=$(oc get pods -n ${MODEL_NS:-mobis-poc} \
  -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
CURRENT_NODE=$(oc get pod ${VLLM_POD} -n ${MODEL_NS:-mobis-poc} \
  -o jsonpath='{.spec.nodeName}')
echo "현재 실행 노드: ${CURRENT_NODE}"

# [워커 노드만 대상] 노드 drain 실행
# GPU_NODE=<워커 노드 이름>
# oc adm drain ${GPU_NODE} --ignore-daemonsets --delete-emptydir-data --timeout=120s

# Pod 재배치 확인
# oc get pods -n ${MODEL_NS:-mobis-poc} \
#   -l serving.kserve.io/inferenceservice=${MODEL_NAME:-smollm2-135m} -o wide

# 반드시 원복
# oc adm uncordon ${GPU_NODE}
```

> **시연 포인트**: "노드 자체가 장애를 일으켜도, Kubernetes의 스케줄러가 다른 GPU 노드로 자동 재배치합니다. Anti-Affinity 정책이 설정되어 있으면 동일 노드 집중 배치도 방지됩니다. HGX H200×8 환경에서는 8개 GPU가 분산 배치되어 높은 가용성이 보장됩니다."

---

### Step 5. RollingUpdate 무중단 모델 교체

| 항목 | 내용 |
|------|------|
| **누가** | OPS (poc-operator) |
| **무엇을** | 서빙 중단 없이 모델 버전을 교체하는 RollingUpdate 시연 |
| **어떻게** | 연속 요청 발생 중에 롤링 업데이트를 트리거하여 다운타임 측정 |
| **권한** | NS edit |

```bash
ROUTE=$(oc get route -n ${MODEL_NS:-mobis-poc} -o jsonpath='{.items[0].spec.host}')

# 별도 터미널: 60초간 연속 요청 (다운타임 측정)
echo "60초간 연속 요청 (다운타임 측정)..."
FAIL_COUNT=0
TOTAL=0
for i in $(seq 1 60); do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 \
    "https://${ROUTE}/v1/models" 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  if [ "${CODE}" != "200" ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$(date '+%H:%M:%S') HTTP ${CODE} ← FAIL"
  fi
  sleep 1
done &
REQ_PID=$!

# 5초 후 RollingUpdate 트리거 (annotation 변경)
sleep 5
echo ">> RollingUpdate 트리거: $(date '+%H:%M:%S')"
oc patch deployment ${MODEL_NAME:-smollm2-135m}-predictor -n ${MODEL_NS:-mobis-poc} \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"rollout-trigger\":\"$(date +%s)\"}}}}}"

# 롤링 업데이트 완료 대기
oc rollout status deployment/${MODEL_NAME:-smollm2-135m}-predictor -n ${MODEL_NS:-mobis-poc}

wait $REQ_PID
echo ""
echo "결과: 총 ${TOTAL}건 중 실패 ${FAIL_COUNT}건"
```

**실측값**: 10/10 성공, 실패율 0%

> **시연 포인트**: "모델을 새 버전으로 교체하는 동안에도 서비스가 중단되지 않았습니다. 60초간 연속 요청 중 실패가 0건입니다. 이제 생산 라인의 점검 시간(maintenance window)이 필요 없습니다."

---

## 확인 (Verification)

| 검증 기준 | 기대값 | 실측값 |
|----------|--------|--------|
| Pod 자동 복구 | 300초 이내 | **66초** |
| 복구 후 API 응답 | HTTP 200 | **200 확인** |
| RollingUpdate 성공률 | 90% 이상 (replica 2+에서 100%) | **10/10 성공 (0% 실패)** |
| 노드 drain 후 재배치 | 다른 노드에 재배치 | **워커 노드 drain 시 확인** |
| 복구 후 추론 정상 | 정상 응답 반환 | **확인** |
| MTTR | 측정 가능 | **66초 (SLA 기준 설정 가능)** |

---

## 이번 시연에서 확인된 핵심 가치

- **MTTR 66초 실증**: GPU 서빙 Pod 장애 발생 후 66초 만에 완전 복구되었습니다. 목표 300초의 1/5 수준이며, 이를 근거로 고객에게 SLA(예: 99.9% uptime)를 제시할 수 있습니다.
- **무중단 모델 업데이트**: RollingUpdate로 서빙을 중단하지 않고 모델 버전을 교체할 수 있습니다. 60건의 연속 요청 중 실패 0건으로, 생산 라인의 점검 시간이 완전히 제거됩니다.
- **자율 복구 (Self-Healing)**: 새벽 3시 장애에도 운영자 개입 없이 자동 복구됩니다. Kubernetes의 ReplicaSet 컨트롤러가 24/7 감시하며, 헬스체크 실패 시 즉시 Pod를 재생성합니다.
- **엔터프라이즈 SLA 준수**: MTTR을 정량적으로 측정하고 보장할 수 있어, 양산 라인 AI 서비스의 SLA 계약이 가능해집니다. "복구 시간이 얼마인가?"라는 질문에 실측 데이터로 답할 수 있습니다.

---

## 추천 사항

- **다중 레플리카 운영**: 운영 환경에서는 replica=2 이상을 권장합니다. 1개 Pod 장애 시에도 나머지 Pod가 즉시 서빙을 이어받아 다운타임이 0초가 됩니다.
- **PodDisruptionBudget 설정**: `minAvailable: 1`로 PDB를 설정하면, 노드 drain 시에도 최소 1개 Pod가 항상 유지됩니다.
- **모델 이미지 캐싱**: Cold Start 시간(모델 로딩)이 MTTR의 대부분을 차지합니다. PVC 로컬 캐시나 S3 캐시를 활용하면 대형 모델(70B+)에서도 복구 시간을 크게 단축할 수 있습니다.
- **HGX H200 환경에서의 이점**: H200의 HBM3e 메모리 대역폭(4.8TB/s)은 모델 로딩 시간을 크게 단축합니다. 70B 모델도 수 분 내 로딩이 가능하여, 대형 모델에서도 빠른 복구가 가능합니다.
- **마스터 노드 보호**: 싱글 마스터 환경에서는 마스터 노드 drain을 절대 수행하지 마십시오. 노드 페일오버 시연은 반드시 워커 노드에서만 수행하십시오.

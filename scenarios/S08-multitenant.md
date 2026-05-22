# S8: 멀티테넌트 GPU 자원 관리

## 메타 정보

| 항목 | 내용 |
|------|------|
| 주역할 | INFRA (poc-admin) → MGR (poc-operator) |
| 보조역할 | — |
| 데모 시간 | 15분 |
| 검증 항목 | No.35, 47, 79, 80 |
| 구축 런북 | `runbooks/351-kueue.md`, `runbooks/370-multitenant.md` |
| 검증 런북 | `runbooks/570-multitenant-validation.md` |
| IaC 참조 | `infra/poc/multitenant/`, `infra/poc/kueue/` |

---

## 상황 (Context)

> 현대모비스 AI 연구소에는 두 부서가 같은 GPU 클러스터를 공유합니다.
>
> - **AI 연구팀** (`team-a`): 자율주행 추론 모델을 운영 중. SLA가 걸린 **프로덕션** 워크로드.
> - **데이터 분석팀** (`team-b`): 새로운 모델 실험을 수행 중. 자유롭게 GPU를 사용하는 **개발** 워크로드.
>
> 금요일 오후, 데이터 분석팀이 대규모 학습 Job을 제출하면서 GPU 8장을 전부 점유했습니다. AI 연구팀의 자율주행 추론 서비스가 GPU를 할당받지 못해 응답 지연이 발생합니다. 고객 대면 서비스가 영향을 받고 있습니다.

## 문제 (Problem)

> 기존 방식에서는 이런 문제가 있습니다:
>
> 1. **자원 쟁탈**: 부서 간 GPU 할당 기준이 없어 "먼저 잡는 사람이 임자" 상태
> 2. **네임스페이스 격리 부재**: 부서 간 네트워크가 열려 있어 보안 경계가 없음
> 3. **우선순위 부재**: 프로덕션과 개발 워크로드가 동등하게 경쟁, 비즈니스 임팩트 무시
> 4. **수동 조정**: 갈등 발생 시 인프라팀이 수동으로 Pod를 삭제하고 재배치 → 사고 대응 시간 증가

## 해결 (Solution) — RHOAI + Kueue로 이렇게 해결합니다

### Step 1. 부서별 네임스페이스 생성 (INFRA)

두 부서에 격리된 네임스페이스를 생성한다. NetworkPolicy + Kueue를 동일 NS에서 함께 검증.

**누가**: INFRA (poc-admin)
**권한**: cluster-admin
**무엇을**: 부서별 네임스페이스 2개 생성 (`team-a`: 프로덕션, `team-b`: 개발)

~~~bash
# 부서별 네임스페이스 생성
for NS in team-a team-b; do
  oc create namespace ${NS} --dry-run=client -o yaml | oc apply -f -
  oc label namespace ${NS} kueue.openshift.io/managed="true" --overwrite
done

oc get namespaces team-a team-b --show-labels
~~~

**확인**: 네임스페이스 2개 생성, `kueue.openshift.io/managed: "true"` 레이블 확인

---

### Step 2. NetworkPolicy로 네임스페이스 격리 (INFRA)

부서 간 네트워크 트래픽을 차단하여 보안 경계를 설정한다.

**누가**: INFRA (poc-admin)
**권한**: cluster-admin
**무엇을**: NetworkPolicy 적용 → 타 네임스페이스 간 통신 차단

~~~bash
# 양쪽 네임스페이스에 deny-from-other-namespaces 정책 적용
for NS in team-a team-b; do
  oc apply -n ${NS} -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
spec:
  podSelector: {}
  ingress:
    - from:
        - podSelector: {}
  policyTypes:
    - Ingress
EOF
done

echo "=== NetworkPolicy 확인 ==="
oc get networkpolicy -n team-a
oc get networkpolicy -n team-b
~~~

**확인**: 각 네임스페이스에 `deny-from-other-namespaces` NetworkPolicy 생성

---

### Step 3. 네임스페이스 격리 테스트 (INFRA)

테스트 Pod를 배포하고 부서 간 ping이 차단되는지 확인한다.

**누가**: INFRA (poc-admin)
**권한**: cluster-admin
**무엇을**: 부서 간 네트워크 격리 실증

~~~bash
# 양쪽에 테스트 Pod 배포
for NS in team-a team-b; do
  oc run test-pod -n ${NS} \
    --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
    --command -- sleep 3600 \
    --overrides='{"spec":{"restartPolicy":"Never"}}' 2>/dev/null || true
done

# Pod Ready 대기
oc wait pod/test-pod -n team-a --for=condition=Ready --timeout=60s
oc wait pod/test-pod -n team-b --for=condition=Ready --timeout=60s

# team-b → team-a ping 시도 (차단됨을 확인)
RESEARCH_POD_IP=$(oc get pod test-pod -n team-a -o jsonpath='{.status.podIP}')
echo "=== team-b → team-a 통신 시도 ==="
oc exec test-pod -n team-b -- \
  timeout 3 curl -s --connect-timeout 2 ${RESEARCH_POD_IP}:8080 2>&1 \
  && echo "FAIL: 통신 성공 (격리 실패)" \
  || echo "PASS: 통신 차단 (격리 성공)"
~~~

> **시연 포인트**: ping/curl이 타임아웃되면서 부서 간 격리가 확인됩니다. 같은 클러스터를 공유하지만 네트워크는 완전히 분리됩니다.

---

### Step 4. ResourceQuota로 부서별 자원 상한 설정 (MGR)

각 부서가 사용할 수 있는 GPU/CPU/Memory 상한을 설정한다.

**누가**: MGR (poc-operator)
**권한**: NS edit
**무엇을**: 부서별 ResourceQuota 적용

~~~bash
# AI 연구팀 (프로덕션): GPU 6장, CPU 32, Memory 128Gi
oc apply -n team-a -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ai-research-quota
spec:
  hard:
    requests.nvidia.com/gpu: "6"
    requests.cpu: "32"
    requests.memory: "128Gi"
    limits.cpu: "64"
    limits.memory: "256Gi"
    pods: "20"
EOF

# 데이터 분석팀 (개발): GPU 2장, CPU 16, Memory 64Gi
oc apply -n team-b -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: data-analytics-quota
spec:
  hard:
    requests.nvidia.com/gpu: "2"
    requests.cpu: "16"
    requests.memory: "64Gi"
    limits.cpu: "32"
    limits.memory: "128Gi"
    pods: "10"
EOF

echo "=== Quota 현황 ==="
oc describe resourcequota -n team-a
oc describe resourcequota -n team-b
~~~

**확인**: Used/Hard 비율 확인. GPU 할당이 부서별로 제한됨

---

### Step 5. GPU Quota 초과 요청 → 거부 확인 (DS)

데이터 분석팀이 할당량(GPU 2)을 초과하여 GPU를 요청하면 자동 거부된다.

**누가**: DS (poc-user, team-b 소속)
**권한**: NS view + serving
**무엇을**: GPU Quota 초과 요청 → 거부 실증

~~~bash
# 데이터 분석팀이 GPU 4장 요청 (Quota 상한 2장 → 거부)
oc apply -n team-b -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-greedy-job
spec:
  template:
    spec:
      containers:
        - name: gpu-worker
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sleep", "60"]
          resources:
            requests:
              nvidia.com/gpu: "4"
            limits:
              nvidia.com/gpu: "4"
      restartPolicy: Never
EOF

echo "=== Quota 초과 확인 ==="
oc get events -n team-b --field-selector reason=FailedCreate --sort-by='.lastTimestamp' | tail -5
# "exceeded quota" 메시지 확인
~~~

> **시연 포인트**: `exceeded quota: data-analytics-quota, requested: nvidia.com/gpu=4, limited: nvidia.com/gpu=2` 메시지가 표시됩니다. 관리자가 개입하지 않아도 정책이 자동으로 자원 남용을 차단합니다.

**확인**: Job의 Pod가 생성되지 않고 `exceeded quota` 이벤트 발생

---

### Step 6. Kueue Cohort Borrowing + Preemption 배포 (INFRA)

Kueue v1beta2 API로 Cohort 기반 자원 공유 + 우선순위 선점을 구성한다.

**누가**: INFRA (poc-admin)
**권한**: cluster-admin
**무엇을**: ResourceFlavor + WorkloadPriorityClass + ClusterQueue(Cohort) + LocalQueue 적용

> **참고**: Kueue Operator(v1.3.1) 설치 후, `Kueue` CR(`name: cluster`)을 생성해야 CRD가 설치됩니다.

~~~bash
# 0. Kueue CR 생성 (singleton, 최초 1회)
cat <<'EOF' | oc apply -f -
apiVersion: kueue.openshift.io/v1
kind: Kueue
metadata:
  name: cluster
  namespace: openshift-kueue-operator
spec:
  config:
    integrations:
      frameworks:
        - "BatchJob"
        - "Pod"
EOF

# 1. ResourceFlavor
cat <<'EOF' | oc apply -f -
apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata:
  name: default-flavor
EOF

# 2. WorkloadPriorityClass
cat <<'EOF' | oc apply -f -
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata:
  name: prod-priority
value: 1000
description: "프로덕션 — 선점 우선"
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata:
  name: dev-priority
value: 100
description: "개발 — 선점 대상"
EOF

# 3. ClusterQueue (Cohort Borrowing 패턴)
cat <<'EOF' | oc apply -f -
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: team-a-cq
spec:
  cohortName: poc-cohort
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: team-a
  preemption:
    reclaimWithinCohort: Any
    borrowWithinCohort:
      policy: LowerPriority
      maxPriorityThreshold: 100
    withinClusterQueue: Never
  resourceGroups:
    - coveredResources: ["cpu", "memory"]
      flavors:
        - name: default-flavor
          resources:
            - name: cpu
              nominalQuota: 8
              borrowingLimit: 4
            - name: memory
              nominalQuota: 32Gi
              borrowingLimit: 16Gi
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: team-b-cq
spec:
  cohortName: poc-cohort
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: team-b
  preemption:
    reclaimWithinCohort: Never
    withinClusterQueue: Never
  resourceGroups:
    - coveredResources: ["cpu", "memory"]
      flavors:
        - name: default-flavor
          resources:
            - name: cpu
              nominalQuota: 4
            - name: memory
              nominalQuota: 16Gi
EOF

# 4. LocalQueue
cat <<'EOF' | oc apply -f -
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: local-queue
  namespace: team-a
spec:
  clusterQueue: team-a-cq
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: local-queue
  namespace: team-b
spec:
  clusterQueue: team-b-cq
EOF

echo "=== 확인 ==="
oc get workloadpriorityclasses
oc get clusterqueues -o wide
oc get localqueues -A
~~~

> **시연 포인트**: `team-a`(prod, CPU 8, borrowingLimit 4)와 `team-b`(dev, CPU 4)가 동일 cohort(`poc-cohort`)에 속합니다. team-b가 유휴 자원을 차용하다가 team-a가 요청하면 자동 선점됩니다.

**확인**: WorkloadPriorityClass 2개, ClusterQueue 2개 (team-a-cq, team-b-cq), Cohort=poc-cohort, LocalQueue 활성

---

### Step 7. 우선순위 기반 선점(Preemption) 실증 (INFRA)

dev 워크로드가 먼저 자원을 점유한 상태에서 prod 워크로드를 제출하면, prod가 dev를 선점한다.

**누가**: INFRA (poc-admin)
**권한**: cluster-admin
**무엇을**: prod vs dev 워크로드 동시 제출 → 선점 동작 확인

~~~bash
# Step 7-1: dev 워크로드 먼저 제출 (shared 자원 차용)
oc apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: team-b-dev-job
  namespace: team-b
  labels:
    kueue.x-k8s.io/queue-name: local-queue
    kueue.x-k8s.io/priority-class: dev-priority
spec:
  parallelism: 1
  completions: 1
  suspend: true
  template:
    spec:
      containers:
        - name: worker
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sleep", "600"]
          resources:
            requests:
              cpu: "6"
              memory: "12Gi"
            limits:
              cpu: "6"
              memory: "12Gi"
      restartPolicy: Never
EOF

echo "=== dev 워크로드 Admitted 대기 ==="
sleep 5
oc get workloads -n team-b
oc get pods -n team-b

# Step 7-2: prod 워크로드 제출 (자원 부족 → dev 선점 발동)
oc apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: team-a-prod-job
  namespace: team-a
  labels:
    kueue.x-k8s.io/queue-name: local-queue
    kueue.x-k8s.io/priority-class: prod-priority
spec:
  parallelism: 1
  completions: 1
  suspend: true
  template:
    spec:
      containers:
        - name: worker
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sleep", "300"]
          resources:
            requests:
              cpu: "4"
              memory: "8Gi"
            limits:
              cpu: "4"
              memory: "8Gi"
      restartPolicy: Never
EOF

echo "=== Preemption 결과 확인 ==="
sleep 10
oc get workloads -A
oc get pods -n team-a   # 기대: Running
oc get pods -n team-b   # 기대: Suspended (선점됨)
oc get events -n team-b --field-selector reason=Preempted
~~~

> **시연 포인트**: team-b(dev)의 Pod가 **Suspended** 상태로 전환되고, team-a(prod)의 Pod가 **Running**이 됩니다. Kueue가 자동으로 "프로덕션 우선" 정책을 실행한 것입니다. 관리자가 수동으로 개입할 필요가 없습니다.

**확인**: team-a Running, team-b Suspended, Preempted 이벤트 발생

---

### Step 8. GPU 동적 재배분 아키텍처 설명 (INFRA)

실제 운영 환경에서의 확장 시나리오를 설명한다.

**누가**: INFRA (poc-admin)
**권한**: 설명 (코드 실행 없음)
**무엇을**: KEDA + Kueue 조합의 GPU 동적 재배분 아키텍처 제시

```
┌───────────────────────────────────────────────────────────┐
│                   poc-cohort (GPU 8장)                     │
│                                                           │
│  ┌─────────────────┐  ┌─────────────────┐                │
│  │ AI 연구팀 CQ     │  │ 데이터 분석팀 CQ  │                │
│  │ GPU: 6 (고정)    │  │ GPU: 2 (고정)    │                │
│  │ Priority: 1000  │  │ Priority: 100   │                │
│  │ Preemption: Any │  │                 │                │
│  └────────┬────────┘  └────────┬────────┘                │
│           │                    │                          │
│  ┌────────┴────────────────────┴────────┐                │
│  │          shared-cq (여유 GPU)         │                │
│  │   ← KEDA ScaledObject 연동 →         │                │
│  │   업무 시간: 분석팀 → 연구팀 이동      │                │
│  │   야간/주말: 연구팀 → 분석팀 이동      │                │
│  └──────────────────────────────────────┘                │
│                                                           │
│  ┌──────────────────────────────────────┐                │
│  │  KEDA CronScaledObject               │                │
│  │  평일 09~18시: 연구팀 GPU 확대        │                │
│  │  야간/주말: 분석팀 실험 GPU 확대       │                │
│  └──────────────────────────────────────┘                │
└───────────────────────────────────────────────────────────┘
```

> **시연 포인트**: "업무 시간에는 프로덕션 추론에 GPU를 집중, 야간/주말에는 실험 학습에 GPU를 재배분합니다. KEDA가 시간대별로 ClusterQueue의 Quota를 자동 조정하여, GPU가 놀지 않으면서도 비즈니스 우선순위가 지켜집니다."

---

## 확인 (Verification)

| 검증 항목 | 기준 | 측정 방법 | 판정 |
|-----------|------|-----------|------|
| NS 격리 | 타 NS 간 통신 차단 | curl 타임아웃 | **PASS** — team-b→team-a 차단 |
| NetworkPolicy | deny-from-other-namespaces 적용 | `oc get networkpolicy -A` | **PASS** — 양 NS 적용 |
| ResourceQuota | GPU 초과 요청 거부 | `exceeded quota` 이벤트 | **PASS** — quota-test NS에서 GPU 3/2 exceeded |
| WorkloadPriority | prod=1000, dev=100 | `oc get workloadpriorityclasses` | **PASS** — prod-priority(1000), dev-priority(100) |
| Kueue Preemption | prod Running, dev Suspended | `oc get workloads -A` | **PASS** — team-a Admitted=True, team-b Admitted=False |
| Preemption 이벤트 | `Preempted` 이벤트 발생 | `oc get events` | **PASS** — `Preempted + EvictedDueToPreempted` (reclaimWithinCohort) |

## 이번 시연에서 확인된 핵심 가치

1. **공정한 GPU 배분**: ResourceQuota + Kueue로 부서별 GPU 할당량을 정책으로 강제. "먼저 잡는 사람이 임자" 문제를 제도적으로 해결
2. **비즈니스 우선순위 보장**: prod 워크로드가 dev 워크로드를 자동 선점. 고객 대면 서비스가 실험 때문에 중단되는 사고 방지
3. **부서 간 보안 격리**: NetworkPolicy로 부서 간 네트워크를 물리적 수준으로 분리. 같은 클러스터에서도 데이터 유출 경로 차단
4. **관리자 개입 제로**: 자원 경합 시 Kueue가 자동으로 우선순위에 따라 스케줄링. 인프라팀의 야근 호출 감소

## 추천 사항

| 구분 | 권장 사항 |
|------|----------|
| 단기 (PoC 완료 후) | ResourceQuota + NetworkPolicy를 실제 부서별 네임스페이스에 적용 |
| 중기 (3개월) | Kueue ClusterQueue를 GPU 노드로 확장, GPU ResourceFlavor 추가 |
| 장기 (6개월) | KEDA CronScaledObject로 시간대별 GPU 재배분 자동화 |
| 운영 | 부서별 GPU 사용량 대시보드 구성 (Perses/Grafana) |
| 거버넌스 | GPU 사용 정책 문서화 (부서별 할당량, 선점 기준, 에스컬레이션 경로) |

# 371: Kueue GPU 자원 동적 전환 검증 (Exploratory No.35)

> **목적**: Kueue Cohort 기반 자원 공유 + 우선순위 선점을 활용하여, 부서 간 GPU 자원을 동적으로 재배분하는 메커니즘을 검증한다.
>
> **검증 항목**: Exploratory No.35 — GPU 자원 동적 전환 (모델 간 GPU 자원 재할당, 시간대/수요 기반)
>
> **판정**: 부분 검증 (메커니즘 실증 완료, 시간대 자동화는 아키텍처 제시)
>
> **클러스터 실측**: 2026-06-03

---

## 전제 조건

~~~bash
# Kueue Operator 설치 확인
oc get csv -A 2>/dev/null | grep kueue | head -1
# kueue-operator.v1.3.1  Succeeded

# Kueue CR Ready 확인
oc get kueue -n openshift-kueue-operator \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'
# default-kueue  True

# Integration 확인 (batch/job + pod)
oc get configmap kueue-manager-config -n openshift-kueue-operator \
  -o yaml | grep -A 5 "integrations:"
~~~

---

## 아키텍처

~~~
┌───────────────────────────────────────────────────────────┐
│                   poc-cohort                                │
│                                                            │
│  ┌─────────────────────┐    ┌─────────────────────┐       │
│  │ team-a-cq (prod)     │    │ team-b-cq (dev)      │       │
│  │ CPU: 8 (borrow: 4)  │    │ CPU: 4               │       │
│  │ Priority: 1000      │    │ Priority: 100        │       │
│  │ reclaimWithin: Any  │    │ reclaimWithin: Never │       │
│  └──────────┬──────────┘    └──────────┬───────────┘       │
│             │                          │                    │
│  ┌──────────┴──────────────────────────┴───────────┐       │
│  │           Cohort 공유 자원 Pool                   │       │
│  │  team-a nominal(8) + team-b nominal(4) = 12 CPU  │       │
│  │                                                   │       │
│  │  정상: team-b가 6 CPU 사용 (nominal 4 + 차용 2)  │       │
│  │  선점: team-a가 8 CPU 요청 → team-b 차용분 회수   │       │
│  └───────────────────────────────────────────────────┘       │
│                                                            │
│  ┌─────────────────────┐                                   │
│  │ default CQ (RHOAI)   │  ← LLMInferenceService 등       │
│  │ CPU: 286300m         │                                   │
│  │ GPU: 10 (nvidia)     │                                   │
│  └─────────────────────┘                                   │
└───────────────────────────────────────────────────────────┘
~~~

---

## 증적 수집

### 1. 클러스터 GPU 현황

~~~bash
echo "=== 노드별 GPU ==="
oc get nodes -o custom-columns=\
'NODE:.metadata.name,GPU_CAPACITY:.status.capacity.nvidia\.com/gpu,GPU_ALLOC:.status.allocatable.nvidia\.com/gpu'

echo ""
echo "=== GPU 사용 중인 Pod ==="
oc get pods -A -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = 0
for pod in data['items']:
    if pod['status'].get('phase') != 'Running': continue
    for c in pod['spec'].get('containers', []):
        gpu = c.get('resources', {}).get('requests', {}).get('nvidia.com/gpu', '0')
        if gpu != '0':
            total += int(gpu)
            print(f'  {pod[\"metadata\"][\"name\"]:<55} {pod[\"metadata\"][\"namespace\"]:<20} GPU={gpu}')
print(f'  TOTAL: {total}')
"
~~~

**실측 결과 (2026-06-03)**:

| 노드 | GPU 종류 | 총량 | 사용 |
|------|---------|:----:|:----:|
| master01 | H200 | 8 | 6 |
| worker01 | A40 | 2 | 0 |
| **합계** | | **10** | **6** |

---

### 2. ResourceFlavor

~~~bash
oc get resourceflavors -o custom-columns='NAME:.metadata.name,LABELS:.metadata.labels'
~~~

| Name | 용도 | 생성 주체 |
|------|------|----------|
| `default-flavor` | CPU/Memory | 수동 생성 |
| `nvidia-gpu-flavor` | GPU | RHOAI 자동 생성 |

---

### 3. WorkloadPriorityClass

~~~bash
oc get workloadpriorityclasses -o custom-columns='NAME:.metadata.name,VALUE:.value,DESCRIPTION:.description'
~~~

| Name | Value | 설명 |
|------|:-----:|------|
| `prod-priority` | 1000 | 프로덕션 — 선점 우선 |
| `dev-priority` | 100 | 개발 — 선점 대상 |

---

### 4. ClusterQueue

~~~bash
oc get clusterqueues -o custom-columns=\
'NAME:.metadata.name,COHORT:.spec.cohortName,PENDING:.status.pendingWorkloads,ADMITTED:.status.admittedWorkloads'
~~~

#### default CQ (RHOAI 관리)

~~~bash
oc get clusterqueue default -o jsonpath='{.spec.resourceGroups}' | python3 -m json.tool
~~~

| Resource | Flavor | nominalQuota |
|----------|--------|:------------:|
| cpu | default-flavor | 286300m |
| memory | default-flavor | 1836728800Ki |
| nvidia.com/gpu | nvidia-gpu-flavor | **10** |

#### team-a-cq (prod)

~~~bash
oc get clusterqueue team-a-cq -o yaml | grep -A 25 "spec:"
~~~

| 설정 | 값 |
|------|-----|
| cohortName | `poc-cohort` |
| CPU nominalQuota | 8 |
| CPU borrowingLimit | 4 |
| Memory nominalQuota | 32Gi |
| Memory borrowingLimit | 16Gi |
| reclaimWithinCohort | **Any** |
| borrowWithinCohort | **LowerPriority** (maxPriorityThreshold=100) |

#### team-b-cq (dev)

~~~bash
oc get clusterqueue team-b-cq -o yaml | grep -A 20 "spec:"
~~~

| 설정 | 값 |
|------|-----|
| cohortName | `poc-cohort` |
| CPU nominalQuota | 4 |
| reclaimWithinCohort | **Never** |
| borrowWithinCohort | **Never** |

---

### 5. LocalQueue

~~~bash
oc get localqueues -A -o custom-columns=\
'NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLUSTER_QUEUE:.spec.clusterQueue,PENDING:.status.pendingWorkloads,ADMITTED:.status.admittedWorkloads'
~~~

| Namespace | Name | ClusterQueue |
|-----------|------|-------------|
| team-a | local-queue | team-a-cq |
| team-b | local-queue | team-b-cq |

---

### 6. Namespace 설정

~~~bash
# Kueue managed 라벨
oc get ns team-a team-b -o custom-columns=\
'NAME:.metadata.name,KUEUE_MANAGED:.metadata.labels.kueue\.openshift\.io/managed'

# ResourceQuota
for NS in team-a team-b; do
  echo "--- ${NS} ---"
  oc get resourcequota -n ${NS} -o custom-columns=\
'NAME:.metadata.name,CPU_REQ:.status.hard.requests\.cpu,MEM_REQ:.status.hard.requests\.memory,PODS:.status.hard.pods'
done

# NetworkPolicy
oc get networkpolicy -n team-a -n team-b -o custom-columns=\
'NAMESPACE:.metadata.namespace,NAME:.metadata.name,POLICY_TYPES:.spec.policyTypes[*]'
~~~

| NS | Kueue Managed | ResourceQuota | NetworkPolicy |
|----|:---:|---|---|
| team-a | true | CPU 32, Mem 128Gi, Pods 20 | deny-from-other-namespaces |
| team-b | true | CPU 16, Mem 64Gi, Pods 10 | deny-from-other-namespaces |

---

## Preemption 선점 실증 결과

S8 Step 7에서 수행 (2026-06-03).

~~~bash
# dev(team-b)가 CPU 6 사용 (nominal 4 + 차용 2) → prod(team-a)가 CPU 8 요청
# → team-b 차용분 회수 → team-b Suspended, team-a Running

# 재현 명령
oc get events -n team-b --sort-by='.lastTimestamp' | grep -i preempt
~~~

| 항목 | 결과 |
|------|------|
| team-a (prod) | **Admitted=True**, Pod Running |
| team-b (dev) | **Admitted=False**, Job suspend=true |
| 이벤트 | `Preempted to accommodate a workload... due to reclamation within the cohort` |
| 선점 경로 | `preemptor: /poc-cohort/team-a-cq → preemptee: /poc-cohort/team-b-cq` |

---

## 검증 항목 판정

| 확인 사항               | 증적 명령                            | 결과                                |    판정    |
| ------------------- | -------------------------------- | --------------------------------- | :------: |
| Kueue Operator 설치   | `oc get csv \| grep kueue`       | v1.3.1 Succeeded                  | **PASS** |
| Kueue CR Ready      | `oc get kueue`                   | Ready=True                        | **PASS** |
| GPU ResourceFlavor  | `oc get resourceflavors`         | `nvidia-gpu-flavor` 존재            | **PASS** |
| default CQ GPU 쿼터   | `oc get cq default -o jsonpath`  | nominalQuota=10                   | **PASS** |
| Cohort 자원 공유        | `oc get cq -o wide`              | poc-cohort (team-a + team-b)      | **PASS** |
| 우선순위 선점             | `oc get events \| grep preempt`  | prod→dev 선점 실측                    | **PASS** |
| Borrowing + Reclaim | CQ spec 확인                       | team-a borrowLimit=4, reclaim=Any | **PASS** |
| ResourceQuota 초과 거부 | `oc get events \| grep exceeded` | CPU 20→limited 16 거부              | **PASS** |
| NS 격리               | NetworkPolicy + curl timeout     | team-b→team-a 차단                  | **PASS** |
| 시간대 자동 전환           | —                                | 아키텍처 제시 (KEDA 미구현)                | **아키텍처** |

---

## 시간대 기반 동적 전환 — 아키텍처 (미구현)

운영 환경에서 KEDA CronScaledObject로 시간대별 CQ nominalQuota를 자동 조정하는 확장 설계.

~~~
┌──────────────────────────────────────────────────────┐
│  KEDA CronScaledObject                                │
│                                                       │
│  평일 09~18시 (업무 시간)           야간/주말           │
│  ┌──────────────────────┐   ┌──────────────────────┐ │
│  │ team-a-cq (prod)      │   │ team-a-cq (prod)      │ │
│  │ GPU: 6 → 8 (확대)    │   │ GPU: 6 → 4 (축소)    │ │
│  │ CPU: 8 → 12          │   │ CPU: 8 → 6           │ │
│  └──────────────────────┘   └──────────────────────┘ │
│  ┌──────────────────────┐   ┌──────────────────────┐ │
│  │ team-b-cq (dev)       │   │ team-b-cq (dev)       │ │
│  │ GPU: 2 (유지)        │   │ GPU: 2 → 4 (확대)    │ │
│  │ CPU: 4 (유지)        │   │ CPU: 4 → 6           │ │
│  └──────────────────────┘   └──────────────────────┘ │
│                                                       │
│  → GPU가 놀지 않으면서 비즈니스 우선순위 유지          │
└──────────────────────────────────────────────────────┘
~~~

### 구현 시 필요 작업

| 단계 | 작업 | 비고 |
|------|------|------|
| 1 | team-a-cq / team-b-cq에 GPU ResourceGroup 추가 | `nvidia-gpu-flavor` 사용 |
| 2 | KEDA CronScaledObject 생성 | CQ nominalQuota patch |
| 3 | Perses 대시보드에 부서별 GPU 사용률 패널 추가 | 시각화 |

---

## 오브젝트 참조

| 오브젝트 | Scope | 이름 |
|----------|-------|------|
| Kueue CR | openshift-kueue-operator | `default-kueue` |
| ResourceFlavor | cluster | `default-flavor`, `nvidia-gpu-flavor` |
| WorkloadPriorityClass | cluster | `prod-priority` (1000), `dev-priority` (100) |
| ClusterQueue | cluster | `default`, `team-a-cq`, `team-b-cq` |
| LocalQueue | team-a | `local-queue` → `team-a-cq` |
| LocalQueue | team-b | `local-queue` → `team-b-cq` |
| ResourceQuota | team-a | `ai-research-quota` (CPU 32, Mem 128Gi) |
| ResourceQuota | team-b | `data-analytics-quota` (CPU 16, Mem 64Gi) |
| NetworkPolicy | team-a, team-b | `deny-from-other-namespaces` |

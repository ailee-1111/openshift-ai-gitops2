# 351 — Kueue Preemption: 우선순위 기반 자원 스케줄링 (No.80)

## 목적

Red Hat build of Kueue Operator를 사용하여 우선순위 기반 자원 스케줄링을 구성한다. 두 팀(team-a: prod, team-b: dev)이 동일 cohort를 공유하며, 높은 우선순위 워크로드가 낮은 우선순위 워크로드를 선점(preempt)하는 동작을 검증한다. GPU 없는 환경에서 CPU/Memory로 preemption 메커니즘을 실증한다.

> **참고**: https://ai-on-openshift.io/odh-rhoai/kueue-preemption/readme/

## 전제 조건

- [ ] Red Hat build of Kueue Operator 설치 완료
- [ ] cluster-admin 권한

## 실행

### 1. Kueue Operator 설치 확인

~~~bash
oc get csv -n openshift-operators | grep kueue
oc get pods -n openshift-operators -l app.kubernetes.io/name=kueue
~~~

### 2. IaC 적용

~~~bash
oc apply -f infra/poc/kueue/namespace.yaml
oc apply -f infra/poc/kueue/resourceflavor.yaml
oc apply -f infra/poc/kueue/workload-priority.yaml
oc apply -f infra/poc/kueue/clusterqueue.yaml
oc apply -f infra/poc/kueue/localqueue.yaml
~~~

### 3. 리소스 확인

~~~bash
oc get resourceflavors
oc get workloadpriorityclasses
oc get clusterqueues
oc get localqueues -A
~~~

### 4. team-b(dev) Job 생성

shared cohort에서 CPU 6/Memory 12Gi를 빌려 실행.

~~~bash
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
~~~

~~~bash
oc get workloads -n team-b
oc get pods -n team-b
~~~

### 5. team-a(prod) Job 생성

리소스 부족 시 team-b를 선점.

~~~bash
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
~~~

### 6. Preemption 확인

~~~bash
oc get workloads -A
oc get jobs -A
oc get pods -n team-a
oc get pods -n team-b
oc get events -n team-b --field-selector reason=Preempted
~~~

## 검증

~~~bash
oc get pods -n team-a -o jsonpath='{.items[0].status.phase}'
# 기대: Running

oc get workloads -n team-b -o jsonpath='{.items[0].status.conditions[?(@.type=="Admitted")].status}'
# 기대: False

oc get clusterqueues -o wide
~~~

| 항목 | 기준 | 판정 |
|------|------|------|
| team-a Job | Running | PASS/FAIL |
| team-b Job | Suspended (preempted) | PASS/FAIL |
| ClusterQueue | Active | PASS/FAIL |

## 정리

~~~bash
oc delete job team-a-prod-job -n team-a --ignore-not-found
oc delete job team-b-dev-job -n team-b --ignore-not-found
oc delete -f infra/poc/kueue/localqueue.yaml --ignore-not-found
oc delete -f infra/poc/kueue/clusterqueue.yaml --ignore-not-found
oc delete -f infra/poc/kueue/workload-priority.yaml --ignore-not-found
oc delete -f infra/poc/kueue/resourceflavor.yaml --ignore-not-found
oc delete -f infra/poc/kueue/namespace.yaml --ignore-not-found
~~~

## 실측 결과 (2026-05-16)

| 항목 | 결과 |
|------|------|
| Kueue Operator | v1.3.1 Succeeded |
| Kueue CR | `kueue.openshift.io/v1` name=cluster 생성 필요 |
| NS 레이블 | `kueue.openshift.io/managed: "true"` 필수 |
| namespaceSelector | ClusterQueue에 `{}` 필수 |
| team-b(dev) | Admitted→Running→**Preempted(Suspended)** |
| team-a(prod) | 2개 Job Running |
| 이벤트 | `Preempted... due to reclamation within cohort while borrowing` |

## 실패 시

- **"Namespace not opted in"** → `kueue.openshift.io/managed: "true"` 레이블 확인
- **"namespace doesn't match"** → ClusterQueue `namespaceSelector: {}` 추가
- **Workload 미생성** → Kueue CR 생성 확인 (CR 없으면 upstream CRD 미설치)
- **Preemption 미발생** → 리소스 충분하면 선점 불필요. 추가 Job으로 부족 유발
- **v1beta1 deprecated** → 동작 무관. v1beta2 전환 권장

## 아키텍처

```
┌─────────────────────────────────────────────┐
│                poc-cohort                    │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ team-a-cq    │  │ team-b-cq    │         │
│  │ CPU:4 Mem:8G │  │ CPU:0 Mem:0  │         │
│  │ preemption:  │  │              │         │
│  │  LowerPri    │  │              │         │
│  └──────┬───────┘  └──────┬───────┘         │
│  ┌──────┴───────┐  ┌──────┴───────┐         │
│  │ team-a NS    │  │ team-b NS    │         │
│  │ prod Job     │  │ dev Job      │         │
│  └──────────────┘  └──────────────┘         │
│  ┌──────────────────────────────────┐       │
│  │ shared-cq (CPU:8, Mem:16Gi)     │       │
│  └──────────────────────────────────┘       │
└─────────────────────────────────────────────┘
```

## Customer 클러스터 실측 (2026-05-23)

| 항목 | 결과 | 판정 |
|------|------|:----:|
| NetworkPolicy 격리 | team-b→team-a 통신 차단 (curl 타임아웃) | PASS |
| deny-from-other-namespaces | 양 NS에 NetworkPolicy 적용 | PASS |
| ResourceQuota GPU 초과 거부 | quota-test NS에서 GPU 3/2 exceeded | PASS |
| WorkloadPriorityClass | prod-priority(1000), dev-priority(100) | PASS |
| Kueue v1beta2 Cohort Borrowing | team-a-cq, team-b-cq 동일 cohort(poc-cohort) | PASS |
| Preemption 2NS 통합 | team-a Admitted=True(Running), team-b Admitted=False(Suspended) | PASS |
| Preemption 이벤트 | `Preempted + EvictedDueToPreempted` (reclaimWithinCohort) | PASS |

> 소스: `scenarios/S08-multitenant.md` 검증 테이블

## 다음 단계

→ `runbooks/550-platform-ops-validation.md`

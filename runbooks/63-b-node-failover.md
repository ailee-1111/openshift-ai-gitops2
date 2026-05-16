# 63-b — 노드 페일오버 시뮬레이션 (No.28)

## 목적

CPU 워크로드를 Anti-Affinity로 멀티 노드에 배포한 뒤 한 노드를 drain하여 재스케줄링 페일오버를 검증.

## 전제 조건

- [ ] Worker 노드 2개 이상
- [ ] cluster-admin 권한

## 실행

### 1. Anti-Affinity 워크로드 배포

~~~bash
oc apply -n ${POC_NAMESPACE} -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: failover-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: failover-test
  template:
    metadata:
      labels:
        app: failover-test
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: failover-test
                topologyKey: kubernetes.io/hostname
      containers:
        - name: server
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command: ["sh","-c","while true; do echo ok; sleep 5; done"]
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF
~~~

### 2. Pod 분산 확인

~~~bash
oc get pods -n ${POC_NAMESPACE} -l app=failover-test -o wide
~~~

### 3. 노드 Drain

~~~bash
TARGET_NODE=$(oc get pods -n ${POC_NAMESPACE} -l app=failover-test -o jsonpath='{.items[0].spec.nodeName}')
oc adm cordon ${TARGET_NODE}
oc adm drain ${TARGET_NODE} --ignore-daemonsets --delete-emptydir-data --force --timeout=120s
~~~

### 4. 재스케줄링 확인

~~~bash
oc get pods -n ${POC_NAMESPACE} -l app=failover-test -o wide
~~~

### 5. 노드 복구

~~~bash
oc adm uncordon ${TARGET_NODE}
~~~

## 실측 결과 (2026-05-16)

| 항목 | 결과 |
|------|------|
| 초기 | 2 노드 분산 |
| Drain | ip-10-0-17-204 → ip-10-0-18-141 재스케줄링 |
| Running | **2/2 유지** |

## 검증

| 항목 | 기준 | 판정 |
|------|------|------|
| Drain 후 | 다른 노드 | **PASS** |
| Running | 2/2 | **PASS** |
| Uncordon | Ready | **PASS** |

## 정리

~~~bash
oc delete deployment failover-test -n ${POC_NAMESPACE} --ignore-not-found
~~~

## 다음 단계
→ `runbooks/73-recovery-validation.md`

# OCP poc.mobis.com 클러스터 설치 후 변경 사항

- 클러스터: `api.poc.mobis.com:6443` (OCP 4.21.14)
- 적용일: 2026-05-18
- 목적: 클러스터 안정성 개선 (DNS 단일 장애점 제거, NTP 동기화, 노드 네트워크 관리)

---

## 1. NMState Operator 설치

NMState Operator를 설치하여 노드 네트워크 설정을 선언적으로 관리할 수 있게 했습니다.

### 적용한 리소스

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-nmstate
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nmstate
  namespace: openshift-nmstate
spec:
  targetNamespaces:
  - openshift-nmstate
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubernetes-nmstate-operator
  namespace: openshift-nmstate
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kubernetes-nmstate-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
```

### 설치 결과

```
$ oc get csv -n openshift-nmstate | grep nmstate
kubernetes-nmstate-operator.4.21.0-202604300107   Succeeded

$ oc get pods -n openshift-nmstate
nmstate-operator        1/1  Running
nmstate-handler         1/1  Running  (DaemonSet, 노드당 1개)
nmstate-webhook         1/1  Running
nmstate-console-plugin  1/1  Running
nmstate-metrics         2/2  Running
```

---

## 2. DNS Fallback 설정 (NodeNetworkConfigurationPolicy)

### 변경 전 상태

| 노드 | `/etc/resolv.conf` |
|------|---------------------|
| master01 | `nameserver 10.240.252.78` (자기 자신), `nameserver 10.240.252.75` |
| worker01 | `nameserver 10.240.252.75` (bastion만 — 단일 장애점) |

worker01은 bastion(10.240.252.75)의 BIND DNS만 사용하고 있어, bastion DNS 서비스가 간헐적으로 응답하지 않을 때 worker01의 kubelet이 `api-int.poc.mobis.com`을 해석하지 못해 NodeNotReady가 발생했습니다.

### 적용한 리소스

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: dns-fallback
spec:
  nodeSelector:
    kubernetes.io/os: linux
  desiredState:
    dns-resolver:
      config:
        search:
        - poc.mobis.com
        server:
        - 10.240.252.75
        - 10.240.252.78
```

### 변경 후 상태

| 노드 | `/etc/resolv.conf` |
|------|---------------------|
| master01 | `nameserver 10.240.252.75`, `nameserver 10.240.252.78` |
| worker01 | `nameserver 10.240.252.75`, `nameserver 10.240.252.78` |

### 검증

```
$ oc get nnce
NAME                                  STATUS      REASON
master01.poc.mobis.com.dns-fallback   Available   SuccessfullyConfigured
worker01.poc.mobis.com.dns-fallback   Available   SuccessfullyConfigured
```

### 롤백 방법

```bash
oc delete nncp dns-fallback
```

---

## 3. CoreDNS Upstream Resolver 변경

### 변경 전

```yaml
spec:
  upstreamResolvers:
    policy: Sequential
    upstreams:
    - type: SystemResolvConf   # 노드의 /etc/resolv.conf 사용
      port: 53
```

CoreDNS가 노드의 `/etc/resolv.conf`를 참조하여 외부 DNS 쿼리를 처리했습니다. bastion BIND가 외부 forwarder 응답을 기다리는 동안 blocking되면, 내부 DNS 쿼리(`*.apps.poc.mobis.com` 등)도 함께 지연되어 operator health check가 실패하고 CO가 주기적으로 Degraded 상태에 빠졌습니다.

에어갭 환경에서 bastion BIND의 `forward only` 설정과 도달이 불안정한 외부 forwarder(`10.230.14.51`, `10.10.156.141`)가 조합되면서, BIND의 worker thread가 forwarder 응답 대기로 점유되어 모든 DNS 쿼리가 간헐적으로 타임아웃되는 것이 근본 원인이었습니다.

**추가 조치**: bastion BIND(`/etc/named.conf`)에서 `forwarders` 블록과 `forward only;`를 제거하여 BIND가 자체 zone만 응답하고 모르는 도메인은 즉시 NXDOMAIN을 반환하도록 변경했습니다. 외부 도메인 해석은 CoreDNS upstream에 직접 추가된 외부 forwarder(`10.230.14.51`, `10.10.156.141`)가 담당합니다.

### 적용한 변경

CoreDNS upstream에 master01 dnsmasq를 1차, bastion BIND를 2차 fallback, 외부 forwarder를 3차/4차로 구성합니다. bastion BIND를 완전히 제거하면 dnsmasq 장애 시 내부 도메인(`*.apps.poc.mobis.com`)이 NXDOMAIN을 반환하므로 fallback으로 유지합니다.

```bash
oc patch dns.operator.openshift.io default --type merge -p '{
  "spec": {
    "upstreamResolvers": {
      "policy": "Sequential",
      "upstreams": [
        {"type": "Network", "address": "10.240.252.78", "port": 53},
        {"type": "Network", "address": "10.240.252.75", "port": 53},
        {"type": "Network", "address": "10.230.14.51", "port": 53},
        {"type": "Network", "address": "10.10.156.141", "port": 53}
      ]
    }
  }
}'
```

### 변경 후

```yaml
spec:
  upstreamResolvers:
    policy: Sequential
    upstreams:
    - type: Network
      address: 10.240.252.78   # master01 dnsmasq (1차 — 내부 도메인 즉시 응답)
      port: 53
    - type: Network
      address: 10.240.252.75   # bastion BIND (2차 — dnsmasq 장애 시 내부 도메인 fallback)
      port: 53
    - type: Network
      address: 10.230.14.51    # 외부 forwarder 직접 (3차 — BIND 우회)
      port: 53
    - type: Network
      address: 10.10.156.141   # 외부 forwarder 직접 (4차 — BIND 우회)
      port: 53
```

CoreDNS Corefile에 반영된 결과:

```
forward . 10.240.252.78:53 10.240.252.75:53 10.230.14.51:53 10.10.156.141:53 {
    policy sequential
}
```

DNS 해석 경로:
- 정상: dnsmasq가 내부/외부 모두 처리
- dnsmasq 장애: bastion BIND가 내부 도메인(`*.apps.poc.mobis.com`) fallback → NXDOMAIN 방지
- BIND도 장애: 외부 forwarder가 외부 도메인만 처리

### 검증

```
$ oc get configmap dns-default -n openshift-dns -o yaml | grep forward
        forward . 10.240.252.78:53 10.240.252.75:53 10.230.14.51:53 10.10.156.141:53 {
```

### 롤백 방법

```bash
oc patch dns.operator.openshift.io default --type merge -p '{
  "spec": {
    "upstreamResolvers": {
      "policy": "Sequential",
      "upstreams": [
        {"type": "SystemResolvConf", "port": 53}
      ]
    }
  }
}'
```

---

## 4. NTP(chrony) 설정 (MachineConfig)

### 변경 전 상태

양쪽 노드 모두 외부 NTP 서버(`0.rhel.pool.ntp.org` 등)에 연결을 시도하지만, 외부 인터넷 접근이 제한된 환경이라 모든 NTP 소스가 `Reach: 0`이고 `Leap status: Not synchronised` 상태였습니다.

### 적용한 리소스

#### master01: 로컬 NTP 서버 (Stratum 10)

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-chrony
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          # 디코딩된 내용:
          #   pool 0.rhel.pool.ntp.org iburst
          #   local stratum 10
          #   allow 10.240.252.0/24
          #   driftfile /var/lib/chrony/drift
          #   makestep 1.0 3
          #   rtcsync
          #   logdir /var/log/chrony
          source: data:text/plain;charset=utf-8;base64,cG9vbCAwLnJoZWwucG9vbC5udHAub3JnIGlidXJzdAoKIyBMb2NhbCBjbG9jayBhcyBmYWxsYmFjawpsb2NhbCBzdHJhdHVtIDEwCgojIEFsbG93IHdvcmtlciBub2RlIHN1Ym5ldAphbGxvdyAxMC4yNDAuMjUyLjAvMjQKCmRyaWZ0ZmlsZSAvdmFyL2xpYi9jaHJvbnkvZHJpZnQKbWFrZXN0ZXAgMS4wIDMKcnRjc3luYwpsb2dkaXIgL3Zhci9sb2cvY2hyb255Cg==
        filesystem: root
        mode: 0644
        path: /etc/chrony.conf
```

- `local stratum 10`: 외부 NTP 접근 불가 시 자체 시계를 NTP 소스로 제공
- `allow 10.240.252.0/24`: worker 노드가 이 master를 NTP 서버로 사용 가능

#### worker01: master01을 NTP 소스로 사용

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-chrony
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          # 디코딩된 내용:
          #   server 10.240.252.78 iburst
          #   driftfile /var/lib/chrony/drift
          #   makestep 1.0 3
          #   rtcsync
          #   logdir /var/log/chrony
          source: data:text/plain;charset=utf-8;base64,IyBVc2UgbWFzdGVyMDEgYXMgTlRQIHNlcnZlcgpzZXJ2ZXIgMTAuMjQwLjI1Mi43OCBpYnVyc3QKCmRyaWZ0ZmlsZSAvdmFyL2xpYi9jaHJvbnkvZHJpZnQKbWFrZXN0ZXAgMS4wIDMKcnRjc3luYwpsb2dkaXIgL3Zhci9sb2cvY2hyb255Cg==
        filesystem: root
        mode: 0644
        path: /etc/chrony.conf
```

### 변경 후 상태

```
master01: Stratum 10, Leap status: Normal (로컬 시계 기준 NTP 서빙)
worker01: ^* master01.poc.mobis.com  Stratum 11, offset +40us (master01에 동기화 완료)
```

### 주의사항

- MachineConfig 적용 시 노드가 **순차적으로 재부팅**됩니다.
- SingleReplica 환경에서는 master 재부팅 중 API가 일시적으로 사용 불가합니다.

### 롤백 방법

```bash
oc delete mc 99-master-chrony
oc delete mc 99-worker-chrony
```

---

## 변경 사항 요약

| # | 변경 항목 | 리소스 종류 | 리소스 이름 | 노드 재부팅 |
|---|-----------|------------|------------|------------|
| 1 | NMState Operator 설치 | Namespace, OperatorGroup, Subscription, NMState | `openshift-nmstate` | 불필요 |
| 2 | DNS fallback 추가 | NodeNetworkConfigurationPolicy | `dns-fallback` | 불필요 |
| 3 | CoreDNS upstream 변경 | DNS (operator.openshift.io) | `default` | 불필요 |
| 4 | NTP master 설정 | MachineConfig | `99-master-chrony` | master 재부팅 |
| 5 | NTP worker 설정 | MachineConfig | `99-worker-chrony` | worker 재부팅 |

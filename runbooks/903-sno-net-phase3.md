## Phase 3: OpenShift SNO 진단 (Sprint 11~15)

### Sprint 11 — API Server 상태 점검

#### 11-1. API Server healthz

```bash
curl -sk https://api.<cluster-domain>:6443/healthz
curl -sk https://api.<cluster-domain>:6443/readyz
curl -sk https://api.<cluster-domain>:6443/livez
```

#### 11-2. API Server 응답 지연 측정

```bash
for i in $(seq 1 20); do
  echo -n "$(date '+%H:%M:%S') "
  curl -sk -o /dev/null -w "total=%{time_total}s http=%{http_code}\n" \
    --max-time 15 https://api.<cluster-domain>:6443/api/v1/namespaces/default
  sleep 3
done
```

#### 11-3. API Server 감사 로그 지연

```bash
oc get --raw /apis/flowcontrol.apiserver.k8s.io/v1/prioritylevelconfigurations 2>/dev/null | \
  python3 -c "import sys,json; [print(f'{p[\"metadata\"][\"name\"]}: {p[\"status\"]}') for p in json.load(sys.stdin).get('items',[])]" 2>/dev/null
```

#### 11-4. API Server Pod 리소스 사용량

```bash
oc adm top pods -n openshift-kube-apiserver --no-headers 2>/dev/null
oc adm top pods -n openshift-apiserver --no-headers 2>/dev/null
```

#### 11-5. API Request 큐 길이

```bash
# Prometheus 메트릭 (SNO에서 직접)
oc exec -n openshift-monitoring prometheus-k8s-0 -- \
  curl -sk 'http://localhost:9090/api/v1/query?query=apiserver_current_inflight_requests' 2>/dev/null | \
  python3 -c "import sys,json; [print(f'{r[\"metric\"].get(\"requestKind\",\"?\")}: {r[\"value\"][1]}') for r in json.load(sys.stdin).get('data',{}).get('result',[])]" 2>/dev/null
```

---

### Sprint 12 — etcd 성능 점검

#### 12-1. etcd 헬스 체크

```bash
oc get etcd -o jsonpath='{.items[0].status.conditions}' 2>/dev/null | python3 -m json.tool
```

#### 12-2. etcd 리더/팔로워 상태 (SNO는 단일)

```bash
oc rsh -n openshift-etcd $(oc get pods -n openshift-etcd -l app=etcd -o name | head -1) \
  etcdctl endpoint health --cluster 2>/dev/null
```

#### 12-3. etcd fsync 지연

```bash
oc rsh -n openshift-etcd $(oc get pods -n openshift-etcd -l app=etcd -o name | head -1) \
  etcdctl endpoint status --write-out=table 2>/dev/null
```

#### 12-4. etcd 디스크 I/O 확인

```bash
oc debug node/<sno-node> -- chroot /host \
  iostat -xz 1 5 2>/dev/null | tail -20
```

#### 12-5. etcd 데이터베이스 크기

```bash
oc rsh -n openshift-etcd $(oc get pods -n openshift-etcd -l app=etcd -o name | head -1) \
  etcdctl endpoint status --write-out=json 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'DB size: {d[0][\"Status\"][\"dbSize\"]/1024/1024:.1f} MB')" 2>/dev/null
```

---

### Sprint 13 — SNO 노드 리소스 점검

#### 13-1. 노드 CPU / Memory / Disk

```bash
oc adm top nodes
echo ""
oc get nodes -o custom-columns=\
NAME:.metadata.name,\
CPU:.status.allocatable.cpu,\
MEM:.status.allocatable.memory,\
DISK:.status.allocatable.ephemeral-storage
```

#### 13-2. 시스템 Pod 리소스 사용량 Top 20

```bash
oc adm top pods -A --sort-by=cpu | head -20
echo ""
oc adm top pods -A --sort-by=memory | head -20
```

#### 13-3. 디스크 압력 확인

```bash
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.conditions[*]}{.type}={.status} {end}{"\n"}{end}'
```

#### 13-4. kubelet 로그에서 지연 이벤트

```bash
oc adm node-logs <sno-node> --unit=kubelet --since "1 hour ago" 2>/dev/null | \
  grep -iE "timeout|slow|latency|deadline" | tail -20
```

#### 13-5. CRI-O / 컨테이너 런타임 상태

```bash
oc debug node/<sno-node> -- chroot /host \
  crictl ps --state running | wc -l
echo "running containers"

oc debug node/<sno-node> -- chroot /host \
  systemctl status crio | head -5
```

---

### Sprint 14 — 인증서 / 토큰 점검

#### 14-1. API 서버 인증서 만료일

```bash
echo | openssl s_client -connect api.<cluster-domain>:6443 -servername api.<cluster-domain> 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null
```

#### 14-2. *.apps 와일드카드 인증서 만료일

```bash
echo | openssl s_client -connect console-openshift-console.apps.<cluster-domain>:443 \
  -servername console-openshift-console.apps.<cluster-domain> 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null
```

#### 14-3. oc 토큰 유효성 확인

```bash
oc whoami 2>/dev/null && echo "[PASS] 토큰 유효" || echo "[FAIL] 토큰 만료 — oc login 필요"
oc whoami --show-token 2>/dev/null | head -c 20
echo "..."
```

#### 14-4. OAuth 서버 응답

```bash
curl -sk -o /dev/null -w "http=%{http_code} time=%{time_total}s\n" \
  --max-time 10 https://oauth-openshift.apps.<cluster-domain>/healthz
```

#### 14-5. 내부 인증서 회전 이벤트

```bash
oc get events -A --field-selector reason=CertificateRotated --no-headers 2>/dev/null | tail -10
oc get co kube-apiserver -o jsonpath='{.status.conditions[?(@.type=="Progressing")].message}' 2>/dev/null
echo ""
```

---

### Sprint 15 — Ingress Controller 점검

#### 15-1. Ingress Controller 상태

```bash
oc get ingresscontroller -n openshift-ingress-operator
oc get pods -n openshift-ingress --no-headers
```

#### 15-2. Router Pod 리소스

```bash
oc adm top pods -n openshift-ingress --no-headers
```

#### 15-3. Router 연결 수

```bash
oc exec -n openshift-ingress $(oc get pods -n openshift-ingress -o name | head -1) -- \
  cat /var/lib/haproxy/conf/haproxy.config 2>/dev/null | grep maxconn | head -5
```

#### 15-4. Router 타임아웃 설정

```bash
oc get ingresscontroller default -n openshift-ingress-operator \
  -o jsonpath='{.spec.tuningOptions}' 2>/dev/null | python3 -m json.tool 2>/dev/null
# 비어 있으면 기본값 사용
```

#### 15-5. Ingress 관련 이벤트

```bash
oc get events -n openshift-ingress --sort-by=.lastTimestamp | tail -20
```

---


## 다음 단계

→ `runbooks/904-sno-net-phase4.md`

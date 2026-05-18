## Phase 2: Bastion 서비스 진단 (Sprint 6~10)

### Sprint 6 — HAProxy 상태 점검

#### 6-1. HAProxy 프로세스 상태

```bash
ssh bastion << 'REMOTE'
echo "=== HAProxy 프로세스 ==="
systemctl status haproxy
echo ""
echo "=== PID 및 메모리 ==="
ps aux | grep haproxy | grep -v grep
echo ""
echo "=== 열린 파일 수 ==="
ls /proc/$(pgrep -o haproxy)/fd 2>/dev/null | wc -l
REMOTE
```

#### 6-2. HAProxy 백엔드 헬스 체크

```bash
ssh bastion << 'REMOTE'
echo "=== HAProxy stats ==="
echo "show stat" | sudo socat stdio /var/lib/haproxy/stats 2>/dev/null | \
  awk -F, '{printf "%-30s %-10s %-8s\n", $1"/"$2, $18, $17}' | head -20

# 또는 stats 페이지 활성화된 경우
# curl -s http://localhost:9000/stats\;csv | awk -F, '{print $1,$2,$18}'
REMOTE
```

#### 6-3. HAProxy 연결 큐 확인

```bash
ssh bastion << 'REMOTE'
echo "=== 현재 연결 수 ==="
echo "show info" | sudo socat stdio /var/lib/haproxy/stats 2>/dev/null | \
  grep -E "CurrConns|MaxConn|ConnRate"
REMOTE
```

#### 6-4. HAProxy 에러 로그 최근 항목

```bash
ssh bastion << 'REMOTE'
echo "=== HAProxy 에러 (최근 50줄) ==="
sudo journalctl -u haproxy --since "1 hour ago" --no-pager | \
  grep -iE "error|timeout|refused|reset|503|504" | tail -50
REMOTE
```

#### 6-5. HAProxy 설정 파일 검증

```bash
ssh bastion << 'REMOTE'
echo "=== HAProxy 설정 검증 ==="
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
echo ""
echo "=== 프론트엔드/백엔드 요약 ==="
grep -E "^(frontend|backend|server)" /etc/haproxy/haproxy.cfg
REMOTE
```

---

### Sprint 7 — HAProxy 타임아웃 설정 점검

#### 7-1. 글로벌 타임아웃 값 확인

```bash
ssh bastion << 'REMOTE'
echo "=== 타임아웃 설정 ==="
grep -E "timeout" /etc/haproxy/haproxy.cfg
REMOTE
# 권장값:
# timeout client  5m
# timeout server  5m
# timeout connect 10s
# timeout tunnel  1h    ← WebSocket/스트리밍에 중요
# timeout http-keep-alive 10s
```

#### 7-2. API 서버 백엔드 타임아웃 최적화

```bash
ssh bastion << 'REMOTE'
# API 서버(6443) 백엔드에 tunnel 타임아웃 추가 (watch/exec용)
grep -A10 "backend.*api\|backend.*6443" /etc/haproxy/haproxy.cfg
REMOTE

# 권장 수정 (Bastion에서):
# backend api-server
#   timeout server  10m
#   timeout tunnel  1h
#   server sno-api <sno-ip>:6443 check inter 5s fall 3 rise 2
```

#### 7-3. TCP 킵얼라이브 설정

```bash
ssh bastion << 'REMOTE'
echo "=== 시스템 TCP keepalive ==="
sysctl net.ipv4.tcp_keepalive_time
sysctl net.ipv4.tcp_keepalive_intvl
sysctl net.ipv4.tcp_keepalive_probes

echo ""
echo "=== HAProxy option 확인 ==="
grep -E "option.*tcpka|option.*httpchk|option.*http-keep-alive" /etc/haproxy/haproxy.cfg
REMOTE
```

#### 7-4. 연결 재시도 설정

```bash
ssh bastion << 'REMOTE'
echo "=== retries 설정 ==="
grep -E "retries|redispatch|retry-on" /etc/haproxy/haproxy.cfg
REMOTE
# 권장:
# retries 3
# option redispatch
```

#### 7-5. maxconn 제한 확인

```bash
ssh bastion << 'REMOTE'
echo "=== maxconn 설정 ==="
grep -i maxconn /etc/haproxy/haproxy.cfg

echo ""
echo "=== 현재 연결 vs 최대 ==="
echo "show info" | sudo socat stdio /var/lib/haproxy/stats 2>/dev/null | \
  grep -E "Maxconn|CurrConns|MaxSessRate"

echo ""
echo "=== 시스템 fd 제한 ==="
ulimit -n
cat /proc/sys/fs/file-max
REMOTE
```

---

### Sprint 8 — Bastion DNS 서비스 점검

#### 8-1. DNS 서비스 상태 확인

```bash
ssh bastion << 'REMOTE'
echo "=== DNS 서비스 상태 ==="
systemctl status named 2>/dev/null || systemctl status dnsmasq 2>/dev/null
echo ""
echo "=== 리스닝 포트 ==="
ss -ulnp | grep ":53"
ss -tlnp | grep ":53"
REMOTE
```

#### 8-2. DNS 존 파일 정합성

```bash
ssh bastion << 'REMOTE'
echo "=== DNS 존 파일 확인 ==="
# named 사용 시
named-checkconf 2>/dev/null
for ZONE in $(grep "zone " /etc/named.conf 2>/dev/null | grep -v "^//" | awk -F'"' '{print $2}'); do
  echo -n "Zone ${ZONE}: "
  named-checkzone ${ZONE} /var/named/${ZONE}.zone 2>/dev/null | tail -1
done

# dnsmasq 사용 시
echo "=== dnsmasq 설정 ==="
grep -v "^#" /etc/dnsmasq.conf 2>/dev/null | grep -v "^$"
REMOTE
```

#### 8-3. DNS 쿼리 지연시간 반복 측정

```bash
# 노트북에서 Bastion DNS 응답시간 100회 측정
for i in $(seq 1 100); do
  START=$(python3 -c "import time; print(time.time())")
  dig @${BASTION_IP} api.<cluster-domain> +short +time=2 +tries=1 > /dev/null 2>&1
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f'{${END}-${START}:.3f}')")
  echo "${i} ${ELAPSED}s"
  sleep 0.5
done | tee /tmp/dns-latency.log

# 통계
awk '{sum+=$2; if($2>max)max=$2; if(min==""||$2<min)min=$2} END{printf "avg=%.3f min=%.3f max=%.3f\n",sum/NR,min,max}' /tmp/dns-latency.log
```

#### 8-4. DNS 포워더 설정 확인

```bash
ssh bastion << 'REMOTE'
echo "=== DNS 포워더 ==="
grep -E "forwarders|server=" /etc/named.conf /etc/dnsmasq.conf 2>/dev/null

echo ""
echo "=== 외부 DNS 포워더 응답 확인 ==="
dig @8.8.8.8 google.com +short +time=2
REMOTE
```

#### 8-5. DNS 로그에서 실패 쿼리 추출

```bash
ssh bastion << 'REMOTE'
echo "=== DNS 에러 로그 (최근 1시간) ==="
sudo journalctl -u named --since "1 hour ago" --no-pager 2>/dev/null | \
  grep -iE "error|refused|timeout|SERVFAIL|NXDOMAIN" | tail -20

# dnsmasq
sudo journalctl -u dnsmasq --since "1 hour ago" --no-pager 2>/dev/null | \
  grep -iE "error|refused|timeout" | tail -20
REMOTE
```

---

### Sprint 9 — Bastion 시스템 리소스 점검

#### 9-1. CPU / Memory / Disk 상태

```bash
ssh bastion << 'REMOTE'
echo "=== CPU ==="
uptime
echo ""
echo "=== Memory ==="
free -h
echo ""
echo "=== Disk ==="
df -h /
echo ""
echo "=== Swap ==="
swapon --show
REMOTE
```

#### 9-2. 시스템 로드 추이

```bash
ssh bastion << 'REMOTE'
echo "=== 로드 추이 (sar) ==="
sar -u 1 10 2>/dev/null || (echo "sysstat 미설치"; mpstat 1 5 2>/dev/null)
REMOTE
```

#### 9-3. 네트워크 인터페이스 에러/드롭

```bash
ssh bastion << 'REMOTE'
echo "=== 인터페이스 에러 ==="
ip -s link show | grep -A4 "^[0-9]"
echo ""
echo "=== 에러 카운터 ==="
cat /proc/net/dev | column -t
REMOTE
```

#### 9-4. conntrack 테이블 포화 확인

```bash
ssh bastion << 'REMOTE'
echo "=== conntrack ==="
CURRENT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)
MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)
echo "  현재: ${CURRENT} / 최대: ${MAX}"
if [[ -n "${CURRENT}" ]] && [[ -n "${MAX}" ]]; then
  PCT=$((CURRENT * 100 / MAX))
  echo "  사용률: ${PCT}%"
  [[ ${PCT} -gt 80 ]] && echo "  [WARN] conntrack 80% 초과 — 증가 필요"
fi
REMOTE
```

#### 9-5. OOM 킬러 이력 확인

```bash
ssh bastion << 'REMOTE'
echo "=== OOM 이력 ==="
dmesg | grep -i "out of memory\|oom-killer\|killed process" | tail -10
echo ""
echo "=== 서비스 재시작 이력 ==="
systemctl list-units --type=service --state=failed
journalctl -p err --since "24 hours ago" --no-pager | grep -E "haproxy|named|dnsmasq" | tail -10
REMOTE
```

---

### Sprint 10 — HAProxy 로그 상관 분석

#### 10-1. 끊김 시점 HAProxy 로그 추출

```bash
ssh bastion << 'REMOTE'
echo "=== HAProxy 로그 (최근 30분) ==="
sudo journalctl -u haproxy --since "30 min ago" --no-pager | tail -100
REMOTE
```

#### 10-2. HTTP 5xx / 타임아웃 패턴

```bash
ssh bastion << 'REMOTE'
echo "=== 5xx 에러 ==="
sudo journalctl -u haproxy --since "1 hour ago" --no-pager | \
  grep -E " 5[0-9]{2} " | awk '{print $1,$2,$3}' | uniq -c | sort -rn | head -20
REMOTE
```

#### 10-3. 연결 시간 분포 분석

```bash
ssh bastion << 'REMOTE'
# HAProxy 로그에서 Tc(연결시간) 추출
sudo journalctl -u haproxy --since "1 hour ago" --no-pager | \
  grep -oP '\d+/\d+/\d+/\d+/\d+' | \
  awk -F/ '{print "connect="$2"ms server="$4"ms total="$5"ms"}' | head -20
REMOTE
```

#### 10-4. 백엔드 다운 이벤트

```bash
ssh bastion << 'REMOTE'
echo "=== 백엔드 상태 변경 ==="
sudo journalctl -u haproxy --since "24 hours ago" --no-pager | \
  grep -iE "server.*is (UP|DOWN|going)" | tail -20
REMOTE
```

#### 10-5. 클라이언트 연결 끊김(CD) 로그

```bash
ssh bastion << 'REMOTE'
# CD = client disconnect, SD = server disconnect
echo "=== 비정상 종료 ==="
sudo journalctl -u haproxy --since "1 hour ago" --no-pager | \
  grep -E "<(CD|SD|SC|CC)>" | wc -l
echo "건"

echo "=== 종료 원인 분포 ==="
sudo journalctl -u haproxy --since "1 hour ago" --no-pager | \
  grep -oP '<[A-Z]{2}>' | sort | uniq -c | sort -rn
REMOTE
```

---


## 다음 단계

→ `runbooks/903-sno-net-phase3.md`

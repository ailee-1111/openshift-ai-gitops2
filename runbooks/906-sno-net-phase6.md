## Phase 6: 해결 및 최적화 (Sprint 26~30)

### Sprint 26 — VPN 최적화

#### 26-1. VPN MTU 고정 설정

```bash
# VPN 클라이언트 설정에 MTU 명시
# OpenVPN: mssfix 1300 + tun-mtu 1300
# WireGuard: MTU = 1280
# AnyConnect: Profile XML에 MTU 지정
echo "[ACTION] VPN MTU를 Sprint 4에서 찾은 최적값으로 고정"
```

#### 26-2. VPN TCP → UDP 전환

```bash
echo "=== VPN 프로토콜 ==="
echo "TCP VPN은 'TCP over TCP' 문제로 재전송 증폭 발생"
echo "가능하면 UDP 기반 VPN(WireGuard, OpenVPN UDP)으로 전환"
echo "방화벽이 UDP를 차단하면 TCP fallback 사용"
```

#### 26-3. VPN 킵얼라이브 최적화

```bash
# OpenVPN: keepalive 10 60 (10초 간격 ping, 60초 무응답 시 재시작)
# WireGuard: PersistentKeepalive = 25
# IPSec: dpd_delay=10, dpd_timeout=60
echo "[ACTION] VPN keepalive 간격을 10~25초로 설정"
```

#### 26-4. VPN 스플릿 터널링 최적화

```bash
echo "=== 스플릿 터널 ==="
echo "전체 트래픽을 VPN으로 보내면 불필요한 부하"
echo "Bastion 서브넷 + 클러스터 서브넷만 VPN 라우팅"
echo "나머지는 직접 인터넷 접속"
```

#### 26-5. VPN 재연결 자동화

```bash
# crontab 또는 launchd로 VPN 상태 감시
cat << 'PLIST'
[ACTION] macOS: ~/Library/LaunchAgents/com.vpn.monitor.plist
또는 crontab:
*/5 * * * * ping -c 1 -W 3 <bastion-ip> > /dev/null || /usr/local/bin/vpn-reconnect.sh
PLIST
```

---

### Sprint 27 — HAProxy 최적화

#### 27-1. 타임아웃 최적화 적용

```bash
ssh bastion << 'REMOTE'
echo "=== 권장 HAProxy 타임아웃 ==="
cat << 'CFG'
defaults
  timeout connect         10s
  timeout client          5m
  timeout server          5m
  timeout tunnel          1h
  timeout http-keep-alive 10s
  timeout http-request    30s
  timeout queue           1m
  timeout check           10s
  option  tcpka
  option  redispatch
  retries 3
CFG
echo ""
echo "[ACTION] /etc/haproxy/haproxy.cfg 수정 후: sudo systemctl reload haproxy"
REMOTE
```

#### 27-2. TCP 킵얼라이브 활성화

```bash
ssh bastion << 'REMOTE'
# 시스템 레벨 TCP keepalive
sudo sysctl -w net.ipv4.tcp_keepalive_time=60
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=10
sudo sysctl -w net.ipv4.tcp_keepalive_probes=6

# 영구 적용
echo "net.ipv4.tcp_keepalive_time=60" | sudo tee -a /etc/sysctl.d/99-keepalive.conf
echo "net.ipv4.tcp_keepalive_intvl=10" | sudo tee -a /etc/sysctl.d/99-keepalive.conf
echo "net.ipv4.tcp_keepalive_probes=6" | sudo tee -a /etc/sysctl.d/99-keepalive.conf
REMOTE
```

#### 27-3. conntrack 테이블 확장

```bash
ssh bastion << 'REMOTE'
sudo sysctl -w net.netfilter.nf_conntrack_max=131072
echo "net.netfilter.nf_conntrack_max=131072" | sudo tee -a /etc/sysctl.d/99-conntrack.conf
REMOTE
```

#### 27-4. HAProxy stats 페이지 활성화

```bash
ssh bastion << 'REMOTE'
echo "[ACTION] haproxy.cfg에 stats 추가:"
cat << 'CFG'
listen stats
  bind *:9000
  mode http
  stats enable
  stats uri /stats
  stats refresh 10s
  stats admin if TRUE
CFG
echo "접근: http://<bastion-ip>:9000/stats"
REMOTE
```

#### 27-5. HAProxy 로그 레벨 최적화

```bash
ssh bastion << 'REMOTE'
echo "[ACTION] 상세 로깅 활성화:"
cat << 'CFG'
global
  log /dev/log local0 info
  log /dev/log local1 notice

defaults
  log global
  option httplog
  option dontlognull
CFG
REMOTE
```

---

### Sprint 28 — DNS 최적화

#### 28-1. DNS 캐싱 최적화

```bash
ssh bastion << 'REMOTE'
# dnsmasq 캐시 크기 증가
echo "cache-size=1000" | sudo tee -a /etc/dnsmasq.d/cache.conf
# named: max-cache-size 확인
grep "max-cache-size" /etc/named.conf 2>/dev/null
REMOTE
```

#### 28-2. 네거티브 캐시 TTL 단축

```bash
ssh bastion << 'REMOTE'
# NXDOMAIN 캐시 줄이기 (빠른 복구)
echo "neg-ttl=60" | sudo tee -a /etc/dnsmasq.d/cache.conf 2>/dev/null
REMOTE
```

#### 28-3. DNS over TCP 폴백 설정

```bash
# UDP DNS 패킷이 VPN에서 단편화될 때 TCP 폴백
dig @${BASTION_IP} api.<cluster-domain> +tcp +short
```

#### 28-4. 노트북 hosts 파일 완전성 보장

```bash
echo "=== 필수 hosts 엔트리 ==="
cat << 'HOSTS'
<bastion-ip>  api.<cluster-domain>
<bastion-ip>  api-int.<cluster-domain>
<bastion-ip>  console-openshift-console.apps.<cluster-domain>
<bastion-ip>  oauth-openshift.apps.<cluster-domain>
<bastion-ip>  downloads-openshift-console.apps.<cluster-domain>
<bastion-ip>  canary-openshift-ingress-canary.apps.<cluster-domain>
<bastion-ip>  alertmanager-main-openshift-monitoring.apps.<cluster-domain>
<bastion-ip>  grafana-openshift-monitoring.apps.<cluster-domain>
<bastion-ip>  prometheus-k8s-openshift-monitoring.apps.<cluster-domain>
<bastion-ip>  thanos-querier-openshift-monitoring.apps.<cluster-domain>
HOSTS
```

#### 28-5. mDNS / Bonjour 충돌 방지

```bash
# macOS mDNSResponder가 .local 도메인과 충돌할 수 있음
# 클러스터 도메인이 .local이면 변경 권장
echo "클러스터 도메인이 .local로 끝나면 mDNS 충돌 가능"
echo "scutil --dns 에서 resolver 순서 확인"
scutil --dns | grep -A5 "resolver #"
```

---

### Sprint 29 — 종합 자동 진단 스크립트

#### 29-1. 원클릭 전체 진단

```bash
cat << 'SCRIPT' > /tmp/sno-full-diag.sh
#!/bin/bash
set -euo pipefail
BASTION_IP="${1:?Usage: $0 <bastion-ip>}"
CLUSTER_DOMAIN="${2:?Usage: $0 <bastion-ip> <cluster-domain>}"
LOG="/tmp/sno-diag-$(date +%Y%m%d_%H%M%S).log"

exec > >(tee ${LOG}) 2>&1
echo "=== SNO 접근 전체 진단 — $(date) ==="

echo -e "\n[1] VPN Ping"
ping -c 5 -W 3 ${BASTION_IP}

echo -e "\n[2] DNS"
dig @${BASTION_IP} api.${CLUSTER_DOMAIN} +short +time=2

echo -e "\n[3] TCP 6443"
curl -sk -o /dev/null -w "tcp=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code}\n" \
  --max-time 15 https://api.${CLUSTER_DOMAIN}:6443/healthz

echo -e "\n[4] TCP 443"
curl -sk -o /dev/null -w "tcp=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code}\n" \
  --max-time 15 https://console-openshift-console.apps.${CLUSTER_DOMAIN}

echo -e "\n[5] oc CLI"
oc whoami 2>/dev/null && time oc get nodes 2>/dev/null

echo -e "\n[6] 소켓 상태"
netstat -an | grep ${BASTION_IP} | awk '{print $6}' | sort | uniq -c | sort -rn

echo -e "\n[7] MTU"
ping -D -s 1372 -c 2 -W 3 ${BASTION_IP} 2>&1 | tail -1

echo -e "\n[8] 라우팅"
route get ${BASTION_IP} 2>/dev/null || ip route get ${BASTION_IP} 2>/dev/null

echo -e "\n[9] hosts 파일"
grep ${CLUSTER_DOMAIN} /etc/hosts

echo -e "\n[10] 인증서 만료"
echo | openssl s_client -connect api.${CLUSTER_DOMAIN}:6443 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null

echo -e "\n=== 완료: ${LOG} ==="
SCRIPT
chmod +x /tmp/sno-full-diag.sh
echo "실행: bash /tmp/sno-full-diag.sh <bastion-ip> <cluster-domain>"
```

#### 29-2. Bastion 원클릭 진단

```bash
cat << 'SCRIPT' > /tmp/bastion-diag.sh
#!/bin/bash
echo "=== Bastion 진단 — $(date) ==="
echo -e "\n[1] HAProxy"
systemctl is-active haproxy
echo "show info" | sudo socat stdio /var/lib/haproxy/stats 2>/dev/null | grep -E "Curr|Max|Rate"

echo -e "\n[2] DNS"
systemctl is-active named 2>/dev/null || systemctl is-active dnsmasq 2>/dev/null

echo -e "\n[3] 리소스"
free -h | head -2
df -h / | tail -1
uptime

echo -e "\n[4] conntrack"
echo "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null) / $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"

echo -e "\n[5] 에러 (최근 1h)"
journalctl -u haproxy --since "1 hour ago" --no-pager 2>/dev/null | grep -ciE "error|timeout"
echo "errors"
SCRIPT
echo "Bastion에서 실행: bash /tmp/bastion-diag.sh"
```

#### 29-3. 끊김 시 자동 진단 트리거

```bash
cat << 'SCRIPT' > /tmp/auto-diag-on-fail.sh
#!/bin/bash
BASTION_IP="${1:?}"
CLUSTER_DOMAIN="${2:?}"
FAIL_COUNT=0

while true; do
  if ! ping -c 1 -W 3 ${BASTION_IP} > /dev/null 2>&1; then
    ((FAIL_COUNT++))
    if [[ ${FAIL_COUNT} -eq 3 ]]; then
      echo "$(date) 3회 연속 실패 — 자동 진단 실행"
      bash /tmp/sno-full-diag.sh ${BASTION_IP} ${CLUSTER_DOMAIN}
      FAIL_COUNT=0
      sleep 60
    fi
  else
    FAIL_COUNT=0
  fi
  sleep 5
done
SCRIPT
chmod +x /tmp/auto-diag-on-fail.sh
```

#### 29-4. 진단 결과 요약 리포트 생성

```bash
cat << 'SCRIPT' > /tmp/generate-report.sh
#!/bin/bash
echo "========================================="
echo "  SNO 접근 진단 요약 리포트"
echo "  $(date '+%Y-%m-%d %H:%M')"
echo "========================================="

for F in /tmp/sno-diag-*.log; do
  [[ -f "${F}" ]] || continue
  echo ""
  echo "--- $(basename ${F}) ---"
  grep -E "TIMEOUT|FAIL|error|http=5|time_total=[3-9]" "${F}" 2>/dev/null | head -5
done

echo ""
echo "=== 권장 조치 ==="
echo "1. Ping 손실 > 1% → VPN MTU 조정 또는 킵얼라이브 강화"
echo "2. API 응답 > 3s → HAProxy 타임아웃 확인"
echo "3. DNS 지연 > 500ms → Bastion DNS 서비스 점검"
echo "4. TLS > 1s → 인증서 체인 또는 OCSP 확인"
echo "5. 소켓 TIME_WAIT > 100 → TCP 재사용 설정"
SCRIPT
chmod +x /tmp/generate-report.sh
```

#### 29-5. 크론 기반 정기 진단

```bash
echo "=== crontab 설정 ==="
echo "# 30분마다 베이스라인 체크"
echo "*/30 * * * * /tmp/baseline-check.sh >> /tmp/baseline-history.log 2>&1"
echo ""
echo "# 매시간 전체 진단"
echo "0 * * * * /tmp/sno-full-diag.sh <bastion-ip> <cluster-domain> > /dev/null 2>&1"
```

---

### Sprint 30 — 운영 안정화 및 최종 점검

#### 30-1. 최적화 적용 결과 비교

```bash
echo "=== Before vs After 비교 ==="
echo "Sprint 25 베이스라인과 현재 값 비교:"
bash /tmp/baseline-check.sh

echo ""
echo "모니터링 로그 분석:"
bash /tmp/analyze-monitors.sh 2>/dev/null
```

#### 30-2. 안정화 체크리스트

```bash
echo "=== 운영 안정화 체크리스트 ==="
echo "[ ] VPN MTU 최적화 적용"
echo "[ ] VPN 킵얼라이브 설정"
echo "[ ] HAProxy 타임아웃 최적화 (tunnel=1h)"
echo "[ ] HAProxy TCP keepalive (option tcpka)"
echo "[ ] Bastion conntrack max 증가"
echo "[ ] Bastion TCP keepalive sysctl 적용"
echo "[ ] DNS 캐시 크기 최적화"
echo "[ ] 노트북 hosts 파일 완전성"
echo "[ ] 장기 모니터링 스크립트 가동"
echo "[ ] 자동 진단 트리거 설정"
echo "[ ] 인증서 만료일 달력 등록"
echo "[ ] 베이스라인 문서화"
```

#### 30-3. 에스컬레이션 기준 정의

```bash
echo "=== 에스컬레이션 기준 ==="
echo "Level 1 (자체 해결): Ping 손실 < 5%, API 응답 < 5s"
echo "Level 2 (네트워크팀): Ping 손실 > 5%, VPN 터널 반복 끊김"
echo "Level 3 (인프라팀): HAProxy 장애, Bastion 리소스 고갈"
echo "Level 4 (Red Hat SR): API Server 장애, etcd 지연, OCP 버그"
```

#### 30-4. 장기 SLA 목표

```bash
echo "=== SLA 목표 ==="
echo "  API 가용성: 99.5% (월간)"
echo "  평균 응답시간: < 1s"
echo "  최대 연속 끊김: < 30초"
echo "  Ping 손실률: < 0.5%"
echo "  VPN 재연결 빈도: < 1회/일"
```

#### 30-5. 정기 점검 스케줄

```bash
echo "=== 정기 점검 스케줄 ==="
echo "  일간: 베이스라인 체크 (자동, 30분 간격)"
echo "  주간: 모니터링 로그 분석 + SLA 보고서"
echo "  월간: 인증서 만료일 확인, HAProxy 설정 리뷰"
echo "  분기: VPN 설정 리뷰, 전체 진단 스크립트 업데이트"
```

---


## 다음 단계

→ 전체 인덱스: `runbooks/900-sno-network-index.md`

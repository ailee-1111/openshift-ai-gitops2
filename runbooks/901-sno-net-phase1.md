## Phase 1: 네트워크 기초 진단 (Sprint 1~5)

### Sprint 1 — VPN 터널 안정성 점검

#### 1-1. VPN 연결 상태 연속 모니터링

```bash
# Bastion IP 주소로 1초 간격 ping — 패킷 손실률 확인
BASTION_IP="<bastion-ip>"
ping -i 1 -c 300 ${BASTION_IP} | tee /tmp/vpn-ping-$(date +%s).log

# 완료 후 손실률 확인
tail -3 /tmp/vpn-ping-*.log
# 1% 이상이면 VPN 터널 불안정
```

#### 1-2. VPN MTU 최적값 탐색

```bash
# VPN 인터페이스 MTU 확인
ifconfig | grep -A1 "utun\|tun\|ppp" | grep mtu

# MTU 탐색 (큰 값부터 줄여가며 테스트)
for MTU in 1500 1400 1300 1200; do
  echo -n "MTU ${MTU}: "
  ping -D -s $((MTU - 28)) -c 3 -W 2 ${BASTION_IP} 2>/dev/null | tail -1
done
# "Frag needed" 없이 통과하는 최대 MTU가 최적값
```

#### 1-3. VPN 재연결 시 경로 복구 확인

```bash
# VPN 연결 직후 라우팅 확인
netstat -rn | grep ${BASTION_IP}

# VPN 끊기 → 재연결 → 경로 복구 여부
# macOS: networksetup -showallnetworkservices
route get ${BASTION_IP}
```

#### 1-4. VPN 킵얼라이브 설정 확인

```bash
# VPN 클라이언트 설정에서 keepalive 확인
# OpenVPN: grep keepalive /etc/openvpn/*.conf
# WireGuard: grep PersistentKeepalive /etc/wireguard/*.conf
# IPSec/AnyConnect: 클라이언트 GUI에서 DPD(Dead Peer Detection) 간격 확인

# 수동 킵얼라이브 테스트 (5분간 10초 간격)
for i in $(seq 1 30); do
  echo -n "$(date '+%H:%M:%S') "
  ping -c 1 -W 2 ${BASTION_IP} | grep "time=" || echo "TIMEOUT"
  sleep 10
done
```

#### 1-5. VPN 스플릿 터널링 충돌 확인

```bash
# 전체 라우팅 테이블에서 충돌하는 경로 탐색
netstat -rn | sort -t. -k1,1n -k2,2n

# Bastion 서브넷이 VPN 터널을 통하는지 확인
traceroute -n -m 10 ${BASTION_IP}

# DNS 요청이 VPN을 통하는지 vs 로컬로 나가는지
# (hosts 파일 우선이면 DNS 불필요하지만, 다른 도메인에서 충돌 가능)
scutil --dns | head -30
```

---

### Sprint 2 — DNS 해석 경로 점검

#### 2-1. hosts 파일 vs DNS 우선순위 확인

```bash
# hosts 파일 내용 확인
cat /etc/hosts | grep -v "^#" | grep -v "^$"

# nsswitch 또는 macOS resolver 순서
# macOS는 /etc/hosts가 기본 우선
# hosts 파일에 정의된 호스트의 DNS 해석 확인
dscacheutil -q host -a name api.<cluster-domain>
```

#### 2-2. Bastion DNS 서비스 응답시간 측정

```bash
# Bastion의 DNS 포트(53) 응답시간 (10회)
for i in $(seq 1 10); do
  echo -n "$(date '+%H:%M:%S') "
  dig @${BASTION_IP} api.<cluster-domain> +short +time=2 +tries=1 | head -1
  sleep 1
done
```

#### 2-3. DNS 캐시 오염 확인

```bash
# macOS DNS 캐시 플러시
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# 플러시 후 즉시 해석 테스트
time nslookup api.<cluster-domain> ${BASTION_IP}
time nslookup console-openshift-console.apps.<cluster-domain> ${BASTION_IP}
```

#### 2-4. 와일드카드 *.apps 해석 확인

```bash
# *.apps 도메인 해석 (Bastion DNS에서)
for SUB in console-openshift-console oauth-openshift grafana; do
  echo -n "${SUB}.apps.<cluster-domain> → "
  dig @${BASTION_IP} ${SUB}.apps.<cluster-domain> +short +time=2
done
```

#### 2-5. DNS 타임아웃과 폴백 경로

```bash
# VPN DNS vs 로컬 DNS 폴백 순서 확인
cat /etc/resolv.conf 2>/dev/null || scutil --dns

# 첫 번째 DNS 실패 시 두 번째로 폴백하는 시간 측정
time dig @${BASTION_IP} api.<cluster-domain> +time=1 +tries=1
time dig @8.8.8.8 api.<cluster-domain> +time=1 +tries=1
# 외부 DNS가 다른 IP를 반환하면 hosts 파일에서 해결되지 않는 도메인에서 충돌 발생
```

---

### Sprint 3 — TCP 연결성 점검

#### 3-1. API 서버(6443) TCP 핸드셰이크 시간

```bash
# 6443 포트 TCP 연결 시간 측정 (10회)
for i in $(seq 1 10); do
  echo -n "$(date '+%H:%M:%S') 6443: "
  curl -sk -o /dev/null -w "tcp=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s\n" \
    --max-time 10 https://api.<cluster-domain>:6443/healthz
  sleep 2
done
```

#### 3-2. 콘솔(443) TCP 연결 시간

```bash
# 443 포트 (*.apps 도메인)
for i in $(seq 1 10); do
  echo -n "$(date '+%H:%M:%S') 443: "
  curl -sk -o /dev/null -w "tcp=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code}\n" \
    --max-time 10 https://console-openshift-console.apps.<cluster-domain>
  sleep 2
done
```

#### 3-3. TCP 재전송 모니터링

```bash
# macOS: nettop으로 실시간 네트워크 모니터링
# Linux 노트북:
# ss -ti dst ${BASTION_IP} | grep -E "retrans|rto"
# 또는
netstat -s | grep -i retransmit
```

#### 3-4. TCP 동시 연결 수 확인

```bash
# Bastion으로의 활성 TCP 연결 수
netstat -an | grep ${BASTION_IP} | grep ESTABLISHED | wc -l

# 연결 상태 분포
netstat -an | grep ${BASTION_IP} | awk '{print $6}' | sort | uniq -c | sort -rn
# TIME_WAIT가 많으면 연결 재사용 문제
```

#### 3-5. 포트별 연결 가능 여부

```bash
# 핵심 포트 연결 테스트
for PORT in 22 53 80 443 6443; do
  echo -n "Port ${PORT}: "
  nc -z -w 3 ${BASTION_IP} ${PORT} && echo "OK" || echo "FAIL"
done
```

---

### Sprint 4 — MTU / 패킷 단편화 진단

#### 4-1. VPN 인터페이스 MTU 확인 및 조정

```bash
# 현재 MTU 확인
ifconfig | grep -B1 mtu | grep -E "utun|tun|ppp|mtu"

# VPN 인터페이스 MTU 조정 (관리자 권한)
# sudo ifconfig utun0 mtu 1280
# 또는 VPN 클라이언트 설정에서 MTU 지정
```

#### 4-2. Path MTU Discovery 테스트

```bash
# DF(Don't Fragment) 플래그로 패킷 크기 탐색
# macOS:
for SIZE in 1472 1400 1372 1300 1272 1200; do
  echo -n "Size ${SIZE}: "
  ping -D -s ${SIZE} -c 2 -W 2 ${BASTION_IP} 2>&1 | tail -1
done
```

#### 4-3. TCP MSS 클램핑 확인 (Bastion)

```bash
# Bastion 서버에서 (SSH 접속 후)
ssh bastion "sudo iptables -t mangle -L FORWARD -v | grep -i mss"
# MSS 클램핑이 없으면 VPN 환경에서 단편화 문제 발생 가능

# 클램핑 설정 (Bastion에서)
# sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

#### 4-4. 큰 페이로드 전송 테스트

```bash
# 큰 데이터 전송 시 끊김 재현
curl -sk -o /dev/null -w "speed=%{speed_download} size=%{size_download} time=%{time_total}s\n" \
  --max-time 30 https://api.<cluster-domain>:6443/apis

# oc 명령으로 큰 응답 테스트
time oc get nodes -o yaml > /dev/null 2>&1
time oc get pods -A -o yaml > /dev/null 2>&1
```

#### 4-5. ICMP 단편화 필요 메시지 차단 확인

```bash
# ICMP가 차단되면 PMTUD 실패 → 끊김
# Bastion에서 ICMP 정책 확인
ssh bastion "sudo iptables -L -v | grep icmp"

# traceroute로 중간 경로 ICMP 차단 확인
traceroute -F -n ${BASTION_IP}
```

---

### Sprint 5 — 라우팅 경로 진단

#### 5-1. VPN 라우팅 테이블 전체 검사

```bash
# 전체 라우팅 테이블
netstat -rn > /tmp/routes-$(date +%s).txt
cat /tmp/routes-*.txt

# Bastion 서브넷 경로
route get ${BASTION_IP}
```

#### 5-2. 비대칭 라우팅 확인

```bash
# 요청 경로 vs 응답 경로 불일치 탐색
traceroute -n ${BASTION_IP}
# Bastion에서 역방향 확인
ssh bastion "traceroute -n <노트북-vpn-ip>"
```

#### 5-3. VPN 재연결 후 경로 유지 검증

```bash
# VPN 끊기 전 경로 저장
netstat -rn | grep ${BASTION_IP} > /tmp/routes-before.txt

# VPN 재연결 후
netstat -rn | grep ${BASTION_IP} > /tmp/routes-after.txt

diff /tmp/routes-before.txt /tmp/routes-after.txt
```

#### 5-4. 다중 인터페이스 우선순위

```bash
# macOS: 인터페이스 순서
networksetup -listnetworkserviceorder

# 활성 인터페이스별 게이트웨이
for IF in $(ifconfig -l); do
  GW=$(route -n get -ifscope ${IF} default 2>/dev/null | grep gateway | awk '{print $2}')
  [[ -n "${GW}" ]] && echo "${IF}: gateway=${GW}"
done
```

#### 5-5. 라우팅 메트릭/우선순위 충돌

```bash
# 동일 대상에 대한 중복 경로
netstat -rn | awk '{print $1}' | sort | uniq -d

# VPN과 물리 인터페이스의 기본 게이트웨이 경쟁
route -n get default
```

---


## 다음 단계

→ `runbooks/902-sno-net-phase2.md`

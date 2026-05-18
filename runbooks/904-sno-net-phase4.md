## Phase 4: 클라이언트 측 진단 (Sprint 16~20)

### Sprint 16 — hosts 파일 / DNS 캐시

#### 16-1. hosts 파일 정합성 검증

```bash
echo "=== /etc/hosts 검증 ==="
grep -v "^#" /etc/hosts | grep -v "^$" | while read IP HOST REST; do
  echo -n "${HOST} → ${IP}: "
  ping -c 1 -W 2 ${IP} > /dev/null 2>&1 && echo "REACHABLE" || echo "UNREACHABLE"
done
```

#### 16-2. hosts 파일에 누락된 항목 찾기

```bash
# 필수 항목 확인
for HOST in \
  api.<cluster-domain> \
  console-openshift-console.apps.<cluster-domain> \
  oauth-openshift.apps.<cluster-domain> \
  downloads-openshift-console.apps.<cluster-domain>; do
  echo -n "${HOST}: "
  grep -q "${HOST}" /etc/hosts && echo "OK" || echo "MISSING — hosts 파일에 추가 필요"
done
```

#### 16-3. DNS 캐시 완전 초기화

```bash
# macOS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "[DONE] DNS 캐시 플러시"

# Linux
# sudo systemd-resolve --flush-caches
# sudo resolvectl flush-caches
```

#### 16-4. DNS 해석 소스 추적

```bash
# 어떤 소스(hosts/DNS)로 해석되는지 확인
dscacheutil -q host -a name api.<cluster-domain>
# "source: file" → hosts 파일
# "source: dns" → DNS 서버
```

#### 16-5. 잘못된 캐시 엔트리 탐지

```bash
# hosts 파일의 IP와 실제 ping 대상 IP 비교
EXPECTED_IP=$(grep "api.<cluster-domain>" /etc/hosts | awk '{print $1}')
ACTUAL_IP=$(python3 -c "import socket; print(socket.gethostbyname('api.<cluster-domain>'))")
echo "Expected: ${EXPECTED_IP}"
echo "Actual:   ${ACTUAL_IP}"
[[ "${EXPECTED_IP}" == "${ACTUAL_IP}" ]] && echo "[PASS]" || echo "[FAIL] DNS 캐시 오염"
```

---

### Sprint 17 — 브라우저 / oc CLI 점검

#### 17-1. oc 버전 호환성

```bash
echo "Client:"
oc version --client
echo ""
echo "Server:"
oc version 2>/dev/null | grep -i server
```

#### 17-2. oc 요청 상세 로그

```bash
# -v=6 으로 HTTP 요청 상세 출력
oc get nodes -v=6 2>&1 | grep -E "GET|POST|round_trip|Status"
```

#### 17-3. oc 연결 타임아웃 설정

```bash
# 기본 타임아웃 확인
oc config view --minify -o jsonpath='{.clusters[0].cluster}' | python3 -m json.tool
# request-timeout 추가 가능:
# oc config set-cluster <name> --request-timeout=30s
```

#### 17-4. 브라우저 콘솔 연결 디버깅

```bash
echo "=== 브라우저 디버깅 ==="
echo "1. Chrome DevTools → Network 탭 → 'Preserve log' 체크"
echo "2. 콘솔 접근 후 끊김 발생 시:"
echo "   - Stalled 요청 확인 (DNS 또는 TCP 레벨 지연)"
echo "   - TTFB(Time To First Byte) 확인"
echo "   - WebSocket 연결 끊김 확인 (ws://)"
echo "3. Console → Application → Cookies → 세션 토큰 만료 확인"
```

#### 17-5. 브라우저 TLS 세션 재사용 확인

```bash
# TLS 핸드셰이크가 매번 반복되면 느려짐
curl -vsk https://console-openshift-console.apps.<cluster-domain> 2>&1 | \
  grep -E "TLS|SSL|handshake|session"
```

---

### Sprint 18 — TLS 핸드셰이크 점검

#### 18-1. TLS 핸드셰이크 시간 측정

```bash
for TARGET in api.<cluster-domain>:6443 console-openshift-console.apps.<cluster-domain>:443; do
  echo -n "${TARGET}: "
  curl -sk -o /dev/null -w "tcp=%{time_connect}s tls=%{time_appconnect}s\n" \
    --max-time 10 "https://${TARGET}/"
done
```

#### 18-2. TLS 버전/암호 스위트 확인

```bash
echo | openssl s_client -connect api.<cluster-domain>:6443 2>/dev/null | \
  grep -E "Protocol|Cipher|Session-ID"
```

#### 18-3. 인증서 체인 검증

```bash
echo | openssl s_client -showcerts -connect api.<cluster-domain>:6443 2>/dev/null | \
  grep -E "depth|subject|verify"
```

#### 18-4. OCSP/CRL 지연 확인

```bash
# 인증서 유효성 검증(OCSP)이 VPN을 통해 외부로 나가며 지연될 수 있음
echo | openssl s_client -connect api.<cluster-domain>:6443 -status 2>/dev/null | \
  grep -A3 "OCSP response"
```

#### 18-5. SNI(Server Name Indication) 정합

```bash
# SNI 불일치 시 TLS 실패
curl -vsk --resolve "api.<cluster-domain>:6443:${BASTION_IP}" \
  https://api.<cluster-domain>:6443/healthz 2>&1 | grep -E "TLS|SSL|subject|issuer"
```

---

### Sprint 19 — TCP 소켓 상태 분석

#### 19-1. Bastion 연결 소켓 상태 분포

```bash
netstat -an | grep ${BASTION_IP} | awk '{print $6}' | sort | uniq -c | sort -rn
# ESTABLISHED: 정상
# TIME_WAIT: 연결 재사용 문제
# CLOSE_WAIT: 클라이언트 측 소켓 미해제
# SYN_SENT: 연결 시도 중 — 지연 원인
```

#### 19-2. TIME_WAIT 소켓 추적

```bash
TW_COUNT=$(netstat -an | grep ${BASTION_IP} | grep TIME_WAIT | wc -l | tr -d ' ')
echo "TIME_WAIT: ${TW_COUNT}"
[[ ${TW_COUNT} -gt 100 ]] && echo "[WARN] TIME_WAIT 과다 — 포트 고갈 위험"
```

#### 19-3. 소켓 버퍼 크기 확인

```bash
# macOS
sysctl net.inet.tcp.sendspace net.inet.tcp.recvspace
# Linux
# sysctl net.core.rmem_max net.core.wmem_max
```

#### 19-4. TCP 윈도우 스케일링

```bash
sysctl net.inet.tcp.win_scale_factor 2>/dev/null
# 또는
sysctl -a | grep tcp | grep -i window
```

#### 19-5. RST 패킷 탐지

```bash
# RST(연결 강제 종료) 감지
# macOS:
sudo tcpdump -i any -c 20 "tcp[tcpflags] & tcp-rst != 0 and host ${BASTION_IP}" 2>/dev/null
# 5초간만 캡처
```

---

### Sprint 20 — VPN 클라이언트 고급 설정

#### 20-1. VPN 클라이언트 로그 확인

```bash
# OpenVPN
cat /var/log/openvpn.log 2>/dev/null | tail -30

# AnyConnect
# /opt/cisco/anyconnect/log/ 또는 macOS Console.app에서 'vpn' 필터

# WireGuard
sudo wg show 2>/dev/null
```

#### 20-2. VPN DPD(Dead Peer Detection) 설정

```bash
# VPN 터널이 죽었는지 탐지하는 간격
# OpenVPN: keepalive 10 120 (10초 ping, 120초 무응답 시 재시작)
# IPSec: dpd_delay, dpd_timeout
echo "VPN 클라이언트 설정에서 DPD/keepalive 간격 확인 필요"
```

#### 20-3. VPN 재연결 자동화 스크립트

```bash
cat << 'SCRIPT'
#!/bin/bash
# VPN 연결 모니터링 + 자동 재연결
BASTION_IP="<bastion-ip>"
while true; do
  if ! ping -c 1 -W 3 ${BASTION_IP} > /dev/null 2>&1; then
    echo "$(date) VPN 끊김 감지 — 재연결 시도"
    # VPN 클라이언트별 재연결 명령
    # networksetup -disconnectpppoeservice "VPN"
    # sleep 5
    # networksetup -connectpppoeservice "VPN"
  fi
  sleep 30
done
SCRIPT
```

#### 20-4. VPN 압축 비활성화

```bash
# 압축이 활성화되면 암호화된 트래픽에 추가 오버헤드
# OpenVPN: comp-lzo no
# WireGuard: 압축 없음 (기본)
echo "VPN 설정에서 compression/comp-lzo 비활성화 권장"
```

#### 20-5. VPN DNS 누출 테스트

```bash
# VPN 연결 상태에서 DNS 요청이 VPN 바깥으로 나가는지
dig +short myip.opendns.com @resolver1.opendns.com
# 결과가 VPN IP가 아니면 DNS 누출
```

---


## 다음 단계

→ `runbooks/905-sno-net-phase5.md`

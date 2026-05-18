## Phase 5: 고급 진단 (Sprint 21~25)

### Sprint 21 — 패킷 캡처 분석

#### 21-1. API 서버 연결 패킷 캡처

```bash
# 6443 포트 캡처 (30초)
sudo tcpdump -i any -w /tmp/api-capture.pcap \
  "host ${BASTION_IP} and port 6443" -c 500 &
TCPDUMP_PID=$!

# 트래픽 생성
for i in $(seq 1 5); do
  oc get nodes > /dev/null 2>&1
  sleep 2
done

kill ${TCPDUMP_PID} 2>/dev/null
echo "캡처 파일: /tmp/api-capture.pcap"
```

#### 21-2. DNS 패킷 캡처

```bash
sudo tcpdump -i any -w /tmp/dns-capture.pcap \
  "host ${BASTION_IP} and port 53" -c 100 &
sleep 15
kill $! 2>/dev/null
```

#### 21-3. TCP 재전송 캡처

```bash
sudo tcpdump -i any -w /tmp/retransmit.pcap \
  "host ${BASTION_IP} and tcp[tcpflags] & tcp-syn != 0" -c 100 &
sleep 30
kill $! 2>/dev/null
```

#### 21-4. TLS 핸드셰이크 캡처

```bash
# TLS ClientHello/ServerHello 만 캡처
sudo tcpdump -i any -w /tmp/tls-handshake.pcap \
  "host ${BASTION_IP} and tcp port 6443 and (tcp[((tcp[12:1] & 0xf0) >> 2)] = 0x16)" -c 50 &
sleep 20
kill $! 2>/dev/null
```

#### 21-5. Wireshark 분석 가이드

```bash
echo "=== Wireshark 분석 포인트 ==="
echo "1. tcp.analysis.retransmission — 재전송 패킷"
echo "2. tcp.analysis.zero_window — 수신 버퍼 포화"
echo "3. tcp.analysis.ack_rtt > 0.5 — 높은 RTT"
echo "4. dns.time > 0.5 — DNS 응답 지연"
echo "5. ssl.handshake.type == 1 — TLS 핸드셰이크 시작"
echo "6. tcp.flags.reset == 1 — 연결 강제 종료"
echo ""
echo "캡처 파일: /tmp/*.pcap"
```

---

### Sprint 22 — 부하 테스트 / 스트레스 테스트

#### 22-1. API 서버 동시 요청 테스트

```bash
# 10개 병렬 요청
for i in $(seq 1 10); do
  (curl -sk -o /dev/null -w "req${i}: %{http_code} %{time_total}s\n" \
    --max-time 30 https://api.<cluster-domain>:6443/api/v1/namespaces) &
done
wait
```

#### 22-2. 지속적 요청 부하

```bash
# 5분간 2초 간격 요청
END=$((SECONDS + 300))
SEQ=0
while [[ $SECONDS -lt $END ]]; do
  ((SEQ++))
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    https://api.<cluster-domain>:6443/healthz)
  echo "$(date '+%H:%M:%S') #${SEQ}: HTTP ${CODE}"
  sleep 2
done | tee /tmp/load-test.log

echo ""
grep -c "HTTP 200" /tmp/load-test.log
echo "successful"
grep -vc "HTTP 200" /tmp/load-test.log
echo "failed"
```

#### 22-3. HAProxy 동시 연결 부하

```bash
# Bastion으로 50개 동시 TCP 연결
for i in $(seq 1 50); do
  (nc -z -w 5 ${BASTION_IP} 6443 && echo "${i}: OK" || echo "${i}: FAIL") &
done
wait
```

#### 22-4. 대용량 응답 전송 테스트

```bash
# 큰 응답을 유발하는 API 호출
time oc get pods -A -o json 2>/dev/null | wc -c
time oc get events -A -o json 2>/dev/null | wc -c
```

#### 22-5. WebSocket 장시간 연결 (oc exec/logs)

```bash
# oc exec 세션 유지 테스트 (5분)
timeout 300 oc exec -it $(oc get pods -n openshift-monitoring -o name | head -1) -- \
  sh -c 'for i in $(seq 1 60); do echo "tick $i"; sleep 5; done' 2>/dev/null
echo "Exit code: $?"
# 중간에 끊기면 tunnel 타임아웃 문제
```

---

### Sprint 23 — 장기 모니터링 자동화

#### 23-1. 연속 ping + 타임스탬프 로깅

```bash
# 24시간 모니터링 (백그라운드)
nohup bash -c '
BASTION_IP="<bastion-ip>"
LOG="/tmp/ping-24h-$(date +%Y%m%d).log"
while true; do
  echo -n "$(date "+%Y-%m-%d %H:%M:%S") " >> ${LOG}
  ping -c 1 -W 3 ${BASTION_IP} 2>/dev/null | grep "time=" >> ${LOG} || echo "TIMEOUT" >> ${LOG}
  sleep 5
done
' &
echo "PID: $!"
```

#### 23-2. API 연결 연속 모니터링

```bash
nohup bash -c '
LOG="/tmp/api-monitor-$(date +%Y%m%d).log"
while true; do
  echo -n "$(date "+%Y-%m-%d %H:%M:%S") " >> ${LOG}
  curl -sk -o /dev/null -w "tcp=%{time_connect}s total=%{time_total}s http=%{http_code}\n" \
    --max-time 15 https://api.<cluster-domain>:6443/healthz >> ${LOG} 2>&1
  sleep 10
done
' &
echo "PID: $!"
```

#### 23-3. VPN 인터페이스 상태 모니터링

```bash
nohup bash -c '
LOG="/tmp/vpn-if-$(date +%Y%m%d).log"
while true; do
  echo "=== $(date "+%Y-%m-%d %H:%M:%S") ===" >> ${LOG}
  ifconfig utun0 2>/dev/null >> ${LOG} || echo "VPN interface DOWN" >> ${LOG}
  sleep 30
done
' &
echo "PID: $!"
```

#### 23-4. DNS 해석 연속 모니터링

```bash
nohup bash -c '
BASTION_IP="<bastion-ip>"
LOG="/tmp/dns-monitor-$(date +%Y%m%d).log"
while true; do
  START=$(python3 -c "import time; print(time.time())")
  RESULT=$(dig @${BASTION_IP} api.<cluster-domain> +short +time=2 +tries=1 2>/dev/null)
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f\"{${END}-${START}:.3f}\")")
  echo "$(date "+%Y-%m-%d %H:%M:%S") ${ELAPSED}s ${RESULT}" >> ${LOG}
  sleep 10
done
' &
echo "PID: $!"
```

#### 23-5. 모니터링 결과 분석 스크립트

```bash
cat << 'SCRIPT' > /tmp/analyze-monitors.sh
#!/bin/bash
echo "=== Ping 분석 ==="
if [[ -f /tmp/ping-24h-*.log ]]; then
  TOTAL=$(wc -l < /tmp/ping-24h-*.log)
  TIMEOUT=$(grep -c TIMEOUT /tmp/ping-24h-*.log)
  echo "  총: ${TOTAL}, 타임아웃: ${TIMEOUT}, 손실률: $((TIMEOUT * 100 / TOTAL))%"
  echo "  최대 연속 타임아웃:"
  awk '/TIMEOUT/{c++; if(c>max)max=c} !/TIMEOUT/{c=0} END{print "  "max" 회"}' /tmp/ping-24h-*.log
fi

echo ""
echo "=== API 분석 ==="
if [[ -f /tmp/api-monitor-*.log ]]; then
  TOTAL=$(wc -l < /tmp/api-monitor-*.log)
  OK=$(grep -c "http=200" /tmp/api-monitor-*.log)
  echo "  총: ${TOTAL}, 성공: ${OK}, 실패: $((TOTAL - OK))"
  echo "  느린 요청 (>3s):"
  grep -E "total=[3-9]\.|total=[0-9]{2}" /tmp/api-monitor-*.log | head -5
fi
SCRIPT
chmod +x /tmp/analyze-monitors.sh
echo "분석: bash /tmp/analyze-monitors.sh"
```

---

### Sprint 24 — 장애 재현 및 패턴 분석

#### 24-1. 시간대별 끊김 패턴

```bash
# 모니터링 로그에서 시간대별 실패 분포
awk '/TIMEOUT/{print substr($2,1,2)}' /tmp/ping-24h-*.log 2>/dev/null | \
  sort | uniq -c | sort -rn
# 특정 시간대에 집중되면 VPN 세션 갱신, 백업 작업 등 상관 분석
```

#### 24-2. VPN 재연결과 끊김 상관관계

```bash
# VPN 로그와 ping 타임아웃 시점 교차 분석
echo "VPN 로그 경로에서 disconnect/reconnect 이벤트를 추출하여 비교"
echo "예: grep -E 'disconnect|reconnect|timeout' /var/log/vpn.log"
```

#### 24-3. Bastion 리소스 사용량과 끊김 상관

```bash
ssh bastion << 'REMOTE'
# SAR 데이터에서 CPU/메모리 피크 시점 확인
sar -u -r 2>/dev/null | tail -30
# HAProxy 재시작 이력
journalctl -u haproxy --since "24 hours ago" | grep -E "start|stop|restart|reload"
REMOTE
```

#### 24-4. 의도적 끊김 재현

```bash
echo "=== 끊김 재현 시나리오 ==="
echo "1. 대기 모드: VPN 연결 후 5분간 아무 작업 안 함 → oc get nodes"
echo "2. 대량 전송: oc get pods -A -o yaml 반복"
echo "3. 장시간 세션: oc logs -f <pod> 10분 유지"
echo "4. 동시 접속: 브라우저 콘솔 + oc CLI 동시 사용"
echo "5. VPN 재연결: VPN 끊기 → 즉시 재연결 → oc get nodes"
```

#### 24-5. 끊김 시 네트워크 스냅샷 자동 수집

```bash
cat << 'SCRIPT' > /tmp/capture-on-failure.sh
#!/bin/bash
BASTION_IP="<bastion-ip>"
while true; do
  if ! ping -c 1 -W 3 ${BASTION_IP} > /dev/null 2>&1; then
    TS=$(date +%Y%m%d_%H%M%S)
    echo "$(date) 끊김 감지 — 스냅샷 수집"
    netstat -rn > /tmp/snapshot-routes-${TS}.txt
    netstat -an | grep ${BASTION_IP} > /tmp/snapshot-conns-${TS}.txt
    ifconfig > /tmp/snapshot-if-${TS}.txt
    scutil --dns > /tmp/snapshot-dns-${TS}.txt 2>/dev/null
    echo "스냅샷: /tmp/snapshot-*-${TS}.txt"
  fi
  sleep 5
done
SCRIPT
chmod +x /tmp/capture-on-failure.sh
echo "실행: nohup bash /tmp/capture-on-failure.sh &"
```

---

### Sprint 25 — 성능 베이스라인 수립

#### 25-1. 정상 상태 지표 기록

```bash
echo "=== 성능 베이스라인 ==="
echo "1) Ping RTT:" && ping -c 10 ${BASTION_IP} | tail -1
echo "2) API 응답시간:" && curl -sk -o /dev/null -w "%{time_total}s\n" --max-time 10 https://api.<cluster-domain>:6443/healthz
echo "3) DNS 응답시간:" && dig @${BASTION_IP} api.<cluster-domain> +stats | grep "Query time"
echo "4) TLS 핸드셰이크:" && curl -sk -o /dev/null -w "%{time_appconnect}s\n" --max-time 10 https://api.<cluster-domain>:6443/
echo "5) oc 명령 시간:" && time oc get nodes > /dev/null 2>&1
```

#### 25-2. 베이스라인 대비 임계값 정의

```bash
echo "=== 임계값 정의 ==="
echo "  Ping RTT: 정상 < 50ms, 경고 50~200ms, 위험 > 200ms"
echo "  API 응답: 정상 < 1s, 경고 1~3s, 위험 > 3s"
echo "  DNS 해석: 정상 < 100ms, 경고 100~500ms, 위험 > 500ms"
echo "  TLS 핸드셰이크: 정상 < 500ms, 경고 500ms~1s, 위험 > 1s"
echo "  oc get nodes: 정상 < 2s, 경고 2~5s, 위험 > 5s"
```

#### 25-3. 주기적 베이스라인 비교

```bash
cat << 'SCRIPT' > /tmp/baseline-check.sh
#!/bin/bash
BASTION_IP="<bastion-ip>"
echo "$(date '+%Y-%m-%d %H:%M:%S') Baseline Check"

# Ping
RTT=$(ping -c 3 -W 3 ${BASTION_IP} 2>/dev/null | tail -1 | awk -F/ '{print $5}')
echo "  Ping RTT: ${RTT:-TIMEOUT}ms"

# API
API_TIME=$(curl -sk -o /dev/null -w "%{time_total}" --max-time 10 https://api.<cluster-domain>:6443/healthz 2>/dev/null)
echo "  API: ${API_TIME}s"

# DNS
DNS_TIME=$(dig @${BASTION_IP} api.<cluster-domain> +time=2 +tries=1 2>/dev/null | grep "Query time" | awk '{print $4}')
echo "  DNS: ${DNS_TIME}ms"
SCRIPT
chmod +x /tmp/baseline-check.sh
```

#### 25-4. SLA 보고서 생성

```bash
echo "=== SLA 계산 ==="
if [[ -f /tmp/api-monitor-*.log ]]; then
  TOTAL=$(wc -l < /tmp/api-monitor-*.log)
  OK=$(grep -c "http=200" /tmp/api-monitor-*.log)
  SLA=$(python3 -c "print(f'{${OK}/${TOTAL}*100:.2f}%')")
  echo "  가용성: ${SLA}"
fi
```

#### 25-5. 트렌드 분석 (시간대별 평균)

```bash
if [[ -f /tmp/api-monitor-*.log ]]; then
  echo "=== 시간대별 평균 응답시간 ==="
  awk '{
    hour=substr($2,1,2)
    match($0, /total=([0-9.]+)s/, a)
    if(a[1]) { sum[hour]+=a[1]; cnt[hour]++ }
  } END {
    for(h in sum) printf "  %s시: %.3fs (n=%d)\n", h, sum[h]/cnt[h], cnt[h]
  }' /tmp/api-monitor-*.log | sort
fi
```

---


## 다음 단계

→ `runbooks/906-sno-net-phase6.md`

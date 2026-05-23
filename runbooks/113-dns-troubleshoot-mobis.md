# 113 — Mobis PoC DNS 문제 해결 (VPN + Bastion 환경)

## 목적

VPN → Bastion(DNS+HAProxy) → SNO 아키텍처에서 발생하는 DNS 해석 지연을 진단하고 해결한다. 클라이언트(노트북) 측 `oc` CLI 5초 지연과, 클러스터 내부 Authentication/Console Operator Degraded를 모두 다룬다.

## 아키텍처

```
노트북 ──VPN(F5)──► Bastion(.75) ──HAProxy──► master01(.78)
                    DNS(named/dnsmasq)          worker01(.63)
```

---

## 문제 1: 노트북 oc CLI 매 요청 5초 지연

### 근본 원인

macOS `mDNSResponder`가 DNS 서버를 `/etc/hosts`보다 우선 쿼리한다. VPN DNS(`10.240.31.130`)가 `poc.mobis.com`을 NXDOMAIN으로 반환(7ms)하지만, 로컬 DNS(`168.126.63.1`) 폴백 + IPv6 AAAA 쿼리 타임아웃으로 **총 5초 지연** 후에야 hosts 파일로 폴백한다.

```
curl/oc → mDNSResponder
  → VPN DNS(10.240.31.130) A쿼리 → NXDOMAIN (7ms)
  → VPN DNS AAAA쿼리 → NXDOMAIN (7ms)
  → 로컬 DNS(168.126.63.1) A+AAAA → 타임아웃 (5초)
  → /etc/hosts → 10.240.252.75 → 연결
  총: ~5초
```

### 진단 명령

~~~bash
# DNS 경유 vs 우회 비교
curl -sk -o /dev/null -w "total=%{time_total}s\n" https://api.poc.mobis.com:6443/healthz
# → 5.07초

curl -4 -sk -o /dev/null -w "total=%{time_total}s\n" https://api.poc.mobis.com:6443/healthz
# → 0.05초

curl -sk -o /dev/null -w "total=%{time_total}s\n" \
  --resolve "api.poc.mobis.com:6443:10.240.252.75" https://api.poc.mobis.com:6443/healthz
# → 0.05초

# Go resolver vs macOS resolver
GODEBUG=netdns=go oc get nodes   # 0.4초
GODEBUG=netdns=cgo oc get nodes  # 5.5초
~~~

### 해결

~~~bash
echo 'export GODEBUG=netdns=go' >> ~/.zshrc
source ~/.zshrc
~~~

`oc`, `kubectl`, `helm` 등 Go 기반 CLI가 `/etc/hosts`를 직접 읽어 macOS DNS 타임아웃을 우회한다.

| 명령 | Before | After |
|------|--------|-------|
| `oc get nodes` | 5.5초 | **0.42초** |
| `oc whoami` | 5.3초 | **0.35초** |
| `oc get pods -A` | 10초+ | **0.63초** |

### 보조: macOS /etc/resolver 설정

~~~bash
sudo mkdir -p /etc/resolver
sudo tee /etc/resolver/poc.mobis.com << 'EOF'
nameserver 127.0.0.1
search_order 1
timeout 1
EOF
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
~~~

---

## 문제 2: Authentication/Console Operator Degraded 반복

### 근본 원인

Authentication Operator가 `oauth-openshift.apps.poc.mobis.com/healthz`를 호출하여 상태를 확인한다. 이 도메인이 노드 `/etc/hosts`에 없으면 CoreDNS → Bastion DNS 경유가 필요한데, Bastion DNS가 순단되면 healthz 실패 → Pod 재생성 반복.

```
Operator → https://oauth-openshift.apps.poc.mobis.com/healthz
  → /etc/hosts에 없음
  → CoreDNS → forward → Bastion(.75) DNS
  → Bastion 순단 → EOF/타임아웃
  → healthz 실패 → Degraded → Pod 재생성
```

### 이중 의존성 루프

~~~
resolv.conf → .75(Bastion) → 실패 시
           → .78(CoreDNS) → forward → .75 (같은 죽은 서버)
~~~

폴백이 폴백이 아니다 — 결국 같은 Bastion을 호출한다.

### 해결

양쪽 노드의 `/etc/hosts`에 추가:

~~~bash
# master01, worker01 모두
echo '10.240.252.78 api.poc.mobis.com api-int.poc.mobis.com console-openshift-console.apps.poc.mobis.com oauth-openshift.apps.poc.mobis.com' >> /etc/hosts
~~~

### 검증

~~~bash
oc get co authentication console
# Available=True, Degraded=False 확인

oc get pods -n openshift-authentication -o wide
# Running 1/1
~~~

### 주의: DNS Operator와 CoreDNS

DNS Operator가 CoreDNS ConfigMap(`dns-default`)을 관리하므로, `hosts` 플러그인을 직접 추가해도 **Operator가 즉시 덮어쓴다**. `/etc/hosts` 수동 추가는 노드 리붓 시 사라지므로, 영구 해결은 MachineConfig 적용(유지보수 창 필요).

---

## 노트북 hosts 파일 필수 엔트리

~~~
10.240.252.75 console-openshift-console.apps.poc.mobis.com oauth-openshift.apps.poc.mobis.com api.poc.mobis.com api-int.poc.mobis.com
10.240.252.75 rh-ai.apps.poc.mobis.com maas.apps.poc.mobis.com
~~~

---

## 문제 3: 클러스터 전체 DNS 불안정 — 근본 원인 분석 (2026-05-22)

### 증상

- API 서버 간헐적 타임아웃 (`connection refused`)
- OAuth 로그인 실패
- Route 기반 서비스(Console, Dashboard, MaaS) 접속 불안정
- Pod 내부에서 `*.apps.poc.mobis.com` 해석 실패 또는 지연

### DNS 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│ 외부 DNS (mobis.com 권위 DNS)                            │
│   10.230.14.51 / 10.10.156.141                          │
│   - *.mobis.com 관리                                     │
│   - poc.mobis.com 위임 없음 → NXDOMAIN                   │
└──────────────────────────┬──────────────────────────────┘
                           │ forward only (53/tcp)
┌──────────────────────────┴──────────────────────────────┐
│ Bastion BIND (10.240.252.75)                            │
│   - poc.mobis.com zone 로컬 관리                         │
│   - 그 외 → forward only → 외부 DNS                      │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────┐
│ 노드 /etc/resolv.conf                                   │
│   nameserver 10.240.252.75 (bastion)                    │
│   nameserver 10.240.252.78 (master01)                   │
│   search poc.mobis.com                                  │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────┐
│ OpenShift CoreDNS (172.30.0.10)                         │
│   - cluster.local → 내부 처리                            │
│   - 나머지 → upstreamResolvers (SystemResolvConf)        │
└─────────────────────────────────────────────────────────┘
```

### 근본 원인 (3가지 동시 발생)

#### 원인 1: Bastion zone 파일 IP 오류

`poc.mobis.com.zone`에서 `api`, `api-int`, `*.apps`가 bastion 자신(75)을 가리킴. HAProxy가 있었으나 실제 서비스는 master01(78)에 위치.

```
# 수정 전 (잘못됨)                   # 수정 후 (올바름)
api      IN A 10.240.252.75         api      IN A 10.240.252.78
api-int  IN A 10.240.252.75         api-int  IN A 10.240.252.78
*.apps   IN A 10.240.252.75         *.apps   IN A 10.240.252.78
                                    maas.apps IN A 10.240.252.81  ← 신규
```

**영향**: API/OAuth/Console 트래픽이 bastion(75)으로 가서 연결 실패.

#### 원인 2: CoreDNS가 poc.mobis.com 일부만 내부 처리

DNS Operator에서 4개 호스트명만 내부 DNS(custom-dns)로 포워딩하고, 나머지 `*.poc.mobis.com`은 외부로 나감.

```yaml
# 수정 전 (4개만 내부)               # 수정 후 (전체 도메인)
zones:                              zones:
- oauth-openshift.apps...           - poc.mobis.com
- api-int.poc.mobis.com
- api.poc.mobis.com
- maas.apps.poc.mobis.com
upstreams: ["172.30.44.135:53"]     upstreams: ["10.240.252.75:53"]
```

**영향**: `console.apps`, `rh-ai.apps` 등 20+개 Route 호스트가 외부 DNS로 나가서 NXDOMAIN.

#### 원인 3: 외부 DNS가 poc.mobis.com을 모름

`mobis.com`은 외부 DNS(10.230.14.51 / 10.10.156.141)가 관리하는 실제 회사 도메인. `poc.mobis.com` 서브도메인에 대한 NS 위임(delegation)이 없음.

```
Pod가 "rh-ai.apps.poc.mobis.com" 조회
  → CoreDNS: zones에 없음 → upstream → bastion BIND
    → poc.mobis.com zone에 개별 레코드 없음
    → *.apps 와일드카드 매칭 → 75 반환 → 연결 실패

어떤 경로로 외부 DNS 도달 시:
  → 외부 DNS: "mobis.com은 내가 권위 DNS인데, poc은 없음"
    → NXDOMAIN → 클러스터 깨짐
```

### 해결

#### Step 1: Bastion zone 파일 수정

~~~bash
# /var/named/poc.mobis.com.zone
$TTL 86400
@   IN  SOA     bastion.poc.mobis.com. root.bastion.poc.mobis.com. (
           2026052201 ; Serial
           3600       ; Refresh
           1800       ; Retry
           604800     ; Expire
           86400 )    ; Minimum TTL
    IN  NS      bastion.poc.mobis.com.

bastion         IN  A   10.240.252.75
api             IN  A   10.240.252.78
api-int         IN  A   10.240.252.78
*.apps          IN  A   10.240.252.78
maas.apps       IN  A   10.240.252.81
master01        IN  A   10.240.252.78
worker01        IN  A   10.240.252.63
~~~

~~~bash
named-checkzone poc.mobis.com /var/named/poc.mobis.com.zone
systemctl restart named
~~~

#### Step 2: OpenShift DNS Operator 수정

~~~bash
oc patch dns.operator.openshift.io default --type=merge -p '{
  "spec": {
    "servers": [
      {
        "name": "poc-private",
        "zones": ["poc.mobis.com"],
        "forwardPlugin": {
          "policy": "Sequential",
          "upstreams": ["10.240.252.75:53"]
        }
      }
    ]
  }
}'
~~~

#### Step 3: 검증

~~~bash
# bastion 직접
dig @10.240.252.75 api.poc.mobis.com +short              # → 78
dig @10.240.252.75 maas.apps.poc.mobis.com +short         # → 81

# CoreDNS 경유
dig @172.30.0.10 api.poc.mobis.com +short                 # → 78
dig @172.30.0.10 maas.apps.poc.mobis.com +short            # → 81
dig @172.30.0.10 rh-ai.apps.poc.mobis.com +short           # → 78
~~~

### 수정 후 DNS 흐름

```
Pod → CoreDNS (172.30.0.10)
  ├─ cluster.local → 내부 처리
  ├─ *.poc.mobis.com → bastion BIND (10.240.252.75) → zone 파일 즉시 응답
  └─ 그 외 → upstream → bastion → forward → 외부 DNS (51/141)
```

- `poc.mobis.com` 쿼리는 **절대 외부 DNS에 도달하지 않음**
- `*.mobis.com` (회사 도메인)은 기존대로 외부 DNS에서 정상 해석

### custom-dns (우회용)

```
namespace: custom-dns
deploy: oauth-route-dns (CoreDNS v1.11.3)
service: 172.30.44.135:53
```

원인 2를 우회하기 위해 만든 클러스터 내부 DNS Pod. 4개 호스트명을 정적 IP로 응답하는 역할이었음. DNS Operator가 bastion으로 직접 포워딩하므로 더 이상 사용되지 않음. 리소스 미미하여 유지 중.

### 교훈

1. **에어갭 환경에서 DNS zone 파일의 IP는 반드시 실제 서비스 호스트를 가리켜야 한다** — bastion(LB 역할 없이)을 가리키면 안 됨
2. **CoreDNS 포워딩은 개별 호스트가 아닌 도메인 단위로 설정해야 한다** — 새 Route가 추가될 때마다 DNS 설정을 변경하는 것은 운영 불가
3. **프라이빗 서브도메인(poc.mobis.com)의 상위 도메인(mobis.com)이 외부 DNS에 존재할 때, 프라이빗 쿼리가 외부로 유출되지 않도록 CoreDNS 레벨에서 차단해야 한다**

---

## 다음 단계

→ `runbooks/100-platform-setup.md`

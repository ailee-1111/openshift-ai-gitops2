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

## 다음 단계

→ `runbooks/100-platform-setup.md`

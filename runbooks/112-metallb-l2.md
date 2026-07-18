# 112 — MetalLB L2 모드 구성

## 목적

Bare metal 클러스터에서 LoadBalancer 타입 서비스에 외부 IP를 할당하기 위해 MetalLB를 L2(ARP) 모드로 구성한다.

## 전제 조건

- [ ] MetalLB Operator 설치 완료 (`oc get csv -A | grep metallb`)
- [ ] VIP용 미사용 IP 대역 확보 (서브넷 ping 스캔으로 충돌 확인)
- [ ] 환경변수: `VIP_RANGE_START`, `VIP_RANGE_END`

## 실행

### 0. IP 충돌 사전 스캔

~~~bash
: "${VIP_RANGE_START:=80}"
: "${VIP_RANGE_END:=89}"
SUBNET="10.240.252"

echo "=== ${SUBNET}.${VIP_RANGE_START}~${VIP_RANGE_END} 스캔 ==="
oc debug node/master01.poc.customer.com -- chroot /host \
  bash -c "
for i in \$(seq ${VIP_RANGE_START} ${VIP_RANGE_END}); do
  IP=\"${SUBNET}.\${i}\"
  if ping -c 1 -W 1 \${IP} > /dev/null 2>&1; then
    echo \"  \${IP} — 사용 중 [충돌]\"
  else
    echo \"  \${IP} — 비어 있음\"
  fi
done
"
~~~

### 1. MetalLB CR 생성

~~~bash
oc apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: MetalLB
metadata:
  name: metallb
  namespace: metallb-system
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
EOF

echo "Speaker Pod 배포 대기..."
for i in $(seq 1 24); do
  READY=$(oc get pods -n metallb-system -l component=speaker --no-headers 2>/dev/null | grep -c "Running")
  [[ "${READY}" -ge 1 ]] && echo "[PASS] Speaker Running" && break
  sleep 5
done
~~~

### 2. IPAddressPool 생성

~~~bash
SUBNET="10.240.252"
: "${VIP_RANGE_START:=80}"
: "${VIP_RANGE_END:=89}"

oc apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: poc-pool
  namespace: metallb-system
spec:
  addresses:
    - ${SUBNET}.${VIP_RANGE_START}-${SUBNET}.${VIP_RANGE_END}
EOF
~~~

### 3. L2Advertisement 생성

~~~bash
oc apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: poc-l2adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - poc-pool
EOF
~~~

### 4. 동작 검증 (테스트 서비스)

~~~bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: metallb-test
  namespace: default
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: metallb-test-dummy
EOF

sleep 5
oc get svc metallb-test -n default
EXT_IP=$(oc get svc metallb-test -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP: ${EXT_IP}"
[[ -n "${EXT_IP}" ]] && echo "[PASS]" || echo "[FAIL]"

oc delete svc metallb-test -n default
~~~

## 검증

~~~bash
echo "=== MetalLB 검증 ==="
echo "1) MetalLB CR:"
oc get metallb -n metallb-system

echo "2) Speaker Pod:"
oc get pods -n metallb-system -l component=speaker -o wide --no-headers

echo "3) IPAddressPool:"
oc get ipaddresspool -n metallb-system

echo "4) L2Advertisement:"
oc get l2advertisement -n metallb-system
~~~

## 실패 시

- **Speaker Pod 미배포** → nodeSelector 확인, worker 노드에 `node-role.kubernetes.io/worker` 라벨 존재 여부
- **VIP 미할당 (Pending)** → IPAddressPool 주소 범위 확인, L2Advertisement가 pool을 참조하는지 확인
- **VIP 충돌** → `arping -D -I br-ex <VIP>` 로 중복 ARP 확인
- **외부 접근 불가** → 같은 L2 서브넷에서만 접근 가능 (다른 서브넷은 라우팅 필요)

## BGP 모드 전환 시

네트워크 팀에서 아래 정보를 받은 후 BGPPeer + BGPAdvertisement 추가:

~~~yaml
# BGPPeer 예시
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: tor-switch
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 64513
  peerAddress: 10.240.252.1
~~~

## 다음 단계

→ `runbooks/200-model-registry.md`

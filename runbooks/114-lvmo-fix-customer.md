# 114 — LVMO vg-master Degraded 수정

## 목적

LVMCluster의 `vg-master` deviceSelector에 존재하지 않는 디바이스(`/dev/sde`)가 지정되어 Degraded 상태인 문제를 수정한다.

## 전제 조건

- [ ] LVM Storage Operator 설치 완료
- [ ] LVMCluster CR 존재

## 진단

### 1. LVMCluster 상태 확인

~~~bash
oc get lvmcluster -n openshift-storage
# STATUS: Degraded
~~~

### 2. Degraded 원인 확인

~~~bash
oc get lvmcluster lvmcluster -n openshift-storage \
  -o jsonpath='{.status.deviceClassStatuses[?(@.name=="vg-master")].nodeStatus[0].reason}'
# "failed to resolve symlink ... lstat /dev/sde: no such file or directory"
~~~

### 3. 실제 VG 구성 확인

~~~bash
oc debug node/master01.poc.customer.com -- chroot /host pvs
#   /dev/sda   vg-master   3.49t
#   /dev/sdc   vg-master   6.99t
# → /dev/sde는 존재하지 않음
~~~

### 4. 블록 디바이스 확인

~~~bash
oc debug node/master01.poc.customer.com -- chroot /host \
  lsblk -o NAME,SIZE,TYPE,FSTYPE | grep -E "^sd"
# sda   3.5T  disk  LVM2_member  ← VG에 사용 중
# sdb   893G  disk               ← OS 부트 디스크
# sdc   7T    disk  LVM2_member  ← VG에 사용 중
~~~

## 실행

~~~bash
oc patch lvmcluster lvmcluster -n openshift-storage --type=json \
  -p '[
    {
      "op": "replace",
      "path": "/spec/storage/deviceClasses/0/deviceSelector/paths",
      "value": ["/dev/sda", "/dev/sdc"]
    }
  ]'
~~~

## 검증

~~~bash
echo "=== LVMCluster 상태 ==="
oc get lvmcluster -n openshift-storage

echo "=== VG 상태 ==="
oc get lvmcluster lvmcluster -n openshift-storage \
  -o jsonpath='{range .status.deviceClassStatuses[*]}{.name}: {.nodeStatus[0].status} [{.nodeStatus[0].devices}]{"\n"}{end}'

echo "=== PVC ==="
oc get pvc -A --no-headers | grep lvms | wc -l
echo "PVCs bound"
~~~

### 결과

| 항목 | Before | After |
|------|--------|-------|
| LVMCluster | Degraded | Ready (또는 Progressing → Ready) |
| vg-master | Degraded (`/dev/sde` 없음) | Ready (`/dev/sda` + `/dev/sdc` = 10.5TB) |
| vg-worker | Ready | Ready (`/dev/sdb`) |
| PVC 12개 | 모두 Bound | 모두 Bound |

## 실패 시

- **Progressing 지속** → VG readiness check 완료까지 수 분 소요. 양쪽 VG Ready이면 기능적으로 정상
- **VG 크기 불일치** → `pvs`, `vgs` 로 실제 VG 크기 확인

## 다음 단계

→ `runbooks/200-model-registry.md`

# 000 — Preflight (읽기 전용 전제조건 점검)

## 목적

Phase 1에 진입하기 전, **기존 OpenShift 클러스터의 상태와 제약을 읽기 전용으로 파악**한다. 본 runbook은 어떤 리소스도 생성·수정하지 않는다. 산출물은 `claude-context/current-state.md`·`version-matrix.md`·`constraints.md`를 채우는 근거로 사용된다.

## 전제 조건

- [ ] `.env` 작성 완료 (`KUBECONFIG`, `CLUSTER_DOMAIN`, `OCP_AI_ENV_MODE`)
- [ ] `oc` CLI 설치 (`oc version --client` 정상)
- [ ] `KUBECONFIG`가 가리키는 kubeconfig로 클러스터 접속 가능
- [ ] 사용 계정이 최소 `view` 권한 (`cluster-admin`이면 더 좋음, 단 읽기만 수행)

## 실행

아래 블록은 **모두 읽기 전용**이며 독립 실행 가능하다. 각 블록 결과를 해당 Layer 2 파일에 **사람이** 옮겨 적는다. AI는 `version-matrix.md`에 직접 쓰지 않는다 (`guidelines/05-state-management.md`).

### 0-1. 환경 변수 로드 및 접속 확인

```bash
# 환경 변수 로드
set -a; source .env; set +a

# 접속 확인
oc whoami
oc whoami --show-server
oc cluster-info | head -3
```

### 0-2. OpenShift 버전 → `version-matrix.md`

```bash
# ClusterVersion
oc get clusterversion version -o jsonpath='{.status.desired.version}'; echo
oc get clusterversion version -o jsonpath='{.status.channel}'; echo

# 노드 요약 (OS·Kubelet 버전)
oc get nodes -o wide
```

### 0-3. 기존 Operator 목록 → `version-matrix.md`

```bash
# 클러스터 전체 CSV (Operator 인스턴스)
oc get csv -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase'

# Subscription (설치 채널 파악용)
oc get subscription -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PACKAGE:.spec.name,CHANNEL:.spec.channel,SOURCE:.spec.source'

# OperatorHub 기본 카탈로그 상태
oc get catalogsource -n openshift-marketplace
```

### 0-4. ArgoCD / GitOps 유무 → `constraints.md`

```bash
# OpenShift GitOps Operator 설치 여부
oc get csv -A | grep -i -E 'gitops|argocd' || echo '(none)'

# 네임스페이스 후보들
oc get ns openshift-gitops openshift-gitops-operator 2>/dev/null || echo '(ns not present)'

# ArgoCD CR (있으면)
oc get argocd -A 2>/dev/null || echo '(argocd CR not present)'
```

### 0-5. 기존 RHOAI 설치 여부 → `constraints.md`

```bash
# RHOAI Operator CSV
oc get csv -A | grep -i 'rhods\|opendatahub\|openshift-ai' || echo '(none)'

# DataScienceCluster / DSCInitialization CR
oc get datasciencecluster -A 2>/dev/null || echo '(DSC not present)'
oc get dscinitialization -A 2>/dev/null || echo '(DSCI not present)'

# 예상 네임스페이스들
for ns in redhat-ods-operator redhat-ods-applications rhods-notebooks; do
  oc get ns "$ns" 2>/dev/null || true
done
```

### 0-6. 기반 인프라 상태 → `current-state.md`

```bash
# Ingress 도메인 (실제 CLUSTER_DOMAIN과 일치 확인)
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'; echo

# API endpoint
oc whoami --show-server

# StorageClass (DSC의 PVC가 필요로 함)
oc get storageclass

# 워커 노드 capacity 요약
oc get nodes -l node-role.kubernetes.io/worker -o custom-columns='NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory'
```

### 0-7. GPU 관련 선점 상태 → `constraints.md` (해당 시)

```bash
# NFD / GPU Operator 존재 확인 (없으면 정상)
oc get csv -A | grep -i -E 'nfd|gpu-operator' || echo '(GPU stack not present)'

# GPU 라벨이 붙은 노드
oc get nodes -l 'nvidia.com/gpu.present=true' 2>/dev/null || echo '(no GPU nodes labeled)'
```

### 0-8. 네트워크 정책·제약 → `constraints.md`

```bash
# 전체 네트워크 정책 개수 (존재만 확인)
oc get networkpolicy -A --no-headers 2>/dev/null | wc -l

# Cluster Proxy (Air-gap 힌트)
oc get proxy/cluster -o jsonpath='{.spec}' | head -c 500; echo

# ImageContentSourcePolicy / ImageDigestMirrorSet (미러 레지스트리 힌트)
oc get imagecontentsourcepolicy 2>/dev/null || true
oc get imagedigestmirrorset 2>/dev/null || true
```

> **Bare metal / Restricted 환경 참고**:
> - 스토리지 클래스: AWS `gp3-csi` 대신 `lvms-vg1` (LVM Storage) — `oc get storageclass`로 확인
> - DNS: 외부 DNS 미사용 시 CoreDNS upstream 설정 필요 (`runbooks/113-dns-troubleshoot-customer.md`)
> - NTP: chrony 로컬 서버 구성 필요 (Restricted 환경에서 외부 NTP 불가)
> - 이미지 미러링: Restricted 환경에서는 oc-mirror 사전 구성 필요 (`OC_MIRROR_WORKSPACE` 참조)
> - MetalLB: bare metal 환경에서 LoadBalancer 서비스 필요 시 (`runbooks/112-metallb-l2.md`)

## 검증

전체 블록 실행 후 **아래 체크리스트를 사람이 수동 확인**한다. 각 항목을 해당 Layer 2 파일에 기록했을 때 "검증 통과"로 간주.

- [ ] `current-state.md` — OpenShift 버전 · API endpoint · 도메인 3개 placeholder 모두 채워짐
- [ ] `version-matrix.md` — OpenShift 행 + 기존 설치된 Operator 행 모두 채워짐
- [ ] `constraints.md` — ArgoCD/RHOAI 기존 설치 유무, GPU 스택 유무, Proxy/Mirror 설정 기록
- [ ] 기록되지 않은 "예상 외" 리소스(Unknown Operator 등)는 `constraints.md`에 **발견된 그대로** 추가

## 실패 시

| 증상 | 원인 | 대응 |
|---|---|---|
| `oc: command not found` | CLI 미설치 | `oc` 설치 후 재실행 |
| `Unauthorized` / `error: You must be logged in` | kubeconfig 만료·잘못된 경로 | `KUBECONFIG` 재확인, `oc login` 재수행 |
| `no matches for kind "ArgoCD"` | CR 없음 (GitOps 미설치) | 정상. `(none)`으로 기록 |
| `the server could not find the requested resource` on DSC | RHOAI 미설치 | 정상. `(none)`으로 기록 |
| `clusterversion` 조회 권한 거부 | `view` 권한 부족 | 관리자에게 `cluster-reader` 요청 |
| Cluster Proxy `httpProxy` 값 존재 | Air-gap 또는 프록시 환경 | `constraints.md`에 기록, `work-plans/001-dual-env-strategy.md`의 `OCP_AI_ENV_MODE` 결정에 반영 |

## 다음 단계

- Phase 1 체크리스트(`state.md`) 업데이트
- `work-plans/001-dual-env-strategy.md`의 Open Questions 중 **클러스터 확인으로 결정되는 항목** 결론 기록
- 모두 채워지면 → `runbooks/010-argocd-operator-install.md` (Phase 2 시작)

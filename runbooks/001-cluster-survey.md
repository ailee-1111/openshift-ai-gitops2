# 001 — Cluster Survey (Phase 1 현황 조사)

## 목적

기존 OpenShift 클러스터의 **현재 상태를 읽기 전용으로 정밀 조사**하여 Phase 2 이후 작업 계획의 근거를 확보한다. 본 runbook은 어떤 리소스도 생성·수정·삭제하지 않는다.

> **반복 가능성 원칙**: 모든 명령은 `.env` 변수로 파라메터화되어 있으며, 어떤 OCP 4.x 클러스터에서도 재실행 가능하다. 특정 클러스터 값(도메인·IP·버전)을 명령어에 직접 하드코딩하지 않는다.

---

## 전제 조건

- [ ] `.env` 파일 존재 (`CLUSTER_API_URL`, `OCP_ADMIN_USER`, `OCP_ADMIN_PASSWORD` 필수)
- [ ] `oc` CLI 설치 (`oc version --client` 정상)
  - 없으면 클러스터 Console → **?** → **Command Line Tools** 에서 OS 맞는 바이너리 다운로드
  - 또는 `https://mirror.openshift.com/pub/openshift-v4/clients/ocp/`
- [ ] 사용 계정이 `cluster-admin` 또는 최소 `cluster-reader` 권한

---

## 실행 방법

### 방법 A — 스크립트로 한 번에 실행 (권장)

```bash
cd <repo-root>

# 표준 실행 (화면 출력만)
bash scripts/cluster-survey.sh

# 결과를 파일에도 저장 (survey-output/survey-YYYYMMDD-HHmmss.txt)
bash scripts/cluster-survey.sh --save
```

스크립트는 `.env`를 자동으로 `source`하며, 클러스터 로그인부터 전체 조사를 순서대로 수행한다.

### 방법 B — 섹션별 수동 실행

환경 변수를 직접 로드한 후 아래 섹션 1-A ~ 1-G를 순서대로 실행한다.

```bash
set -a; source .env; set +a
```

---

## 1-A. 클러스터 로그인

```bash
oc login \
  --server="${CLUSTER_API_URL}" \
  --username="${OCP_ADMIN_USER}" \
  --password="${OCP_ADMIN_PASSWORD}"
# TLS 오류 시: --insecure-skip-tls-verify=true 추가 (constraints.md에 기록)

oc whoami               # 사용자 확인
oc whoami --show-server # 서버 주소 확인
```

**기대 출력 예시**
```
admin
https://api.<cluster-name>.<base-domain>:6443
```

---

## 1-B. OCP 버전 · 채널 · 노드 구성

```bash
# ClusterVersion (현재 버전·채널)
oc get clusterversion version \
  -o jsonpath='버전: {.status.desired.version}{"\n"}채널: {.status.channel}{"\n"}'

# 노드 목록
oc get nodes \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1:].type,OS:.status.nodeInfo.osImage,K8S:.status.nodeInfo.kubeletVersion' \
  --sort-by=.metadata.name
```

**기대 출력 예시**
```
버전: 4.20.x
채널: stable-4.20

NAME            STATUS   OS                                       K8S
master-0        Ready    Red Hat Enterprise Linux CoreOS 420.x    v1.33.x
worker-0        Ready    Red Hat Enterprise Linux CoreOS 420.x    v1.33.x
```

---

## 1-C. 워커 노드 리소스 여유

```bash
# 워커 노드 capacity
oc get nodes -l node-role.kubernetes.io/worker='' \
  -o custom-columns='NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory,PODS:.status.capacity.pods'

# 워커 노드 allocatable
oc get nodes -l node-role.kubernetes.io/worker='' \
  -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory'

# 현재 사용량 (metrics-server 필요 — 없으면 생략 가능)
oc adm top nodes 2>/dev/null || echo "(metrics-server 미설치)"
```

**RHOAI 최소 요구사항** (참고용):
- RHOAI Operator 자체: CPU 2 / Memory 4Gi
- DataScienceCluster 컴포넌트 합산: CPU 6+ / Memory 16Gi+

---

## 1-D. 설치된 Operator 전체 목록

```bash
# CSV (Operator 인스턴스)
oc get csv -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase' \
  --sort-by=.metadata.namespace

# Subscription (채널·승인 방식)
oc get subscription -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,PACKAGE:.spec.name,CHANNEL:.spec.channel,SOURCE:.spec.source,APPROVAL:.spec.installPlanApproval' \
  --sort-by=.metadata.namespace

# CatalogSource 상태
oc get catalogsource -n openshift-marketplace \
  -o custom-columns='NAME:.metadata.name,STATE:.status.connectionState.lastObservedState'
```

---

## 1-E. RHOAI / OpenShift AI 상태

```bash
# RHOAI/ODH Operator CSV
oc get csv -A | grep -iE 'rhods|opendatahub|openshift-ai|odh' || echo "(none)"

# DataScienceCluster / DSCInitialization CR
oc get datasciencecluster -A -o wide 2>/dev/null || echo "(none)"
oc get dscinitialization -A -o wide 2>/dev/null || echo "(none)"

# 관련 네임스페이스
oc get ns | grep -iE 'rhods|opendatahub|ai-|notebooks' || echo "(none)"
```

**해석**:
- `(none)` → RHOAI 미설치 (Phase 3에서 신규 설치 예정 — 정상)
- 기존 설치 발견 → `constraints.md`에 버전·채널 기록 필수. 기존 설치 위에 재설치 시 충돌 가능성 검토 필요

---

## 1-F. ArgoCD / OpenShift GitOps 상태

```bash
# GitOps Operator CSV
oc get csv -A | grep -iE 'gitops|argocd' || echo "(none)"

# 네임스페이스
oc get ns | grep -iE 'openshift-gitops|argocd' || echo "(none)"

# ArgoCD CR (설치 시)
oc get argocd -A 2>/dev/null || echo "(ArgoCD CRD 없음)"
```

**해석**:
- `(none)` → Phase 2에서 신규 설치 예정 (정상)
- 기존 설치 발견 → `constraints.md`에 버전 기록. 기존 ArgoCD가 관리하는 App 목록 추가 확인 필요

---

## 1-G. 기반 인프라

```bash
# Ingress 도메인 (.env의 CLUSTER_DOMAIN과 일치 여부)
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'; echo

# StorageClass (RHOAI PVC 프로비저닝용)
oc get storageclass

# Cluster Proxy
oc get proxy/cluster -o jsonpath='{.spec}' | python3 -m json.tool 2>/dev/null \
  || echo "(프록시 설정 없음)"

# Image Mirror Policy
oc get imagecontentsourcepolicy 2>/dev/null || echo "(ICSP 없음)"
oc get imagedigestmirrorset 2>/dev/null     || echo "(IDMS 없음)"

# GPU 노드 라벨
oc get nodes -l 'nvidia.com/gpu.present=true' --no-headers 2>/dev/null \
  | wc -l | xargs -I{} echo "GPU 노드 수: {}"

# GPU/NFD Operator
oc get csv -A | grep -iE 'nfd|gpu-operator' || echo "(GPU stack 미설치)"
```

---

## 결과 기록 위치

실행 완료 후 아래 파일을 갱신한다. **`version-matrix.md`는 사람만 갱신**(`guidelines/05-state-management.md`).

| 발견 항목 | 기록 위치 |
|---|---|
| OCP 버전·채널 | `claude-context/version-matrix.md` |
| 기존 설치 Operator 버전·채널 | `claude-context/version-matrix.md` |
| ArgoCD/RHOAI 설치 유무 | `claude-context/current-state.md` (체크박스) |
| 재사용 클러스터 제약 (Proxy, GPU, 기존 Operator 충돌 등) | `claude-context/constraints.md` |
| StorageClass 이름 | `claude-context/constraints.md` |

---

## 실패 시 대응

| 증상 | 원인 | 대응 |
|---|---|---|
| `oc: command not found` | CLI 미설치 | Console → Command Line Tools 또는 mirror.openshift.com |
| `Login failed (401)` | 잘못된 인증 | `.env`의 `OCP_ADMIN_USER`/`OCP_ADMIN_PASSWORD` 재확인 |
| `x509: certificate signed by unknown authority` | 자가서명 인증서 | `--insecure-skip-tls-verify=true` 추가 → `constraints.md`에 기록 |
| `no matches for kind "DataScienceCluster"` | RHOAI 미설치 | 정상. `(none)`으로 기록 |
| `no matches for kind "ArgoCD"` | GitOps 미설치 | 정상. `(none)`으로 기록 |
| `adm top nodes` 오류 | metrics-server 없음 | 생략 가능. 이후 설치 예정 |
| `.env` 파일 없음 | 초기 설정 미완 | `.env.example`을 복사하여 값 채우기 |

---

## 다음 단계

조사 완료 후 `claude-context/` 파일 갱신 → `runbooks/010-argocd-operator-install.md` (Phase 2: ArgoCD 설치)

---

## 참고: 스크립트 실행 예시

```bash
$ bash scripts/cluster-survey.sh --save

=====================================================
  OpenShift Cluster Survey — Phase 1
  실행 시각: 2026-04-19 HH:MM:SS KST
  대상 클러스터: https://api.<...>:6443
=====================================================

══════════════════════════════════════
  1-A. 클러스터 로그인
══════════════════════════════════════
[INFO] TLS 검증 활성화 상태로 로그인 성공
로그인 사용자: admin
서버 주소:     https://api.<...>:6443

══════════════════════════════════════
  1-B. OCP 버전 및 노드 구성
══════════════════════════════════════
버전: 4.20.x
채널: stable-4.20

NAME           STATUS  OS                                      K8S
master-0       Ready   Red Hat Enterprise Linux CoreOS 420.x  v1.33.x
worker-0       Ready   Red Hat Enterprise Linux CoreOS 420.x  v1.33.x
worker-1       Ready   Red Hat Enterprise Linux CoreOS 420.x  v1.33.x
...
```

## 검증

~~~bash
# survey 출력 파일 존재 확인
ls -la survey-output/survey-*.txt
# 기대: 1개 이상의 survey 파일
~~~

## 다음 단계

→ `runbooks/010-argocd-operator-install.md`

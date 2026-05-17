#!/usr/bin/env bash
# =============================================================================
# cluster-survey.sh — Phase 1 클러스터 현황 조사
# =============================================================================
# 목적: 기존 OpenShift 클러스터의 상태를 읽기 전용으로 조사한다.
#       어떤 OCP 4.x 클러스터에서도 재실행 가능하도록 파라메터화됨.
#
# 사용법:
#   cd <repo-root>
#   bash scripts/cluster-survey.sh [--save]
#
# 옵션:
#   --save   결과를 survey-output/ 디렉토리에 파일로도 저장
#
# 전제 조건:
#   - .env 파일 존재 (CLUSTER_API_URL, OCP_ADMIN_USER, OCP_ADMIN_PASSWORD 필수)
#   - oc CLI 설치됨 (oc version --client 정상)
#
# 반복 가능성: 이 스크립트는 읽기 전용이며 몇 번 실행해도 idempotent하다.
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────
# 색상 & 헬퍼
# ─────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

section()  { echo; echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; echo -e "${BOLD}${CYAN}  $1${RESET}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; }
info()     { echo -e "${GREEN}[INFO]${RESET} $*"; }
warn()     { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()      { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
safe_run() { "$@" 2>/dev/null || echo "(조회 결과 없음 — 리소스 미존재 또는 권한 부족)"; }

# ─────────────────────────────────────────────
# 옵션 파싱
# ─────────────────────────────────────────────
SAVE_OUTPUT=false
for arg in "$@"; do
  [[ "$arg" == "--save" ]] && SAVE_OUTPUT=true
done

# ─────────────────────────────────────────────
# .env 로드 (repo root 기준)
# ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  err ".env 파일을 찾을 수 없습니다: $ENV_FILE"
  err ".env.example을 참고하여 .env를 작성하세요."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ─────────────────────────────────────────────
# 필수 변수 확인
# ─────────────────────────────────────────────
REQUIRED_VARS=(CLUSTER_API_URL OCP_ADMIN_USER OCP_ADMIN_PASSWORD)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    err "필수 환경 변수 미설정: $var (.env 확인 필요)"
    exit 1
  fi
done

# ─────────────────────────────────────────────
# oc CLI 확인
# ─────────────────────────────────────────────
if ! command -v oc &>/dev/null; then
  err "oc CLI를 찾을 수 없습니다."
  err "설치 방법: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"
  err "또는 클러스터 Console → ? → Command Line Tools 에서 다운로드"
  exit 1
fi

# ─────────────────────────────────────────────
# 출력 저장 설정 (--save 옵션)
# ─────────────────────────────────────────────
OUTPUT_DIR="${REPO_ROOT}/survey-output"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/survey-${TIMESTAMP}.txt"

if [[ "$SAVE_OUTPUT" == true ]]; then
  mkdir -p "$OUTPUT_DIR"
  # tee로 화면 + 파일 동시 출력
  exec > >(tee -a "$OUTPUT_FILE") 2>&1
  info "결과를 파일에도 저장합니다: $OUTPUT_FILE"
fi

# ─────────────────────────────────────────────
# 조사 시작
# ─────────────────────────────────────────────
echo
echo -e "${BOLD}=====================================================${RESET}"
echo -e "${BOLD}  OpenShift Cluster Survey — Phase 1${RESET}"
echo -e "${BOLD}  실행 시각: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
echo -e "${BOLD}  대상 클러스터: ${CLUSTER_API_URL}${RESET}"
echo -e "${BOLD}=====================================================${RESET}"

# ─────────────────────────────────────────────
# 1-A. 로그인
# ─────────────────────────────────────────────
section "1-A. 클러스터 로그인"

# insecure-skip-tls-verify 자동 fallback
if oc login \
    --server="${CLUSTER_API_URL}" \
    --username="${OCP_ADMIN_USER}" \
    --password="${OCP_ADMIN_PASSWORD}" \
    --insecure-skip-tls-verify=false 2>/dev/null; then
  info "TLS 검증 활성화 상태로 로그인 성공"
elif oc login \
    --server="${CLUSTER_API_URL}" \
    --username="${OCP_ADMIN_USER}" \
    --password="${OCP_ADMIN_PASSWORD}" \
    --insecure-skip-tls-verify=true; then
  warn "자가서명 인증서 — TLS 검증 비활성화로 로그인 (constraints.md에 기록 필요)"
else
  err "로그인 실패. 인증 정보 또는 클러스터 API URL을 확인하세요."
  exit 1
fi

echo "로그인 사용자: $(oc whoami)"
echo "서버 주소:     $(oc whoami --show-server)"

# ─────────────────────────────────────────────
# 1-B. OCP 버전 · 채널 · 노드 구성
# ─────────────────────────────────────────────
section "1-B. OCP 버전 및 노드 구성"

echo "--- ClusterVersion ---"
oc get clusterversion version \
  -o jsonpath='버전: {.status.desired.version}{"\n"}채널: {.spec.channel}{"\n"}'
# history 슬라이스([0:3])는 항목이 3개 미만이면 array index out of bounds로 실패.
# range .status.history[*] 로 전체를 순회하고 head로 최근 3개만 표시.
echo -n "업데이트 이력(최근 3): "
oc get clusterversion version \
  -o jsonpath='{range .status.history[*]}{.version}({.state}) {end}' 2>/dev/null \
  | tr ' ' '\n' | head -3 | tr '\n' ' '; echo

echo
echo "--- 노드 목록 ---"
oc get nodes \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1:].type,OS:.status.nodeInfo.osImage,K8S:.status.nodeInfo.kubeletVersion' \
  --sort-by=.metadata.name

echo
echo "--- 역할별 노드 수 ---"
echo "Control-plane: $(oc get nodes -l node-role.kubernetes.io/master --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "Worker:        $(oc get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "Infra:         $(oc get nodes -l node-role.kubernetes.io/infra  --no-headers 2>/dev/null | wc -l | tr -d ' ')"

# ─────────────────────────────────────────────
# 1-C. 노드 리소스 여유
# ─────────────────────────────────────────────
section "1-C. 워커 노드 리소스 여유"

echo "--- Capacity ---"
oc get nodes -l node-role.kubernetes.io/worker='' \
  -o custom-columns='NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,PODS:.status.capacity.pods' \
  2>/dev/null || oc get nodes \
  -o custom-columns='NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,PODS:.status.capacity.pods'

echo
echo "--- Allocatable ---"
oc get nodes -l node-role.kubernetes.io/worker='' \
  -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory' \
  2>/dev/null || oc get nodes \
  -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory'

echo
echo "--- Top Nodes (metrics-server 필요) ---"
safe_run oc adm top nodes

# ─────────────────────────────────────────────
# 1-D. 설치된 Operator 전체 목록
# ─────────────────────────────────────────────
section "1-D. 설치된 Operator 목록 (CSV)"

echo "--- ClusterServiceVersions ---"
safe_run oc get csv -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase' \
  --sort-by=.metadata.namespace

echo
echo "--- Subscriptions (채널 정보) ---"
safe_run oc get subscription -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,PACKAGE:.spec.name,CHANNEL:.spec.channel,SOURCE:.spec.source,APPROVAL:.spec.installPlanApproval' \
  --sort-by=.metadata.namespace

echo
echo "--- CatalogSources (OperatorHub 상태) ---"
safe_run oc get catalogsource -n openshift-marketplace \
  -o custom-columns='NAME:.metadata.name,STATE:.status.connectionState.lastObservedState,UPDATED:.status.connectionState.lastConnect'

# ─────────────────────────────────────────────
# 1-E. RHOAI / OpenShift AI 상태
# ─────────────────────────────────────────────
section "1-E. RHOAI / OpenShift AI 상태"

echo "--- RHOAI/ODH CSV ---"
oc get csv -A 2>/dev/null | grep -iE 'rhods|opendatahub|openshift-ai|odh' \
  || echo "(none — RHOAI 미설치)"

echo
echo "--- DataScienceCluster CR ---"
safe_run oc get datasciencecluster -A -o wide

echo
echo "--- DSCInitialization CR ---"
safe_run oc get dscinitialization -A -o wide

echo
echo "--- RHOAI 관련 네임스페이스 ---"
oc get ns 2>/dev/null \
  | grep -iE 'rhods|opendatahub|ai-|notebooks' \
  || echo "(none)"

# ─────────────────────────────────────────────
# 1-F. ArgoCD / OpenShift GitOps
# ─────────────────────────────────────────────
section "1-F. ArgoCD / OpenShift GitOps 상태"

echo "--- GitOps Operator CSV ---"
oc get csv -A 2>/dev/null | grep -iE 'gitops|argocd' \
  || echo "(none — OpenShift GitOps 미설치)"

echo
echo "--- GitOps 관련 네임스페이스 ---"
oc get ns 2>/dev/null | grep -iE 'openshift-gitops|argocd' \
  || echo "(none)"

echo
echo "--- ArgoCD CR ---"
safe_run oc get argocd -A

# ─────────────────────────────────────────────
# 1-G. 기반 인프라
# ─────────────────────────────────────────────
section "1-G. 기반 인프라"

echo "--- Ingress 도메인 ---"
actual_domain=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "조회 실패")
echo "Ingress 도메인: $actual_domain"
if [[ -n "${CLUSTER_DOMAIN:-}" && "$actual_domain" != "$CLUSTER_DOMAIN" ]]; then
  warn ".env의 CLUSTER_DOMAIN($CLUSTER_DOMAIN)과 실제 도메인($actual_domain)이 다릅니다."
fi

echo
echo "--- StorageClass ---"
safe_run oc get storageclass

echo
echo "--- Cluster Proxy 설정 ---"
proxy_spec=$(oc get proxy/cluster -o jsonpath='{.spec}' 2>/dev/null || echo "")
if [[ -z "$proxy_spec" || "$proxy_spec" == "{}" ]]; then
  echo "(프록시 설정 없음)"
else
  echo "$proxy_spec" | python3 -m json.tool 2>/dev/null || echo "$proxy_spec"
  warn "Proxy 설정 발견 → constraints.md에 기록 필요"
fi

echo
echo "--- Image Mirror Policy ---"
oc get imagecontentsourcepolicy 2>/dev/null || echo "(ICSP 없음)"
oc get imagedigestmirrorset 2>/dev/null || echo "(IDMS 없음)"

echo
echo "--- GPU 노드 ---"
gpu_nodes=$(oc get nodes -l 'nvidia.com/gpu.present=true' --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$gpu_nodes" -gt 0 ]]; then
  oc get nodes -l 'nvidia.com/gpu.present=true' \
    -o custom-columns='NAME:.metadata.name,GPU:.metadata.labels.nvidia\.com/gpu\.count'
  info "GPU 노드 ${gpu_nodes}개 발견 → NFD/GPU Operator 설치 후보"
else
  echo "(GPU 라벨 노드 없음)"
fi

echo
echo "--- GPU/NFD Operator CSV ---"
oc get csv -A 2>/dev/null | grep -iE 'nfd|gpu-operator' \
  || echo "(GPU stack 미설치)"

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo
echo -e "${BOLD}=====================================================${RESET}"
echo -e "${BOLD}  Survey 완료: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
if [[ "$SAVE_OUTPUT" == true ]]; then
  echo -e "${BOLD}  결과 파일: ${OUTPUT_FILE}${RESET}"
fi
echo -e "${BOLD}=====================================================${RESET}"
echo
info "다음 단계: 위 결과를 claude-context/current-state.md, version-matrix.md, constraints.md에 반영하세요."
info "반영 가이드: runbooks/001-cluster-survey.md 참조"

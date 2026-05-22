#!/bin/bash
set -euo pipefail

# ── 색상 ──
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_CYAN='\033[44m'

# ── 터미널 크기 ──
COLS=$(tput cols 2>/dev/null || echo 80)
ROWS=$(tput lines 2>/dev/null || echo 40)

# ── 유틸 ──
hr() {
  printf "${DIM}${CYAN}"
  printf '─%.0s' $(seq 1 "$COLS")
  printf "${NC}\n"
}

center() {
  local text="$1" color="${2:-$NC}"
  local pad=$(( (COLS - ${#text}) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf "%*s${color}%s${NC}\n" "$pad" "" "$text"
}

badge() {
  local label="$1" color="$2"
  printf " ${color} %s ${NC}" "$label"
}

status_line() {
  local icon="$1" label="$2" detail="$3" color="$4"
  printf "  ${color}%s${NC}  %-28s %s\n" "$icon" "$label" "$detail"
}

count_badge() {
  local ok="$1" warn="$2" crit="$3"
  printf "  "
  [[ $ok -gt 0 ]]   && printf "${BG_GREEN}${WHITE} %d OK ${NC} " "$ok"
  [[ $warn -gt 0 ]] && printf "${BG_YELLOW}${WHITE} %d WARN ${NC} " "$warn"
  [[ $crit -gt 0 ]] && printf "${BG_RED}${WHITE} %d CRIT ${NC} " "$crit"
  printf "\n"
}

# ── 데이터 수집 ──
collect() {
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  CONTEXT=$(oc whoami --show-context 2>/dev/null || echo "unknown")
  SERVER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
  USER_NAME=$(oc whoami 2>/dev/null || echo "unknown")

  # 1. ClusterOperator
  CO_ALL=$(oc get co --no-headers 2>/dev/null | wc -l | tr -d ' ')
  CO_BAD_DATA=$(oc get co --no-headers 2>/dev/null | awk '($3 == "False" || $4 == "True" || $5 == "True") {printf "%s|%s|%s|%s\n", $1, $3, $4, $5}')
  if [[ -z "$CO_BAD_DATA" ]]; then
    CO_BAD_COUNT=0
  else
    CO_BAD_COUNT=$(echo "$CO_BAD_DATA" | wc -l | tr -d ' ')
  fi
  CO_OK_COUNT=$((CO_ALL - CO_BAD_COUNT))

  # 2. Node
  NODE_DATA=$(oc get nodes --no-headers 2>/dev/null)
  NODE_ALL=$(echo "$NODE_DATA" | wc -l | tr -d ' ')
  NODE_BAD_DATA=$(echo "$NODE_DATA" | awk '$2 != "Ready" {print $1"|"$2}')
  if [[ -z "$NODE_BAD_DATA" ]]; then NODE_BAD_COUNT=0; else NODE_BAD_COUNT=$(echo "$NODE_BAD_DATA" | wc -l | tr -d ' '); fi

  NODE_RES=$(oc adm top node --no-headers 2>/dev/null || true)

  # 3. Pod
  POD_BAD_DATA=$(oc get pods -A --no-headers --field-selector status.phase!=Running,status.phase!=Succeeded 2>/dev/null \
    | grep -v 'Completed' \
    | awk '{printf "%s|%s|%s\n", $1, $2, $4}' || true)
  if [[ -z "$POD_BAD_DATA" ]]; then POD_BAD_COUNT=0; else POD_BAD_COUNT=$(echo "$POD_BAD_DATA" | wc -l | tr -d ' '); fi

  # 4. 재시작
  RESTART_DATA=$(oc get pods -A -o json 2>/dev/null | jq -r '
    .items[] |
    select(.status.containerStatuses != null) |
    select([.status.containerStatuses[].restartCount] | add > 10) |
    "\(.metadata.namespace)/\(.metadata.name)|\([.status.containerStatuses[].restartCount] | add)"
  ' 2>/dev/null || true)
  if [[ -z "$RESTART_DATA" ]]; then RESTART_COUNT=0; else RESTART_COUNT=$(echo "$RESTART_DATA" | wc -l | tr -d ' '); fi

  # 5. CSV
  CSV_BAD_DATA=$(oc get csv -A --no-headers 2>/dev/null | grep -v Succeeded | awk '{printf "%s|%s|%s\n", $1, $2, $NF}' || true)
  if [[ -z "$CSV_BAD_DATA" ]]; then CSV_BAD_COUNT=0; else CSV_BAD_COUNT=$(echo "$CSV_BAD_DATA" | wc -l | tr -d ' '); fi

  # 6. PVC
  PVC_BAD_DATA=$(oc get pvc -A --no-headers 2>/dev/null | awk '$3 != "Bound" {printf "%s|%s|%s\n", $1, $2, $3}' || true)
  if [[ -z "$PVC_BAD_DATA" ]]; then PVC_BAD_COUNT=0; else PVC_BAD_COUNT=$(echo "$PVC_BAD_DATA" | wc -l | tr -d ' '); fi

  # 7. Warning Events
  EVENTS_DATA=$(oc get events -A --field-selector type=Warning --sort-by='.lastTimestamp' --no-headers 2>/dev/null | tail -8 \
    | awk '{printf "%s|%s|%s\n", $1, $5, substr($0, index($0,$6))}' || true)
  EVENTS_COUNT=$(oc get events -A --field-selector type=Warning --no-headers 2>/dev/null | wc -l | tr -d ' ')

  # 8. GPU
  HAS_GPU=false
  if oc get ns nvidia-gpu-operator &>/dev/null; then
    HAS_GPU=true
    GPU_BAD_DATA=$(oc get pods -n nvidia-gpu-operator --no-headers 2>/dev/null \
      | grep -v Running | grep -v Completed \
      | awk '{printf "%s|%s\n", $1, $3}' || true)
    if [[ -z "$GPU_BAD_DATA" ]]; then GPU_BAD_COUNT=0; else GPU_BAD_COUNT=$(echo "$GPU_BAD_DATA" | wc -l | tr -d ' '); fi
  fi

  # 9. RHOAI
  HAS_RHOAI=false
  if oc get ns redhat-ods-operator &>/dev/null; then
    HAS_RHOAI=true
    RHOAI_BAD_DATA=$(oc get pods -n redhat-ods-operator -n redhat-ods-applications --no-headers 2>/dev/null \
      | grep -v Running | grep -v Completed \
      | awk '{printf "%s|%s\n", $1, $3}' || true)
    if [[ -z "$RHOAI_BAD_DATA" ]]; then RHOAI_BAD_COUNT=0; else RHOAI_BAD_COUNT=$(echo "$RHOAI_BAD_DATA" | wc -l | tr -d ' '); fi
  fi

  # 10. MCP
  MCP_BAD_DATA=$(oc get mcp --no-headers 2>/dev/null | awk '($3 == "True" || $4 == "True" || $5 == "True") && $4 != "False" {printf "%s|%s|%s|%s\n", $1, $3, $4, $5}' || true)
  if [[ -z "$MCP_BAD_DATA" ]]; then MCP_BAD_COUNT=0; else MCP_BAD_COUNT=$(echo "$MCP_BAD_DATA" | wc -l | tr -d ' '); fi

  # 종합
  TOTAL_ISSUES=0
  [[ $CO_BAD_COUNT -gt 0 ]]  && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
  [[ $NODE_BAD_COUNT -gt 0 ]] && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
  [[ $POD_BAD_COUNT -gt 0 ]] && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
  [[ $RESTART_COUNT -gt 0 ]] && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
  [[ $CSV_BAD_COUNT -gt 0 ]] && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
  [[ $PVC_BAD_COUNT -gt 0 ]] && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
  [[ $MCP_BAD_COUNT -gt 0 ]] && TOTAL_ISSUES=$((TOTAL_ISSUES + 1)) || true
}

# ── 렌더링 ──
render() {
  # watch 모드에서만 화면 클리어
  if [[ "${WATCH_MODE:-false}" == "true" ]]; then
    tput clear 2>/dev/null || printf '\033[2J\033[H'
  fi

  # ── 헤더 ──
  printf "${BG_CYAN}${WHITE}${BOLD}"
  printf "%-${COLS}s" "  OPENSHIFT CLUSTER HEALTH DASHBOARD"
  printf "${NC}\n"

  printf "  ${DIM}Context:${NC} ${BOLD}%s${NC}" "$CONTEXT"
  printf "  ${DIM}Server:${NC} %s" "$SERVER"
  printf "  ${DIM}User:${NC} %s" "$USER_NAME"

  # 오른쪽 정렬 타임스탬프
  local info_len=${#CONTEXT}+${#SERVER}+${#USER_NAME}+30
  local remaining=$((COLS - info_len - 20))
  [[ $remaining -gt 0 ]] && printf "%*s" "$remaining" ""
  printf "  ${DIM}%s${NC}\n" "$TIMESTAMP"

  # ── 요약 바 ──
  hr
  if [[ $TOTAL_ISSUES -eq 0 ]]; then
    printf "  ${BG_GREEN}${WHITE}${BOLD}  ALL CLEAR  ${NC}  "
  else
    printf "  ${BG_RED}${WHITE}${BOLD}  %d ISSUES  ${NC}  " "$TOTAL_ISSUES"
  fi

  local checks=("CO:$CO_BAD_COUNT" "Node:$NODE_BAD_COUNT" "Pod:$POD_BAD_COUNT" "Restart:$RESTART_COUNT" "CSV:$CSV_BAD_COUNT" "PVC:$PVC_BAD_COUNT" "MCP:$MCP_BAD_COUNT")
  for c in "${checks[@]}"; do
    local name="${c%%:*}" val="${c##*:}"
    if [[ $val -eq 0 ]]; then
      printf "${GREEN}%s${NC} " "$name"
    else
      printf "${RED}${BOLD}%s(%d)${NC} " "$name" "$val"
    fi
  done
  printf "\n"
  hr

  # ── 패널 1: 노드 리소스 ──
  printf "\n${BOLD}${CYAN} NODES${NC}  ${DIM}(%d total)${NC}\n" "$NODE_ALL"
  if [[ -n "$NODE_RES" ]]; then
    echo "$NODE_RES" | while IFS= read -r line; do
      local name cpu cpu_pct mem mem_pct
      name=$(echo "$line" | awk '{print $1}')
      cpu=$(echo "$line" | awk '{print $2}')
      cpu_pct=$(echo "$line" | awk '{print $3}' | tr -d '%')
      mem=$(echo "$line" | awk '{print $4}')
      mem_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')

      # CPU 바
      local cpu_color="$GREEN"
      [[ ${cpu_pct:-0} -gt 70 ]] && cpu_color="$YELLOW"
      [[ ${cpu_pct:-0} -gt 90 ]] && cpu_color="$RED"
      local cpu_bar_len=20
      local cpu_filled=$(( (${cpu_pct:-0} * cpu_bar_len) / 100 ))
      local cpu_empty=$((cpu_bar_len - cpu_filled))
      local cpu_bar="${cpu_color}"
      for ((i=0; i<cpu_filled; i++)); do cpu_bar+="█"; done
      cpu_bar+="${DIM}"
      for ((i=0; i<cpu_empty; i++)); do cpu_bar+="░"; done
      cpu_bar+="${NC}"

      # Mem 바
      local mem_color="$GREEN"
      [[ ${mem_pct:-0} -gt 70 ]] && mem_color="$YELLOW"
      [[ ${mem_pct:-0} -gt 90 ]] && mem_color="$RED"
      local mem_bar_len=20
      local mem_filled=$(( (${mem_pct:-0} * mem_bar_len) / 100 ))
      local mem_empty=$((mem_bar_len - mem_filled))
      local mem_bar="${mem_color}"
      for ((i=0; i<mem_filled; i++)); do mem_bar+="█"; done
      mem_bar+="${DIM}"
      for ((i=0; i<mem_empty; i++)); do mem_bar+="░"; done
      mem_bar+="${NC}"

      printf "  %-30s  CPU ${cpu_bar} %3s%% %-7s  MEM ${mem_bar} %3s%% %-9s\n" \
        "$name" "${cpu_pct:-?}" "$cpu" "${mem_pct:-?}" "$mem"
    done
  fi

  # ── 패널 2: ClusterOperator ──
  printf "\n${BOLD}${CYAN} CLUSTER OPERATORS${NC}  "
  if [[ $CO_BAD_COUNT -eq 0 ]]; then
    badge "${CO_OK_COUNT}/${CO_ALL} OK" "$BG_GREEN"
  else
    badge "${CO_BAD_COUNT} degraded" "$BG_RED"
  fi
  printf "\n"
  if [[ -n "$CO_BAD_DATA" ]]; then
    echo "$CO_BAD_DATA" | while IFS='|' read -r name avail prog deg; do
      status_line "x" "$name" "Avail=$avail Prog=$prog Deg=$deg" "$RED"
    done
  fi

  # ── 패널 3: 비정상 Pod ──
  printf "\n${BOLD}${CYAN} PODS${NC}  "
  if [[ $POD_BAD_COUNT -eq 0 ]]; then
    badge "ALL HEALTHY" "$BG_GREEN"
  else
    badge "$POD_BAD_COUNT unhealthy" "$BG_RED"
  fi
  printf "\n"
  if [[ -n "$POD_BAD_DATA" ]]; then
    echo "$POD_BAD_DATA" | head -8 | while IFS='|' read -r ns pod status; do
      status_line "x" "$ns/$pod" "$status" "$RED"
    done
    [[ $POD_BAD_COUNT -gt 8 ]] && printf "  ${DIM}... +%d more${NC}\n" "$((POD_BAD_COUNT - 8))"
  fi

  # ── 패널 4: 재시작 ──
  if [[ $RESTART_COUNT -gt 0 ]]; then
    printf "\n${BOLD}${CYAN} HIGH RESTARTS${NC}  "
    badge "$RESTART_COUNT pods >10" "$BG_YELLOW"
    printf "\n"
    echo "$RESTART_DATA" | sort -t'|' -k2 -rn | head -5 | while IFS='|' read -r pod cnt; do
      local icon="!"
      [[ $cnt -gt 50 ]] && icon="x"
      local color="$YELLOW"
      [[ $cnt -gt 50 ]] && color="$RED"
      status_line "$icon" "$pod" "restarts=$cnt" "$color"
    done
    [[ $RESTART_COUNT -gt 5 ]] && printf "  ${DIM}... +%d more${NC}\n" "$((RESTART_COUNT - 5))"
  fi

  # ── 패널 5: CSV / PVC ──
  if [[ $CSV_BAD_COUNT -gt 0 || $PVC_BAD_COUNT -gt 0 ]]; then
    printf "\n${BOLD}${CYAN} OPERATORS / STORAGE${NC}\n"
    if [[ -n "$CSV_BAD_DATA" ]]; then
      echo "$CSV_BAD_DATA" | while IFS='|' read -r ns name phase; do
        status_line "x" "CSV: $ns/$name" "$phase" "$RED"
      done
    fi
    if [[ -n "$PVC_BAD_DATA" ]]; then
      echo "$PVC_BAD_DATA" | while IFS='|' read -r ns name status; do
        status_line "!" "PVC: $ns/$name" "$status" "$YELLOW"
      done
    fi
  fi

  # ── 패널 6: GPU / RHOAI ──
  if [[ "$HAS_GPU" == "true" || "$HAS_RHOAI" == "true" ]]; then
    printf "\n${BOLD}${CYAN} AI PLATFORM${NC}  "
    if [[ "$HAS_GPU" == "true" ]]; then
      if [[ $GPU_BAD_COUNT -eq 0 ]]; then
        badge "GPU OK" "$BG_GREEN"
      else
        badge "GPU $GPU_BAD_COUNT err" "$BG_RED"
      fi
    fi
    if [[ "$HAS_RHOAI" == "true" ]]; then
      if [[ $RHOAI_BAD_COUNT -eq 0 ]]; then
        badge "RHOAI OK" "$BG_GREEN"
      else
        badge "RHOAI $RHOAI_BAD_COUNT err" "$BG_RED"
      fi
    fi
    printf "\n"
    if [[ "$HAS_GPU" == "true" && -n "${GPU_BAD_DATA:-}" ]]; then
      echo "$GPU_BAD_DATA" | while IFS='|' read -r pod status; do
        status_line "x" "GPU: $pod" "$status" "$RED"
      done
    fi
    if [[ "$HAS_RHOAI" == "true" && -n "${RHOAI_BAD_DATA:-}" ]]; then
      echo "$RHOAI_BAD_DATA" | while IFS='|' read -r pod status; do
        status_line "x" "RHOAI: $pod" "$status" "$RED"
      done
    fi
  fi

  # ── 패널 7: MCP ──
  if [[ $MCP_BAD_COUNT -gt 0 ]]; then
    printf "\n${BOLD}${CYAN} MACHINE CONFIG POOLS${NC}  "
    badge "$MCP_BAD_COUNT degraded" "$BG_RED"
    printf "\n"
    echo "$MCP_BAD_DATA" | while IFS='|' read -r name upd prog deg; do
      status_line "x" "$name" "Updated=$upd Updating=$prog Degraded=$deg" "$RED"
    done
  fi

  # ── 패널 8: Warning Events ──
  printf "\n${BOLD}${CYAN} RECENT WARNINGS${NC}  "
  if [[ $EVENTS_COUNT -eq 0 ]]; then
    badge "NONE" "$BG_GREEN"
  else
    badge "$EVENTS_COUNT total" "$BG_YELLOW"
  fi
  printf "\n"
  if [[ -n "$EVENTS_DATA" ]]; then
    echo "$EVENTS_DATA" | while IFS='|' read -r ns reason msg; do
      local short_msg="${msg:0:$((COLS - 50))}"
      printf "  ${DIM}%-14s${NC} ${YELLOW}%-18s${NC} %s\n" "$ns" "$reason" "$short_msg"
    done
  fi

  # ── 푸터 ──
  hr
  if [[ "${WATCH_MODE:-false}" == "true" ]]; then
    printf "  ${DIM}Refresh: ${INTERVAL}s | Press Ctrl+C to exit | Next: $(date -d "+${INTERVAL} seconds" '+%H:%M:%S' 2>/dev/null || date -v+${INTERVAL}S '+%H:%M:%S' 2>/dev/null || echo '...')${NC}\n"
  else
    printf "  ${DIM}Run with 'watch' argument for live dashboard (default 30s refresh)${NC}\n"
    printf "  ${DIM}  ./scripts/cluster-health-check.sh watch [interval]${NC}\n"
  fi
}

# ── 메인 ──
main() {
  if [[ "${1:-}" == "watch" ]]; then
    WATCH_MODE=true
    INTERVAL="${2:-30}"
    trap 'tput cnorm 2>/dev/null; echo; exit 0' INT TERM
    tput civis 2>/dev/null || true

    while true; do
      collect
      render
      sleep "$INTERVAL"
    done
  else
    WATCH_MODE=false
    INTERVAL=0
    collect
    render
  fi
}

main "$@"

#!/usr/bin/env bash
# ===============================================================================
# gaudi3_diag_wrapper.sh - PRODUCTION READY (FULLY FIXED)
# ===============================================================================

set -euo pipefail
[[ "${DEBUG:-}" == "true" ]] && set -x

# ==================== COLORS ====================
readonly RED="\033[0;31m" GREEN="\033[0;32m" YELLOW="\033[1;33m" 
readonly BLUE="\033[1;34m" CYAN="\033[0;36m" MAGENTA="\033[1;35m" NC="\033[0m"

# ==================== VALIDATION WITH HELP ====================
missing_vars=()
: "${PASSWORD:?missing_vars+=(PASSWORD)}"
: "${REMOTE_HOST:?missing_vars+=(REMOTE_HOST)}"
: "${SERVER:?missing_vars+=(SERVER)}"
: "${JIRA:?missing_vars+=(JIRA)}"

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    cat << EOF >&2
${RED}❌ Missing: ${missing_vars[*]}${NC}

${YELLOW}💡 Quick start:${NC}
  export PASSWORD=pass REMOTE_HOST=192.168.72.48 \\
         SERVER=dal2-qz1-sr3-rk506-s20 JIRA="SYS-44278"
  ./gaudi3_diag_wrapper.sh

${BLUE}🔍 One-liner:${NC}
  PASSWORD=pass REMOTE_HOST=192.168.72.48 SERVER=server JIRA=SYS-44278 ./gaudi3_diag_wrapper.sh
EOF
    exit 1
fi

# ==================== FIXED IP INCREMENT ====================
increment_ip() {
    local IFS=. a b c d
    read -r a b c d <<< "$1"
    d=$((d + 1))
    (( d > 255 )) && { d=0; c=$((c + 1)); }
    printf '%s.%s.%s.%s' "$a" "$b" "$c" "$d"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/wrapper.log"
}

cleanup() {
    local exit_code=$?
    [[ -n "${LOG_DIR:-}" ]] && log "Wrapper cleanup (exit: $exit_code)"
    
    # Auto-archive
    if [[ -d "$LOG_DIR" && -n "${TIMESTAMP:-}" ]]; then
        local archive="$LOG_BASE_DIR/${SERVER//[^a-zA-Z0-9]/_}_${TIMESTAMP}.tgz"
        log "Creating archive: $archive"
        tar -czf "$archive" -C "$LOG_BASE_DIR" "gaudi3_diag_$TIMESTAMP" 2>/dev/null || true
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

# ==================== SETUP ====================
JIRA_KEY=$(echo "${JIRA}" | sed -E 's/.*\[([A-Z]+-[0-9]+)\].*/\1/' || echo "${JIRA}")
OS_IP=$(increment_ip "${REMOTE_HOST}")
REMOTE_USER="${REMOTE_USER:-root}"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

LOG_BASE_DIR="$HOME/gaudi3_diag_logs"
LOG_DIR="$LOG_BASE_DIR/gaudi3_diag_$TIMESTAMP"
mkdir -p "$LOG_DIR"

# ==================== PREREQUISITES ====================
[[ -x "./g3_full_diagnostics.sh" ]] || { 
    echo -e "${RED}❌ g3_full_diagnostics.sh missing${NC}" >&2
    exit 1 
}
command -v sshpass >/dev/null 2>&1 || { 
    echo -e "${RED}❌ sshpass required: sudo apt install sshpass${NC}" >&2
    exit 1 
}

# ==================== HEADER ====================
clear
echo -e "${CYAN}
╔══════════════════════════════════════════════════════════════╗
║              🚀 GAUDI3 PRODUCTION DIAGNOSTICS v3.0           ║
╚══════════════════════════════════════════════════════════════╝${NC}

${BLUE}🐙 Server:${NC} ${CYAN}$SERVER${NC} | ${BLUE}🎫 JIRA:${NC} ${CYAN}${JIRA_KEY}${NC}
${BLUE}🌐 BMC:${NC}   ${CYAN}$REMOTE_HOST${NC} | ${BLUE}💻 OS:${NC} ${CYAN}${OS_IP}${NC}
${BLUE}👤 User:${NC}  ${CYAN}${REMOTE_USER}${NC} | ${BLUE}📁 Logs:${NC} ${CYAN}${LOG_DIR}${NC}
"
log "Starting: SERVER=$SERVER JIRA=$JIRA_KEY OS_IP=$OS_IP"

# ==================== EXECUTE ====================
cd "$(dirname "./g3_full_diagnostics.sh")"
(
    export SERVER="$SERVER" JIRA="$JIRA" PASSWORD="$PASSWORD" 
    export REMOTE_HOST="$REMOTE_HOST" OS_IP="$OS_IP" REMOTE_USER="$REMOTE_USER"
    export JIRA_KEY="$JIRA_KEY" LOG_DIR="$LOG_DIR"
    exec ./g3_full_diagnostics.sh
) && {
    echo -e "${GREEN}🎉 ALL DIAGNOSTICS PASSED${NC}"
    echo -e "${GREEN}📦 Archive: $LOG_BASE_DIR/${SERVER//[^a-zA-Z0-9]/_}_${TIMESTAMP}.tgz${NC}"
    exit 0
} || {
    echo -e "${RED}❌ DIAGNOSTICS FAILED${NC}"
    echo -e "${RED}📋 Logs: $LOG_DIR/wrapper.log${NC}"
    exit 1
}

#!/usr/bin/env bash
# ===============================================================================
# GAUDI3 PROD WRAPPER v3.1 - ENTERPRISE READY
# Deployed: fra1-qz1-sr6-rk182-s02 | JIRA: SYS-44487 | Date: 2026-01-09
# ===============================================================================

set -euo pipefail
[[ "${DEBUG:-}" == "true" ]] && set -x

# ==================== COLORS ====================
readonly RED="\033[0;31m" GREEN="\033[0;32m" YELLOW="\033[1;33m"
readonly BLUE="\033[1;34m" CYAN="\033[0;36m" MAGENTA="\033[1;35m" NC="\033[0m"

# ==================== VALIDATION ====================
missing_vars=()
: "${PASSWORD:?missing_vars+=(PASSWORD)}"
: "${SERVER:?missing_vars+=(SERVER)}"
: "${JIRA:?missing_vars+=(JIRA)}"

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    cat << EOF >&2
${RED}❌ Missing: ${missing_vars[*]}${NC}

${YELLOW}💡 Quick start:${NC}
  export PASSWORD=ibm-Genesis-Cl0ud SERVER=fra1-qz1-sr6-rk182-s02 JIRA=SYS-44487
  ./gaudi3_diag_wrapper.sh

${BLUE}🔍 One-liner:${NC}
  PASSWORD=ibm-Genesis-Cl0ud SERVER=fra1-qz1-sr6-rk182-s02 JIRA=SYS-44487 ./gaudi3_diag_wrapper.sh
EOF
    exit 1
fi

# ==================== UTILITIES ====================
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
        log "✅ Archive created: $archive"
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

# ==================== SETUP ====================
JIRA_KEY=$(echo "${JIRA}" | sed -E 's/.*\[([A-Z]+-[0-9]+)\].*/\1/' || echo "${JIRA}")
REMOTE_HOST="${REMOTE_HOST:-192.168.23.14}"
OS_IP=$(increment_ip "${REMOTE_HOST}")
REMOTE_USER="${REMOTE_USER:-root}"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

LOG_BASE_DIR="$HOME/gaudi3_diag_logs"
LOG_DIR="$LOG_BASE_DIR/gaudi3_diag_$TIMESTAMP"
mkdir -p "$LOG_DIR"

# ==================== PREREQUISITES ====================
command -v racadm >/dev/null 2>&1 || { echo -e "${RED}❌ racadm required${NC}"; exit 1; }
command -v hl-smi >/dev/null 2>&1 || echo -e "${YELLOW}⚠️  hl-smi not found (Gaudi3 tools)${NC}"
[[ -x "./g3_full_diagnostics.sh" ]] || { echo -e "${RED}❌ g3_full_diagnostics.sh missing${NC}"; exit 1; }

# ==================== HEADER ====================
clear
echo -e "${CYAN}
╔══════════════════════════════════════════════════════════════╗
║              🚀 GAUDI3 PRODUCTION DIAGNOSTICS v3.1           ║
╚══════════════════════════════════════════════════════════════╝${NC}

${BLUE}🐙 Server:${NC} ${CYAN}$SERVER${NC} | ${BLUE}🎫 JIRA:${NC} ${CYAN}${JIRA_KEY}${NC}
${BLUE}🌐 BMC:${NC}   ${CYAN}$REMOTE_HOST${NC} | ${BLUE}💻 OS:${NC} ${CYAN}${OS_IP}${NC}
${BLUE}👤 User:${NC}  ${CYAN}${REMOTE_USER}${NC} | ${BLUE}📁 Logs:${NC} ${CYAN}${LOG_DIR}${NC}
"
log "Starting: SERVER=$SERVER JIRA=$JIRA_KEY BMC=$REMOTE_HOST OS=$OS_IP"

# ==================== INTERACTIVE MENU ====================
cat << 'EOF'

📋 Gaudi3 Diagnostics Menu (PRODUCTION READY):
  0) 🔄 Run ALL 12 steps (RECOMMENDED)
  1) 🧹 Clear SEL
  2) 🔄 Refresh DCIM
  3) 🔄 Powercycle  
  4) 📦 TSR Collect (w/ fallback)
  5) ▶️  Power On
  6) ✅ Health Check & Server Boot
  7) 🎮 Gaudi3 Diag (hl-smi/npu-smi)
  8) 📜 OS Logs
  9) 🔄 Power Cycle
  10) 📦 Release Bundle
  11) ⏹️  Power Off
  12) 📦 Archive Logs
  q) Quit

💡 PRO TIP: Option 0 = Full production diagnostics
EOF

read -p "Enter choice (0-12,q): " choice

# ==================== EXECUTE ====================
cd "$(dirname "./g3_full_diagnostics.sh")"
case $choice in
    0)
        echo -e "${BLUE}🚀 Running ALL 12 production steps...${NC}"
        export SERVER="$SERVER" JIRA="$JIRA" PASSWORD="$PASSWORD" REMOTE_HOST="$REMOTE_HOST"
        export OS_IP="$OS_IP" REMOTE_USER="$REMOTE_USER" JIRA_KEY="$JIRA_KEY" LOG_DIR="$LOG_DIR"
        ./g3_full_diagnostics.sh | tee "$LOG_DIR/full.log"
        ;;
    [1-9]|1[0-2])
        echo -e "${BLUE}[${choice}/12] Executing step ${choice}...${NC}"
        export SERVER="$SERVER" JIRA="$JIRA" PASSWORD="$PASSWORD" REMOTE_HOST="$REMOTE_HOST"
        export OS_IP="$OS_IP" REMOTE_USER="$REMOTE_USER" JIRA_KEY="$JIRA_KEY" LOG_DIR="$LOG_DIR"
        ./g3_full_diagnostics.sh "step_$choice" | tee -a "$LOG_DIR/full.log"
        ;;
    q|Q) echo -e "${GREEN}👋 Diagnostics cancelled${NC}"; exit 0 ;;
    *) echo -e "${RED}❌ Invalid choice (0-12 or q)${NC}"; exit 1 ;;
esac

echo -e "${GREEN}🎉 DIAGNOSTICS COMPLETE!${NC}"
echo -e "${GREEN}📦 Archive:${NC} ${CYAN}$LOG_BASE_DIR/${SERVER//[^a-zA-Z0-9]/_}_${TIMESTAMP}.tgz${NC}"
echo -e "${GREEN}📋 Full logs:${NC} ${CYAN}$LOG_DIR/full.log${NC}"

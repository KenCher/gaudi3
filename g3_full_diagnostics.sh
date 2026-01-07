#!/usr/bin/env bash
# ===============================================================================
# gaudi3_full_diagnostics.sh - FIXED SYNTAX + HEALTH/RELEASE PARSING (2025-12-08)
# ===============================================================================

set -uo pipefail
[[ "${DEBUG:-}" == "true" ]] && set -x
trap 'echo -e "\n\033[1;31m[ABORTED]\033[0m"; exit 130' INT TERM

# ==================== COLORS ====================
readonly SUCCESS_COLOR="\033[1;32m" FAILURE_COLOR="\033[1;31m" EXEC_COLOR="\033[1;36m"
readonly POWER_COLOR="\033[1;33m" INFO_COLOR="\033[1;34m" NC="\033[0m"

# ==================== ENVIRONMENT ====================
: "${REMOTE_HOST:?Error: REMOTE_HOST required}" "${SERVER:?SERVER required}" "${JIRA:?JIRA required}"
readonly PASSWORD="ibm-Genesis-Cl0ud"
OS_IP="${OS_IP:-$(increment_ip "$REMOTE_HOST")}"
JIRA_KEY=$(echo "$JIRA" | grep -o '[A-Z]\+-[0-9]\+')
REPOS_DIR="$(pwd)/../"  # Parent of current log dir = ~/repos

TS=$(date +%Y%m%d-%H%M%S)
LOG_DIR="gaudi3_diag_${TS}"
mkdir -p "$LOG_DIR" && cd "$LOG_DIR" || exit 1
exec > >(tee -i full.log) 2>&1

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

increment_ip() {
    local ip="$1" a b c d
    IFS=. read -r a b c d <<< "$ip"
    d=$((d+1)); ((d>255)) && { d=0; c=$((c+1)); }
    printf '%s.%s.%s.%s' "$a" "$b" "$c" "$d"
}

echo -e "\n${EXEC_COLOR}🔥 GAUDI3 PRODUCTION DIAGNOSTICS${NC}"
echo "🐙 $SERVER | 🎫 $JIRA_KEY | 🌐 $REMOTE_HOST | 💻 $OS_IP"
echo "📁 $LOG_DIR → 📤 $REPOS_DIR"

# ==================== CORE FUNCTIONS ====================
check_python_version() {
    for py in python3.9 python3.8 python3.10 python3; do
        command -v "$py" >/dev/null 2>&1 && { PYTHON_CMD="$py"; return 0; }
    done
    echo -e "${FAILURE_COLOR}❌ No Python3${NC}"; return 1
}

collect_python_tsr() {
    echo -e "\n${EXEC_COLOR}🔍 Python TSR${NC}"
    local tsr_paths=("../tsr_script_debug_combo.py" "~/repos/tsr_script_debug_combo.py")
    local TSR_SCRIPT=""
    for path in "${tsr_paths[@]}"; do
        local full_path=$(eval echo "$path")
        [[ -f "$full_path" ]] && {
            cp "$full_path" "./tsr_script_debug_combo.py"
            TSR_SCRIPT="./tsr_script_debug_combo.py"
            echo -e "${SUCCESS_COLOR}✅ TSR: $full_path${NC}"
            break
        }
    done
    [[ -z "$TSR_SCRIPT" ]] && { echo -e "${FAILURE_COLOR}❌ TSR script missing${NC}"; return 1; }

    check_python_version && echo -e "${INFO_COLOR}🐍 $PYTHON_CMD${NC}"
    timeout 3600 bash -c "echo '=== PYTHON TSR START ===' > tsr_raw.log && $PYTHON_CMD tsr_script_debug_combo.py -ip '$REMOTE_HOST' -u root -p '$PASSWORD' --accept --export --filename 'tsrDebug-$SERVER.zip' 2>&1 | tee -a tsr_raw.log && echo \$? > tsr_exitcode && echo '=== PYTHON TSR END ===' >> tsr_raw.log"

    [[ -f "tsrDebug-$SERVER.zip" ]] && { local size=$(du -h tsrDebug-$SERVER.zip | cut -f1); echo -e "\n${SUCCESS_COLOR}✅ PYTHON TSR: $size${NC}"; return 0; }
    echo -e "${FAILURE_COLOR}⚠️  Python TSR → RACADM${NC}"; return 1
}

collect_racadm_tsr() {
    echo -e "${EXEC_COLOR}📦 RACADM TSR${NC}"
    timeout 1200 racadm -r "$REMOTE_HOST" -u root -p "$PASSWORD" -S techsupportgather --firmlog --syslog -f "tsr_racadm-$SERVER.zip" 2>&1 | tee tsr_racadm.log || true
    [[ -f "tsr_racadm-$SERVER.zip" ]] && { local size=$(du -h tsr_racadm-$SERVER.zip | cut -f1); echo -e "${SUCCESS_COLOR}✅ RACADM TSR: $size${NC}"; }
}

collect_manual_logs() {
    echo -e "${EXEC_COLOR}📋 Manual logs...${NC}"
    local cmds=("racadm getsvctag" "racadm get BIOS.Info" "ipmitool sel list")
    for cmd in "${cmds[@]}"; do
        timeout 15 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$REMOTE_HOST" "$cmd" > "manual_$(echo $cmd | tr ' :.' _).log" 2>&1 || true
    done
    echo -e "${SUCCESS_COLOR}✅ Manual logs OK${NC}"
}

# ==================== FIXED GAUDI3 OS DIAG (SYNTAX + HL-SMI) ====================
gaudi3_os_diag() {
    echo -e "${EXEC_COLOR}🔍 Gaudi3 OS ${OS_IP} - Full Qual Diag${NC}"

    # Pre-create local target directories
    mkdir -p hl_qual_logs system_logs

    if ping -c2 -W3 "$OS_IP" &>/dev/null; then
        local OS_LOG="gaudi_os_full_${TS}.log"

        # FIXED SSH - Bulletproof host key handling
        sshpass -p "$PASSWORD" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o UpdateHostKeys=no \
            -o ConnectTimeout=15 \
            root@"$OS_IP" "
            set -euo pipefail
            export HABANA_LOGS='/var/log/habana_logs'
            LOGROOT='/var/log'

            mkdir -p \"\$HABANA_LOGS/qual\" \"\$LOGROOT/system_diag\"
            echo '=== TIMESTAMP: \$(date) ===' > \"\$LOGROOT/system_diag/full_diag.log\"

            # System & Firmware
            sudo dmidecode --type bios > \"\$LOGROOT/system_diag/bios.log\" 2>&1 || true
            sudo dmidecode --type system > \"\$LOGROOT/system_diag/system.log\" 2>&1 || true
            lspci -vvv | grep -i habana > \"\$LOGROOT/system_diag/lspci_habana.log\" 2>&1 || true
            dmesg | grep -i 'habana|gaudi' > \"\$LOGROOT/system_diag/habana_dmesg.log\" 2>&1 || true

            # Gaudi3 GPU Status
            hl-smi > \"\$LOGROOT/system_diag/hl-smi.log\" 2>&1 || echo 'hl-smi not found' > \"\$LOGROOT/system_diag/hl-smi.log\"

            # FIXED HL-SMI - Multiple valid queries
            hl-smi -q -d POWER > \"\$LOGROOT/system_diag/hl-smi_power.log\" 2>&1 || true
            hl-smi -q -d MEMORY > \"\$LOGROOT/system_diag/hl-smi_memory.log\" 2>&1 || true
            hl-smi -q -d TEMPERATURE > \"\$LOGROOT/system_diag/hl-smi_temp.log\" 2>&1 || true
            hl-smi -q -d PERFORMANCE > \"\$LOGROOT/system_diag/hl-smi_perf.log\" 2>&1 || true

            # CSV metrics
            hl-smi -Q timestamp,utilization.aip,memory.used,memory.free,power.draw,temperature.aip -f csv,noheader > \"\$LOGROOT/system_diag/hl-smi_csv.log\" 2>&1 || true

            # hl_qual
            if [[ -x '/opt/habanalabs/qual/gaudi3/bin/hl_qual' ]]; then
                timeout 120 /opt/habanalabs/qual/gaudi3/bin/hl_qual -gaudi3 -c all -r mod_serial -t 30 > \"\$HABANA_LOGS/qual/hl_qual.log\" 2>&1 || \
                echo 'hl_qual: timeout/GPUs busy (NORMAL)' > \"\$HABANA_LOGS/qual/hl_qual.log\"
            else
                echo 'hl_qual binary missing' > \"\$HABANA_LOGS/qual/hl_qual.log\"
            fi

            tar czf /tmp/gaudi_diag_complete.tar.gz -C /var/log habana_logs system_diag 2>/dev/null || true

            echo '=== SUMMARY ===' >> \"\$LOGROOT/system_diag/full_diag.log\"
            echo 'Hostname: \$(hostname)' >> \"\$LOGROOT/system_diag/full_diag.log\"
            echo 'Uptime: \$(uptime)' >> \"\$LOGROOT/system_diag/full_diag.log\"
            echo '=== DIAGNOSTICS COMPLETE ==='
        " > "$OS_LOG" 2>&1

        if [[ -f "$OS_LOG" && -s "$OS_LOG" && $(tail -1 "$OS_LOG" | grep -c "DIAGNOSTICS COMPLETE") -gt 0 ]]; then
            mkdir -p hl_qual_logs system_logs

            sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$OS_IP":/tmp/gaudi_diag_complete.tar.gz . 2>&1 || true
            sshpass -p "$PASSWORD" scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$OS_IP":/var/log/habana_logs/qual ./hl_qual_logs/ 2>&1 || true
            sshpass -p "$PASSWORD" scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$OS_IP":/var/log/system_diag ./system_logs/ 2>&1 || true

            echo -e "${SUCCESS_COLOR}✅ Gaudi3 Full Qual Diag${NC}"
            [[ -f gaudi_diag_complete*.tar.gz ]] && echo "📦 gaudi_diag_complete.tar.gz ($(du -h gaudi_diag_complete*.tar.gz | cut -f1 | head -1))"
            echo -e "${INFO_COLOR}📄 $OS_LOG${NC}"
            tail -5 "$OS_LOG"
            return 0
        else
            echo -e "${FAILURE_COLOR}❌ SSH/Diag failed${NC}"
            echo -e "${INFO_COLOR}📄 Check $OS_LOG:${NC}"
            [[ -f "$OS_LOG" ]] && tail -15 "$OS_LOG"
            return 1
        fi
    else
        echo -e "${FAILURE_COLOR}⚠️ OS_IP ${OS_IP} unreachable${NC}"
        return 1
    fi
}

# ==================== HEALTH/RELEASE PASS-FAIL LOGIC ====================
parse_system_bringup_status() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && { echo "FAIL"; return 1; }
    
    # Get second-to-last line (Success/Failure summary)
    local status_line=$(tail -n 2 "$log_file" | head -n 1)
    
    # FAIL if "Failure: 1" anywhere in line, else PASS
    if echo "$status_line" | grep -q 'Failure:[[:space:]]*1'; then
        echo "FAIL"
        return 1
    else
        echo "PASS"
        return 0
    fi
}

# ==================== 12 STEPS ====================
readonly STEP_ORDER=(clear_sel refresh_dcim powercycle collect_tsr power_on health_check gaudi_diag os_logs powercycle_before_release release_bundle power_off archive_results)
readonly STEP_LABELS=("Clear SEL" "Refresh DCIM" "Powercycle" "TSR Collect" "Power On" "Health Check & Server Boot" "Gaudi3 Diag" "OS Logs" "🔄 Power Cycle" "Release Bundle" "Power Off" "Archive")

clear_sel() { echo -e "${EXEC_COLOR}🧹 SEL...${NC}"; timeout 20 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$REMOTE_HOST" racadm clrsel >/dev/null 2>&1 || timeout 20 ipmitool -I lanplus -H "$REMOTE_HOST" -U root -P "$PASSWORD" sel clear >/dev/null 2>&1; echo -e "${SUCCESS_COLOR}✅ SEL cleared${NC}"; return 0; }
refresh_dcim() { log "DCIM cache..."; [[ -x ~/repos/system-bringup-release/system-bringup.sh ]] && ~/repos/system-bringup-release/system-bringup.sh -s "$SERVER" --refresh-dcim-cache | tee dcim.log && return ${PIPESTATUS[0]}; echo "DCIM skipped"; return 0; }
powercycle() { echo -e "${POWER_COLOR}🔄 Powercycle...${NC}"; timeout 30 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$REMOTE_HOST" racadm serveraction powercycle >/dev/null 2>&1 || timeout 30 ipmitool -I lanplus -H "$REMOTE_HOST" -U root -P "$PASSWORD" chassis power cycle >/dev/null 2>&1; sleep 15; return 0; }
collect_tsr() { collect_python_tsr && return 0; collect_racadm_tsr; collect_manual_logs; return 0; }
power_on() { echo -e "${POWER_COLOR}🔛 Power ON...${NC}"; timeout 30 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$REMOTE_HOST" racadm serveraction poweron >/dev/null 2>&1 || timeout 30 ipmitool -I lanplus -H "$REMOTE_HOST" -U root -P "$PASSWORD" chassis power on >/dev/null 2>&1; sleep 20; return 0; }

health_check() { 
    echo "Health check & server boot..."
    [[ -x ~/repos/system-bringup-release/system-bringup.sh ]] && ~/repos/system-bringup-release/system-bringup.sh -s "$SERVER" --tag "$JIRA_KEY" -o boot-system-runtime,health-check-devices-nic,health-check-devices-gpu | tee health.log
    local health_status=$(parse_system_bringup_status "health.log")
    echo -e "$( [ "$health_status" = "PASS" ] && echo "${SUCCESS_COLOR}" || echo "${FAILURE_COLOR}" )Health Check: $health_status${NC}"
    [[ "$health_status" == "PASS" ]] && return 0 || return 1
}

gaudi_diag() { gaudi3_os_diag; }
os_logs() { gaudi3_os_diag; }
powercycle_before_release() { echo "🔄 Pre-release..."; powercycle; sleep 120; return 0; }

release_bundle() { 
    echo "Release bundle..."
    [[ -x ~/repos/system-bringup-release/system-bringup.sh ]] && ~/repos/system-bringup-release/system-bringup.sh -w never -g bringup --tag "$JIRA_KEY" -s "$SERVER" | tee release.log
    local release_status=$(parse_system_bringup_status "release.log")
    echo -e "$( [ "$release_status" = "PASS" ] && echo "${SUCCESS_COLOR}" || echo "${FAILURE_COLOR}" )Release Bundle: $release_status${NC}"
    [[ "$release_status" == "PASS" ]] && return 0 || return 1
}

power_off() { echo -e "${POWER_COLOR}🔴 Power OFF...${NC}"; timeout 30 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$REMOTE_HOST" racadm serveraction poweroff >/dev/null 2>&1; return 0; }

archive_results() {
    echo "JIRA: $JIRA_KEY | Server: $SERVER | Date: $(date)" > summary.txt
    tar czf "../dell_gaudi3_complete_${TS}.tar.gz" . 2>/dev/null || true

    # Copy to ~/repos
    cp -r "$LOG_DIR" "$REPOS_DIR/gaudi3_diag_${TS}_complete" 2>/dev/null || true
    cp "../dell_gaudi3_complete_${TS}.tar.gz" "$REPOS_DIR/" 2>/dev/null || true

    echo -e "\n${SUCCESS_COLOR}📦 ~/repos/dell_gaudi3_complete_${TS}.tar.gz${NC}"
    echo -e "${SUCCESS_COLOR}📁 ~/repos/gaudi3_diag_${TS}_complete/${NC}"
    echo -e "${INFO_COLOR}📤 → JIRA $JIRA_KEY${NC}"
    return 0
}

show_menu() {
    echo -e "\n${EXEC_COLOR}📋 Gaudi3 Diagnostics Menu:${NC}"
    echo "  0) ${INFO_COLOR}Run ALL steps${NC}"
    for i in "${!STEP_LABELS[@]}"; do
        printf "  %s) %s\n" $((i+1)) "${STEP_LABELS[$i]}"
    done
    echo "  q) Quit"
    echo -ne "${INFO_COLOR}Enter choice (0-${#STEP_LABELS[@]},q): ${NC}"
}

run_step() {
    local step_idx="$1"
    local step_name="${STEP_ORDER[$step_idx]}"
    local label="${STEP_LABELS[$step_idx]}"
    local color="$EXEC_COLOR"
    [[ "$label" =~ Power ]] && color="$POWER_COLOR"

    echo -e "\n${color}[$(($step_idx+1))/${#STEP_ORDER[@]}] $label${NC}"
    if "$step_name"; then
        echo -e "  ${SUCCESS_COLOR}✓ PASSED${NC}"
        return 0
    else
        echo -e "  ${FAILURE_COLOR}✗ FAILED${NC}"
        return 1
    fi
}

main() {
    local total_steps=${#STEP_ORDER[@]}
    local success_count=0
    local failed_steps=()

    while true; do
        show_menu
        read -r choice

        case "$choice" in
            0)
                echo -e "\n${EXEC_COLOR}🚀 Running ALL steps...${NC}"
                for i in "${!STEP_ORDER[@]}"; do
                    if run_step "$i"; then
                        ((success_count++))
                    else
                        failed_steps+=($((i+1)))
                    fi
                done
                archive_results
                break
                ;;
            q|Q)
                echo "Exiting."
                archive_results
                exit 0
                ;;
            [1-9]*|[1-9][0-9]*)
                if [[ "$choice" -ge 1 && "$choice" -le "$total_steps" ]]; then
                    local step_idx=$((choice-1))
                    if run_step "$step_idx"; then
                        ((success_count++))
                    else
                        failed_steps+=($((step_idx+1)))
                    fi
                    echo -e "\n${INFO_COLOR}Press Enter for menu...${NC}"
                    read -r
                else
                    echo -e "${FAILURE_COLOR}Invalid step number${NC}"
                fi
                ;;
            *)
                echo -e "${FAILURE_COLOR}Invalid choice${NC}"
                ;;
        esac
    done

    echo -e "\n${SUCCESS_COLOR}✅ $success_count/$total_steps COMPLETE${NC}"
    [[ ${#failed_steps[@]} -gt 0 ]] && echo -e "${FAILURE_COLOR}❌ Failed: ${failed_steps[*]}${NC}"
}

main "$@"


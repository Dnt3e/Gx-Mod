#!/usr/bin/env bash

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Gx-Mod"
AUTHOR="D3nte"
SERVICE_NAME="gx-mod"
CONFIG_DIR="/etc/gx-mod"
LOG_FILE="/var/log/gx-mod.log"
BENCH_LOG="/var/log/gx-mod-benchmark.log"
BACKUP_DIR="/etc/gx-mod/backup"
STATE_FILE="/etc/gx-mod/state"
SYSCTL_FILE="/etc/sysctl.d/99-gx-mod.conf"
SERVICE_FILE="/etc/systemd/system/gx-mod.service"

SEP="================================================================"
THIN_SEP="----------------------------------------------------------------"

R="\033[0;31m"
G="\033[0;32m"
Y="\033[1;33m"
B="\033[0;34m"
C="\033[0;36m"
M="\033[0;35m"
W="\033[1;37m"
DIM="\033[2m"
BOLD="\033[1m"
NC="\033[0m"

cecho() {
    echo -e "$*${NC}"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

die() {
    echo "ERROR: $*" >&2
    log "ERROR: $*"
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root."
}

print_header() {
    clear
    cecho "${C}${BOLD}${SEP}"
    cecho "${W}${BOLD}"
    cecho "   ██████╗ ██╗  ██╗      ███╗   ███╗ ██████╗ ██████╗ "
    cecho "  ██╔════╝ ╚██╗██╔╝      ████╗ ████║██╔═══██╗██╔══██╗"
    cecho "  ██║  ███╗ ╚███╔╝  ████╗██╔████╔██║██║   ██║██║  ██║"
    cecho "  ██║   ██║ ██╔██╗  ╚═══╝██║╚██╔╝██║██║   ██║██║  ██║"
    cecho "  ╚██████╔╝██╔╝ ██╗      ██║ ╚═╝ ██║╚██████╔╝██████╔╝"
    cecho "   ╚═════╝ ╚═╝  ╚═╝      ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ "
    cecho "${DIM}${W}                           Author: ${C}D3nte${W}  v${SCRIPT_VERSION}"
    cecho "${C}${BOLD}${SEP}"
    print_status_bar
    cecho "${C}${BOLD}${SEP}"
}

print_status_bar() {
    local dep_status opt_status active_mode
    dep_status="Not Installed"
    opt_status="Not Applied"
    active_mode="None"
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE" 2>/dev/null || true
        [[ "${DEPS_INSTALLED:-0}" == "1" ]] && dep_status="Installed"
        [[ "${OPT_APPLIED:-0}" == "1" ]] && opt_status="Applied"
        active_mode="${ACTIVE_MODE:-None}"
    fi

    local dep_color="$R" opt_color="$R" mode_color="$Y"
    [[ "$dep_status" == "Installed" ]] && dep_color="$G"
    [[ "$opt_status" == "Applied" ]]   && opt_color="$G"
    [[ "$active_mode" == "None" ]]     && mode_color="$DIM$W"

    cecho "  ${DIM}${W}Dependencies :${NC} ${dep_color}${BOLD}${dep_status}"
    cecho "  ${DIM}${W}Optimization :${NC} ${opt_color}${BOLD}${opt_status}"
    cecho "  ${DIM}${W}Active Mode  :${NC} ${mode_color}${BOLD}${active_mode}"
}

save_state() {
    mkdir -p "$CONFIG_DIR"
    cat > "$STATE_FILE" <<EOF
DEPS_INSTALLED=${DEPS_INSTALLED:-0}
OPT_APPLIED=${OPT_APPLIED:-0}
ACTIVE_MODE=${ACTIVE_MODE:-None}
EOF
}

detect_hardware() {
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
    TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))
    CPU_CORES=$(nproc)

    DISK_TYPE="HDD"
    ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | xargs basename 2>/dev/null || echo "sda")
    if [[ -f "/sys/block/${ROOT_DEV}/queue/rotational" ]]; then
        ROT=$(cat "/sys/block/${ROOT_DEV}/queue/rotational" 2>/dev/null || echo "1")
        if [[ "$ROT" == "0" ]]; then
            if ls /sys/block/ 2>/dev/null | grep -q "^nvme"; then
                DISK_TYPE="NVMe"
            else
                DISK_TYPE="SSD"
            fi
        fi
    fi

    VIRT_TYPE="Dedicated"
    if command -v systemd-detect-virt &>/dev/null; then
        VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
        [[ "$VIRT" != "none" ]] && VIRT_TYPE="VPS ($VIRT)"
    elif [[ -f /proc/1/environ ]] && grep -q "container" /proc/1/environ 2>/dev/null; then
        VIRT_TYPE="Container"
    fi

    PRIMARY_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    [[ -z "$PRIMARY_IFACE" ]] && PRIMARY_IFACE=$(ip link show | awk -F': ' '/^[0-9]+: [^lo]/{print $2}' | head -1)
    [[ -z "$PRIMARY_IFACE" ]] && PRIMARY_IFACE="eth0"

    NIC_SPEED="unknown"
    if [[ -f "/sys/class/net/${PRIMARY_IFACE}/speed" ]]; then
        NIC_SPEED=$(cat "/sys/class/net/${PRIMARY_IFACE}/speed" 2>/dev/null || echo "unknown")
    fi

    HAS_ETHTOOL=0
    command -v ethtool &>/dev/null && HAS_ETHTOOL=1

    log "Hardware: RAM=${TOTAL_RAM_GB}GB CPU=${CPU_CORES} Disk=${DISK_TYPE} Virt=${VIRT_TYPE} NIC=${PRIMARY_IFACE}(${NIC_SPEED}Mbps)"
}

detect_rtt() {
    local targets=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    local total=0
    local count=0
    local rtts=()

    for t in "${targets[@]}"; do
        local rtt
        rtt=$(ping -c 5 -W 2 "$t" 2>/dev/null | tail -1 | awk -F'/' '{print $5}' 2>/dev/null || echo "")
        if [[ -n "$rtt" && "$rtt" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            total=$(echo "$total + $rtt" | bc 2>/dev/null || awk "BEGIN{print $total + $rtt}")
            count=$((count + 1))
            rtts+=("$rtt")
        fi
    done

    if [[ $count -gt 0 ]]; then
        AVG_RTT=$(awk "BEGIN{printf \"%.2f\", $total / $count}")
    else
        AVG_RTT="50"
    fi

    RTT_JITTER="0"
    if [[ ${#rtts[@]} -gt 1 ]]; then
        RTT_JITTER=$(awk -v avg="$AVG_RTT" 'BEGIN{
            n='"${#rtts[@]}"'; sum=0
        }' <<< "" 2>/dev/null || echo "0")
        local sum_sq=0
        for r in "${rtts[@]}"; do
            local diff
            diff=$(awk "BEGIN{printf \"%.4f\", ($r - $AVG_RTT)^2}")
            sum_sq=$(awk "BEGIN{printf \"%.4f\", $sum_sq + $diff}")
        done
        RTT_JITTER=$(awk "BEGIN{printf \"%.2f\", sqrt($sum_sq / ${#rtts[@]})}")
    fi

    log "RTT detection: avg=${AVG_RTT}ms jitter=${RTT_JITTER}ms"
}

measure_packet_loss() {
    local target="${1:-8.8.8.8}"
    local result
    result=$(ping -c 10 -W 2 "$target" 2>/dev/null | grep -oP '\d+(?=% packet loss)' || echo "0")
    echo "${result:-0}"
}

measure_retransmits() {
    local retrans
    retrans=$(ss -s 2>/dev/null | grep -i "retrans" | awk '{print $2}' | head -1 || echo "0")
    if [[ -z "$retrans" ]]; then
        retrans=$(cat /proc/net/snmp 2>/dev/null | awk '/^Tcp:/{getline; print $13}' || echo "0")
    fi
    echo "${retrans:-0}"
}

measure_throughput_approx() {
    local bytes_before bytes_after elapsed_ns speed_mbps
    local iface="$PRIMARY_IFACE"
    local rx_file="/sys/class/net/${iface}/statistics/rx_bytes"
    local tx_file="/sys/class/net/${iface}/statistics/tx_bytes"
    if [[ -f "$rx_file" ]]; then
        bytes_before=$(cat "$rx_file" 2>/dev/null || echo "0")
        sleep 2
        bytes_after=$(cat "$rx_file" 2>/dev/null || echo "0")
        speed_mbps=$(awk "BEGIN{printf \"%.2f\", (($bytes_after - $bytes_before) * 8) / (2 * 1000000)}")
    else
        speed_mbps="N/A"
    fi
    echo "$speed_mbps"
}

run_benchmark() {
    local phase="$1"
    log "Running benchmark phase: $phase"

    detect_rtt

    local pkt_loss retransmits throughput
    pkt_loss=$(measure_packet_loss "8.8.8.8")
    retransmits=$(measure_retransmits)
    throughput=$(measure_throughput_approx)

    if [[ "$phase" == "before" ]]; then
        BENCH_RTT_BEFORE="$AVG_RTT"
        BENCH_JITTER_BEFORE="$RTT_JITTER"
        BENCH_LOSS_BEFORE="$pkt_loss"
        BENCH_RETRANS_BEFORE="$retransmits"
        BENCH_THROUGHPUT_BEFORE="$throughput"
    else
        BENCH_RTT_AFTER="$AVG_RTT"
        BENCH_JITTER_AFTER="$RTT_JITTER"
        BENCH_LOSS_AFTER="$pkt_loss"
        BENCH_RETRANS_AFTER="$retransmits"
        BENCH_THROUGHPUT_AFTER="$throughput"
    fi
}

display_benchmark_report() {
    local diff_rtt diff_jitter diff_loss diff_retrans
    diff_rtt=$(awk "BEGIN{printf \"%.2f\", ${BENCH_RTT_BEFORE:-0} - ${BENCH_RTT_AFTER:-0}}")
    diff_jitter=$(awk "BEGIN{printf \"%.2f\", ${BENCH_JITTER_BEFORE:-0} - ${BENCH_JITTER_AFTER:-0}}")
    diff_loss=$(awk "BEGIN{printf \"%.1f\", ${BENCH_LOSS_BEFORE:-0} - ${BENCH_LOSS_AFTER:-0}}")
    diff_retrans=$(awk "BEGIN{printf \"%d\", ${BENCH_RETRANS_BEFORE:-0} - ${BENCH_RETRANS_AFTER:-0}}")

    echo ""
    cecho "  ${C}${SEP}"
    cecho "  ${W}${BOLD}BENCHMARK REPORT"
    cecho "  ${C}${THIN_SEP}"
    printf "  ${BOLD}${W}%-20s %-12s %-12s %-12s${NC}\n" "Metric" "Before" "After" "Difference"
    cecho "  ${C}${THIN_SEP}"

    local rtt_col="$G"
    awk "BEGIN{exit ($diff_rtt > 0) ? 0 : 1}" 2>/dev/null && rtt_col="$G" || rtt_col="$R"
    printf "  ${DIM}${W}%-20s${NC} %-12s %-12s ${rtt_col}%-12s${NC}\n" \
        "RTT (ms)" "${BENCH_RTT_BEFORE:-N/A}" "${BENCH_RTT_AFTER:-N/A}" "${diff_rtt}ms"

    local jit_col="$G"
    awk "BEGIN{exit ($diff_jitter > 0) ? 0 : 1}" 2>/dev/null && jit_col="$G" || jit_col="$R"
    printf "  ${DIM}${W}%-20s${NC} %-12s %-12s ${jit_col}%-12s${NC}\n" \
        "Jitter (ms)" "${BENCH_JITTER_BEFORE:-N/A}" "${BENCH_JITTER_AFTER:-N/A}" "${diff_jitter}ms"

    printf "  ${DIM}${W}%-20s${NC} %-12s %-12s ${G}%-12s${NC}\n" \
        "Packet Loss (%)" "${BENCH_LOSS_BEFORE:-N/A}" "${BENCH_LOSS_AFTER:-N/A}" "${diff_loss}%"

    printf "  ${DIM}${W}%-20s${NC} %-12s %-12s ${G}%-12s${NC}\n" \
        "Retransmits" "${BENCH_RETRANS_BEFORE:-N/A}" "${BENCH_RETRANS_AFTER:-N/A}" "${diff_retrans}"

    cecho "  ${C}${SEP}"

    {
        echo "=== Gx-Mod Benchmark Report ==="
        echo "Timestamp: $(date)"
        echo "Mode: ${ACTIVE_MODE:-Unknown}"
        printf "%-20s %-12s %-12s %-12s\n" "Metric" "Before" "After" "Difference"
        printf "%-20s %-12s %-12s %-12s\n" "RTT (ms)" "${BENCH_RTT_BEFORE:-N/A}" "${BENCH_RTT_AFTER:-N/A}" "${diff_rtt}ms"
        printf "%-20s %-12s %-12s %-12s\n" "Jitter (ms)" "${BENCH_JITTER_BEFORE:-N/A}" "${BENCH_JITTER_AFTER:-N/A}" "${diff_jitter}ms"
        printf "%-20s %-12s %-12s %-12s\n" "Packet Loss (%)" "${BENCH_LOSS_BEFORE:-N/A}" "${BENCH_LOSS_AFTER:-N/A}" "${diff_loss}%"
        printf "%-20s %-12s %-12s %-12s\n" "Retransmits" "${BENCH_RETRANS_BEFORE:-N/A}" "${BENCH_RETRANS_AFTER:-N/A}" "${diff_retrans}"
        echo ""
    } >> "$BENCH_LOG"

    local improved=0
    awk "BEGIN{exit (${diff_rtt} > 0.5) ? 0 : 1}" && improved=1 || true
    if [[ $improved -eq 0 ]]; then
        cecho "  ${Y}Note: No significant measurable improvement detected."
        cecho "  ${DIM}${W}This is honest reporting. Results depend on network conditions."
        cecho "  ${C}${THIN_SEP}"
    fi
}

install_dependencies() {
    local deps=(iproute2 ethtool bc iputils-ping procps)
    local to_install=()

    for d in "${deps[@]}"; do
        dpkg -s "$d" &>/dev/null || to_install+=("$d")
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq "${to_install[@]}" 2>/dev/null
    fi
}

progress_bar() {
    local current=$1
    local total=$2
    local label="${3:-}"
    local width=38
    local filled=$(( (current * width) / total ))
    local empty=$(( width - filled ))
    local pct=$(( (current * 100) / total ))
    local bar_filled bar_empty
    bar_filled=$(printf '█%.0s' $(seq 1 $filled) 2>/dev/null || printf '#%.0s' $(seq 1 $filled))
    bar_empty=$(printf '░%.0s' $(seq 1 $empty) 2>/dev/null || printf '-%.0s' $(seq 1 $empty))
    printf "\r  \033[0;36m[\033[1;32m%s\033[2;37m%s\033[0;36m]\033[0m \033[1;33m%3d%%\033[0m  \033[2;37m%s\033[0m" \
        "$bar_filled" "$bar_empty" "$pct" "$label"
}

do_install() {
    print_header
    cecho "  ${Y}${BOLD}Starting installation..."
    cecho "  ${C}${THIN_SEP}"

    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    touch "$LOG_FILE" "$BENCH_LOG"
    log "Installation started"

    local steps=10
    local step=0

    step=$((step+1)); progress_bar $step $steps "Checking system compatibility"
    [[ -f /etc/os-release ]] && source /etc/os-release
    sleep 0.3

    step=$((step+1)); progress_bar $step $steps "Installing dependencies"
    install_dependencies
    log "Dependencies installed"

    step=$((step+1)); progress_bar $step $steps "Detecting hardware"
    detect_hardware
    log "Hardware detected"

    step=$((step+1)); progress_bar $step $steps "Backing up sysctl settings"
    sysctl -a 2>/dev/null > "$BACKUP_DIR/sysctl_backup.conf" || true
    cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak" 2>/dev/null || true
    [[ -f "$SYSCTL_FILE" ]] && cp "$SYSCTL_FILE" "$BACKUP_DIR/99-gx-mod.conf.bak" 2>/dev/null || true

    step=$((step+1)); progress_bar $step $steps "Backing up network settings"
    ip link show > "$BACKUP_DIR/ip_link_before.txt" 2>/dev/null || true
    if [[ $HAS_ETHTOOL -eq 1 ]]; then
        ethtool -c "$PRIMARY_IFACE" > "$BACKUP_DIR/ethtool_coalesce_before.txt" 2>/dev/null || true
        ethtool -g "$PRIMARY_IFACE" > "$BACKUP_DIR/ethtool_ring_before.txt" 2>/dev/null || true
    fi

    step=$((step+1)); progress_bar $step $steps "Detecting RTT baseline"
    detect_rtt

    step=$((step+1)); progress_bar $step $steps "Creating systemd service"
    create_systemd_service

    step=$((step+1)); progress_bar $step $steps "Applying initial Balanced profile"
    ACTIVE_MODE="Balanced"
    apply_mode_balanced

    step=$((step+1)); progress_bar $step $steps "Enabling service"
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable "$SERVICE_NAME" 2>/dev/null || true

    step=$((step+1)); progress_bar $step $steps "Finalizing"
    DEPS_INSTALLED=1
    OPT_APPLIED=1
    save_state
    log "Installation complete. Active mode: $ACTIVE_MODE"

    echo ""
    echo ""
    cecho "  ${C}${THIN_SEP}"
    cecho "  ${G}${BOLD}✔  Installation complete."
    cecho "  ${W}   Default mode : ${Y}${BOLD}Balanced"
    cecho "  ${W}   Use ${C}Mode Selection${W} to switch profiles."
    cecho "  ${C}${SEP}"
    read -rp "  Press Enter to continue..."
}

backup_exists() {
    [[ -f "$BACKUP_DIR/sysctl_backup.conf" ]]
}

create_systemd_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Gx-Mod Gaming Server Optimization
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash $CONFIG_DIR/apply.sh
ExecStop=/bin/bash $CONFIG_DIR/restore.sh

[Install]
WantedBy=multi-user.target
EOF

    cat > "$CONFIG_DIR/apply.sh" <<'APPLY'
#!/usr/bin/env bash
STATE_FILE="/etc/gx-mod/state"
[[ -f "$STATE_FILE" ]] && source "$STATE_FILE"
SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
[[ -f "$SCRIPT_DIR/mode_apply.sh" ]] && bash "$SCRIPT_DIR/mode_apply.sh"
APPLY

    chmod +x "$CONFIG_DIR/apply.sh"

    cat > "$CONFIG_DIR/restore.sh" <<'RESTORE'
#!/usr/bin/env bash
[[ -f /etc/gx-mod/backup/sysctl_backup.conf ]] && sysctl -p /etc/gx-mod/backup/sysctl_backup.conf &>/dev/null || true
RESTORE
    chmod +x "$CONFIG_DIR/restore.sh"
}

compute_buffer_sizes() {
    if [[ $TOTAL_RAM_GB -ge 16 ]]; then
        NET_WMEM_MAX=67108864
        NET_RMEM_MAX=67108864
        TCP_WMEM_MAX=33554432
        TCP_RMEM_MAX=33554432
    elif [[ $TOTAL_RAM_GB -ge 8 ]]; then
        NET_WMEM_MAX=33554432
        NET_RMEM_MAX=33554432
        TCP_WMEM_MAX=16777216
        TCP_RMEM_MAX=16777216
    elif [[ $TOTAL_RAM_GB -ge 4 ]]; then
        NET_WMEM_MAX=16777216
        NET_RMEM_MAX=16777216
        TCP_WMEM_MAX=8388608
        TCP_RMEM_MAX=8388608
    else
        NET_WMEM_MAX=8388608
        NET_RMEM_MAX=8388608
        TCP_WMEM_MAX=4194304
        TCP_RMEM_MAX=4194304
    fi

    if [[ $TOTAL_RAM_GB -ge 8 ]]; then
        NETDEV_BACKLOG=8192
    else
        NETDEV_BACKLOG=4096
    fi
}

write_sysctl_and_apply() {
    local params=("$@")
    {
        echo "# Gx-Mod - Generated $(date)"
        echo "# Mode: ${ACTIVE_MODE}"
        for p in "${params[@]}"; do
            echo "$p"
        done
    } > "$SYSCTL_FILE"
    sysctl -p "$SYSCTL_FILE" &>/dev/null || true
    log "sysctl applied for mode: ${ACTIVE_MODE}"
}

setup_qdisc_bbr() {
    if ! modprobe tcp_bbr 2>/dev/null; then
        log "BBR module unavailable, falling back to cubic"
        return
    fi

    local avail_cc
    avail_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    if echo "$avail_cc" | grep -q "bbr"; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null || true
    else
        sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null || true
        log "BBR not available, using cubic"
    fi

    tc qdisc del dev "$PRIMARY_IFACE" root 2>/dev/null || true
    tc qdisc add dev "$PRIMARY_IFACE" root fq 2>/dev/null || \
        tc qdisc add dev "$PRIMARY_IFACE" root fq_codel 2>/dev/null || true
    log "qdisc configured on $PRIMARY_IFACE"
}

set_cpu_governor() {
    local governor="$1"
    if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "$governor" > "$cpu" 2>/dev/null || true
        done
        log "CPU governor set to $governor"
    fi
}

set_disk_scheduler() {
    local dev="$ROOT_DEV"
    local scheduler_file="/sys/block/${dev}/queue/scheduler"
    if [[ ! -f "$scheduler_file" ]]; then
        return
    fi
    if [[ "$DISK_TYPE" == "NVMe" ]]; then
        echo "none" > "$scheduler_file" 2>/dev/null || true
    elif [[ "$DISK_TYPE" == "SSD" ]]; then
        if grep -q "mq-deadline" "$scheduler_file" 2>/dev/null; then
            echo "mq-deadline" > "$scheduler_file" 2>/dev/null || true
        fi
    else
        if grep -q "mq-deadline" "$scheduler_file" 2>/dev/null; then
            echo "mq-deadline" > "$scheduler_file" 2>/dev/null || true
        fi
    fi
    log "Disk scheduler set for $DISK_TYPE on $dev"
}

apply_nic_tuning() {
    local mode="$1"
    [[ $HAS_ETHTOOL -eq 0 ]] && return

    case "$mode" in
        balanced)
            ethtool -C "$PRIMARY_IFACE" adaptive-rx on adaptive-tx on 2>/dev/null || true
            ;;
        high_rtt)
            ethtool -C "$PRIMARY_IFACE" adaptive-rx on adaptive-tx on 2>/dev/null || true
            ;;
        ultra_fps)
            if [[ $CPU_CORES -ge 4 && $TOTAL_RAM_GB -ge 8 ]]; then
                ethtool -C "$PRIMARY_IFACE" rx-usecs 10 tx-usecs 10 2>/dev/null || true
            else
                ethtool -C "$PRIMARY_IFACE" adaptive-rx on adaptive-tx on 2>/dev/null || true
            fi
            ;;
    esac

    local max_rx
    max_rx=$(ethtool -g "$PRIMARY_IFACE" 2>/dev/null | awk '/^Pre-set maximums/{found=1} found && /RX:/{print $2; exit}' || echo "")
    if [[ -n "$max_rx" && "$max_rx" =~ ^[0-9]+$ ]]; then
        local target_rx=$(( max_rx > 4096 ? 4096 : max_rx ))
        ethtool -G "$PRIMARY_IFACE" rx "$target_rx" 2>/dev/null || true
    fi
}

apply_mode_balanced() {
    detect_hardware
    compute_buffer_sizes

    local params=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
        "net.ipv4.tcp_ecn=2"
        "net.core.rmem_max=${NET_RMEM_MAX}"
        "net.core.wmem_max=${NET_WMEM_MAX}"
        "net.ipv4.tcp_rmem=4096 87380 ${TCP_RMEM_MAX}"
        "net.ipv4.tcp_wmem=4096 16384 ${TCP_WMEM_MAX}"
        "net.core.netdev_max_backlog=${NETDEV_BACKLOG}"
        "net.ipv4.tcp_fastopen=3"
        "net.ipv4.tcp_fin_timeout=15"
        "net.ipv4.tcp_keepalive_time=300"
        "net.ipv4.tcp_keepalive_intvl=30"
        "net.ipv4.tcp_keepalive_probes=5"
        "net.ipv4.tcp_tw_reuse=1"
        "vm.swappiness=10"
        "net.ipv4.tcp_slow_start_after_idle=0"
        "net.ipv4.tcp_mtu_probing=1"
        "net.ipv4.ip_local_port_range=1024 65535"
        "net.ipv4.tcp_max_syn_backlog=4096"
        "net.core.somaxconn=4096"
    )

    write_sysctl_and_apply "${params[@]}"
    setup_qdisc_bbr
    apply_nic_tuning "balanced"
    set_disk_scheduler
    save_mode_apply_script "balanced"
    log "Balanced mode applied"
}

apply_mode_iran_high_rtt() {
    detect_hardware
    compute_buffer_sizes

    local params=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
        "net.ipv4.tcp_ecn=0"
        "net.core.rmem_max=${NET_RMEM_MAX}"
        "net.core.wmem_max=${NET_WMEM_MAX}"
        "net.ipv4.tcp_rmem=4096 87380 ${TCP_RMEM_MAX}"
        "net.ipv4.tcp_wmem=4096 16384 ${TCP_WMEM_MAX}"
        "net.core.netdev_max_backlog=${NETDEV_BACKLOG}"
        "net.ipv4.tcp_fastopen=3"
        "net.ipv4.tcp_fin_timeout=20"
        "net.ipv4.tcp_keepalive_time=300"
        "net.ipv4.tcp_keepalive_intvl=30"
        "net.ipv4.tcp_keepalive_probes=5"
        "net.ipv4.tcp_tw_reuse=1"
        "vm.swappiness=10"
        "net.ipv4.tcp_mtu_probing=2"
        "net.ipv4.tcp_retries2=8"
        "net.ipv4.tcp_notsent_lowat=16384"
        "net.ipv4.tcp_slow_start_after_idle=0"
        "net.ipv4.ip_local_port_range=1024 65535"
        "net.ipv4.tcp_max_syn_backlog=4096"
        "net.core.somaxconn=4096"
        "net.ipv4.tcp_sack=1"
        "net.ipv4.tcp_dsack=1"
        "net.ipv4.tcp_fack=0"
    )

    write_sysctl_and_apply "${params[@]}"
    setup_qdisc_bbr
    apply_nic_tuning "high_rtt"
    set_disk_scheduler
    save_mode_apply_script "high_rtt"
    log "Iran High RTT mode applied"
}

apply_mode_ultra_fps() {
    detect_hardware
    compute_buffer_sizes

    local warn=0
    if [[ $CPU_CORES -lt 4 || $TOTAL_RAM_GB -lt 8 ]]; then
        warn=1
        echo ""
        cecho "  ${Y}${BOLD}WARNING: Hardware insufficient for full Ultra FPS mode."
        cecho "  ${DIM}${W}CPU cores: ${CPU_CORES} (recommended: 4+)"
        cecho "  ${DIM}${W}RAM: ${TOTAL_RAM_GB}GB (recommended: 8GB+)"
        cecho "  ${Y}Applying safe fallback Ultra FPS settings."
        cecho "  ${C}${THIN_SEP}"
    fi

    local notsent_lowat=4096
    local netdev_backlog=4096
    if [[ $warn -eq 0 ]]; then
        notsent_lowat=4096
        netdev_backlog=8192
    fi

    local params=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
        "net.ipv4.tcp_ecn=2"
        "net.core.rmem_max=${NET_RMEM_MAX}"
        "net.core.wmem_max=${NET_WMEM_MAX}"
        "net.ipv4.tcp_rmem=4096 87380 ${TCP_RMEM_MAX}"
        "net.ipv4.tcp_wmem=4096 16384 ${TCP_WMEM_MAX}"
        "net.core.netdev_max_backlog=${netdev_backlog}"
        "net.ipv4.tcp_autocorking=0"
        "net.ipv4.tcp_notsent_lowat=${notsent_lowat}"
        "net.ipv4.tcp_fastopen=3"
        "net.ipv4.tcp_fin_timeout=10"
        "net.ipv4.tcp_keepalive_time=120"
        "net.ipv4.tcp_keepalive_intvl=15"
        "net.ipv4.tcp_keepalive_probes=5"
        "net.ipv4.tcp_tw_reuse=1"
        "vm.swappiness=10"
        "net.ipv4.tcp_slow_start_after_idle=0"
        "net.ipv4.tcp_mtu_probing=1"
        "net.ipv4.ip_local_port_range=1024 65535"
        "net.ipv4.tcp_max_syn_backlog=8192"
        "net.core.somaxconn=8192"
    )

    write_sysctl_and_apply "${params[@]}"
    setup_qdisc_bbr

    if [[ $warn -eq 0 ]]; then
        set_cpu_governor "performance"
    fi

    apply_nic_tuning "ultra_fps"
    set_disk_scheduler
    save_mode_apply_script "ultra_fps"
    log "Ultra Competitive FPS mode applied"
}

auto_detect_and_apply() {
    detect_hardware
    detect_rtt

    cecho "  ${C}RTT detected: ${Y}${AVG_RTT}ms"
    cecho "  ${C}RAM: ${Y}${TOTAL_RAM_GB}GB${C} | CPU Cores: ${Y}${CPU_CORES}${C} | Virt: ${Y}${VIRT_TYPE}"
    cecho "  ${C}${THIN_SEP}"

    local is_vps=0
    [[ "$VIRT_TYPE" != "Dedicated" ]] && is_vps=1

    if awk "BEGIN{exit (${AVG_RTT} > 50) ? 0 : 1}"; then
        cecho "  ${Y}RTT > 50ms detected. Applying Iran High RTT profile."
        ACTIVE_MODE="Iran High RTT"
        save_state
        apply_mode_iran_high_rtt
    elif awk "BEGIN{exit (${AVG_RTT} < 30) ? 0 : 1}" && \
         [[ $TOTAL_RAM_GB -ge 8 && $CPU_CORES -ge 4 && $is_vps -eq 0 ]]; then
        cecho "  ${G}Low RTT + strong hardware detected. Applying Ultra FPS profile."
        ACTIVE_MODE="Ultra Competitive FPS"
        save_state
        apply_mode_ultra_fps
    else
        cecho "  ${W}Applying Balanced profile (safe default)."
        ACTIVE_MODE="Balanced"
        save_state
        apply_mode_balanced
    fi
}

save_mode_apply_script() {
    local mode="$1"
    cat > "$CONFIG_DIR/mode_apply.sh" <<EOF
#!/usr/bin/env bash
MODE="$mode"
PRIMARY_IFACE="$PRIMARY_IFACE"
[[ -f $SYSCTL_FILE ]] && sysctl -p $SYSCTL_FILE &>/dev/null || true
modprobe tcp_bbr 2>/dev/null || true
tc qdisc del dev $PRIMARY_IFACE root 2>/dev/null || true
tc qdisc add dev $PRIMARY_IFACE root fq 2>/dev/null || true
EOF
    if [[ "$mode" == "ultra_fps" && $CPU_CORES -ge 4 && $TOTAL_RAM_GB -ge 8 ]]; then
        echo "for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > \"\$cpu\" 2>/dev/null || true; done" >> "$CONFIG_DIR/mode_apply.sh"
    fi
    chmod +x "$CONFIG_DIR/mode_apply.sh"
}

mode_selection_menu() {
    while true; do
        print_header
        cecho "  ${W}${BOLD}MODE SELECTION"
        cecho "  ${C}${THIN_SEP}"
        cecho "  ${M}0)${NC} Auto-Detect RTT Mode"
        cecho "  ${Y}1)${NC} Balanced ${DIM}(Default)"
        cecho "  ${Y}2)${NC} Iran High RTT"
        cecho "  ${Y}3)${NC} Ultra Competitive FPS Low Jitter"
        cecho "  ${DIM}${W}b) Back"
        cecho "  ${C}${THIN_SEP}"
        read -rp "$(echo -e "  ${C}Select${NC}: ")" choice
        case "$choice" in
            0)
                echo ""
                cecho "  ${Y}Running auto-detection..."
                cecho "  ${C}${THIN_SEP}"
                run_benchmark "before"
                auto_detect_and_apply
                OPT_APPLIED=1
                save_state
                sleep 1
                run_benchmark "after"
                display_benchmark_report
                read -rp "  Press Enter to continue..."
                ;;
            1)
                run_benchmark "before"
                ACTIVE_MODE="Balanced"
                save_state
                apply_mode_balanced
                OPT_APPLIED=1
                save_state
                run_benchmark "after"
                display_benchmark_report
                read -rp "  Press Enter to continue..."
                ;;
            2)
                run_benchmark "before"
                ACTIVE_MODE="Iran High RTT"
                save_state
                apply_mode_iran_high_rtt
                OPT_APPLIED=1
                save_state
                run_benchmark "after"
                display_benchmark_report
                read -rp "  Press Enter to continue..."
                ;;
            3)
                run_benchmark "before"
                ACTIVE_MODE="Ultra Competitive FPS"
                save_state
                apply_mode_ultra_fps
                OPT_APPLIED=1
                save_state
                run_benchmark "after"
                display_benchmark_report
                read -rp "  Press Enter to continue..."
                ;;
            b|B) return ;;
            *) cecho "  ${R}Invalid option." ; sleep 1 ;;
        esac
    done
}

show_status() {
    print_header
    cecho "  ${W}${BOLD}SYSTEM STATUS"
    cecho "  ${C}${THIN_SEP}"
    detect_hardware
    cecho "  ${DIM}${W}RAM        :${NC} ${G}${TOTAL_RAM_GB}GB total"
    cecho "  ${DIM}${W}CPU Cores  :${NC} ${G}${CPU_CORES}"
    cecho "  ${DIM}${W}Disk Type  :${NC} ${G}${DISK_TYPE}"
    cecho "  ${DIM}${W}Virt Type  :${NC} ${Y}${VIRT_TYPE}"
    cecho "  ${DIM}${W}Interface  :${NC} ${C}${PRIMARY_IFACE}"
    echo ""
    cecho "  ${DIM}${W}TCP CC     :${NC} ${G}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
    cecho "  ${DIM}${W}Default QD :${NC} ${G}$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'unknown')"
    cecho "  ${DIM}${W}Live QDisc :${NC} ${DIM}${W}$(tc qdisc show dev "$PRIMARY_IFACE" 2>/dev/null | head -1 || echo 'unknown')"
    echo ""
    local svc_status
    svc_status=$(systemctl is-active $SERVICE_NAME 2>/dev/null || echo 'inactive')
    local svc_color="$R"
    [[ "$svc_status" == "active" || "$svc_status" == "active (exited)" ]] && svc_color="$G"
    cecho "  ${DIM}${W}Service    :${NC} ${svc_color}${svc_status}"
    echo ""
    if [[ -f "$BENCH_LOG" ]]; then
        cecho "  ${W}${BOLD}Last benchmark:"
        tail -20 "$BENCH_LOG" 2>/dev/null | grep -E "(RTT|Jitter|Packet|Retrans)" | sed "s/^/  $(echo -e "${DIM}${W}")/" || true
        echo -e "${NC}"
    fi
    cecho "  ${C}${SEP}"
    read -rp "  Press Enter to continue..."
}

view_logs() {
    print_header
    cecho "  ${W}${BOLD}LOGS ${DIM}- /var/log/gx-mod.log (last 40 lines)"
    cecho "  ${C}${THIN_SEP}"
    tail -40 "$LOG_FILE" 2>/dev/null | sed "s/^/  /" | while IFS= read -r line; do
        if echo "$line" | grep -q "ERROR"; then
            echo -e "  ${R}${line}${NC}"
        else
            echo -e "  ${DIM}${W}${line}${NC}"
        fi
    done || cecho "  ${R}No logs found."
    cecho "  ${C}${SEP}"
    read -rp "  Press Enter to continue..."
}

service_start() {
    systemctl start "$SERVICE_NAME" 2>/dev/null && cecho "  ${G}✔  Service started." || cecho "  ${R}✘  Failed to start service."
    log "Service start requested"
    sleep 1
}

service_stop() {
    systemctl stop "$SERVICE_NAME" 2>/dev/null && cecho "  ${Y}●  Service stopped." || cecho "  ${R}✘  Failed to stop service."
    log "Service stop requested"
    sleep 1
}

service_restart() {
    systemctl restart "$SERVICE_NAME" 2>/dev/null && cecho "  ${G}↺  Service restarted." || cecho "  ${R}✘  Failed to restart service."
    log "Service restart requested"
    sleep 1
}

management_menu() {
    while true; do
        print_header
        cecho "  ${W}${BOLD}MANAGEMENT"
        cecho "  ${C}${THIN_SEP}"
        cecho "  ${Y}1)${NC} Status"
        cecho "  ${Y}2)${NC} View Logs"
        cecho "  ${G}3)${NC} Start Service"
        cecho "  ${R}4)${NC} Stop Service"
        cecho "  ${Y}5)${NC} Restart Service"
        cecho "  ${DIM}${W}b) Back"
        cecho "  ${C}${THIN_SEP}"
        read -rp "$(echo -e "  ${C}Select${NC}: ")" choice
        case "$choice" in
            1) show_status ;;
            2) view_logs ;;
            3) service_start ;;
            4) service_stop ;;
            5) service_restart ;;
            b|B) return ;;
            *) cecho "  ${R}Invalid option." ; sleep 1 ;;
        esac
    done
}

do_uninstall() {
    print_header
    cecho "  ${R}${BOLD}UNINSTALL & RESTORE"
    cecho "  ${C}${THIN_SEP}"
    cecho "  ${Y}This will restore original settings and remove all Gx-Mod files."
    read -rp "$(echo -e "  ${R}Are you sure? (yes/no): ${NC}")" confirm
    [[ "$confirm" != "yes" ]] && return

    echo ""
    cecho "  ${Y}Stopping service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    cecho "  ${Y}Restoring sysctl settings..."
    if [[ -f "$BACKUP_DIR/sysctl.conf.bak" ]]; then
        cp "$BACKUP_DIR/sysctl.conf.bak" /etc/sysctl.conf
        sysctl -p /etc/sysctl.conf &>/dev/null || true
    fi

    [[ -f "$SYSCTL_FILE" ]] && rm -f "$SYSCTL_FILE"
    sysctl --system &>/dev/null || true

    cecho "  ${Y}Restoring qdisc..."
    tc qdisc del dev "$PRIMARY_IFACE" root 2>/dev/null || true

    if [[ $HAS_ETHTOOL -eq 1 && -f "$BACKUP_DIR/ethtool_coalesce_before.txt" ]]; then
        cecho "  ${DIM}${W}Note: NIC interrupt settings may need manual restoration."
    fi

    cecho "  ${Y}Removing service file..."
    [[ -f "$SERVICE_FILE" ]] && rm -f "$SERVICE_FILE"
    systemctl daemon-reload 2>/dev/null || true

    cecho "  ${Y}Removing configuration and logs..."
    rm -rf "$CONFIG_DIR"
    rm -f "$LOG_FILE" "$BENCH_LOG"

    echo ""
    cecho "  ${C}${THIN_SEP}"
    cecho "  ${G}${BOLD}✔  Uninstall complete. Original settings restored."
    cecho "  ${C}${SEP}"
    read -rp "  Press Enter to exit..."
    exit 0
}

main_menu() {
    while true; do
        print_header
        cecho "  ${W}${BOLD}MAIN MENU"
        cecho "  ${C}${THIN_SEP}"
        cecho "  ${Y}1)${NC} Install"
        cecho "  ${Y}2)${NC} Mode Selection"
        cecho "  ${Y}3)${NC} Management"
        cecho "  ${R}4)${NC} Uninstall & Restore"
        cecho "  ${DIM}${W}q) Quit"
        cecho "  ${C}${THIN_SEP}"
        read -rp "$(echo -e "  ${C}Select${NC}: ")" choice
        case "$choice" in
            1)
                if [[ "${DEPS_INSTALLED:-0}" == "1" ]]; then
                    cecho "  ${Y}Already installed. Use Management or Mode Selection."
                    sleep 2
                else
                    do_install
                fi
                ;;
            2)
                if [[ "${DEPS_INSTALLED:-0}" != "1" ]]; then
                    cecho "  ${R}Please install first (option 1)."
                    sleep 2
                else
                    mode_selection_menu
                fi
                ;;
            3) management_menu ;;
            4) do_uninstall ;;
            q|Q) cecho "  ${C}Goodbye." ; exit 0 ;;
            *) cecho "  ${R}Invalid option." ; sleep 1 ;;
        esac
    done
}

require_root
mkdir -p "$CONFIG_DIR" "$BACKUP_DIR" 2>/dev/null || true
touch "$LOG_FILE" "$BENCH_LOG" 2>/dev/null || true

DEPS_INSTALLED=0
OPT_APPLIED=0
ACTIVE_MODE="None"
[[ -f "$STATE_FILE" ]] && source "$STATE_FILE" 2>/dev/null || true

detect_hardware 2>/dev/null || true

main_menu

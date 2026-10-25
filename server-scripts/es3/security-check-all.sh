#!/bin/bash

# Daily Security Check — All Servers
# Runs from es3, checks all 5 production servers for security regressions.
# Sends Telegram alert only when issues are found.
#
# Schedule: daily at 06:30 UTC on es3 (after backup verification at 06:00)
#   30 6 * * * /root/security-check-all.sh >> /var/log/security/check.log 2>&1
#
# SSH config required on es3 (/root/.ssh/config):
#   Host es1               -> ClickForCharity
#   Host es2               -> Listmonk + Uptime Kuma (89.116.44.57)
#   Host es5-uselesscoin   -> Bitcoin node
#   Host es7-roflfaucet    -> ROFLFaucet
#   Host rn1               -> DirectSponsor (104.168.38.197)
#   (es3 checks itself locally)

set -uo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
[ -f "$SCRIPT_DIR/telegram-notify.sh" ] && source "$SCRIPT_DIR/telegram-notify.sh"

# Authorised SSH key fingerprints (SHA256) for /root/.ssh/authorized_keys.
# Baseline: /home/andy/work/security/es7-unknown-remote-agent-2026-10-20.md
# To allow a new key (e.g. hp4), add its fingerprint here and to the
# per-server check_authorized_keys call below.
FP_HP3="SHA256:WgyQUjzTFGaaNQI990MlZcWVp5F7T9LTwklMkTEWhK8"
FP_HP4="SHA256:KXZMTI/KUJF70X9oQPKKN+QrlsE3mLAwlimp+ZMhQwA"
FP_ES3="SHA256:NXZ/lZofrXrGu7ROFX/Os35MPBDTA6EB4OK+6AqRO4c"

# Enabled .service units not owned by a package that we tolerate everywhere
# (per-server extras are passed at each check_unknown_units call).
UNIT_OK_GLOBAL="fail2ban.service vzfifo.service"

FAILURES=""
WARNINGS=""
SERVER_SUMMARY=""
CHECKS_RUN=0
CHECKS_PASSED=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# Add a non-critical warning (does not affect pass/fail count)
warn() { WARNINGS="${WARNINGS}⚠️  ${1}\n"; log "[WARN] $1"; }

# Check if a reboot is required (Debian/Ubuntu)
check_reboot() {
    local server="$1" host="$2"
    if run_check "$host" "test -f /var/run/reboot-required"; then
        warn "${server}: reboot required (kernel or library update pending)"
    fi
}

# Check for pending non-security upgrades (Debian/Ubuntu)
check_pending_upgrades() {
    local server="$1" host="$2"
    local count
    count=$(run_check "$host" "apt-get -s upgrade 2>/dev/null | grep -oP '^\d+(?= upgraded)'" || echo 0)
    if [ "${count:-0}" -gt 0 ]; then
        warn "${server}: ${count} non-security package upgrade(s) pending"
    fi
}

# Run a command on a remote host (or locally for es3)
run_check() {
    local host="$1"
    local cmd="$2"
    if [ "$host" = "localhost" ]; then
        eval "$cmd" 2>/dev/null
    else
        ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "$cmd" 2>/dev/null
    fi
}

# Check a single condition on a server
# Args: server_name, ssh_host, description, command (should exit 0 for OK)
check() {
    local server="$1"
    local host="$2"
    local desc="$3"
    local cmd="$4"
    CHECKS_RUN=$((CHECKS_RUN + 1))

    if run_check "$host" "$cmd"; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "[OK] $server: $desc"
    else
        FAILURES="${FAILURES}❌ ${server}: ${desc}\n"
        log "[FAIL] $server: $desc"
    fi
}

# Check for unexpected listening ports
# Args: server_name, ssh_host, expected_ports (space-separated, format: port or port/lo)
check_ports() {
    local server="$1"
    local host="$2"
    shift 2
    local expected_ports=("$@")
    CHECKS_RUN=$((CHECKS_RUN + 1))

    # Get current listening ports
    local port_data
    port_data=$(run_check "$host" "/sbin/ss -tlnH 2>/dev/null || ss -tlnH 2>/dev/null")
    if [ -z "$port_data" ]; then
        FAILURES="${FAILURES}❌ ${server}: could not retrieve listening ports\n"
        log "[FAIL] $server: could not retrieve listening ports"
        return
    fi

    # Parse listening ports into a list of "port" or "port/lo"
    local actual_ports=()
    while IFS= read -r line; do
        local addr port
        addr=$(echo "$line" | awk '{print $4}')
        port=$(echo "$addr" | rev | cut -d: -f1 | rev)
        # Determine if localhost-only
        local local_part
        local_part=$(echo "$addr" | rev | cut -d: -f2- | rev)
        if echo "$local_part" | grep -qE '^(127\.0\.0\.1|\[::1\]|127\.0\.0\.53(%lo)?)$'; then
            actual_ports+=("${port}/lo")
        elif echo "$local_part" | grep -qE '^\*$|^0\.0\.0\.0$|\[::\]'; then
            actual_ports+=("$port")
        else
            actual_ports+=("${port}/lo")
        fi
    done <<< "$port_data"

    # Deduplicate
    local unique_actual
    unique_actual=$(printf '%s\n' "${actual_ports[@]}" | sort -u)

    # Find unexpected ports
    local unexpected=""
    while IFS= read -r aport; do
        [ -z "$aport" ] && continue
        local found=false
        for eport in "${expected_ports[@]}"; do
            if [ "$aport" = "$eport" ]; then
                found=true
                break
            fi
            # A localhost port also matches if expected as public
            # (e.g., actual "25/lo" matches expected "25/lo")
            # But a public port doesn't match a localhost expectation
        done
        if [ "$found" = false ]; then
            # Check if this is a localhost version of an expected public port (acceptable)
            local base_port="${aport%/lo}"
            if [ "$aport" != "$base_port" ]; then
                # It's a localhost port — check if the public version is expected
                for eport in "${expected_ports[@]}"; do
                    if [ "$base_port" = "$eport" ]; then
                        found=true
                        break
                    fi
                done
            fi
        fi
        if [ "$found" = false ]; then
            unexpected="${unexpected} ${aport}"
        fi
    done <<< "$unique_actual"

    if [ -z "$unexpected" ]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "[OK] $server: no unexpected ports"
    else
        FAILURES="${FAILURES}❌ ${server}: unexpected ports:${unexpected}\n"
        log "[FAIL] $server: unexpected ports:${unexpected}"
    fi
}

# Check /root/.ssh/authorized_keys contains only allowlisted key fingerprints
# Args: server_name, ssh_host, allowed_sha256_fingerprints...
check_authorized_keys() {
    local server="$1"
    local host="$2"
    shift 2
    local allowed=("$@")
    CHECKS_RUN=$((CHECKS_RUN + 1))

    local fp_data
    if ! fp_data=$(run_check "$host" "ssh-keygen -lf /root/.ssh/authorized_keys"); then
        FAILURES="${FAILURES}❌ ${server}: cannot read /root/.ssh/authorized_keys\n"
        log "[FAIL] $server: cannot read /root/.ssh/authorized_keys"
        return
    fi

    local unexpected=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local fp comment found=false
        fp=$(echo "$line" | awk '{print $2}')
        comment=$(echo "$line" | awk '{print $3}')
        for afp in "${allowed[@]}"; do
            if [ "$fp" = "$afp" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            unexpected="${unexpected} ${fp}(${comment})"
        fi
    done <<< "$fp_data"

    if [ -z "$unexpected" ]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "[OK] $server: authorized_keys fingerprints all known"
    else
        FAILURES="${FAILURES}❌ ${server}: unexpected authorized_keys:${unexpected}\n"
        log "[FAIL] $server: unexpected authorized_keys:${unexpected}"
    fi
}

# Check for enabled .service units whose unit file is not owned by any
# package (dpkg on Debian/Ubuntu, rpm on RHEL-family)
# Args: server_name, ssh_host, allowed_unit_names...
check_unknown_units() {
    local server="$1"
    local host="$2"
    shift 2
    local allowed=("$@")
    CHECKS_RUN=$((CHECKS_RUN + 1))

    # Single remote shell loop: list enabled services, skip template names
    # (e.g. getty@.service), resolve FragmentPath, flag files no package owns.
    local remote_cmd='systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | while read -r u _; do
        case "$u" in *@*) continue ;; esac
        p=$(systemctl show -p FragmentPath --value "$u" 2>/dev/null)
        if [ -z "$p" ] || [ ! -f "$p" ]; then echo "$u"; continue; fi
        if command -v dpkg >/dev/null 2>&1; then
            dpkg -S "$p" >/dev/null 2>&1 || echo "$u"
        else
            rpm -qf "$p" >/dev/null 2>&1 || echo "$u"
        fi
    done'

    local unknown
    unknown=$(run_check "$host" "$remote_cmd")
    if [ -z "$unknown" ]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "[OK] $server: all enabled units are package-owned"
        return
    fi

    local unexpected=""
    while IFS= read -r unit; do
        [ -z "$unit" ] && continue
        local found=false
        for au in "${allowed[@]}"; do
            if [ "$unit" = "$au" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            unexpected="${unexpected} ${unit}"
        fi
    done <<< "$unknown"

    if [ -z "$unexpected" ]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "[OK] $server: all enabled units are package-owned"
    else
        FAILURES="${FAILURES}❌ ${server}: non-package enabled units:${unexpected}\n"
        log "[FAIL] $server: non-package enabled units:${unexpected}"
    fi
}

log "=== Daily Security Check Starting ==="

# =======================================================================
# es1 (ClickForCharity) — SSH host: es1
# =======================================================================
ES1_HOST="es1"
ES1_NAME="es1/ClickForCharity"

_r=$CHECKS_RUN; _p=$CHECKS_PASSED
if ! run_check "$ES1_HOST" "echo ok" > /dev/null; then
    SERVER_SUMMARY="${SERVER_SUMMARY}❌ ${ES1_NAME} (SSH unreachable)\n"
    FAILURES="${FAILURES}❌ ${ES1_NAME}: SSH connection failed\n"
    log "[FAIL] $ES1_NAME: cannot connect"
else
    log "Connected to $ES1_NAME"
    check "$ES1_NAME" "$ES1_HOST" "fail2ban running" \
        "systemctl is-active --quiet fail2ban"
    check "$ES1_NAME" "$ES1_HOST" "ufw active" \
        "ufw status | grep -q 'Status: active'"
    check "$ES1_NAME" "$ES1_HOST" "unattended-upgrades enabled" \
        "systemctl is-enabled --quiet unattended-upgrades"
    check "$ES1_NAME" "$ES1_HOST" "SSH password auth disabled" \
        "grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config"
    check "$ES1_NAME" "$ES1_HOST" "rpcbind not running" \
        "! systemctl is-active --quiet rpcbind && ! systemctl is-active --quiet rpcbind.socket"
    check_ports "$ES1_NAME" "$ES1_HOST" \
        "22" "80" "443" "22000" "25/lo" "8384/lo"
    check_authorized_keys "$ES1_NAME" "$ES1_HOST" \
        "$FP_HP3" "$FP_HP4" "$FP_ES3"
    check_unknown_units "$ES1_NAME" "$ES1_HOST" \
        $UNIT_OK_GLOBAL syncthing-clickforcharity.service
    check_reboot "$ES1_NAME" "$ES1_HOST"
    check_pending_upgrades "$ES1_NAME" "$ES1_HOST"
    _run=$((CHECKS_RUN - _r)); _pass=$((CHECKS_PASSED - _p))
    [ $_pass -eq $_run ] && SERVER_SUMMARY="${SERVER_SUMMARY}✅ ${ES1_NAME} (${_pass}/${_run})\n" || SERVER_SUMMARY="${SERVER_SUMMARY}⚠️ ${ES1_NAME} (${_pass}/${_run})\n"
fi

# =======================================================================
# es2 (Listmonk + Uptime Kuma) — SSH host: es2
# SSH password auth is set in /etc/ssh/sshd_config.d/, so check effective config.
# =======================================================================
ES2_HOST="es2"
ES2_NAME="es2/Kuma-Listmonk"

_r=$CHECKS_RUN; _p=$CHECKS_PASSED
if ! run_check "$ES2_HOST" "echo ok" > /dev/null; then
    SERVER_SUMMARY="${SERVER_SUMMARY}❌ ${ES2_NAME} (SSH unreachable)\n"
    FAILURES="${FAILURES}❌ ${ES2_NAME}: SSH connection failed\n"
    log "[FAIL] $ES2_NAME: cannot connect"
else
    log "Connected to $ES2_NAME"
    check "$ES2_NAME" "$ES2_HOST" "fail2ban running" \
        "systemctl is-active --quiet fail2ban"
    check "$ES2_NAME" "$ES2_HOST" "ufw active" \
        "ufw status | grep -q 'Status: active'"
    check "$ES2_NAME" "$ES2_HOST" "unattended-upgrades enabled" \
        "systemctl is-enabled --quiet unattended-upgrades"
    check "$ES2_NAME" "$ES2_HOST" "SSH password auth disabled" \
        "sshd -T 2>/dev/null | grep -qi '^passwordauthentication no'"
    check "$ES2_NAME" "$ES2_HOST" "rpcbind not running" \
        "! systemctl is-active --quiet rpcbind && ! systemctl is-active --quiet rpcbind.socket"
    check "$ES2_NAME" "$ES2_HOST" "SSL cert valid >14 days" \
        "openssl x509 -checkend 1209600 -noout -in /etc/nginx/ssl/list.clickforcharity.net.cer"
    check "$ES2_NAME" "$ES2_HOST" "Kuma + Listmonk containers up" \
        "[ \$(docker ps -q -f status=running -f name=uptime-kuma -f name=listmonk_app -f name=listmonk_db | wc -l) -eq 3 ]"
    # containerd's unused cri plugin is disabled in /etc/containerd/config.toml; if it is
    # re-enabled it listens on a random 127.0.0.1 port and this check will flag it.
    check_ports "$ES2_NAME" "$ES2_HOST" \
        "22" "80" "443" "25/lo" "3001/lo" "9000/lo"
    check_authorized_keys "$ES2_NAME" "$ES2_HOST" \
        "$FP_HP3" "$FP_HP4" "$FP_ES3"
    # listmonk/uptime-kuma.service = oneshot units running docker-compose up -d at boot
    check_unknown_units "$ES2_NAME" "$ES2_HOST" \
        $UNIT_OK_GLOBAL listmonk.service uptime-kuma.service
    check_reboot "$ES2_NAME" "$ES2_HOST"
    check_pending_upgrades "$ES2_NAME" "$ES2_HOST"
    _run=$((CHECKS_RUN - _r)); _pass=$((CHECKS_PASSED - _p))
    [ $_pass -eq $_run ] && SERVER_SUMMARY="${SERVER_SUMMARY}✅ ${ES2_NAME} (${_pass}/${_run})\n" || SERVER_SUMMARY="${SERVER_SUMMARY}⚠️ ${ES2_NAME} (${_pass}/${_run})\n"
fi

# =======================================================================
# es3 (Hub/Auth) — local checks
# =======================================================================
ES3_HOST="localhost"
ES3_NAME="es3/Hub-Auth"

_r=$CHECKS_RUN; _p=$CHECKS_PASSED
log "Checking $ES3_NAME (local)"
check "$ES3_NAME" "$ES3_HOST" "fail2ban running" \
    "systemctl is-active --quiet fail2ban"
check "$ES3_NAME" "$ES3_HOST" "firewalld active" \
    "systemctl is-active --quiet firewalld"
check "$ES3_NAME" "$ES3_HOST" "dnf-automatic enabled" \
    "systemctl is-enabled --quiet dnf-automatic-install.timer"
check "$ES3_NAME" "$ES3_HOST" "SSH password auth disabled" \
    "grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config"
check "$ES3_NAME" "$ES3_HOST" "rpcbind not running" \
    "! systemctl is-active --quiet rpcbind && ! systemctl is-active --quiet rpcbind.socket"
check "$ES3_NAME" "$ES3_HOST" "MySQL bound to localhost" \
        "! { /sbin/ss -tlnH sport = :3306 2>/dev/null || ss -tlnH sport = :3306 2>/dev/null; } | awk '{print \$4}' | grep -qE '^(0\.0\.0\.0|\*)'"
check_ports "$ES3_NAME" "$ES3_HOST" \
    "22" "80" "443" "22000" "3306/lo" "8384/lo"
check_authorized_keys "$ES3_NAME" "$ES3_HOST" \
    "$FP_HP3" "$FP_HP4"
check_unknown_units "$ES3_NAME" "$ES3_HOST" \
    $UNIT_OK_GLOBAL syncthing-hub.service
_run=$((CHECKS_RUN - _r)); _pass=$((CHECKS_PASSED - _p))
[ $_pass -eq $_run ] && SERVER_SUMMARY="${SERVER_SUMMARY}✅ ${ES3_NAME} (${_pass}/${_run})\n" || SERVER_SUMMARY="${SERVER_SUMMARY}⚠️ ${ES3_NAME} (${_pass}/${_run})\n"
# es3 is Rocky Linux — uses dnf, reboot-required file path differs; skip reboot/upgrade warnings here

# =======================================================================
# es5 (Uselesscoin) — SSH host: es5-uselesscoin
# =======================================================================
ES5_HOST="es5-uselesscoin"
ES5_NAME="es5/Uselesscoin"

_r=$CHECKS_RUN; _p=$CHECKS_PASSED
if ! run_check "$ES5_HOST" "echo ok" > /dev/null; then
    SERVER_SUMMARY="${SERVER_SUMMARY}❌ ${ES5_NAME} (SSH unreachable)\n"
    FAILURES="${FAILURES}❌ ${ES5_NAME}: SSH connection failed\n"
    log "[FAIL] $ES5_NAME: cannot connect"
else
    log "Connected to $ES5_NAME"
    check "$ES5_NAME" "$ES5_HOST" "fail2ban running" \
        "systemctl is-active --quiet fail2ban"
    check "$ES5_NAME" "$ES5_HOST" "ufw active" \
        "ufw status | grep -q 'Status: active'"
    check "$ES5_NAME" "$ES5_HOST" "unattended-upgrades enabled" \
        "systemctl is-enabled --quiet unattended-upgrades"
    check "$ES5_NAME" "$ES5_HOST" "SSH password auth disabled" \
        "grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config"
    check "$ES5_NAME" "$ES5_HOST" "rpcbind not running" \
        "! systemctl is-active --quiet rpcbind && ! systemctl is-active --quiet rpcbind.socket"
    check_ports "$ES5_NAME" "$ES5_HOST" \
        "22" "80" "53/lo"
    check_authorized_keys "$ES5_NAME" "$ES5_HOST" \
        "$FP_HP3" "$FP_HP4" "$FP_ES3"
    check_unknown_units "$ES5_NAME" "$ES5_HOST" \
        $UNIT_OK_GLOBAL
    check_reboot "$ES5_NAME" "$ES5_HOST"
    check_pending_upgrades "$ES5_NAME" "$ES5_HOST"
    _run=$((CHECKS_RUN - _r)); _pass=$((CHECKS_PASSED - _p))
    [ $_pass -eq $_run ] && SERVER_SUMMARY="${SERVER_SUMMARY}✅ ${ES5_NAME} (${_pass}/${_run})\n" || SERVER_SUMMARY="${SERVER_SUMMARY}⚠️ ${ES5_NAME} (${_pass}/${_run})\n"
fi

# =======================================================================
# es7 (ROFLFaucet) — SSH host: es7-roflfaucet
# =======================================================================
ES7_HOST="es7-roflfaucet"
ES7_NAME="es7/ROFLFaucet"

_r=$CHECKS_RUN; _p=$CHECKS_PASSED
if ! run_check "$ES7_HOST" "echo ok" > /dev/null; then
    SERVER_SUMMARY="${SERVER_SUMMARY}❌ ${ES7_NAME} (SSH unreachable)\n"
    FAILURES="${FAILURES}❌ ${ES7_NAME}: SSH connection failed\n"
    log "[FAIL] $ES7_NAME: cannot connect"
else
    log "Connected to $ES7_NAME"
    check "$ES7_NAME" "$ES7_HOST" "fail2ban running" \
        "systemctl is-active --quiet fail2ban"
    check "$ES7_NAME" "$ES7_HOST" "ufw active" \
        "ufw status | grep -q 'Status: active'"
    check "$ES7_NAME" "$ES7_HOST" "unattended-upgrades enabled" \
        "systemctl is-enabled --quiet unattended-upgrades"
    check "$ES7_NAME" "$ES7_HOST" "SSH password auth disabled" \
        "grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config"
    check "$ES7_NAME" "$ES7_HOST" "rpcbind not running" \
        "! systemctl is-active --quiet rpcbind && ! systemctl is-active --quiet rpcbind.socket"
check "$ES7_NAME" "$ES7_HOST" "MySQL bound to localhost" \
        "! ss -tlnH sport = :3306 2>/dev/null | awk '{print \$4}' | grep -qE '^(0\.0\.0\.0|\*)'"
check "$ES7_NAME" "$ES7_HOST" "Postfix bound to localhost" \
        "! ss -tlnH sport = :25 2>/dev/null | awk '{print \$4}' | grep -qE '^(0\.0\.0\.0|\*)'"
    check_ports "$ES7_NAME" "$ES7_HOST" \
        "22" "80" "443" "25/lo" "3306/lo" "33060/lo" "22000" "8384/lo" "53/lo"
    check_authorized_keys "$ES7_NAME" "$ES7_HOST" \
        "$FP_HP3" "$FP_HP4" "$FP_ES3"
    check_unknown_units "$ES7_NAME" "$ES7_HOST" \
        $UNIT_OK_GLOBAL roflfaucet-sync.service syncthing-roflfaucet.service
    check_reboot "$ES7_NAME" "$ES7_HOST"
    check_pending_upgrades "$ES7_NAME" "$ES7_HOST"
    _run=$((CHECKS_RUN - _r)); _pass=$((CHECKS_PASSED - _p))
    [ $_pass -eq $_run ] && SERVER_SUMMARY="${SERVER_SUMMARY}✅ ${ES7_NAME} (${_pass}/${_run})\n" || SERVER_SUMMARY="${SERVER_SUMMARY}⚠️ ${ES7_NAME} (${_pass}/${_run})\n"
fi

# =======================================================================
# RN1 (DirectSponsor) — SSH host: rn1
# =======================================================================
RN1_HOST="rn1"
RN1_NAME="RN1/DirectSponsor"

_r=$CHECKS_RUN; _p=$CHECKS_PASSED
if ! run_check "$RN1_HOST" "echo ok" > /dev/null; then
    SERVER_SUMMARY="${SERVER_SUMMARY}❌ ${RN1_NAME} (SSH unreachable)\n"
    FAILURES="${FAILURES}❌ ${RN1_NAME}: SSH connection failed\n"
    log "[FAIL] $RN1_NAME: cannot connect"
else
    log "Connected to $RN1_NAME"
    check "$RN1_NAME" "$RN1_HOST" "fail2ban running" \
        "systemctl is-active --quiet fail2ban"
    check "$RN1_NAME" "$RN1_HOST" "ufw active" \
        "ufw status | grep -q 'Status: active'"
    check "$RN1_NAME" "$RN1_HOST" "unattended-upgrades enabled" \
        "systemctl is-enabled --quiet unattended-upgrades"
    check "$RN1_NAME" "$RN1_HOST" "SSH password auth disabled" \
        "grep -qE '^PasswordAuthentication no' /etc/ssh/sshd_config"
    check "$RN1_NAME" "$RN1_HOST" "rpcbind not running" \
        "! systemctl is-active --quiet rpcbind && ! systemctl is-active --quiet rpcbind.socket"
    check_ports "$RN1_NAME" "$RN1_HOST" \
        "22" "80" "443" "7777/lo"
    check_authorized_keys "$RN1_NAME" "$RN1_HOST" \
        "$FP_HP3" "$FP_HP4" "$FP_ES3"
    check_unknown_units "$RN1_NAME" "$RN1_HOST" \
        $UNIT_OK_GLOBAL resize-root-fs.service strfry.service
    check_reboot "$RN1_NAME" "$RN1_HOST"
    check_pending_upgrades "$RN1_NAME" "$RN1_HOST"
    _run=$((CHECKS_RUN - _r)); _pass=$((CHECKS_PASSED - _p))
    [ $_pass -eq $_run ] && SERVER_SUMMARY="${SERVER_SUMMARY}✅ ${RN1_NAME} (${_pass}/${_run})\n" || SERVER_SUMMARY="${SERVER_SUMMARY}⚠️ ${RN1_NAME} (${_pass}/${_run})\n"
fi

# =======================================================================
# Summary
# =======================================================================
log "=== Security Check Complete: ${CHECKS_PASSED}/${CHECKS_RUN} checks passed ==="

if [ -n "$FAILURES" ]; then
    log "FAILURES DETECTED — sending Telegram alert"
    MSG="$(echo -e "$SERVER_SUMMARY")
❌ Details:
$(echo -e "$FAILURES")"
    if [ -n "$WARNINGS" ]; then
        MSG="$MSG
$(echo -e "$WARNINGS")"
    fi
    telegram_notify "🔒 Security Check Failed" "$MSG" 2>/dev/null
    exit 1
elif [ -n "$WARNINGS" ]; then
    log "Checks passed but warnings present — sending Telegram alert"
    telegram_notify "🔒 Security Check OK (with warnings)" "$(echo -e "$SERVER_SUMMARY")
$(echo -e "$WARNINGS")" 2>/dev/null
    exit 0
else
    log "All checks passed"
    telegram_notify "🔒 Security Check OK" "$(echo -e "$SERVER_SUMMARY")" 2>/dev/null
    exit 0
fi

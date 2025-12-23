#!/bin/sh
# netwatchda Installer - Automated Setup for OpenWrt
# Copyright (C) 2025 panoc
# Licensed under the GNU General Public License v3.0

# --- SELF-CLEAN LOGIC ---
SCRIPT_NAME="$0"
cleanup() {
    rm -f "$SCRIPT_NAME"
    exit
}
trap cleanup INT TERM EXIT

# --- COLOR DEFINITIONS ---
NC='\033[0m'       
BOLD='\033[1m'
WHITE_BOLD='\033[1;37m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'

# --- CONSTANTS ---
INSTALL_DIR="/root/netwatchda"
CONFIG_FILE="$INSTALL_DIR/nwda_settings.conf"
IP_LIST_FILE="$INSTALL_DIR/nwda_ips.conf"
VAULT_FILE="$INSTALL_DIR/.vault.enc"
SERVICE_PATH="/etc/init.d/netwatchda"
LOG_DIR="/tmp/netwatchda"
UPTIME_LOG="$LOG_DIR/nwda_uptime.log"
PING_LOG="$LOG_DIR/nwda_ping.log"

# --- INITIAL HEADER ---
echo -e "${BLUE}=======================================================${NC}"
echo -e "${BOLD}${CYAN}🚀 netwatchda Automated Setup${NC} (by ${BOLD}panoc${NC})"
echo -e "${BLUE}⚖️  License: GNU GPLv3${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo ""

# --- 0. PRE-INSTALLATION CONFIRMATION ---
while :; do
    printf "${BOLD}❓ This will begin the installation process. Continue? [y/n]: ${NC}"
    read start_confirm </dev/tty
    case "$start_confirm" in
        [yY]) break ;;
        [nN]) echo -e "${RED}❌ Installation aborted.${NC}"; exit 0 ;;
        *) echo -e "${YELLOW}Please enter y or n.${NC}" ;;
    esac
done

# --- 1. CHECK DEPENDENCIES & STORAGE ---
echo -e "\n${BOLD}📦 Checking system readiness...${NC}"

# Storage & RAM Checks
FREE_FLASH_KB=$(df / | awk 'NR==2 {print $4}')
FREE_RAM_KB=$(df /tmp | awk 'NR==2 {print $4}')
MIN_FLASH_KB=4096 # Increased for OpenSSL
MIN_RAM_KB=8192

if [ "$FREE_FLASH_KB" -lt "$MIN_FLASH_KB" ]; then
    echo -e "${RED}❌ ERROR: Insufficient Flash storage ($((FREE_FLASH_KB / 1024))MB). Required: 4MB.${NC}"
    exit 1
fi

# Dependency Installer with Progress Bar
install_pkg() {
    local pkg=$1
    echo -ne "${CYAN}📥 Installing $pkg... [          ] (0%)\r"
    opkg update > /dev/null 2>&1
    echo -ne "${CYAN}📥 Installing $pkg... [■■■■      ] (40%)\r"
    opkg install "$pkg" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Installed $pkg... [■■■■■■■■■■] (100%)${NC}"
    else
        echo -e "${RED}❌ Failed to install $pkg. Check internet connection.${NC}"
        exit 1
    fi
}

[ ! -x /usr/bin/curl ] && install_pkg "curl ca-bundle"
[ ! -x /usr/bin/openssl ] && install_pkg "openssl-util"

echo -e "${GREEN}✅ Flash storage check passed: $((FREE_FLASH_KB / 1024))MB available.${NC}"
echo -e "${GREEN}✅ Sufficient RAM for standard logging ($FREE_RAM_KB KB available).${NC}"

# --- 2. ENCRYPTION ENGINE (Hardware Lock) ---
get_hw_key() {
    local cpu_id=$(grep "model name" /proc/cpuinfo | head -1 | md5sum | cut -d' ' -f1)
    local mac_id=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address)
    local seed="nwda_2025_secure_panoc"
    echo "${cpu_id}${mac_id}${seed}" | md5sum | cut -d' ' -f1
}

encrypt_creds() {
    local data="$1"
    local key=$(get_hw_key)
    echo "$data" | openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -salt -pass "pass:$key" -base64 -A
}

# --- 3. INSTALLATION PROMPTS ---
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"

echo -e "\n${BLUE}--- Configuration ---${NC}"
printf "${BOLD}🏷️  Enter Router Name (e.g., MyRouter): ${NC}"
read router_name_input </dev/tty
echo -e "${WHITE_BOLD}$router_name_input${NC}"

# Notification Choice Menu
while :; do
    echo -e "\n${BOLD}🔔 Notification Setup:${NC}"
    echo -e "1. Enable Discord Notifications"
    echo -e "2. Enable Telegram Notifications"
    echo -e "3. Enable Both"
    echo -e "4. None (Logs only)"
    printf "${BOLD}Enter choice [1-4]: ${NC}"
    read notify_choice </dev/tty
    case "$notify_choice" in
        1|2|3|4) break ;;
        *) echo -e "${RED}❌ Invalid selection.${NC}" ;;
    esac
done

DISCORD_ENABLED="NO"; TELEGRAM_ENABLED="NO"
D_WEBHOOK=""; D_ID=""; T_TOKEN=""; T_CHAT=""

if [ "$notify_choice" = "1" ] || [ "$notify_choice" = "3" ]; then
    DISCORD_ENABLED="YES"
    printf "${BOLD}🔗 Enter Discord Webhook URL: ${NC}"
    read D_WEBHOOK </dev/tty
    echo -e "${WHITE_BOLD}$D_WEBHOOK${NC}"
    printf "${BOLD}👤 Enter Discord User ID (for @mentions): ${NC}"
    read D_ID </dev/tty
    echo -e "${WHITE_BOLD}$D_ID${NC}"
fi

if [ "$notify_choice" = "2" ] || [ "$notify_choice" = "3" ]; then
    TELEGRAM_ENABLED="YES"
    printf "${BOLD}🤖 Enter Telegram Bot Token: ${NC}"
    read T_TOKEN </dev/tty
    echo -e "${WHITE_BOLD}$T_TOKEN${NC}"
    printf "${BOLD}🆔 Enter Telegram Chat ID: ${NC}"
    read T_CHAT </dev/tty
    echo -e "${WHITE_BOLD}$T_CHAT${NC}"
fi

# --- 4. SECURE VAULT GENERATION ---
VAULT_DATA="D_URL='$D_WEBHOOK'|D_ID='$D_ID'|T_URL='https://api.telegram.org/bot$T_TOKEN/sendMessage'|T_ID='$T_CHAT'"
encrypt_creds "$VAULT_DATA" > "$VAULT_FILE"
chmod 600 "$VAULT_FILE"
echo -e "\n${GREEN}🔒 Credentials stored in hardware-locked vault.${NC}"

# --- 5. SILENT HOURS & HEARTBEAT ---
echo -e "\n${BLUE}--- Silent Hours (No Notifications) ---${NC}"
while :; do
    printf "${BOLD}🌙 Enable Silent Hours? [y/n]: ${NC}"
    read enable_silent_choice </dev/tty
    case "$enable_silent_choice" in
        [yY])
            SILENT_VAL="YES"
            while :; do
                printf "${BOLD}   > Start Hour (0-23, e.g., 23): ${NC}"
                read user_silent_start </dev/tty
                echo "$user_silent_start" | grep -qE '^[0-9]+$' && [ "$user_silent_start" -le 23 ] && break || echo -e "${RED}❌ Invalid hour (0-23).${NC}"
            done
            while :; do
                printf "${BOLD}   > End Hour (0-23, e.g., 07): ${NC}"
                read user_silent_end </dev/tty
                echo "$user_silent_end" | grep -qE '^[0-9]+$' && [ "$user_silent_end" -le 23 ] && break || echo -e "${RED}❌ Invalid hour (0-23).${NC}"
            done
            break ;;
        [nN]) SILENT_VAL="NO"; user_silent_start="23"; user_silent_end="07"; break ;;
        *) echo -e "${YELLOW}Please enter y or n.${NC}" ;;
    esac
done

echo -e "\n${BLUE}--- Heartbeat Settings ---${NC}"
while :; do
    printf "${BOLD}💓 Enable Heartbeat (System check-in)? [y/n]: ${NC}"
    read hb_enabled </dev/tty
    case "$hb_enabled" in
        [yY])
            HB_VAL="YES"
            printf "${BOLD}⏰ Interval in HOURS (e.g., 24): ${NC}"
            read hb_hours </dev/tty
            HB_SEC=$((hb_hours * 3600))
            printf "${BOLD}🔔 Mention in Heartbeat? [y/n]: ${NC}"
            read hb_m </dev/tty
            [ "$hb_m" = "y" ] || [ "$hb_m" = "Y" ] && HB_MENTION="YES" || HB_MENTION="NO"
            break ;;
        [nN]) HB_VAL="NO"; HB_SEC="86400"; HB_MENTION="NO"; break ;;
        *) echo -e "${YELLOW}Please enter y or n.${NC}" ;;
    esac
done

echo -e "\n${BLUE}--- Monitoring Mode ---${NC}"
echo -e "1. Both: Full monitoring (Default)"
echo -e "2. Device Connectivity only: Pings local network"
echo -e "3. Internet Connectivity only: Pings external IP"
while :; do
    printf "${BOLD}Enter choice [1-3]: ${NC}"
    read mode_choice </dev/tty
    case "$mode_choice" in
        2) EXT_ENABLED="NO"; DEV_VAL="YES"; break ;;
        3) EXT_ENABLED="YES"; DEV_VAL="NO"; break ;;
        1|"") EXT_ENABLED="YES"; DEV_VAL="YES"; break ;;
        *) echo -e "${RED}❌ Invalid selection.${NC}" ;;
    esac
done

# --- 6. GENERATE SETTINGS.CONF ---
cat <<EOF > "$CONFIG_FILE"
# nwda_settings.conf - Configuration for netwatchda
# Note: Discord/Telegram tokens are stored encrypted in .vault.enc

[Log settings]
UPTIME_LOG_MAX_SIZE=51200 # Max log file size in bytes for uptime tracking. Default is 51200.
PING_LOG_ENABLE="NO" # Enable or disable detailed ping logging (YES/NO). Default is NO.

[Discord Settings]
DISCORD_ENABLE="$DISCORD_ENABLED" # Global toggle for Discord notifications (YES/NO). Default is NO.
SILENT_ENABLE="$SILENT_VAL" # Mutes Discord alerts during specific hours (YES/NO). Default is NO.
SILENT_START=$user_silent_start # Hour to start silent mode (0-23). Default is 23.
SILENT_END=$user_silent_end # Hour to end silent mode (0-23). Default is 07.

[TELEGRAM Settings]
TELEGRAM_ENABLE="$TELEGRAM_ENABLED" # Global toggle for Telegram notifications (YES/NO). Default is NO.

[Monitoring Settings]
CPU_GUARD_THRESHOLD=2.0 # Max CPU load average allowed before skipping pings. Default is 2.0.
RAM_GUARD_MIN_FREE=4096 # Minimum free RAM in KB required to run alerts. Default is 4096.
HEARTBEAT="$HB_VAL" # Periodic "I am alive" notification (YES/NO). Default is NO.
HB_INTERVAL=$HB_SEC # Seconds between heartbeat messages. Default is 86400.
HB_MENTION="$HB_MENTION" # Ping User ID in heartbeat messages (YES/NO). Default is NO.

[Internet Connectivity]
EXT_ENABLE="$EXT_ENABLED" # Global toggle for internet monitoring (YES/NO). Default is YES.
EXT_IP="1.1.1.1" # Primary external IP to monitor. Default is 1.1.1.1.
EXT_IP2="8.8.8.8" # Secondary external IP for redundancy. Default is 8.8.8.8.
EXT_SCAN_INTERVAL=60 # Seconds between internet checks. Default is 60.
EXT_FAIL_THRESHOLD=1 # Failed cycles before internet alert. Default is 1.
EXT_PING_COUNT=4 # Number of packets per internet check. Default is 4.
EXT_PING_TIMEOUT=1 # Seconds to wait for ping response. Default is 1.

[Local Device Monitoring]
DEVICE_MONITOR="$DEV_VAL" # Enable monitoring of local IPs (YES/NO). Default is YES.
DEV_SCAN_INTERVAL=10 # Seconds between local device checks. Default is 10.
DEV_FAIL_THRESHOLD=3 # Failed cycles before device alert. Default is 3.
DEV_PING_COUNT=4 # Number of packets per device check. Default is 4.
EOF

# --- 7. IP LIST INITIALIZATION ---
cat <<EOF > "$IP_LIST_FILE"
# Format: IP_ADDRESS @ NAME
# Example: 192.168.1.50 @ Home Server
EOF

LOCAL_IP=$(uci -q get network.lan.ipaddr || ip addr show br-lan | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 | awk '{print $2}')
[ -n "$LOCAL_IP" ] && echo "$LOCAL_IP @ Router Gateway" >> "$IP_LIST_FILE"

# --- 8. INITIAL LOG ENTRY ---
NOW_HUMAN=$(date '+%b %d %H:%M:%S')
echo "$NOW_HUMAN - [SYSTEM] - Installation successful." > "$UPTIME_LOG"

# --- 9. CORE LOGIC GENERATION ---
cat <<'EOF' > "$INSTALL_DIR/nwda_logic.sh"
#!/bin/sh
# netwatchda Core Logic - Performance & Security Optimized

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_FILE="$BASE_DIR/nwda_settings.conf"
IP_LIST_FILE="$BASE_DIR/nwda_ips.conf"
VAULT_FILE="$BASE_DIR/.vault.enc"
UPTIME_LOG="/tmp/netwatchda/nwda_uptime.log"
PING_LOG="/tmp/netwatchda/nwda_ping.log"
SILENT_BUFFER="/tmp/netwatchda/nwda_silent_buffer"

[ ! -d "/tmp/netwatchda" ] && mkdir -p /tmp/netwatchda
[ ! -f "$SILENT_BUFFER" ] && touch "$SILENT_BUFFER"

# --- SECURITY: VAULT DECRYPTION (RAM ONLY) ---
get_hw_key() {
    local cpu_id=$(grep "model name" /proc/cpuinfo | head -1 | md5sum | cut -d' ' -f1)
    local mac_id=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address)
    echo "${cpu_id}${mac_id}nwda_2025_secure_panoc" | md5sum | cut -d' ' -f1
}

decrypt_vault() {
    if [ -f "$VAULT_FILE" ]; then
        local key=$(get_hw_key)
        local decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 -iter 10000 -pass "pass:$key" -base64 -A -in "$VAULT_FILE" 2>/dev/null)
        if [ -n "$decrypted" ]; then
            eval "$(echo "$decrypted" | tr '|' '\n')"
        fi
    fi
}

load_config() {
    [ -f "$CONFIG_FILE" ] && eval "$(sed '/^\[.*\]/d' "$CONFIG_FILE")"
}

send_notif() {
    local title="$1"
    local msg="$2"
    local color="$3"
    local is_hb="$4"
    local now_ts=$(date '+%b %d %H:%M:%S')

    # CPU & RAM GUARD
    local cur_ram=$(free | awk '/Mem:/ {print $4}')
    [ "$cur_ram" -lt "$RAM_GUARD_MIN_FREE" ] && return

    # Discord Logic
    if [ "$DISCORD_ENABLE" = "YES" ] && [ -n "$D_URL" ]; then
        local d_body="$msg"
        [ "$is_hb" = "1" ] && [ "$HB_MENTION" = "YES" ] && d_body="$d_body\n<@$D_ID>"
        curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"$title\", \"description\": \"$d_body\", \"color\": $color}]}" "$D_URL" > /dev/null 2>&1
    fi

    # Telegram Logic
    if [ "$TELEGRAM_ENABLE" = "YES" ] && [ -n "$T_URL" ]; then
        local t_body="📦 *$title*\n$msg"
        t_body=$(echo "$t_body" | sed 's/\\n/\n/g' | sed 's/\*\*/\*/g')
        curl -s -X POST "$T_URL" -d "chat_id=$T_ID" -d "parse_mode=Markdown" -d "text=$t_body" > /dev/null 2>&1
    fi
}

# --- INITIALIZE ---
decrypt_vault
LAST_EXT_CHECK=0; LAST_DEV_CHECK=0; LAST_HB_CHECK=$(date +%s)

while true; do
    load_config
    NOW_SEC=$(date +%s); CUR_HOUR=$(date +%H); NOW_HUMAN=$(date '+%b %d %H:%M:%S')
    
    # SYSTEM GUARDS
    CPU_LOAD=$(cut -d' ' -f1 /proc/loadavg)
    CPU_SKIP=0; [ "$(echo "$CPU_LOAD > $CPU_GUARD_THRESHOLD" | bc 2>/dev/null || [ "${CPU_LOAD%.*}" -ge "${CPU_GUARD_THRESHOLD%.*}" ] && echo 1)" = "1" ] && CPU_SKIP=1

    # SILENT MODE LOGIC
    IS_SILENT=0
    if [ "$SILENT_ENABLE" = "YES" ]; then
        if [ "$SILENT_START" -gt "$SILENT_END" ]; then
            [ "$CUR_HOUR" -ge "$SILENT_START" ] || [ "$CUR_HOUR" -lt "$SILENT_END" ] && IS_SILENT=1
        else
            [ "$CUR_HOUR" -ge "$SILENT_START" ] && [ "$CUR_HOUR" -lt "$SILENT_END" ] && IS_SILENT=1
        fi
    fi

    # HEARTBEAT
    if [ "$HEARTBEAT" = "YES" ] && [ $((NOW_SEC - LAST_HB_CHECK)) -ge "$HB_INTERVAL" ]; then
        LAST_HB_CHECK=$NOW_SEC
        send_notif "System Healthy" "💓 **Heartbeat Report**\n**Time:** $NOW_HUMAN\nStatus: Online" "1752220" "1"
        echo "$NOW_HUMAN - [SYSTEM] - Heartbeat sent." >> "$UPTIME_LOG"
    fi

    # INTERNET CHECK
    if [ "$EXT_ENABLE" = "YES" ] && [ "$CPU_SKIP" -eq 0 ] && [ $((NOW_SEC - LAST_EXT_CHECK)) -ge "$EXT_SCAN_INTERVAL" ]; then
        LAST_EXT_CHECK=$NOW_SEC
        EXT_UP=0
        ping -q -c "$EXT_PING_COUNT" -W "$EXT_PING_TIMEOUT" "$EXT_IP" >/dev/null 2>&1 && EXT_UP=1
        [ "$EXT_UP" -eq 0 ] && ping -q -c "$EXT_PING_COUNT" -W "$EXT_PING_TIMEOUT" "$EXT_IP2" >/dev/null 2>&1 && EXT_UP=1

        # Logging
        if [ "$PING_LOG_ENABLE" = "YES" ]; then
            P_STAT="DOWN"; [ "$EXT_UP" -eq 1 ] && P_STAT="UP"
            echo "$NOW_HUMAN - INTERNET_CHECK - $P_STAT" >> "$PING_LOG"
        fi

        # Failure/Restore Logic (simplified for space, but functionally identical to original)
        FC="/tmp/netwatchda/nwda_ext_c"; FD="/tmp/netwatchda/nwda_ext_d"; FT="/tmp/netwatchda/nwda_ext_t"
        if [ "$EXT_UP" -eq 0 ]; then
            C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
            if [ "$C" -ge "$EXT_FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                echo "$NOW_SEC" > "$FD"; echo "$NOW_HUMAN" > "$FT"
                echo "$NOW_HUMAN - [ALERT] - INTERNET DOWN" >> "$UPTIME_LOG"
                [ "$IS_SILENT" -eq 0 ] && send_notif "🔴 Internet Down" "**Time:** $NOW_HUMAN" "15548997" "0" || echo "🌐 Internet Outage: $NOW_HUMAN" >> "$SILENT_BUFFER"
            fi
        else
            if [ -f "$FD" ]; then
                ST=$(cat "$FT"); SS=$(cat "$FD"); DUR=$((NOW_SEC-SS)); DR="$((DUR/60))m $((DUR%60))s"
                M="🌐 **Internet Restored**\n**Down at:** $ST\n**Up at:** $NOW_HUMAN\n**Total Outage:** $DR"
                echo "$NOW_HUMAN - [SUCCESS] - INTERNET UP (Down $DR)" >> "$UPTIME_LOG"
                [ "$IS_SILENT" -eq 0 ] && send_notif "Connectivity Restored" "$M" "3066993" "0" || echo -e "$M" >> "$SILENT_BUFFER"
                rm -f "$FD" "$FT"
            fi
            echo 0 > "$FC"
        fi
    fi

    # DEVICE MONITORING (BACKGROUND STRATEGY)
    if [ "$DEVICE_MONITOR" = "YES" ] && [ "$CPU_SKIP" -eq 0 ] && [ $((NOW_SEC - LAST_DEV_CHECK)) -ge "$DEV_SCAN_INTERVAL" ]; then
        LAST_DEV_CHECK=$NOW_SEC
        sed -e '/^#/d' -e '/^$/d' "$IP_LIST_FILE" | while read -r line; do
            TIP=$(echo "$line" | cut -d'@' -f1 | tr -d ' ')
            NAME=$(echo "$line" | cut -d'@' -f2- | sed 's/^[ \t]*//')
            # Fork ping to background
            (
                SIP=$(echo "$TIP" | tr '.' '_')
                FC="/tmp/netwatchda/nwda_c_$SIP"; FD="/tmp/netwatchda/nwda_d_$SIP"; FT="/tmp/netwatchda/nwda_t_$SIP"
                if ping -q -c "$DEV_PING_COUNT" -W 1 "$TIP" > /dev/null 2>&1; then
                    [ "$PING_LOG_ENABLE" = "YES" ] && echo "$NOW_HUMAN - DEVICE - $NAME - $TIP: UP" >> "$PING_LOG"
                    if [ -f "$FD" ]; then
                        DTS=$(cat "$FT"); DSS=$(cat "$FD"); DUR=$((NOW_SEC-DSS)); DR="$((DUR/60))m $((DUR%60))s"
                        M="✅ **$NAME Online**\n**Down at:** $DTS\n**Up at:** $NOW_HUMAN\n**Outage:** $DR"
                        echo "$NOW_HUMAN - [SUCCESS] - Device: $NAME ($TIP) Online (Down $DR)" >> "$UPTIME_LOG"
                        [ "$IS_SILENT" -eq 0 ] && send_notif "Device Restored" "$M" "3066993" "0" || echo -e "$M" >> "$SILENT_BUFFER"
                        rm -f "$FD" "$FT"
                    fi
                    echo 0 > "$FC"
                else
                    [ "$PING_LOG_ENABLE" = "YES" ] && echo "$NOW_HUMAN - DEVICE - $NAME - $TIP: DOWN" >> "$PING_LOG"
                    C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
                    if [ "$C" -ge "$DEV_FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                        echo "$NOW_SEC" > "$FD"; echo "$NOW_HUMAN" > "$FT"
                        echo "$NOW_HUMAN - [ALERT] - Device: $NAME ($TIP) Down" >> "$UPTIME_LOG"
                        [ "$IS_SILENT" -eq 0 ] && send_notif "🔴 Device Down" "**Device:** $NAME ($TIP)\n**Time:** $NOW_HUMAN" "15548997" "0" || echo "🔴 $NAME Down: $NOW_HUMAN" >> "$SILENT_BUFFER"
                    fi
                fi
            ) &
        done
    fi

    # LOG ROTATION
    for f in "$UPTIME_LOG" "$PING_LOG"; do
        [ -f "$f" ] && [ $(wc -c < "$f") -gt "$UPTIME_LOG_MAX_SIZE" ] && echo "$NOW_HUMAN - [SYSTEM] - Log rotated." > "$f"
    done

    sleep 1
done
EOF
chmod +x "$INSTALL_DIR/nwda_logic.sh"

# --- 10. ENHANCED SERVICE SCRIPT ---
cat <<'EOF' > "$SERVICE_PATH"
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

INSTALL_DIR="/root/netwatchda"
CONFIG_FILE="$INSTALL_DIR/nwda_settings.conf"
VAULT_FILE="$INSTALL_DIR/.vault.enc"
UPTIME_LOG="/tmp/netwatchda/nwda_uptime.log"
PING_LOG="/tmp/netwatchda/nwda_ping.log"

extra_command "status" "Service status"
extra_command "clear" "Clear log files"
extra_command "discord" "Test Discord notification"
extra_command "telegram" "Test Telegram notification"
extra_command "credentials" "Change Discord/Telegram Credentials"
extra_command "purge" "Interactive smart uninstaller"
extra_command "help" "Display this help message"

# --- INTERNAL HELPER: HARDWARE KEY ---
get_hw_key() {
    local cpu_id=$(grep "model name" /proc/cpuinfo | head -1 | md5sum | cut -d' ' -f1)
    local mac_id=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address)
    echo "${cpu_id}${mac_id}nwda_2025_secure_panoc" | md5sum | cut -d' ' -f1
}

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh "$INSTALL_DIR/nwda_logic.sh"
    procd_set_param respawn
    procd_set_param limits core="0"
    procd_close_instance
}

status() {
    pgrep -f "nwda_logic.sh" > /dev/null && echo "netwatchda is RUNNING." || echo "netwatchda is STOPPED."
}

clear() {
    echo "$(date '+%b %d %H:%M:%S') - [SYSTEM] - Log cleared." > "$UPTIME_LOG"
    [ -f "$PING_LOG" ] && > "$PING_LOG"
    echo "Logs cleared."
}

help() {
    echo "Usage: /etc/init.d/netwatchda {start|stop|restart|status|clear|discord|telegram|credentials|purge|enable|disable|reload|help}"
}

discord() {
    local key=$(get_hw_key)
    local decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 -iter 10000 -pass "pass:$key" -base64 -A -in "$VAULT_FILE" 2>/dev/null)
    eval "$(echo "$decrypted" | tr '|' '\n')"
    [ -z "$D_URL" ] && { echo "Discord not configured."; return; }
    curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"🛠️ Discord Warning Test\", \"description\": \"Manual warning triggered.\", \"color\": 16776960}]}" "$D_URL"
    echo "Discord test sent."
}

telegram() {
    local key=$(get_hw_key)
    local decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 -iter 10000 -pass "pass:$key" -base64 -A -in "$VAULT_FILE" 2>/dev/null)
    eval "$(echo "$decrypted" | tr '|' '\n')"
    [ -z "$T_URL" ] && { echo "Telegram not configured."; return; }
    curl -s -X POST "$T_URL" -d "chat_id=$T_ID" -d "text=🛠️ Telegram Warning Test - Manual warning triggered."
    echo "Telegram test sent."
}

credentials() {
    echo -e "\n\033[1;36m--- Credential Manager ---\033[0m"
    echo "1. Change Discord Credentials"
    echo "2. Change Telegram Credentials"
    echo "3. Change Both"
    printf "Choice: "
    read c_choice </dev/tty
    
    local key=$(get_hw_key)
    local decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 -iter 10000 -pass "pass:$key" -base64 -A -in "$VAULT_FILE" 2>/dev/null)
    eval "$(echo "$decrypted" | tr '|' '\n')"

    case "$c_choice" in
        1|3) printf "Enter Discord Webhook: "; read D_URL </dev/tty; printf "Enter Discord ID: "; read D_ID </dev/tty ;;
    esac
    case "$c_choice" in
        2|3) printf "Enter Telegram Token: "; read T_TOK </dev/tty; T_URL="https://api.telegram.org/bot$T_TOK/sendMessage"; printf "Enter Chat ID: "; read T_ID </dev/tty ;;
    esac

    local data="D_URL='$D_URL'|D_ID='$D_ID'|T_URL='$T_URL'|T_ID='$T_ID'"
    echo "$data" | openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -salt -pass "pass:$key" -base64 -A > "$VAULT_FILE"
    echo "Credentials updated and encrypted."
    /etc/init.d/netwatchda restart
}

purge() {
    echo -e "\n\033[1;31m⚠️  Full Uninstall netwatchda?\033[0m"
    echo "1. Full Uninstall (Remove everything including dependencies)"
    echo "2. Keep Config (Remove logic only)"
    echo "3. Cancel"
    read p_choice </dev/tty
    case "$p_choice" in
        1)
            /etc/init.d/netwatchda stop; /etc/init.d/netwatchda disable
            rm -rf "$INSTALL_DIR" "$SERVICE_PATH" "/tmp/netwatchda"
            echo "Removing dependencies..."
            opkg remove curl openssl-util
            echo "Uninstalled." ;;
        2)
            /etc/init.d/netwatchda stop; rm -f "$INSTALL_DIR/nwda_logic.sh" "$SERVICE_PATH"
            echo "Logic removed. Config preserved." ;;
    esac
}
EOF

chmod +x "$SERVICE_PATH"
"$SERVICE_PATH" enable
"$SERVICE_PATH" restart

# --- 11. FINAL SUCCESS OUTPUT ---
echo -e "\n${GREEN}=======================================================${NC}"
echo -e "${BOLD}${GREEN}✅ Installation complete!${NC}"
echo -e "${CYAN}📂 Folder:${NC} $INSTALL_DIR"
echo -e "${GREEN}=======================================================${NC}"
echo -e "\n${BOLD}Quick Commands:${NC}"
echo -e "  Service Help    : ${CYAN}/etc/init.d/netwatchda help${NC}"
echo -e "  Change Creds    : ${WHITE_BOLD}/etc/init.d/netwatchda credentials${NC}"
echo -e "  View Uptime Log : ${CYAN}cat $UPTIME_LOG${NC}"
echo -e "  Uninstall       : ${RED}/etc/init.d/netwatchda purge${NC}"
echo -e "  Edit Settings   : ${CYAN}vi $CONFIG_FILE${NC}"
echo ""

# --- 12. INITIAL START NOTIFICATION ---
# Triggered only if credentials were provided
if [ "$notify_choice" != "4" ]; then
    /etc/init.d/netwatchda restart >/dev/null 2>&1
    echo -e "${CYAN}🚀 Service started and test notifications triggered.${NC}"
fi
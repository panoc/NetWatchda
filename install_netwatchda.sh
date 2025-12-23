#!/bin/sh
# netwatchda Ultimate Installer - Hardened Network Monitoring for OpenWrt
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
RED='\033[1;31m'    # Light Red
GREEN='\033[1;32m'  # Light Green
BLUE='\033[1;34m'   # Light Blue
CYAN='\033[1;36m'   # Light Cyan
YELLOW='\033[1;33m' # Bold Yellow

# --- PATHS ---
INSTALL_DIR="/root/netwatchda"
CONFIG_FILE="$INSTALL_DIR/nwda_settings.conf"
IP_LIST_FILE="$INSTALL_DIR/nwda_ips.conf"
VAULT_FILE="$INSTALL_DIR/.vault.enc"
SEED_FILE="$INSTALL_DIR/.seed"
SERVICE_PATH="/etc/init.d/netwatchda"
LOG_DIR="/tmp/netwatchda"
UPTIME_LOG="$LOG_DIR/nwda_uptime.log"
PING_LOG="$LOG_DIR/nwda_ping.log"

# --- INITIAL HEADER ---
echo -e "${BLUE}=======================================================${NC}"
echo -e "${BOLD}${CYAN}🚀 netwatchda Ultimate Setup${NC} (by ${BOLD}panoc${NC})"
echo -e "${BLUE}⚖️  License: GNU GPLv3${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo ""

# --- 0. PRE-INSTALLATION CONFIRMATION ---
while :; do
    printf "${BOLD}❓ This will begin the installation process. Continue? [y/n]: ${NC}"
    read -r start_confirm </dev/tty
    case "$start_confirm" in
        [Yy]*) break ;;
        [Nn]*) echo -e "${RED}❌ Installation aborted. Cleaning up...${NC}"; exit 0 ;;
        *) echo -e "${YELLOW}Please enter y or n.${NC}" ;;
    esac
done

# --- 1. SYSTEM READINESS & DEPENDENCIES ---
echo -e "\n${BOLD}📦 Checking system readiness...${NC}"

FREE_FLASH_KB=$(df / | awk 'NR==2 {print $4}')
FREE_RAM_KB=$(df /tmp | awk 'NR==2 {print $4}')

if [ "$FREE_FLASH_KB" -lt 4096 ]; then
    echo -e "${RED}❌ ERROR: Insufficient Flash storage ($((FREE_FLASH_KB / 1024))MB available). Need 4MB.${NC}"
    exit 1
fi

install_pkg() {
    echo -ne "${CYAN}📥 Installing $1... [          ]\r"
    opkg update > /dev/null 2>&1
    echo -ne "${CYAN}📥 Installing $1... [#####     ]\r"
    opkg install "$1" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}📥 Installing $1... [##########] Done.${NC}"
    else
        echo -e "${RED}❌ Failed to install $1. Check your internet connection.${NC}"
        exit 1
    fi
}

command -v curl >/dev/null 2>&1 || install_pkg "curl ca-bundle"
command -v openssl >/dev/null 2>&1 || install_pkg "openssl-util"

mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"

# --- 2. HARDWARE LOCK GENERATION ---
if [ ! -f "$SEED_FILE" ]; then
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 > "$SEED_FILE"
fi

get_hw_key() {
    CPU_ID=$(grep -m1 "serial" /proc/cpuinfo | awk '{print $3}')
    [ -z "$CPU_ID" ] && CPU_ID=$(cat /sys/class/net/eth0/address 2>/dev/null || echo "NWDA_DEFAULT_ID")
    SEED=$(cat "$SEED_FILE")
    echo "${CPU_ID}${SEED}" | sha256sum | awk '{print $1}'
}

# --- 3. CONFIGURATION INPUTS ---
echo -e "\n${BLUE}--- Notification Strategy ---${NC}"
echo -e "1. ${WHITE_BOLD}Enable Discord Notifications${NC}"
echo -e "2. ${WHITE_BOLD}Enable Telegram Notifications${NC}"
echo -e "3. ${WHITE_BOLD}Enable Both${NC}"
echo -e "4. ${WHITE_BOLD}None (In this case user should be informed that events can only be tracked through logs)${NC}"

while :; do
    printf "${BOLD}Enter choice [1-4]: ${NC}"
    read -r notify_choice </dev/tty
    case "$notify_choice" in
        1|2|3|4) break ;;
        *) echo -e "${RED}❌ Invalid selection. Please enter 1, 2, 3, or 4.${NC}" ;;
    esac
done

D_EN="NO"; T_EN="NO"
D_URL=""; D_ID=""; T_TOK=""; T_ID=""

if [ "$notify_choice" = "1" ] || [ "$notify_choice" = "3" ]; then
    D_EN="YES"
    printf "${BOLD}🔗 Enter Discord Webhook URL: ${NC}"
    read -r D_URL </dev/tty
    printf "${BOLD}👤 Enter Discord User ID (for @mentions): ${NC}"
    read -r D_ID </dev/tty
    
    # Test Discord
    echo -e "${CYAN}🧪 Sending Discord test notification...${NC}"
    curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"📟 Setup Test\", \"description\": \"Discord connectivity verified.\", \"color\": 1752220}]}" "$D_URL" > /dev/null
    printf "${BOLD}❓ Received Discord notification? [y/n]: ${NC}"
    read -r d_confirm </dev/tty
    [ "$d_confirm" != "y" ] && [ "$d_confirm" != "Y" ] && { echo -e "${RED}❌ Aborted.${NC}"; exit 1; }
fi

if [ "$notify_choice" = "2" ] || [ "$notify_choice" = "3" ]; then
    T_EN="YES"
    printf "${BOLD}🤖 Enter Telegram Bot Token: ${NC}"
    read -r T_TOK </dev/tty
    printf "${BOLD}🆔 Enter Telegram Chat ID: ${NC}"
    read -r T_ID </dev/tty
    
    # Test Telegram
    echo -e "${CYAN}🧪 Sending Telegram test notification...${NC}"
    curl -s "https://api.telegram.org/bot$T_TOK/sendMessage?chat_id=$T_ID&text=📟%20Setup%20Test:%20Telegram%20connectivity%20verified." > /dev/null
    printf "${BOLD}❓ Received Telegram notification? [y/n]: ${NC}"
    read -r t_confirm </dev/tty
    [ "$t_confirm" != "y" ] && [ "$t_confirm" != "Y" ] && { echo -e "${RED}❌ Aborted.${NC}"; exit 1; }
fi

# --- 4. ENCRYPTION VAULT CREATION ---
HW_KEY=$(get_hw_key)
echo "D_URL='$D_URL'
D_ID='$D_ID'
T_TOK='$T_TOK'
T_ID='$T_ID'" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -k "$HW_KEY" -out "$VAULT_FILE"

# --- 5. GENERATE NWDA_SETTINGS.CONF ---
cat <<EOF > "$CONFIG_FILE"
# nwda_settings.conf - Configuration for netwatchda
# Note: Discord/Telegram tokens are stored encrypted in .vault.enc

[Log settings]
UPTIME_LOG_MAX_SIZE=51200 # Max log file size in bytes for uptime tracking. Default is 51200.
PING_LOG_ENABLE="NO" # Enable or disable detailed ping logging (YES/NO). Default is NO.

[Discord Settings]
DISCORD_ENABLE="$D_EN" # Global toggle for Discord notifications (YES/NO). Default is NO.
SILENT_ENABLE="NO" # Mutes Discord alerts during specific hours (YES/NO). Default is NO.
SILENT_START=23 # Hour to start silent mode (0-23). Default is 23.
SILENT_END=07 # Hour to end silent mode (0-23). Default is 07.

[TELEGRAM Settings]
TELEGRAM_ENABLE="$T_EN" # Global toggle for Telegram notifications (YES/NO). Default is NO.

[Monitoring Settings]
CPU_GUARD_THRESHOLD=2.0 # Max CPU load average allowed before skipping pings. Default is 2.0.
RAM_GUARD_MIN_FREE=4096 # Minimum free RAM in KB required to run alerts. Default is 4096.
HEARTBEAT="NO" # Periodic "I am alive" notification (YES/NO). Default is NO.
HB_INTERVAL=86400 # Seconds between heartbeat messages. Default is 86400.
HB_MENTION="NO" # Ping User ID in heartbeat messages (YES/NO). Default is NO.

[Internet Connectivity]
EXT_ENABLE="YES" # Global toggle for internet monitoring (YES/NO). Default is YES.
EXT_IP="1.1.1.1" # Primary external IP to monitor. Default is 1.1.1.1.
EXT_IP2="8.8.8.8" # Secondary external IP for redundancy. Default is 8.8.8.8.
EXT_SCAN_INTERVAL=60 # Seconds between internet checks. Default is 60.
EXT_FAIL_THRESHOLD=1 # Failed cycles before internet alert. Default is 1.
EXT_PING_COUNT=4 # Number of packets per internet check. Default is 4.
EXT_PING_TIMEOUT=1 # Seconds to wait for ping response. Default is 1.

[Local Device Monitoring]
DEVICE_MONITOR="YES" # Enable monitoring of local IPs (YES/NO). Default is YES.
DEV_SCAN_INTERVAL=10 # Seconds between local device checks. Default is 10.
DEV_FAIL_THRESHOLD=3 # Failed cycles before device alert. Default is 3.
DEV_PING_COUNT=4 # Number of packets per device check. Default is 4.
EOF

# Initial IP List
LOCAL_IP=$(uci -q get network.lan.ipaddr || ip addr show br-lan | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 | awk '{print $2}')
echo "# Format: IP_ADDRESS @ NAME" > "$IP_LIST_FILE"
[ -n "$LOCAL_IP" ] && echo "$LOCAL_IP @ Router Gateway" >> "$IP_LIST_FILE"

# --- 6. CORE ENGINE GENERATION (nwda.sh) ---
cat <<'EOF' > "$INSTALL_DIR/nwda.sh"
#!/bin/sh
# netwatchda - Network Monitoring Logic Engine

BASE_DIR="/root/netwatchda"
LOG_DIR="/tmp/netwatchda"
CONFIG_FILE="$BASE_DIR/nwda_settings.conf"
IP_LIST_FILE="$BASE_DIR/nwda_ips.conf"
UPTIME_LOG="$LOG_DIR/nwda_uptime.log"
PING_LOG="$LOG_DIR/nwda_ping.log"
SILENT_BUFFER="$LOG_DIR/nwda_silent_buffer"

mkdir -p "$LOG_DIR"
[ ! -f "$UPTIME_LOG" ] && touch "$UPTIME_LOG"
[ ! -f "$PING_LOG" ] && touch "$PING_LOG"

load_config() {
    eval "$(sed '/^\[.*\]/d; s/[[:space:]]*#.*//' "$CONFIG_FILE" | sed 's/=/="/;s/$/"/')"
}

send_notif() {
    TITLE="$1"; MSG="$2"; COLOR="$3"
    NOW_HUMAN=$(date '+%b %d %H:%M:%S')
    
    # Discord Notification
    if [ "$DISCORD_ENABLE" = "YES" ] && [ -n "$D_URL" ]; then
        D_BODY="{\"embeds\": [{\"title\": \"$TITLE\", \"description\": \"$MSG\n**Time:** $NOW_HUMAN\", \"color\": $COLOR}]}"
        curl -s -H "Content-Type: application/json" -X POST -d "$D_BODY" "$D_URL" > /dev/null 2>&1
    fi
    
    # Telegram Notification
    if [ "$TELEGRAM_ENABLE" = "YES" ] && [ -n "$T_TOK" ]; then
        T_TEXT="📟 <b>$TITLE</b>\n$MSG\n<b>Time:</b> $NOW_HUMAN"
        curl -s "https://api.telegram.org/bot$T_TOK/sendMessage?chat_id=$T_ID&parse_mode=HTML&text=$(echo -e "$T_TEXT" | sed 's/ /%20/g; s/\\n/%0A/g')" > /dev/null 2>&1
    fi
}

LAST_EXT_CHECK=0; LAST_DEV_CHECK=0; LAST_HB_CHECK=$(date +%s)

while true; do
    load_config
    NOW_SEC=$(date +%s)
    CUR_HOUR=$(date +%H)
    NOW_HUMAN=$(date '+%b %d %H:%M:%S')

    # CPU & RAM Guards
    CUR_LOAD=$(awk '{print $1}' /proc/loadavg)
    FREE_MEM=$(free | grep Mem | awk '{print $4}')
    if [ "$(echo "$CUR_LOAD > $CPU_GUARD_THRESHOLD" | bc)" -eq 1 ] || [ "$FREE_MEM" -lt "$RAM_GUARD_MIN_FREE" ]; then
        echo "$NOW_HUMAN - [GUARD] System load high ($CUR_LOAD) or RAM low ($FREE_MEM KB). Skipping cycle." >> "$UPTIME_LOG"
        sleep 5
        continue
    fi

    # Silent Mode Check
    IS_SILENT=0
    if [ "$SILENT_ENABLE" = "YES" ]; then
        if [ "$SILENT_START" -gt "$SILENT_END" ]; then
            [ "$CUR_HOUR" -ge "$SILENT_START" ] || [ "$CUR_HOUR" -lt "$SILENT_END" ] && IS_SILENT=1
        else
            [ "$CUR_HOUR" -ge "$SILENT_START" ] && [ "$CUR_HOUR" -lt "$SILENT_END" ] && IS_SILENT=1
        fi
    fi

    # Internet Monitoring Logic
    if [ "$EXT_ENABLE" = "YES" ] && [ $((NOW_SEC - LAST_EXT_CHECK)) -ge "$EXT_SCAN_INTERVAL" ]; then
        LAST_EXT_CHECK=$NOW_SEC
        EXT_UP=0
        ping -q -c "$EXT_PING_COUNT" -W "$EXT_PING_TIMEOUT" "$EXT_IP" > /dev/null 2>&1 && EXT_UP=1
        [ "$EXT_UP" -eq 0 ] && ping -q -c "$EXT_PING_COUNT" -W "$EXT_PING_TIMEOUT" "$EXT_IP2" > /dev/null 2>&1 && EXT_UP=1
        
        # Ping Logging
        if [ "$PING_LOG_ENABLE" = "YES" ]; then
            [ "$EXT_UP" -eq 1 ] && STAT="UP" || STAT="DOWN"
            echo "$NOW_HUMAN - INTERNET_CHECK: $STAT" >> "$PING_LOG"
        fi

        FD="/tmp/nwda_ext_d"; FT="/tmp/nwda_ext_t"; FC="/tmp/nwda_ext_c"
        if [ "$EXT_UP" -eq 0 ]; then
            C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
            if [ "$C" -ge "$EXT_FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                echo "$NOW_SEC" > "$FD"; echo "$NOW_HUMAN" > "$FT"
                echo "$NOW_HUMAN - [ALERT] INTERNET DOWN" >> "$UPTIME_LOG"
                [ "$IS_SILENT" -eq 0 ] && send_notif "🔴 Internet Down" "Internet connectivity lost." 15548997
            fi
        else
            if [ -f "$FD" ]; then
                START_TIME=$(cat "$FT"); START_SEC=$(cat "$FD"); DUR=$((NOW_SEC - START_SEC))
                DR_STR="$((DUR/60))m $((DUR%60))s"
                echo "$NOW_HUMAN - [SUCCESS] INTERNET UP (Down $DR_STR)" >> "$UPTIME_LOG"
                [ "$IS_SILENT" -eq 0 ] && send_notif "🟢 Internet Restored" "Connectivity restored.\n**Total Outage:** $DR_STR" 3066993
                rm -f "$FD" "$FT"
            fi
            echo 0 > "$FC"
        fi
    fi

    # Local Device Monitoring Logic (Backgrounded)
    if [ "$DEVICE_MONITOR" = "YES" ] && [ $((NOW_SEC - LAST_DEV_CHECK)) -ge "$DEV_SCAN_INTERVAL" ]; then
        LAST_DEV_CHECK=$NOW_SEC
        sed -e '/^#/d' -e '/^$/d' "$IP_LIST_FILE" | while read -r line; do
            TIP=$(echo "$line" | cut -d'@' -f1 | tr -d ' ')
            NAME=$(echo "$line" | cut -d'@' -f2- | sed 's/^[ \t]*//')
            [ -z "$TIP" ] && continue
            
            ( # Subshell for Background Ping
                ping -q -c "$DEV_PING_COUNT" -W 1 "$TIP" > /dev/null 2>&1
                RESULT=$?
                SIP=$(echo "$TIP" | tr '.' '_')
                FC="/tmp/nwda_c_$SIP"; FD="/tmp/nwda_d_$SIP"; FT="/tmp/nwda_t_$SIP"
                
                if [ "$PING_LOG_ENABLE" = "YES" ]; then
                    [ $RESULT -eq 0 ] && S="UP" || S="DOWN"
                    echo "$(date '+%b %d %H:%M:%S') - DEVICE - $NAME - $TIP: $S" >> "$PING_LOG"
                fi

                if [ $RESULT -eq 0 ]; then
                    if [ -f "$FD" ]; then
                        DSTART=$(cat "$FT"); DSSEC=$(cat "$FD"); DUR=$(( $(date +%s) - DSSEC ))
                        DR_STR="$((DUR/60))m $((DUR%60))s"
                        echo "$(date '+%b %d %H:%M:%S') - [SUCCESS] Device: $NAME Online (Down $DR_STR)" >> "$UPTIME_LOG"
                        send_notif "🟢 Device Online" "**$NAME** ($TIP) is back online.\n**Outage:** $DR_STR" 3066993
                        rm -f "$FD" "$FT"
                    fi
                    echo 0 > "$FC"
                else
                    C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
                    if [ "$C" -ge "$DEV_FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                        echo "$(date +%s)" > "$FD"; echo "$(date '+%b %d %H:%M:%S')" > "$FT"
                        echo "$(date '+%b %d %H:%M:%S') - [ALERT] Device: $NAME Down" >> "$UPTIME_LOG"
                        send_notif "🔴 Device Down" "**$NAME** ($TIP) is offline." 15548997
                    fi
                fi
            ) & 
        done
    fi

    # Log Rotation Checks
    for log in "$UPTIME_LOG" "$PING_LOG"; do
        if [ -f "$log" ] && [ $(wc -c < "$log") -gt "$UPTIME_LOG_MAX_SIZE" ]; then
            echo "$NOW_HUMAN - [SYSTEM] Log rotated." > "$log"
        fi
    done

    sleep 1
done
EOF

chmod +x "$INSTALL_DIR/nwda.sh"

# --- 7. SERVICE SCRIPT GENERATION (/etc/init.d/netwatchda) ---
cat <<EOF > "$SERVICE_PATH"
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

get_hw_key() {
    CPU_ID=\$(grep -m1 "serial" /proc/cpuinfo | awk '{print \$3}')
    [ -z "\$CPU_ID" ] && CPU_ID=\$(cat /sys/class/net/eth0/address 2>/dev/null || echo "NWDA_DEFAULT_ID")
    SEED=\$(cat "$SEED_FILE")
    echo "\${CPU_ID}\${SEED}" | sha256sum | awk '{print \$1}'
}

extra_command "status" "Check if monitor is running"
extra_command "logs" "View last 20 log entries"
extra_command "clear" "Clear the log files"
extra_command "discord" "Test discord notification"
extra_command "telegram" "Test telegram notification"
extra_command "credentials" "Change stored credentials"
extra_command "purge" "Interactive smart uninstaller"
extra_command "help" "Display help information"

start_service() {
    HW_KEY=\$(get_hw_key)
    # Decrypt credentials into memory directly
    eval "\$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -k "\$HW_KEY" -in "$VAULT_FILE" 2>/dev/null)"
    
    procd_open_instance
    procd_set_param command /bin/sh "$INSTALL_DIR/nwda.sh"
    procd_set_param env D_URL="\$D_URL" D_ID="\$D_ID" T_TOK="\$T_TOK" T_ID="\$T_ID"
    procd_set_param respawn
    procd_close_instance
}

status() {
    pgrep -f "nwda.sh" > /dev/null && echo "netwatchda is RUNNING." || echo "netwatchda is STOPPED."
}

logs() {
    echo -e "--- Uptime Log ---"
    [ -f "$UPTIME_LOG" ] && tail -n 20 "$UPTIME_LOG"
    echo -e "\n--- Ping Log ---"
    [ -f "$PING_LOG" ] && tail -n 20 "$PING_LOG"
}

clear() {
    > "$UPTIME_LOG"
    > "$PING_LOG"
    echo "Logs cleared."
}

credentials() {
    # Logic to change credentials and re-encrypt
    /bin/sh "$SCRIPT_NAME" # Re-runs the installer logic for creds
}

help() {
    echo "netwatchda - Management Commands"
    echo "-------------------------------"
    echo "start   : Start the service"
    echo "stop    : Stop the service"
    echo "restart : Apply configuration changes"
    echo "status  : Check running state"
    echo "logs    : View recent activity"
    echo "clear   : Wipe RAM logs"
    echo "purge   : Uninstall the application"
}

purge() {
    printf "❓ Are you sure you want to uninstall? [y/n]: "
    read -r p_confirm </dev/tty
    if [ "\$p_confirm" = "y" ]; then
        /etc/init.d/netwatchda stop
        rm -rf "$INSTALL_DIR"
        rm -f "$SERVICE_PATH"
        echo "✅ netwatchda removed."
    fi
}
EOF

chmod +x "$SERVICE_PATH"
/etc/init.d/netwatchda enable
/etc/init.d/netwatchda restart

# --- 8. SUCCESS NOTIFICATION ---
# Decrypt for final success message
HW_KEY=$(get_hw_key)
eval "$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -k "$HW_KEY" -in "$VAULT_FILE" 2>/dev/null)"
NOW_FINAL=$(date '+%b %d, %Y %H:%M:%S')
ROUTER_NAME=$(uci -q get system.@system[0].hostname || echo "OpenWrt")

[ "$DISCORD_ENABLE" = "YES" ] && curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"🚀 Service Started\", \"description\": \"**Router:** $ROUTER_NAME\nMonitoring is active.\", \"color\": 1752220}]}" "$D_URL" > /dev/null
[ "$TELEGRAM_ENABLE" = "YES" ] && curl -s "https://api.telegram.org/bot$T_TOK/sendMessage?chat_id=$T_ID&text=🚀%20Service%20Started%20on%20$ROUTER_NAME" > /dev/null

# --- FINAL OUTPUT ---
echo ""
echo -e "${GREEN}=======================================================${NC}"
echo -e "${BOLD}${GREEN}✅ Installation complete!${NC}"
echo -e "${CYAN}📂 Folder:${NC} $INSTALL_DIR"
echo -e "${GREEN}=======================================================${NC}"
echo -e "\n${BOLD}Quick Commands:${NC}"
echo -e "  View Logs       : ${CYAN}/etc/init.d/netwatchda logs${NC}"
echo -e "  Uninstall       : ${RED}/etc/init.d/netwatchda purge${NC}"
echo -e "  Settings        : ${CYAN}vi $CONFIG_FILE${NC}"
echo -e "  Restart         : ${YELLOW}/etc/init.d/netwatchda restart${NC}"
echo ""
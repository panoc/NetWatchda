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
RED='\033[1;31m'    # Light Red
GREEN='\033[1;32m'  # Light Green
BLUE='\033[1;34m'   # Light Blue (Vibrant)
CYAN='\033[1;36m'   # Light Cyan (Vibrant)
YELLOW='\033[1;33m' # Bold Yellow

# --- INITIAL HEADER ---
echo -e "${BLUE}=======================================================${NC}"
echo -e "${BOLD}${CYAN}🚀 netwatchda Automated Setup${NC} (by ${BOLD}panoc${NC})"
echo -e "${BLUE}⚖️  License: GNU GPLv3${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo ""

# --- 0. PRE-INSTALLATION CONFIRMATION ---
printf "${BOLD}❓ This will begin the installation process. Continue? [y/n]: ${NC}"
read start_confirm </dev/tty
if [ "$start_confirm" != "y" ] && [ "$start_confirm" != "Y" ]; then
    echo -e "${RED}❌ Installation aborted by user. Cleaning up...${NC}"
    exit 0
fi

INSTALL_DIR="/root/netwatchda"
CONFIG_FILE="$INSTALL_DIR/netwatchda_settings.conf"
IP_LIST_FILE="$INSTALL_DIR/netwatchda_ips.conf"
SERVICE_NAME="netwatchda"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"
LOGFILE="/tmp/netwatchda_log.txt"

# --- 1. CHECK DEPENDENCIES & STORAGE ---
echo -e "\n${BOLD}📦 Checking system readiness...${NC}"

FREE_FLASH_KB=$(df / | awk 'NR==2 {print $4}')
MIN_FLASH_KB=3072 
FREE_RAM_KB=$(df /tmp | awk 'NR==2 {print $4}')
MIN_RAM_KB=512 
DEFAULT_MAX_LOG=512000 

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${CYAN}🔍 curl not found. Checking flash storage...${NC}"
    if [ "$FREE_FLASH_KB" -lt "$MIN_FLASH_KB" ]; then
        echo -e "${RED}❌ ERROR: Insufficient Flash storage!${NC}"
        exit 1
    else
        echo -e "${YELLOW}📥 Installing curl and ca-bundle...${NC}"
        opkg update && opkg install curl ca-bundle
    fi
fi

if [ "$FREE_RAM_KB" -lt "$MIN_RAM_KB" ]; then
    echo -e "${YELLOW}⚠️  Low RAM detected. Scaling logs to 64KB.${NC}"
    DEFAULT_MAX_LOG=65536 
fi

# --- 2. SMART UPGRADE / INSTALL CHECK ---
KEEP_CONFIG=0
if [ -f "$CONFIG_FILE" ]; then
    echo -e "\n${YELLOW}⚠️  Existing installation found.${NC}"
    echo -e "${BOLD}1.${NC} Keep settings (Upgrade)"
    echo -e "${BOLD}2.${NC} Clean install"
    printf "${BOLD}Enter choice [1-2]: ${NC}"
    read choice </dev/tty
    
    if [ "$choice" = "1" ]; then
        echo -e "${CYAN}🔧 Scanning for missing configuration lines...${NC}"
        
        add_if_missing() {
            if ! grep -q "^$1=" "$CONFIG_FILE"; then
                echo "$1=$2 $3" >> "$CONFIG_FILE"
                echo -e "  ${GREEN}➕ Added missing line:${NC} $1"
            fi
        }

        add_if_missing "ROUTER_NAME" "\"My_OpenWrt_Router\"" "# Name that appears in Discord notifications."
        add_if_missing "DISCORD_URL" "\"\"" "# Your Discord Webhook URL."
        add_if_missing "MY_ID" "\"\"" "# Your Discord User ID (for @mentions)."
        add_if_missing "SCAN_INTERVAL" "10" "# Seconds between pings. Default is 10."
        add_if_missing "FAIL_THRESHOLD" "3" "# Number of failed pings before sending an alert. Default is 3."
        add_if_missing "MAX_SIZE" "$DEFAULT_MAX_LOG" "# Max log file size in bytes for the log rotation."
        add_if_missing "HEARTBEAT" "\"OFF\"" "# Set to ON to receive a periodic check-in message."
        add_if_missing "HB_INTERVAL" "86400" "# Interval in seconds. Default is 86400"
        add_if_missing "HB_MENTION" "\"OFF\"" "# Set to ON to include @mention in heartbeats."
        add_if_missing "EXT_PING_COUNT" "4" "# Number of pings per internet check interval. Default 4."
        add_if_missing "DEV_PING_COUNT" "4" "# Number of pings per device check interval. Default 4."
        add_if_missing "EXT_IP" "\"1.1.1.1\"" "# External IP to ping. Leave empty to disable."
        add_if_missing "EXT_INTERVAL" "60" "# Seconds between internet checks. Default is 60."
        add_if_missing "DEVICE_MONITOR" "\"ON\"" "# Set to ON to enable local IP monitoring."

        echo -e "${GREEN}✅ Configuration patch complete.${NC}"
        KEEP_CONFIG=1
    else
        echo -e "${RED}🧹 Performing clean install...${NC}"
        /etc/init.d/netwatchda stop 2>/dev/null
        rm -rf "$INSTALL_DIR"
    fi
fi

mkdir -p "$INSTALL_DIR"

# --- 3. CLEAN INSTALL INPUTS ---
if [ "$KEEP_CONFIG" -eq 0 ]; then
    echo -e "\n${BLUE}--- Configuration ---${NC}"
    printf "${BOLD}🔗 Enter Discord Webhook URL: ${NC}"; read user_webhook </dev/tty
    printf "${BOLD}👤 Enter Discord User ID: ${NC}"; read user_id </dev/tty
    printf "${BOLD}🏷️  Enter Router Name: ${NC}"; read router_name_input </dev/tty
    
    echo -e "\n${BLUE}--- Heartbeat Settings ---${NC}"
    printf "${BOLD}💓 Enable Heartbeat? [y/n]: ${NC}"; read hb_enabled </dev/tty
    if [ "$hb_enabled" = "y" ] || [ "$hb_enabled" = "Y" ]; then
        HB_VAL="ON"
        printf "${BOLD}⏰ Interval in HOURS: ${NC}"; read hb_hours </dev/tty
        HB_SEC=$((hb_hours * 3600))
        printf "${BOLD}🔔 Mention in Heartbeat? [y/n]: ${NC}"; read hb_m </dev/tty
        [ "$hb_m" = "y" ] || [ "$hb_m" = "Y" ] && HB_MENTION="ON" || HB_MENTION="OFF"
    else
        HB_VAL="OFF"; HB_SEC="86400"; HB_MENTION="OFF"
    fi

    echo -e "\n${BLUE}--- Monitoring Mode ---${NC}"
    echo "1. Both | 2. Devices Only | 3. Internet Only"
    printf "${BOLD}Enter choice [1-3]: ${NC}"; read mode_choice </dev/tty
    case "$mode_choice" in
        2) EXT_VAL=""; DEV_VAL="ON" ;;
        3) EXT_VAL="1.1.1.1"; DEV_VAL="OFF" ;;
        *) EXT_VAL="1.1.1.1"; DEV_VAL="ON" ;;
    esac

# --- BASE CODE (DO NOT CHANGE) ---
DEV_COUNT=4 # Number of pings to send to devices
EXT_COUNT=4 # Number of pings to send to external sites
# --- END BASE CODE ---

    cat <<EOF > "$CONFIG_FILE"
[Router Identification]
ROUTER_NAME="$router_name_input" # Name that appears in Discord notifications.

[Discord Settings]
DISCORD_URL="$user_webhook" # Your Discord Webhook URL.
MY_ID="$user_id" # Your Discord User ID (for @mentions).

[Monitoring Settings]
SCAN_INTERVAL=10 # Seconds between pings. Default is 10.
FAIL_THRESHOLD=3 # Number of failed pings before sending an alert. Default is 3.
MAX_SIZE=$DEFAULT_MAX_LOG # Max log file size in bytes for the log rotation.

[Heartbeat Settings]
HEARTBEAT="$HB_VAL" # Set to ON to receive a periodic check-in message.
HB_INTERVAL=$HB_SEC # Interval in seconds. Default is 86400
HB_MENTION="$HB_MENTION" # Set to ON to include @mention in heartbeats.

[Internet Connectivity]
EXT_PING_COUNT=$EXT_COUNT # Number of pings per internet check interval. Default 4.
EXT_IP="$EXT_VAL" # External IP to ping. Leave empty to disable.
EXT_INTERVAL=60 # Seconds between internet checks. Default is 60.

[Local Device Monitoring]
DEVICE_MONITOR="$DEV_VAL" # Set to ON to enable local IP monitoring.
DEV_PING_COUNT=$DEV_COUNT # Number of pings per device check interval. Default 4.
EOF

    cat <<EOF > "$IP_LIST_FILE"
# Format: IP_ADDRESS # NAME
EOF
    LOCAL_IP=$(uci -q get network.lan.ipaddr || ip addr show br-lan | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 | awk '{print $2}')
    [ -n "$LOCAL_IP" ] && echo "$LOCAL_IP # Router Gateway" >> "$IP_LIST_FILE"
fi

# --- 4. INITIAL LOG ---
echo "$(date '+%b %d, %Y %H:%M:%S') - [SYSTEM] netwatchda installation successful." > "$LOGFILE"

# --- 5. CORE SCRIPT GENERATION ---
echo -e "\n${CYAN}🛠️  Generating core script...${NC}"
cat <<'EOF' > "$INSTALL_DIR/netwatchda.sh"
#!/bin/sh
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
IP_LIST_FILE="$BASE_DIR/netwatchda_ips.conf"
CONFIG_FILE="$BASE_DIR/netwatchda_settings.conf"
LOGFILE="/tmp/netwatchda_log.txt"
LAST_EXT_CHECK=0
LAST_HB_CHECK=$(date +%s)

while true; do
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
    NOW_HUMAN=$(date '+%b %d, %Y %H:%M:%S')
    NOW_SEC=$(date +%s)

    # Log Rotation
    if [ -f "$LOGFILE" ] && [ $(wc -c < "$LOGFILE") -gt "$MAX_SIZE" ]; then
        echo "$NOW_HUMAN - [SYSTEM] Log rotated." > "$LOGFILE"
    fi

    PREFIX="📟 **Router:** $ROUTER_NAME\n"
    MENTION="\n🔔 **Attention:** <@$MY_ID>"
    IS_INT_DOWN=0

    # Heartbeat
    if [ "$HEARTBEAT" = "ON" ] && [ $((NOW_SEC - LAST_HB_CHECK)) -ge "$HB_INTERVAL" ]; then
        LAST_HB_CHECK=$NOW_SEC
        DESC="💓 **Heartbeat**: Online at $NOW_HUMAN"
        [ "$HB_MENTION" = "ON" ] && DESC="$DESC$MENTION"
        curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"description\": \"$DESC\", \"color\": 15844367}]}" "$DISCORD_URL" > /dev/null 2>&1
    fi

    # Internet Check
    if [ -n "$EXT_IP" ] && [ $((NOW_SEC - LAST_EXT_CHECK)) -ge "$EXT_INTERVAL" ]; then
        LAST_EXT_CHECK=$NOW_SEC
        if ! ping -q -c "$EXT_PING_COUNT" -W 2 "$EXT_IP" > /dev/null 2>&1; then
            if [ ! -f "/tmp/nwda_ext_d" ]; then
                echo "$NOW_SEC" > "/tmp/nwda_ext_d"; echo "$NOW_HUMAN" > "/tmp/nwda_ext_t"
                echo "$NOW_HUMAN - [ALERT] INTERNET DOWN" >> "$LOGFILE"
            fi
        else
            if [ -f "/tmp/nwda_ext_d" ]; then
                S=$(cat "/tmp/nwda_ext_d"); T=$(cat "/tmp/nwda_ext_t"); D=$((NOW_SEC-S)); DR="$(($D/60))m $(($D%60))s"
                echo "$NOW_HUMAN - [SUCCESS] INTERNET UP (Down for $DR)" >> "$LOGFILE"
                curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"🌐 Internet Restored\", \"description\": \"$PREFIX❌ **Lost:** $T\n✅ **Restored:** $NOW_HUMAN\n**Outage:** $DR$MENTION\", \"color\": 1752220}]}" "$DISCORD_URL" > /dev/null 2>&1
                rm -f "/tmp/nwda_ext_d" "/tmp/nwda_ext_t"
            fi
        fi
    fi
    [ -f "/tmp/nwda_ext_d" ] && IS_INT_DOWN=1

    # Device Check
    if [ "$DEVICE_MONITOR" = "ON" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in ""|\#*) continue ;; esac
            TIP=$(echo "$line" | cut -d'#' -f1 | xargs); NAME=$(echo "$line" | cut -s -d'#' -f2- | xargs)
            SIP=$(echo "$TIP" | tr '.' '_'); FC="/tmp/nwda_c_$SIP"; FD="/tmp/nwda_d_$SIP"
            if ping -q -c "$DEV_PING_COUNT" -W 2 "$TIP" > /dev/null 2>&1; then
                if [ -f "$FD" ]; then
                    echo "$NOW_HUMAN - [SUCCESS] DEVICE UP: $NAME" >> "$LOGFILE"
                    [ "$IS_INT_DOWN" -eq 0 ] && curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"✅ Device ONLINE\", \"description\": \"$PREFIX**$NAME** back online.\", \"color\": 3066993}]}" "$DISCORD_URL" > /dev/null 2>&1
                    rm -f "$FD"
                fi
                echo 0 > "$FC"
            else
                C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
                if [ "$C" -eq "$FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                    echo 1 > "$FD"; echo "$NOW_HUMAN" - [ALERT] DEVICE DOWN: $NAME >> "$LOGFILE"
                    [ "$IS_INT_DOWN" -eq 0 ] && curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"🔴 Device DOWN!\", \"description\": \"$PREFIX**$NAME** unreachable.\", \"color\": 15158332}]}" "$DISCORD_URL" > /dev/null 2>&1
                fi
            fi
        done < "$IP_LIST_FILE"
    fi
    sleep "$SCAN_INTERVAL"
done
EOF

# --- 6. SERVICE SETUP ---
chmod +x "$INSTALL_DIR/netwatchda.sh"
cat <<EOF > "$SERVICE_PATH"
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
extra_command "logs" "View last 20 log entries"
start_service() {
    procd_open_instance
    procd_set_param command /bin/sh "$INSTALL_DIR/netwatchda.sh"
    procd_set_param respawn
    procd_close_instance
}
logs() { [ -f "$LOGFILE" ] && tail -n 20 "$LOGFILE" || echo "No log found."; }
EOF
chmod +x "$SERVICE_PATH"
"$SERVICE_PATH" enable
"$SERVICE_PATH" restart

echo -e "\n${GREEN}=======================================================${NC}"
echo -e "${BOLD}${GREEN}✅ Installation complete!${NC}"
echo -e "${CYAN}📂 Settings:${NC} $CONFIG_FILE"
echo -e "${CYAN}📂 IP List: ${NC} $IP_LIST_FILE"
echo -e "${GREEN}=======================================================${NC}\n"
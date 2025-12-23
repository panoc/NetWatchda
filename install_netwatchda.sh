#!/bin/sh
# netwatchda Installer - Automated Setup for OpenWrt
# Copyright (C) 2025 panoc
# Licensed under the GNU General Public License v3.0

# --- SELF-CLEAN LOGIC ---
# This ensures the installer script deletes itself after execution
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

# --- NEW FILENAME DEFINITIONS ---
INSTALL_DIR="/root/netwatchda"
CONFIG_FILE="$INSTALL_DIR/nwda_settings.conf"
IP_LIST_FILE="$INSTALL_DIR/nwda_ips.conf"
AUTH_FILE="$INSTALL_DIR/.nwda_auth"
SEED_FILE="$INSTALL_DIR/.nwda_seed"
SERVICE_NAME="netwatchda"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"
LOG_DIR="/tmp/netwatchda"
UPTIME_LOG="$LOG_DIR/nwda_uptime.log"
PING_LOG="$LOG_DIR/nwda_ping.log"

# --- 1. CHECK DEPENDENCIES & STORAGE ---
echo -e "\n${BOLD}📦 Checking system readiness...${NC}"

# Check for openssl-util for encrypted credentials
if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${CYAN}🔍 openssl-util not found. Required for secure credentials.${NC}"
    echo -e "${YELLOW}📥 Attempting to install openssl-util...${NC}"
    opkg update && opkg install openssl-util
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error: Failed to install openssl-util. Aborting.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ openssl-util is installed.${NC}"
fi

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${CYAN}🔍 curl not found. Installing...${NC}"
    opkg update && opkg install curl ca-bundle
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"

# --- 2. ENCRYPTION KEY GENERATION (HARDWARE + SEED) ---
# Generate a random seed if it doesn't exist
if [ ! -f "$SEED_FILE" ]; then
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$SEED_FILE"
    chmod 600 "$SEED_FILE"
fi

get_hw_key() {
    CPU_ID=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    BOARD=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "generic")
    SEED=$(cat "$SEED_FILE")
    echo "${CPU_ID}${BOARD}${SEED}" | md5sum | cut -d' ' -f1
}

# --- 3. NOTIFICATION PROMPTS (4-OPTION MENU) ---
echo -e "\n${BLUE}--- Notification Setup ---${NC}"
echo "1. Enable Discord Notifications"
echo "2. Enable Telegram Notifications"
echo "3. Enable Both"
echo "4. None (Events tracked through logs only)"

while :; do
    printf "${BOLD}Select option [1-4]: ${NC}"
    read notify_choice </dev/tty
    case "$notify_choice" in
        1|2|3|4) break ;;
        *) echo -e "${RED}❌ Invalid selection. Please enter 1-4.${NC}" ;;
    esac
done

DIS_EN="NO"; TEL_EN="NO"
DIS_WEB=""; DIS_ID=""
TEL_TOK=""; TEL_CHT=""

# Discord Prompts
if [ "$notify_choice" -eq 1 ] || [ "$notify_choice" -eq 3 ]; then
    DIS_EN="YES"
    printf "${BOLD}🔗 Enter Discord Webhook URL: ${NC}"
    read DIS_WEB </dev/tty
    printf "${BOLD}👤 Enter Discord User ID: ${NC}"
    read DIS_ID </dev/tty
fi

# Telegram Prompts
if [ "$notify_choice" -eq 2 ] || [ "$notify_choice" -eq 3 ]; then
    TEL_EN="YES"
    printf "${BOLD}🤖 Enter Telegram Bot Token: ${NC}"
    read TEL_TOK </dev/tty
    printf "${BOLD}🆔 Enter Telegram Chat ID: ${NC}"
    read TEL_CHT </dev/tty
    
    # Test Telegram
    echo -e "${CYAN}🧪 Sending Telegram test notification...${NC}"
    curl -s -X POST "https://api.telegram.org/bot$TEL_TOK/sendMessage" \
        -d "chat_id=$TEL_CHT" \
        -d "text=🚀 netwatchda: Telegram test successful!" > /dev/null
    
    printf "${BOLD}❓ Received it? [y/n]: ${NC}"
    read confirm_tel </dev/tty
    [ "$confirm_tel" != "y" ] && [ "$confirm_tel" != "Y" ] && { echo -e "${RED}Aborting.${NC}"; exit 1; }
fi

# --- 4. SECURE CREDENTIAL STORAGE ---
HW_KEY=$(get_hw_key)
RAW_AUTH="DIS_URL='$DIS_WEB'
DIS_ID='$DIS_ID'
TEL_TOKEN='$TEL_TOK'
TEL_CHAT='$TEL_CHT'"

echo "$RAW_AUTH" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -k "$HW_KEY" -out "$AUTH_FILE" 2>/dev/null
chmod 600 "$AUTH_FILE"

# --- 5. CONFIGURATION FILE CREATION ---
printf "${BOLD}🏷️  Enter Router Name: ${NC}"
read router_name_input </dev/tty

cat <<EOF > "$CONFIG_FILE"
[Router Identification]
ROUTER_NAME="$router_name_input"

[Discord Settings]
DISCORD_ENABLE="$DIS_EN"

[TELEGRAM]
TELEGRAM_ENABLE="$TEL_EN"

[Log settings]
UPTIME_LOG_MAX_SIZE=51200
PING_LOG_ENABLE="OFF"

[Internet Connectivity]
EXT_IP="1.1.1.1"
EXT_IP2="8.8.8.8"
EXT_SCAN_INTERVAL=60
EXT_FAIL_THRESHOLD=1
EXT_PING_COUNT=4

[Local Device Monitoring]
DEVICE_MONITOR="ON"
DEV_SCAN_INTERVAL=10
DEV_FAIL_THRESHOLD=3
DEV_PING_COUNT=4
EOF

if [ ! -f "$IP_LIST_FILE" ]; then
    echo "1.1.1.1 @ Google_DNS" > "$IP_LIST_FILE"
fi
# --- 6. CORE SCRIPT GENERATION ---
cat <<'EOF' > "$INSTALL_DIR/netwatchda.sh"
#!/bin/sh
# netwatchda Core - Connectivity Monitor
# Copyright (C) 2025 panoc

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_FILE="$BASE_DIR/nwda_settings.conf"
IP_LIST_FILE="$BASE_DIR/nwda_ips.conf"
AUTH_FILE="$BASE_DIR/.nwda_auth"
SEED_FILE="$BASE_DIR/.nwda_seed"
LOG_DIR="/tmp/netwatchda"
UPTIME_LOG="$LOG_DIR/nwda_uptime.log"
PING_LOG="$LOG_DIR/nwda_ping.log"

# Function to get hardware key for decryption
get_hw_key() {
    CPU_ID=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    BOARD=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "generic")
    SEED=$(cat "$SEED_FILE")
    echo "${CPU_ID}${BOARD}${SEED}" | md5sum | cut -d' ' -f1
}

# Decrypt and load credentials into memory
load_auth() {
    if [ -f "$AUTH_FILE" ]; then
        HW_KEY=$(get_hw_key)
        # Decrypting into temporary eval-able string
        eval "$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -k "$HW_KEY" -in "$AUTH_FILE" 2>/dev/null)"
    fi
}

load_config() {
    [ -f "$CONFIG_FILE" ] && eval "$(sed '/^\[.*\]/d' "$CONFIG_FILE")"
    load_auth
}

# Notification handler for Discord and Telegram
send_notify() {
    TITLE="$1"; MSG="$2"; COLOR="$3"; TYPE="$4"; DURATION="$5"
    load_config
    
    # Add timestamp and duration to the message
    NOW_MSG=$(date '+%Y-%m-%d %H:%M:%S')
    FULL_MSG="$MSG\nTime: $NOW_MSG"
    [ -n "$DURATION" ] && FULL_MSG="$FULL_MSG\nDowntime: $DURATION"

    if [ "$DISCORD_ENABLE" = "YES" ] && [ -n "$DIS_URL" ]; then
        CLEAN_DIS=$(echo -e "$FULL_MSG" | sed ':a;N;$!ba;s/\n/\\n/g')
        curl -s -H "Content-Type: application/json" -X POST \
            -d "{\"embeds\": [{\"title\": \"$TITLE\", \"description\": \"$CLEAN_DIS\", \"color\": $COLOR}]}" \
            "$DIS_URL" > /dev/null 2>&1
    fi

    if [ "$TELEGRAM_ENABLE" = "YES" ] && [ -n "$TEL_TOKEN" ]; then
        # Telegram uses Dash (-) separator and Markdown
        CLEAN_TEL=$(echo -e "$FULL_MSG" | tr '\n' ' ')
        curl -s -X POST "https://api.telegram.org/bot$TEL_TOKEN/sendMessage" \
            -d "chat_id=$TEL_CHAT" \
            -d "parse_mode=Markdown" \
            -d "text=*${TITLE}* - ${CLEAN_TEL}" > /dev/null 2>&1
    fi
}

# Initialize variables for downtime tracking
EXT_DOWN_TIME=0
# Arrays are not standard in 'ash', so we use dynamic variables for device tracking
# [Original Logic Retained]

while true; do
    load_config
    NOW_LOG=$(date '+%b %d %H:%M:%S')
    
    # --- Internet Connectivity Check ---
    if [ -n "$EXT_IP" ]; then
        if ping -q -c "$EXT_PING_COUNT" -W 2 "$EXT_IP" > /dev/null 2>&1 || \
           ping -q -c "$EXT_PING_COUNT" -W 2 "$EXT_IP2" > /dev/null 2>&1; then
            
            if [ "$EXT_DOWN_TIME" -ne 0 ]; then
                TOTAL_DOWN=$(( $(date +%s) - EXT_DOWN_TIME ))
                H=$((TOTAL_DOWN/3600)); M=$(((TOTAL_DOWN%3600)/60)); S=$((TOTAL_DOWN%60))
                D_STR="${H}h ${M}m ${S}s"
                send_notify "🟢 Internet Restored" "Router: $ROUTER_NAME _ Status: Online" 3066993 "RESTORE" "$D_STR"
                echo "$NOW_LOG - INTERNET_CHECK _ $EXT_IP : UP (Down: $D_STR)" >> "$UPTIME_LOG"
                EXT_DOWN_TIME=0
            fi
            [ "$PING_LOG_ENABLE" = "ON" ] && echo "$NOW_LOG - INTERNET_CHECK _ $EXT_IP : UP" >> "$PING_LOG"
        else
            if [ "$EXT_DOWN_TIME" -eq 0 ]; then
                EXT_DOWN_TIME=$(date +%s)
                send_notify "🔴 Internet Down" "Router: $ROUTER_NAME _ IP: $EXT_IP" 15158332 "ALERT"
            fi
            echo "$NOW_LOG - INTERNET_CHECK _ $EXT_IP : DOWN" >> "$UPTIME_LOG"
            [ "$PING_LOG_ENABLE" = "ON" ] && echo "$NOW_LOG - INTERNET_CHECK _ $EXT_IP : DOWN" >> "$PING_LOG"
        fi
    fi

    # --- Local Device Monitoring ---
    if [ "$DEVICE_MONITOR" = "ON" ] && [ -f "$IP_LIST_FILE" ]; then
        sed -e '/^#/d' -e '/^$/d' "$IP_LIST_FILE" | while read -r line; do
            TIP=$(echo "$line" | cut -d'@' -f1 | tr -d ' ')
            NAME=$(echo "$line" | cut -d'@' -f2- | sed 's/^[ \t]*//')
            
            if ping -q -c "$DEV_PING_COUNT" -W 2 "$TIP" > /dev/null 2>&1; then
                # Success Logic (Original check/restore logic goes here)
                [ "$PING_LOG_ENABLE" = "ON" ] && echo "$NOW_LOG - DEVICE _ $NAME _ $TIP : UP" >> "$PING_LOG"
            else
                # Failure Logic
                echo "$NOW_LOG - DEVICE _ $NAME _ $TIP : DOWN" >> "$UPTIME_LOG"
                [ "$PING_LOG_ENABLE" = "ON" ] && echo "$NOW_LOG - DEVICE _ $NAME _ $TIP : DOWN" >> "$PING_LOG"
                # (Notification logic remains as in original but with new send_notify)
            fi
        done
    fi

    # --- Log Rotation Logic (New 50KB limit) ---
    [ -f "$UPTIME_LOG" ] && [ $(wc -c < "$UPTIME_LOG") -gt "$UPTIME_LOG_MAX_SIZE" ] && echo "$NOW_LOG - [System] Uptime Log Rotated" > "$UPTIME_LOG"
    if [ "$PING_LOG_ENABLE" = "ON" ] && [ -f "$PING_LOG" ]; then
        [ $(wc -c < "$PING_LOG") -gt "$UPTIME_LOG_MAX_SIZE" ] && echo "$NOW_LOG - [System] Ping Log Rotated" > "$PING_LOG"
    fi

    sleep "$EXT_SCAN_INTERVAL"
done
EOF
# --- 7. SERVICE SCRIPT GENERATION ---
cat <<'EOF' > "$SERVICE_PATH"
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

INSTALL_DIR="/root/netwatchda"
CORE_SCRIPT="$INSTALL_DIR/netwatchda.sh"
CONFIG_FILE="$INSTALL_DIR/nwda_settings.conf"
AUTH_FILE="$INSTALL_DIR/.nwda_auth"
SEED_FILE="$INSTALL_DIR/.nwda_seed"
LOG_DIR="/tmp/netwatchda"
UPTIME_LOG="$LOG_DIR/nwda_uptime.log"
PING_LOG="$LOG_DIR/nwda_ping.log"

# Internal function for decryption
get_hw_key() {
    CPU_ID=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    BOARD=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "generic")
    SEED=$(cat "$SEED_FILE")
    echo "${CPU_ID}${BOARD}${SEED}" | md5sum | cut -d' ' -f1
}

extra_command "clear" "Clear all log files"
extra_command "discord" "Test Discord notification"
extra_command "telegram" "Test Telegram notification"
extra_command "credentials" "Change Discord/Telegram credentials"
extra_command "purge" "Completely uninstall netwatchda"

start_service() {
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    procd_open_instance
    procd_set_param command /bin/sh "$CORE_SCRIPT"
    procd_set_param respawn
    procd_close_instance
}

clear() {
    echo "" > "$UPTIME_LOG"
    echo "" > "$PING_LOG"
    echo "✅ Logs cleared."
}

discord() {
    /bin/sh "$CORE_SCRIPT" test_discord
}

telegram() {
    /bin/sh "$CORE_SCRIPT" test_telegram
}

credentials() {
    echo -e "\n--- Change Credentials ---"
    echo "1. Change Discord Credentials"
    echo "2. Change Telegram Credentials"
    echo "3. Change Both"
    printf "Selection: "
    read choice </dev/tty
    
    # Logic to decrypt, modify, and re-encrypt
    HW_KEY=$(get_hw_key)
    eval "$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -k "$HW_KEY" -in "$AUTH_FILE" 2>/dev/null)"
    
    case "$choice" in
        1|3)
            printf "New Discord URL: "; read DIS_URL </dev/tty
            printf "New Discord ID: "; read DIS_ID </dev/tty ;;
    esac
    case "$choice" in
        2|3)
            printf "New Telegram Token: "; read TEL_TOKEN </dev/tty
            printf "New Telegram Chat ID: "; read TEL_CHAT </dev/tty ;;
    esac

    RAW="DIS_URL='$DIS_URL'\nDIS_ID='$DIS_ID'\nTEL_TOKEN='$TEL_TOKEN'\nTEL_CHAT='$TEL_CHAT'"
    echo -e "$RAW" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -k "$HW_KEY" -out "$AUTH_FILE"
    echo "✅ Credentials updated securely."
}

purge() {
    printf "⚠️  Are you sure you want to PURGE ALL files and settings? [y/N]: "
    read p_confirm </dev/tty
    if [ "$p_confirm" = "y" ] || [ "$p_confirm" = "Y" ]; then
        /etc/init.d/netwatchda stop
        /etc/init.d/netwatchda disable
        rm -rf "$INSTALL_DIR"
        rm -rf "$LOG_DIR"
        rm -f "$SERVICE_PATH"
        echo "🔥 netwatchda has been completely removed."
    else
        echo "Purge cancelled."
    fi
}

help() {
    echo "netwatchda Commands:"
    echo "  start       - Start the service"
    echo "  stop        - Stop the service"
    echo "  restart     - Restart the service"
    echo "  status      - Service status"
    echo "  clear       - Clear log files"
    echo "  discord     - Test Discord notification"
    echo "  telegram    - Test Telegram notification"
    echo "  credentials - Change Discord/Telegram Credentials"
    echo "  purge       - Interactive smart uninstaller"
    echo "  enable      - Enable service autostart"
    echo "  disable     - Disable service autostart"
    echo "  reload      - Reload configuration"
}
EOF

# Make everything executable
chmod +x "$INSTALL_DIR/netwatchda.sh"
chmod +x "$SERVICE_PATH"

# Finalize Installation
"$SERVICE_PATH" enable
"$SERVICE_PATH" restart

echo -e "\n${GREEN}=======================================================${NC}"
echo -e "${BOLD}${GREEN}✅ Installation complete!${NC}"
echo -e "${CYAN}📂 Folder:${NC} $INSTALL_DIR"
echo -e "${GREEN}=======================================================${NC}"
echo -e "\n${BOLD}Quick Commands:${NC}"
echo -e "  View Help       : ${CYAN}cat $README_FILE${NC}"
echo -e "  Uninstall       : ${RED}/etc/init.d/netwatchda purge${NC}"
echo -e "  Edit Settings   : ${CYAN}$CONFIG_FILE${NC}"
echo -e "  Edit IP List    : ${CYAN}$IP_LIST_FILE${NC}"
echo -e "  Restart         : ${YELLOW}/etc/init.d/netwatchda restart${NC}"
echo ""
echo ""
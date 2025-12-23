#!/bin/sh
# netwatchda Installer - Automated Setup for OpenWrt
# Copyright (C) 2025 panoc
# Licensed under the GNU General Public License v3.0

# --- SELF-CLEAN LOGIC ---
SCRIPT_NAME="$0"
cleanup() { rm -f "$SCRIPT_NAME"; exit; }
trap cleanup INT TERM EXIT

# --- COLOR DEFINITIONS ---
NC='\033[0m'        
BOLD='\033[1m'
RED='\033[1;31m'    
GREEN='\033[1;32m'  
BLUE='\033[1;34m'   
CYAN='\033[1;36m'   
YELLOW='\033[1;33m' 

# --- INITIAL HEADER ---
echo -e "${BLUE}=======================================================${NC}"
echo -e "${BOLD}${CYAN}🚀 netwatchda Automated Setup${NC} (by ${BOLD}panoc${NC})"
echo -e "${BLUE}⚖️  License: GNU GPLv3${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo ""

printf "${BOLD}❓ This will begin the installation process. Continue? [y/n]: ${NC}"
read start_confirm </dev/tty
[ "$start_confirm" != "y" ] && [ "$start_confirm" != "Y" ] && exit 0

INSTALL_DIR="/root/netwatchda"
CONFIG_FILE="$INSTALL_DIR/netwatchda_settings.conf"
IP_LIST_FILE="$INSTALL_DIR/netwatchda_ips.conf"
SERVICE_PATH="/etc/init.d/netwatchda"

# --- 1. SYSTEM READINESS ---
echo -e "\n${BOLD}📦 Checking system readiness...${NC}"
FREE_FLASH_KB=$(df / | awk 'NR==2 {print $4}')
if ! command -v curl >/dev/null 2>&1; then
    [ "$FREE_FLASH_KB" -lt 3072 ] && { echo -e "${RED}❌ ERROR: Insufficient Flash!${NC}"; exit 1; }
    opkg update && opkg install curl ca-bundle
fi

# --- 2. NOTIFICATION SELECTION ---
echo -e "\n${BLUE}🔔 Notification Preference Selection${NC}"
echo -e "${BOLD}1)${NC} Enable Discord Notifications"
echo -e "${BOLD}2)${NC} Enable Telegram Notifications"
echo -e "${BOLD}3)${NC} Enable Both"
echo -e "${BOLD}4)${NC} None (Log-only mode)"
printf "${BOLD}Selection [1-4]: ${NC}"
read notify_choice </dev/tty

DIS_EN="NO"; TG_EN="NO"
case $notify_choice in
    1) DIS_EN="YES" ;;
    2) TG_EN="YES" ;;
    3) DIS_EN="YES"; TG_EN="YES" ;;
    *) echo -e "${YELLOW}⚠️  Mode: Log-only.${NC}" ;;
esac

mkdir -p "$INSTALL_DIR"

if [ "$DIS_EN" = "YES" ]; then
    echo -e "\n${CYAN}--- Discord Configuration ---${NC}"
    printf "${BOLD}🔗 Enter Discord Webhook URL: ${NC}"; read user_webhook </dev/tty
    printf "${BOLD}👤 Enter Discord User ID: ${NC}"; read user_id </dev/tty
fi

if [ "$TG_EN" = "YES" ]; then
    echo -e "\n${CYAN}--- Telegram Configuration ---${NC}"
    printf "${BOLD}🤖 Enter Telegram Bot Token: ${NC}"; read tg_token </dev/tty
    while :; do
        printf "${BOLD}🆔 Enter Telegram Chat ID: ${NC}"; read tg_chatid </dev/tty
        if echo "$tg_chatid" | grep -qE '^-?[0-9]+$'; then
            break
        else
            echo -e "${RED}❌ Invalid Chat ID. Numbers only (may start with -).${NC}"
        fi
    done
fi

printf "${BOLD}🏷️  Enter Router Name: ${NC}"; read router_name_input </dev/tty

# --- CONFIG GENERATION ---
cat <<EOF > "$CONFIG_FILE"
[Router Identification]
ROUTER_NAME="$router_name_input"
[Notification Settings]
DISCORD_ENABLE="$DIS_EN"; DISCORD_URL="$user_webhook"; MY_ID="$user_id"
TELEGRAM_ENABLE="$TG_EN"; TG_TOKEN="$tg_token"; TG_CHATID="$tg_chatid"
[Behavior Settings]
SILENT_ENABLE="OFF"; SILENT_START=23; SILENT_END=07; MAX_SIZE=51200
HEARTBEAT="ON"; HB_INTERVAL=86400; HB_MENTION="OFF"
[Internet Connectivity]
EXT_IP="1.1.1.1"; EXT_IP2="8.8.8.8"; EXT_SCAN_INTERVAL=60; EXT_FAIL_THRESHOLD=1; EXT_PING_COUNT=4
[Local Device Monitoring]
DEVICE_MONITOR="ON"; DEV_SCAN_INTERVAL=10; DEV_FAIL_THRESHOLD=3; DEV_PING_COUNT=4
EOF

[ ! -f "$IP_LIST_FILE" ] && echo "192.168.1.1 @ Router Gateway" > "$IP_LIST_FILE"

# --- CORE ENGINE SCRIPT ---
cat <<'EOF' > "$INSTALL_DIR/netwatchda.sh"
#!/bin/sh
BASE_DIR=$(cd "$(dirname "$0")" && pwd); CONFIG_FILE="$BASE_DIR/netwatchda_settings.conf"
IP_LIST_FILE="$BASE_DIR/netwatchda_ips.conf"; LOGFILE="/tmp/netwatchda_log.txt"
LAST_EXT_CHECK=0; LAST_DEV_CHECK=0; LAST_HB_CHECK=$(date +%s)

load_config() { [ -f "$CONFIG_FILE" ] && eval "$(sed '/^\[.*\]/d' "$CONFIG_FILE")"; }
trap load_config 1
load_config

send_alert() {
    T="$1"; M="$2"; C="$3"
    if [ "$DISCORD_ENABLE" = "YES" ] && [ -n "$DISCORD_URL" ]; then
        curl -s -H "Content-Type: application/json" -X POST -d "{\"embeds\": [{\"title\": \"$T\", \"description\": \"$M\", \"color\": $C}]}" "$DISCORD_URL" > /dev/null 2>&1
    fi
    if [ "$TELEGRAM_ENABLE" = "YES" ] && [ -n "$TG_TOKEN" ]; then
        ICON="ℹ️"; [ "$C" = "15548997" ] && ICON="🚨"; [ "$C" = "3066993" ] && ICON="✅"; [ "$C" = "1752220" ] && ICON="💓"
        CM=$(echo "$M" | sed 's/\*\*\([^*]*\)\*\*/<b>\1<\/b>/g')
        curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHATID&text=$ICON <b>$T</b>%0A$CM&parse_mode=HTML" > /dev/null 2>&1
    fi
}

# Handle test commands from service
if [ "$1" = "test_discord" ]; then load_config; send_alert "Test Alert" "Discord notification system is working!" "3066993"; exit; fi
if [ "$1" = "test_telegram" ]; then load_config; send_alert "Test Alert" "Telegram notification system is working!" "3066993"; exit; fi

while true; do
    NOW_H=$(date '+%b %d %H:%M:%S'); NOW_S=$(date +%s)
    
    # Heartbeat Logic
    if [ "$HEARTBEAT" = "ON" ] && [ $((NOW_S - LAST_HB_CHECK)) -ge "$HB_INTERVAL" ]; then
        LAST_HB_CHECK=$NOW_S; send_alert "System Healthy" "💓 **Heartbeat Report**\n**Router:** $ROUTER_NAME\n**Time:** $NOW_H" "1752220"
    fi

    # Internet Logic (Restored ScriptA Logic)
    if [ $((NOW_S - LAST_EXT_CHECK)) -ge "$EXT_SCAN_INTERVAL" ]; then
        LAST_EXT_CHECK=$NOW_S; FD="/tmp/nwda_ext_d"; FT="/tmp/nwda_ext_t"; FC="/tmp/nwda_ext_c"
        if ping -q -c "$EXT_PING_COUNT" -W 2 "$EXT_IP" >/dev/null 2>&1 || ping -q -c "$EXT_PING_COUNT" -W 2 "$EXT_IP2" >/dev/null 2>&1; then
            if [ -f "$FD" ]; then
                ST_SEC=$(cat "$FD"); DUR=$((NOW_S - ST_SEC)); DR_STR="$((DUR/60))m $((DUR%60))s"
                send_alert "Connectivity Restored" "🌐 **Internet Restored**\n**Outage:** $DR_STR\n**Up at:** $NOW_H" "3066993"
                rm -f "$FD" "$FT"
            fi
            echo 0 > "$FC"
        else
            C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
            if [ "$C" -ge "$EXT_FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                echo "$NOW_S" > "$FD"; echo "$NOW_H" > "$FT"
                send_alert "🔴 Internet Down" "**Router:** $ROUTER_NAME\n**Time:** $NOW_H" "15548997"
            fi
        fi
    fi

    # Device Monitoring Logic (Restored ScriptA Logic)
    if [ "$DEVICE_MONITOR" = "ON" ] && [ $((NOW_S - LAST_DEV_CHECK)) -ge "$DEV_SCAN_INTERVAL" ]; then
        LAST_DEV_CHECK=$NOW_S
        sed -e '/^#/d' -e '/^$/d' "$IP_LIST_FILE" | while read -r line; do
            TIP=$(echo "$line" | cut -d'@' -f1 | tr -d ' '); NAME=$(echo "$line" | cut -d'@' -f2- | sed 's/^[ \t]*//')
            [ -z "$TIP" ] && continue; SIP=$(echo "$TIP" | tr '.' '_'); FC="/tmp/nwda_c_$SIP"; FD="/tmp/nwda_d_$SIP"; FT="/tmp/nwda_t_$SIP"
            if ping -q -c "$DEV_PING_COUNT" -W 2 "$TIP" > /dev/null 2>&1; then
                if [ -f "$FD" ]; then
                    ST_SEC=$(cat "$FD"); DUR=$((NOW_S-ST_SEC)); DR_STR="$((DUR/60))m $((DUR%60))s"
                    send_alert "Device Online" "✅ **$NAME Online**\n**Outage:** $DR_STR\n**Time:** $NOW_H" "3066993"
                    rm -f "$FD" "$FT"
                fi
                echo 0 > "$FC"
            else
                C=$(($(cat "$FC" 2>/dev/null || echo 0)+1)); echo "$C" > "$FC"
                if [ "$C" -ge "$DEV_FAIL_THRESHOLD" ] && [ ! -f "$FD" ]; then
                    echo "$NOW_S" > "$FD"; echo "$NOW_H" > "$FT"
                    send_alert "🔴 Device Down" "**Device:** $NAME ($TIP)\n**Time:** $NOW_H" "15548997"
                fi
            fi
        done
    fi
    sleep 1
done
EOF

# --- COMPLETE SERVICE FILE ---
cat <<EOF > "$SERVICE_PATH"
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
extra_command "status" "Service status"
extra_command "clear" "Clear log file"
extra_command "discord" "Test discord notification"
extra_command "telegram" "Test telegram notification"
extra_command "purge" "Interactive smart uninstaller"
extra_command "reload" "Reload configuration files"
extra_command "help" "Display this help message"

start_service() { procd_open_instance; procd_set_param command /bin/sh "$INSTALL_DIR/netwatchda.sh"; procd_set_param respawn; procd_close_instance; }
status() { pgrep -f "netwatchda.sh" > /dev/null && echo -e "${GREEN}RUNNING${NC}" || echo -e "${RED}STOPPED${NC}"; }
clear() { > /tmp/netwatchda_log.txt && echo "Logs cleared."; }
discord() { /bin/sh "$INSTALL_DIR/netwatchda.sh" test_discord; }
telegram() { /bin/sh "$INSTALL_DIR/netwatchda.sh" test_telegram; }
reload() { kill -1 \$(pgrep -f "netwatchda.sh") && echo "Reload signal sent."; }
help() {
    echo -e "${CYAN}netwatchda Commands:${NC}"
    echo "  start, stop, restart, status, enable, disable, reload, clear, discord, telegram, purge, help"
}
purge() {
    echo -e "${RED}=======================================================${NC}"
    echo -e "${BOLD}${RED}🗑️  netwatchda Smart Uninstaller${NC}"
    echo -e "${RED}=======================================================${NC}"
    printf "1) Full Uninstall\n2) Keep Settings\nChoice: "; read p_choice </dev/tty
    if [ "\$p_choice" = "1" ]; then /etc/init.d/netwatchda stop; rm -rf "$INSTALL_DIR" "$SERVICE_PATH"; fi
}
EOF

chmod +x "$SERVICE_PATH" "$INSTALL_DIR/netwatchda.sh"
"$SERVICE_PATH" enable; "$SERVICE_PATH" restart

echo -e "\n${GREEN}=======================================================${NC}"
echo -e "${BOLD}${GREEN}✅ Installation complete!${NC}"
echo -e "  Management: ${CYAN}/etc/init.d/netwatchda help${NC}"
echo -e "${GREEN}=======================================================${NC}"

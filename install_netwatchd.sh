#!/bin/sh

# --- CONFIGURATION ---
INSTALL_DIR="/root/netwatchd"
SERVICE_NAME="netwatchd"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"

echo "🚀 Starting netwatchd Automated Setup..."

# 1. Create the Directory Structure
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating directory $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
fi

# 2. Check Dependencies
if ! command -v curl >/dev/null 2>&1; then
    echo "📦 curl not found. Installing..."
    opkg update && opkg install curl ca-bundle
fi

# 3. Create netwatchd_settings.conf
cat <<EOF > "$INSTALL_DIR/netwatchd_settings.conf"
# Discord Settings
DISCORD_URL="https://discord.com/api/webhooks/your_id"
MY_ID="123456789012345678"

# Monitoring Settings
SCAN_INTERVAL=10 # Default 10 - Check other devices every 10 seconds
FAIL_THRESHOLD=3 # Default 3. Be careful: With a threshold of 1, a single dropped packet (common on Wi-Fi or busy routers) will trigger a "DOWN" alert immediately. Usually, 2 or 3 is safer.
MAX_SIZE=512000  # Default 512000. Size in bytes, make use router has enough memory to hold the log.

# Internet Check
EXT_IP="1.1.1.1" # IP to check for internet connectivity.
EXT_INTERVAL=60  # Default 60 - Check internet every 60 seconds.
EOF

# 4. Create netwatchd_ips.conf
cat <<EOF > "$INSTALL_DIR/netwatchd_ips.conf"
# Format: IP_ADDRESS # NAME
8.8.8.8 # Google DNS
1.1.1.1 # Cloudflare DNS
EOF

# 5. Create netwatchd.sh (The Main Logic)
cat <<'EOF' > "$INSTALL_DIR/netwatchd.sh"
#!/bin/sh
BASE_DIR=$(cd "$(dirname "$0")" && pwd)
IP_LIST_FILE="$BASE_DIR/netwatchd_ips.conf"
CONFIG_FILE="$BASE_DIR/netwatchd_settings.conf"
LOGFILE="/tmp/netwatchd_log.txt"

# Initialize variables
SCAN_INTERVAL=10; EXT_INTERVAL=60; FAIL_THRESHOLD=3; MAX_SIZE=512000; LAST_EXT_CHECK=0

while true; do
    # Load settings from config file
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
    
    NOW_SEC
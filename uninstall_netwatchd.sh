#!/bin/sh

# --- CONFIGURATION ---
INSTALL_DIR="/root/netwatchd"
SERVICE_NAME="netwatchd"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"

echo "🗑️ Starting Force Uninstall..."

# 1. Kill the process manually if it's stuck
echo "🛑 Killing any running netwatchd processes..."
pgrep -f "netwatchd.sh" | xargs kill -9 > /dev/null 2>&1

# 2. Stop and Disable the System Service
if [ -f "$SERVICE_PATH" ]; then
    echo "🚫 Disabling system service..."
    $SERVICE_PATH stop > /dev/null 2>&1
    $SERVICE_PATH disable > /dev/null 2>&1
    rm -f "$SERVICE_PATH"
fi

# 3. Remove the Files
echo "📁 Deleting application files at $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"

# 4. Clean RAM (Temporary Files)
echo "🧹 Clearing logs and temp data..."
rm -f /tmp/netwatchd*
rm -f /tmp/nw_*

echo "✅ Uninstall Complete. Everything has been removed."
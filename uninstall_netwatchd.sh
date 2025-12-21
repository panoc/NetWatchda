#!/bin/sh

# --- CONFIGURATION ---
INSTALL_DIR="/root/netwatchd"
SERVICE_NAME="netwatchd"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"

echo "🗑️ Uninstalling netwatchd..."

# 1. Stop and Disable the Service
if [ -f "$SERVICE_PATH" ]; then
    echo "🛑 Stopping and disabling service..."
    $SERVICE_PATH stop
    $SERVICE_PATH disable
    rm -f "$SERVICE_PATH"
fi

# 2. Remove the Application Directory
if [ -d "$INSTALL_DIR" ]; then
    echo "📁 Removing directory $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
fi

# 3. Clean up temporary files and logs
echo "🧹 Cleaning up temporary logs and status files..."
rm -f /tmp/netwatchd_log.txt
rm -f /tmp/netwatchd_ext_down
rm -f /tmp/nw_cnt_*
rm -f /tmp/nw_down_*
rm -f /tmp/nw_q_*

echo "---"
echo "✅ netwatchd has been successfully uninstalled."
echo "💡 Your router is now clean."
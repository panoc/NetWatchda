#!/bin/sh

# --- INITIAL SPACING ---
echo ""
echo "-------------------------------------------------------"
echo "🗑️  netwatchd Uninstaller"
echo "-------------------------------------------------------"

INSTALL_DIR="/root/netwatchd"
SERVICE_NAME="netwatchd"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"

# --- 1. STOP AND DISABLE SERVICE ---
if [ -f "$SERVICE_PATH" ]; then
    echo "🛑 Stopping and disabling $SERVICE_NAME service..."
    $SERVICE_PATH stop 2>/dev/null
    $SERVICE_PATH disable 2>/dev/null
    rm -f "$SERVICE_PATH"
    echo "✅ System service entry removed."
fi

# --- 2. ASK TO KEEP SETTINGS (Fixed for Pipe/GitHub) ---
if [ -d "$INSTALL_DIR" ]; then
    echo "---"
    # We use </dev/tty to force the script to wait for your keyboard input
    printf "❓ Keep configuration files (settings & IP list)? [y/n]: "
    read keep_choice </dev/tty

    case "$keep_choice" in
        y|Y ) 
            echo "💾 Preserving configuration in $INSTALL_DIR"
            rm -f "$INSTALL_DIR/netwatchd.sh"
            rm -f "$INSTALL_DIR/*.txt" 2>/dev/null
            echo "✅ Core script removed. Settings files remain."
            ;;
        * ) 
            echo "🧹 Removing all files in $INSTALL_DIR..."
            rm -rf "$INSTALL_DIR"
            echo "✅ Entire directory deleted."
            ;;
    esac
else
    echo "❌ Directory $INSTALL_DIR not found."
fi

# --- 3. CLEAN UP TEMP FILES ---
echo "🧹 Purging temporary state files from RAM..."
rm -f /tmp/nw_cnt_* 2>/dev/null
rm -f /tmp/nw_down_* 2>/dev/null
rm -f /tmp/netwatchd_* 2>/dev/null

echo "---"
echo "✨ netwatchd has been successfully uninstalled."
echo "-------------------------------------------------------"
echo ""
#!/bin/sh

# --- INITIAL SPACING ---
echo ""
echo "-------------------------------------------------------"
echo "🗑️  Starting netwatchd Uninstallation..."
echo "-------------------------------------------------------"

INSTALL_DIR="/root/netwatchd"
SERVICE_NAME="netwatchd"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"

# --- 1. USER CHOICE MENU ---
if [ -d "$INSTALL_DIR" ] || [ -f "$SERVICE_PATH" ]; then
    echo "What would you like to do?"
    echo "1. Full Uninstall (Remove everything)"
    echo "2. Keep Settings (Remove script/service only)"
    echo "3. Cancel"
    printf "Enter choice [1-3]: "
    read choice </dev/tty

    case "$choice" in
        3)
            echo "❌ Uninstallation cancelled."
            exit 0
            ;;
        2)
            KEEP_CONF=1
            echo "📂 Preservation Mode selected."
            ;;
        *)
            KEEP_CONF=0
            echo "🗑️  Full Uninstall selected."
            ;;
    esac
else
    echo "ℹ️  No installation found to remove."
    exit 1
fi

# --- 2. STOP AND REMOVE SERVICE ---
if [ -f "$SERVICE_PATH" ]; then
    echo "🛑 Stopping and disabling service..."
    $SERVICE_PATH stop
    $SERVICE_PATH disable
    # Kill any lingering sleep or script processes
    killall -9 netwatchd.sh 2>/dev/null
    rm -f "$SERVICE_PATH"
    echo "✅ Service removed."
fi

# --- 3. CLEAN UP TEMPORARY STATE FILES ---
echo "🧹 Cleaning up temporary state files..."
rm -f /tmp/netwatchd_log.txt
rm -f /tmp/nw_ext_d
rm -f /tmp/nw_ext_t
rm -f /tmp/nw_c_*
rm -f /tmp/nw_d_*
echo "✅ Temp files cleared."

# --- 4. REMOVE INSTALLATION FILES ---
if [ "$KEEP_CONF" -eq 1 ]; then
    # Specifically remove only the core logic script
    rm -f "$INSTALL_DIR/netwatchd.sh"
    echo "✅ Core script removed. Configuration preserved in $INSTALL_DIR"
else
    echo "🗑️  Removing all files in $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    echo "✅ All files removed."
fi

# --- 5. FINAL CLEANUP ---
# The script deletes itself
rm -- "$0"

echo "---"
echo "✨ Uninstallation complete!"
echo "-------------------------------------------------------"
echo ""
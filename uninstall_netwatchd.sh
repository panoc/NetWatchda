#!/bin/sh

# --- INITIAL SPACING ---
echo ""
echo "-------------------------------------------------------"
echo "🗑️  Starting netwatchd Uninstallation..."
echo "-------------------------------------------------------"

INSTALL_DIR="/root/netwatchd"
SERVICE_NAME="netwatchd"
SERVICE_PATH="/etc/init.d/$SERVICE_NAME"

# --- 1. STOP AND REMOVE SERVICE ---
if [ -f "$SERVICE_PATH" ]; then
    echo "🛑 Stopping and disabling service..."
    $SERVICE_PATH stop
    $SERVICE_PATH disable
    rm -f "$SERVICE_PATH"
    echo "✅ Service removed."
else
    echo "ℹ️  Service not found, skipping..."
fi

# --- 2. CLEAN UP TEMPORARY STATE FILES ---
echo "🧹 Cleaning up temporary state files..."
rm -f /tmp/netwatchd_log.txt
rm -f /tmp/nw_ext_d
rm -f /tmp/nw_ext_t
rm -f /tmp/nw_c_*
rm -f /tmp/nw_d_*
echo "✅ Temp files cleared."

# --- 3. REMOVE INSTALLATION FILES ---
if [ -d "$INSTALL_DIR" ]; then
    echo "---"
    printf "❓ Do you want to delete your configuration files (.conf)? [y/n]: "
    read del_conf </dev/tty

    if [ "$del_conf" = "y" ] || [ "$del_conf" = "Y" ]; then
        echo "🗑️  Removing all files in $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
        echo "✅ All files removed."
    else
        echo "📂 Preservation Mode: Keeping .conf files in $INSTALL_DIR"
        # We only remove the core script, keeping the .conf files
        rm -f "$INSTALL_DIR/netwatchd.sh"
        echo "✅ Core script removed. Configuration preserved."
    fi
else
    echo "ℹ️  Installation directory not found."
fi

# --- 4. FINAL CLEANUP ---
# The script deletes itself
rm -- "$0"

echo "---"
echo "✨ Uninstallation complete!"
echo "-------------------------------------------------------"
echo ""
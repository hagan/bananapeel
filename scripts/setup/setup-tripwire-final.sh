#!/bin/bash
# Final Tripwire Service Account and Automation Setup
# This version includes all fixes and improvements from testing

set -euo pipefail

# Configuration
SERVICE_USER="tripwire"
SERVICE_GROUP="tripwire"
SERVICE_HOME="/var/lib/tripwire-service"
SUDOERS_FILE="/etc/sudoers.d/tripwire-service"

echo "========================================="
echo "Tripwire Service Account Setup - Final"
echo "========================================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Create group if it doesn't exist
if ! getent group "$SERVICE_GROUP" > /dev/null; then
    echo "Creating group: $SERVICE_GROUP"
    groupadd --system "$SERVICE_GROUP"
fi

# Create service user if it doesn't exist
if ! id "$SERVICE_USER" > /dev/null 2>&1; then
    echo "Creating service user: $SERVICE_USER"
    useradd --system \
            --gid "$SERVICE_GROUP" \
            --home "$SERVICE_HOME" \
            --shell /bin/bash \
            --comment "Tripwire Service Account" \
            "$SERVICE_USER"
fi

# Create home directory with proper permissions
mkdir -p "$SERVICE_HOME"
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME"
chmod 750 "$SERVICE_HOME"

# Prepare runtime lock directory
mkdir -p /run/bananapeel
chown "$SERVICE_USER:$SERVICE_GROUP" /run/bananapeel
chmod 755 /run/bananapeel

# Create sudoers configuration for limited tripwire access
if [ "${USE_WRAPPER:-1}" = "1" ]; then
cat > "$SUDOERS_FILE" << 'EOF'
# Tripwire service account sudo permissions - Restricted wrapper only
Cmnd_Alias BANANAPEEL_WRAPPER = /usr/local/lib/bananapeel/tripwire-wrapper *
tripwire ALL=(root) NOPASSWD: BANANAPEEL_WRAPPER
EOF
else
cat > "$SUDOERS_FILE" << 'EOF'
# Tripwire service account sudo permissions - Restricted with Cmnd_Alias (debug mode)
Cmnd_Alias TRIPWIRE_CHECK = /usr/sbin/tripwire --check, \
                            /usr/sbin/tripwire --check --quiet, \
                            /usr/sbin/tripwire --check --quiet --email-report
Cmnd_Alias TRIPWIRE_UPDATE = /usr/sbin/tripwire --update --twrfile /var/lib/tripwire/report/*.twr, \
                             /usr/sbin/tripwire --update --twrfile /var/lib/tripwire/report/*.twr --accept-all
Cmnd_Alias TRIPWIRE_PRINT = /usr/sbin/twprint --print-report --twrfile /var/lib/tripwire/report/*.twr
tripwire ALL=(root) NOPASSWD: TRIPWIRE_CHECK, TRIPWIRE_UPDATE, TRIPWIRE_PRINT
EOF
fi

# Validate sudoers file before installing
if visudo -c -f "$SUDOERS_FILE"; then
    chmod 440 "$SUDOERS_FILE"
    echo "✓ Sudoers configuration installed"
else
    echo "ERROR: Sudoers configuration is invalid!"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# Deploy the canonical automation script
# Prefer repo-relative path; fallback to installed share location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_SCRIPT_REPO="$SCRIPT_DIR/../automation/tripwire-auto-update.sh"
CANONICAL_SCRIPT_SHARE="/usr/share/bananapeel/tripwire-auto-update.sh"

if [ -f "$CANONICAL_SCRIPT_REPO" ]; then
    SRC_SCRIPT="$CANONICAL_SCRIPT_REPO"
elif [ -f "$CANONICAL_SCRIPT_SHARE" ]; then
    SRC_SCRIPT="$CANONICAL_SCRIPT_SHARE"
else
    echo "ERROR: Canonical script not found in repo or share locations"
    echo "Checked: $CANONICAL_SCRIPT_REPO and $CANONICAL_SCRIPT_SHARE"
    exit 1
fi

echo "✓ Installing canonical automation script from $SRC_SCRIPT"
cp "$SRC_SCRIPT" "$SERVICE_HOME/tripwire-auto-update.sh"
chmod 755 "$SERVICE_HOME/tripwire-auto-update.sh"
chown "$SERVICE_USER:$SERVICE_GROUP" "$SERVICE_HOME/tripwire-auto-update.sh"

# Create log file with proper permissions
touch /var/log/bananapeel-update.log
chown "$SERVICE_USER:$SERVICE_GROUP" /var/log/bananapeel-update.log
chmod 664 /var/log/bananapeel-update.log

# Create legacy symlink for backward compatibility
if [ ! -e /var/log/tripwire-apt-update.log ]; then
    ln -s /var/log/bananapeel-update.log /var/log/tripwire-apt-update.log
    echo "Created log symlink: tripwire-apt-update.log -> bananapeel-update.log"
fi

# Fix remote-ips files if they don't exist
if [ ! -f /var/lib/tripwire/remote-ips.txt ]; then
    touch /var/lib/tripwire/remote-ips.txt
    chmod 640 /var/lib/tripwire/remote-ips.txt
    chown root:root /var/lib/tripwire/remote-ips.txt
    echo "✓ Created remote-ips.txt"
fi

if [ ! -f /var/lib/tripwire/remote-ips.changes ]; then
    touch /var/lib/tripwire/remote-ips.changes
    chmod 640 /var/lib/tripwire/remote-ips.changes
    chown root:root /var/lib/tripwire/remote-ips.changes
    echo "✓ Created remote-ips.changes"
fi

echo
echo "========================================="
echo "✓ Tripwire Service Account Setup Complete"
echo "========================================="
echo
echo "Service user: $SERVICE_USER"
echo "Home directory: $SERVICE_HOME"
echo "Automation script: $SERVICE_HOME/tripwire-auto-update.sh"
echo "Log file: /var/log/bananapeel-update.log (legacy symlink at /var/log/tripwire-apt-update.log)"
echo
echo "Next steps:"
echo "1. Test the service:"
echo "   sudo -u $SERVICE_USER $SERVICE_HOME/tripwire-auto-update.sh"
echo
echo "2. Check timer status:"
echo "   systemctl status bananapeel-update.timer"
echo
echo "The service will run daily at 6:25 AM and send email reports."
echo
echo "To customize email recipient, edit the script and change:"
echo "  EMAIL_TO=\"root\""
echo
echo "Remote-ips files have been created to prevent errors."

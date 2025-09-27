#!/bin/bash
# Setup script for tripwire service account
# This creates a limited service account for automated tripwire updates

set -euo pipefail

# Configuration (allow environment overrides)
SERVICE_USER="${SERVICE_USER:-tripwire}"
SERVICE_GROUP="${SERVICE_GROUP:-tripwire}"
SERVICE_HOME="${SERVICE_HOME:-/var/lib/tripwire-service}"
SUDOERS_FILE="${SUDOERS_FILE:-/etc/sudoers.d/${SERVICE_USER}-service}"

echo "Setting up Tripwire service account for automated updates..."

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
            --comment "Tripwire Update Service Account" \
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

# Create secure passphrase storage (only accessible by service account)
PASSPHRASE_DIR="$SERVICE_HOME/.tripwire"
mkdir -p "$PASSPHRASE_DIR"
chown "$SERVICE_USER:$SERVICE_GROUP" "$PASSPHRASE_DIR"
chmod 700 "$PASSPHRASE_DIR"

# Create sudoers configuration for limited wrapper access
if [ "${USE_WRAPPER:-1}" = "1" ]; then
cat > "$SUDOERS_FILE" << EOF
# Bananapeel service account sudo permissions - Restricted wrapper only
# Only allows execution of the bananapeel tripwire-wrapper for security
# Wrapper validates all arguments and restricts operations to safe subset

# Define command alias for the wrapper (no direct tripwire binary access)
Cmnd_Alias BANANAPEEL_WRAPPER = /usr/local/lib/bananapeel/tripwire-wrapper

# Grant permissions to service user for wrapper only (no environment manipulation)
Defaults!BANANAPEEL_WRAPPER env_reset
Defaults!BANANAPEEL_WRAPPER !setenv
Defaults!BANANAPEEL_WRAPPER secure_path=/usr/sbin:/usr/bin:/bin
${SERVICE_USER} ALL=(root) NOPASSWD: BANANAPEEL_WRAPPER
EOF
else
cat > "$SUDOERS_FILE" << EOF
# Bananapeel service account sudo permissions - Debug mode (USE_WRAPPER=0)
# Only allows specific tripwire operations needed for automation
# WARNING: This mode bypasses wrapper validation. Use for debugging only.

# Check operations (no dangerous flags like --init)
Cmnd_Alias TRIPWIRE_CHECK = /usr/sbin/tripwire --check, \
                            /usr/sbin/tripwire --check --quiet, \
                            /usr/sbin/tripwire --check --quiet --email-report

# Update operations (path-constrained to report directory only)
Cmnd_Alias TRIPWIRE_UPDATE = /usr/sbin/tripwire --update --twrfile /var/lib/tripwire/report/*.twr, \
                             /usr/sbin/tripwire --update --twrfile /var/lib/tripwire/report/*.twr --accept-all

# Print operations (path-constrained to report directory only)
Cmnd_Alias TRIPWIRE_PRINT = /usr/sbin/twprint --print-report --twrfile /var/lib/tripwire/report/*.twr

# Environment reset for security and disallow setting env
Defaults!TRIPWIRE_CHECK,TRIPWIRE_UPDATE,TRIPWIRE_PRINT env_reset
Defaults!TRIPWIRE_CHECK,TRIPWIRE_UPDATE,TRIPWIRE_PRINT !setenv
Defaults!TRIPWIRE_CHECK,TRIPWIRE_UPDATE,TRIPWIRE_PRINT secure_path=/usr/sbin:/usr/bin:/bin
${SERVICE_USER} ALL=(root) NOPASSWD: TRIPWIRE_CHECK, TRIPWIRE_UPDATE, TRIPWIRE_PRINT
EOF
fi

# Validate sudoers file before installing
if visudo -c -f "$SUDOERS_FILE"; then
    chmod 440 "$SUDOERS_FILE"
    echo "Sudoers configuration installed successfully"
else
    echo "ERROR: Sudoers configuration is invalid!"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# Create passphrase configuration script
cat > "$SERVICE_HOME/setup-passphrase.sh" << 'EOF_SCRIPT'
#!/bin/bash
# Run this script as root to set up the tripwire passphrase for automated updates

PASSPHRASE_FILE="/var/lib/tripwire-service/.tripwire/local-passphrase"

echo "Setting up Tripwire passphrase for automated updates"
echo "This passphrase will be stored encrypted and only accessible by the service account"
echo ""

# Prompt for passphrase
read -s -p "Enter Tripwire LOCAL passphrase: " PASSPHRASE
echo ""

# Store passphrase with encryption using openssl
# Generate a key from machine-id (unique per system)
KEY=$(cat /etc/machine-id | sha256sum | cut -d' ' -f1)

# Encrypt the passphrase
echo "$PASSPHRASE" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:$KEY > "$PASSPHRASE_FILE"

# Set strict permissions
chown ${SERVICE_USER:-tripwire}:${SERVICE_GROUP:-tripwire} "$PASSPHRASE_FILE"
chmod 400 "$PASSPHRASE_FILE"

echo "Passphrase stored securely in $PASSPHRASE_FILE"
echo ""
echo "To decrypt for use:"
echo "cat $PASSPHRASE_FILE | openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:\$(cat /etc/machine-id | sha256sum | cut -d' ' -f1)"
EOF_SCRIPT

chmod 700 "$SERVICE_HOME/setup-passphrase.sh"
chown root:root "$SERVICE_HOME/setup-passphrase.sh"

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

echo "Installing canonical automation script from $SRC_SCRIPT..."
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

# Add service user to necessary groups for reading system files
usermod -a -G adm "$SERVICE_USER" 2>/dev/null || true

echo ""
echo "=== Tripwire Service Account Setup Complete ==="
echo ""
echo "Service user created: $SERVICE_USER"
echo "Home directory: $SERVICE_HOME"
echo ""
echo "Next steps:"
echo "1. Set up the passphrase (as root):"
echo "   $SERVICE_HOME/setup-passphrase.sh"
echo ""
echo "2. Test the service account:"
echo "   sudo -u $SERVICE_USER $SERVICE_HOME/tripwire-auto-update.sh"
echo ""
echo "3. Add to APT hooks by creating /etc/apt/apt.conf.d/99bananapeel:"
echo "   DPkg::Post-Invoke { \"sudo -u $SERVICE_USER /var/lib/tripwire-service/tripwire-auto-update.sh || true\"; };"
echo ""
echo "Security notes:"
if [ "${USE_WRAPPER:-1}" = "1" ]; then
echo "- Service account has wrapper-only sudo access (no direct tripwire binary)"
echo "- Wrapper validates all arguments and restricts operations to safe subset"
else
echo "- Service account has limited sudo access (only tripwire --check, --update, and twprint)"
echo "- Debug mode: Direct tripwire access path-constrained to /var/lib/tripwire/report/"
fi
echo "- Passphrase is stored encrypted, tied to machine-id"
echo "- Service account cannot reinitialize or change tripwire policies"
echo "- Environment variables are reset (env_reset) for security"

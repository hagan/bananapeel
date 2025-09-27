#!/bin/bash
# Complete Tripwire Automation Installation Script
# This script sets up the service account and automation for tripwire
# Supports various flags for customization

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
WITH_APT_HOOK=false
WITH_TIMER=true
EMAIL_TO=""
AUTO_ACCEPT_THRESHOLD=""
DRY_RUN=false
WITH_WRAPPER=true
VERBOSE=false
MIGRATE_SERVICE_USER=false

# Function to print usage
print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Installs Tripwire automation with Bananapeel enhancements.

OPTIONS:
    --with-apt-hook        [DEPRECATED] Install APT hook at /etc/apt/apt.conf.d/99bananapeel
                          (Warning: APT hooks will be removed in v0.3.0)
                          (default: not installed - timer-first approach)

    --no-timer            Do not create/enable systemd timer
                          (default: timer is enabled for daily checks)

    --email <addr>        Set EMAIL_TO for reports
                          (default: root)

    --threshold <N>       Set AUTO_ACCEPT_THRESHOLD for package updates
                          (default: 50, use 0 to disable auto-accept)

    --dry-run            Print planned actions without making changes
                          (default: false)

    --no-wrapper         Skip wrapper installation (debug only)
                          (default: wrapper is installed for security)

    --migrate-service-user  Migrate from 'tripwire' to 'bananapeel' service user
                          (default: false - uses existing or creates 'tripwire' user)

    --verbose            Show detailed output

    --help               Print this help and exit

DEFAULTS:
    - Timer-based execution (daily at 6:25 AM)
    - No APT hook (use --with-apt-hook to enable)
    - Email to root
    - Auto-accept threshold of 50 system files
    - Security wrapper enabled

EXAMPLES:
    # Basic installation with defaults
    sudo $0

    # With APT hook and custom email
    sudo $0 --with-apt-hook --email admin@example.com

    # Disable auto-accept
    sudo $0 --threshold 0

    # Dry run to see what would be done
    sudo $0 --dry-run --with-apt-hook

EOF
}

# Function to run or echo commands based on dry-run
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        if [ "$VERBOSE" = true ]; then
            echo "Executing: $*"
        fi
        "$@"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-apt-hook)
            WITH_APT_HOOK=true
            shift
            ;;
        --no-timer)
            WITH_TIMER=false
            shift
            ;;
        --email)
            if [ -z "${2:-}" ]; then
                echo "Error: --email requires an argument"
                exit 1
            fi
            EMAIL_TO="$2"
            shift 2
            ;;
        --threshold)
            if [ -z "${2:-}" ]; then
                echo "Error: --threshold requires an argument"
                exit 1
            fi
            AUTO_ACCEPT_THRESHOLD="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-wrapper)
            WITH_WRAPPER=false
            echo "Warning: --no-wrapper is for debugging only. Security will be reduced."
            shift
            ;;
        --migrate-service-user)
            MIGRATE_SERVICE_USER=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 2
            ;;
    esac
done

# Check if running as root (unless dry-run)
if [[ $EUID -ne 0 ]] && [ "$DRY_RUN" = false ]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "==================================="
echo "Tripwire Automation Setup"
echo "==================================="
echo
echo "Configuration:"
echo "  Timer:          $([ "$WITH_TIMER" = true ] && echo "Enabled" || echo "Disabled")"
echo "  APT Hook:       $([ "$WITH_APT_HOOK" = true ] && echo "Enabled" || echo "Disabled")"
echo "  Wrapper:        $([ "$WITH_WRAPPER" = true ] && echo "Enabled" || echo "Disabled (debug)")"
echo "  Email To:       ${EMAIL_TO:-root (default)}"
echo "  Auto-Accept:    ${AUTO_ACCEPT_THRESHOLD:-50 (default)}"
echo "  Dry Run:        $([ "$DRY_RUN" = true ] && echo "YES" || echo "No")"
echo

# Check for required packages
echo "Checking prerequisites..."
MISSING_PACKAGES=""

if ! command -v tripwire >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES tripwire"
fi

if ! command -v expect >/dev/null 2>&1; then
    MISSING_PACKAGES="$MISSING_PACKAGES expect"
fi

if [ -n "$MISSING_PACKAGES" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would install missing packages:$MISSING_PACKAGES"
    else
        echo "Installing missing packages:$MISSING_PACKAGES"
        apt-get update
        apt-get install -y "$MISSING_PACKAGES"
    fi
fi

# Step 0: Run service user migration if requested
if [ "$MIGRATE_SERVICE_USER" = true ]; then
    echo
    echo "Step 0: Migrating service user to 'bananapeel'..."
    echo "---------------------------------------------------"
    if [ -f "$SCRIPT_DIR/migrate-service-user.sh" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] Would run: $SCRIPT_DIR/migrate-service-user.sh --dry-run"
            bash "$SCRIPT_DIR/migrate-service-user.sh" --dry-run
        else
            bash "$SCRIPT_DIR/migrate-service-user.sh" || {
                echo "ERROR: Service user migration failed"
                exit 1
            }
        fi
    else
        echo "ERROR: migrate-service-user.sh not found!"
        exit 1
    fi
fi

# Step 1: Setup service account
echo
echo "Step 1: Setting up service account..."
echo "-------------------------------------"
if [ -f "$SCRIPT_DIR/setup-tripwire-service-account.sh" ]; then
    # Determine target user/group: prefer bananapeel if migrated or present
    TARGET_USER="tripwire"
    TARGET_GROUP="tripwire"
    if [ "$MIGRATE_SERVICE_USER" = true ] || id bananapeel >/dev/null 2>&1; then
        TARGET_USER="bananapeel"
        TARGET_GROUP="bananapeel"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would run: SERVICE_USER=$TARGET_USER SERVICE_GROUP=$TARGET_GROUP USE_WRAPPER=$([ "$WITH_WRAPPER" = true ] && echo 1 || echo 0) $SCRIPT_DIR/setup-tripwire-service-account.sh"
    else
        SERVICE_USER="$TARGET_USER" SERVICE_GROUP="$TARGET_GROUP" USE_WRAPPER=$([ "$WITH_WRAPPER" = true ] && echo 1 || echo 0) bash "$SCRIPT_DIR/setup-tripwire-service-account.sh"
    fi
else
    echo "ERROR: setup-tripwire-service-account.sh not found!"
    exit 1
fi

# Step 2: Deploy configuration file
echo
echo "Step 2: Setting up configuration file..."
echo "-----------------------------------------"

# Look for config source
CONFIG_SOURCE=""
if [ -f "$SCRIPT_DIR/../../config/bananapeel.conf.sample" ]; then
    CONFIG_SOURCE="$SCRIPT_DIR/../../config/bananapeel.conf.sample"
elif [ -f "/usr/share/bananapeel/bananapeel.conf.sample" ]; then
    CONFIG_SOURCE="/usr/share/bananapeel/bananapeel.conf.sample"
fi

if [ -f "/etc/bananapeel/bananapeel.conf" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would skip config deployment (already exists)"
    else
        echo "✓ Configuration file already exists (skipping)"
    fi
else
    if [ -n "$CONFIG_SOURCE" ] && [ -f "$CONFIG_SOURCE" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] Would install config sample to /etc/bananapeel/bananapeel.conf"
        else
            install -d /etc/bananapeel
            install -m 0644 "$CONFIG_SOURCE" /etc/bananapeel/bananapeel.conf
            echo "✓ Configuration file deployed from sample: $CONFIG_SOURCE"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] Would create minimal config at /etc/bananapeel/bananapeel.conf"
        else
            install -d /etc/bananapeel
            cat > /etc/bananapeel/bananapeel.conf <<'EOF'
# Bananapeel Configuration
# See bananapeel.conf.sample for documentation

BANANAPEEL_EMAIL_TO="root"
BANANAPEEL_THRESHOLD="50"
BANANAPEEL_DRY_RUN="0"
EOF
            echo "✓ Default configuration file created at /etc/bananapeel/bananapeel.conf"
        fi
    fi
fi

# Step 3: Setup passphrase for automation
echo
echo "Step 3: Setting up passphrase storage..."
echo "-----------------------------------------"
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would prompt for passphrase and store encrypted"
else
    if [ ! -f /var/lib/tripwire-service/.tripwire/local-passphrase ]; then
        echo "Please run the passphrase setup script:"
        echo "  sudo /var/lib/tripwire-service/setup-passphrase.sh"
        echo ""
        read -r -p "Do you want to set up the passphrase now? (y/N): " SETUP_NOW
        if [[ "$SETUP_NOW" =~ ^[Yy]$ ]]; then
            /var/lib/tripwire-service/setup-passphrase.sh
        else
            echo "⚠ Passphrase not configured. Auto-accept will not work."
        fi
    else
        echo "✓ Passphrase already configured"
    fi
fi

# Step 4: Install APT hook (if requested)
if [ "$WITH_APT_HOOK" = true ]; then
    echo
    echo "Step 4: Installing APT hook..."
    echo "------------------------------"

    # Look for the APT hook config
    APT_HOOK_SOURCE=""
    if [ -f "$SCRIPT_DIR/../../config/99bananapeel" ]; then
        APT_HOOK_SOURCE="$SCRIPT_DIR/../../config/99bananapeel"
    elif [ -f "/etc/bananapeel/99bananapeel" ]; then
        APT_HOOK_SOURCE="/etc/bananapeel/99bananapeel"
    elif [ -f "/usr/share/bananapeel/99bananapeel" ]; then
        APT_HOOK_SOURCE="/usr/share/bananapeel/99bananapeel"
    fi

    if [ -z "$APT_HOOK_SOURCE" ]; then
        echo "ERROR: APT hook config not found. Please run 'make install' first."
        exit 1
    fi

    run_cmd install -m 644 "$APT_HOOK_SOURCE" /etc/apt/apt.conf.d/99bananapeel
    echo "✓ APT hook installed at /etc/apt/apt.conf.d/99bananapeel"
else
    echo
    echo "Step 4: Skipping APT hook (default, use --with-apt-hook to enable)"
fi

# Step 5: Verify and test the automation
echo
echo "Step 5: Testing the automation setup..."
echo "---------------------------------------"

# Verify the canonical script was deployed
if [ "$DRY_RUN" = false ]; then
    if [ ! -f /var/lib/tripwire-service/tripwire-auto-update.sh ]; then
        echo "ERROR: Automation script not found at /var/lib/tripwire-service/tripwire-auto-update.sh"
        echo "Installation may have failed. Please check the setup scripts."
        exit 1
    fi

    echo "Running a test update check as the service user..."
    if sudo -u tripwire /var/lib/tripwire-service/tripwire-auto-update.sh; then
        echo "✓ Test successful!"
    else
        echo "⚠ Test completed with warnings (check /var/log/bananapeel-update.log)"
    fi
else
    echo "[DRY-RUN] Would verify automation script and run test"
fi

# Step 6: Create systemd timer (if requested)
if [ "$WITH_TIMER" = true ]; then
    echo
    echo "Step 6: Creating systemd timer for daily checks..."
    echo "---------------------------------------------------"

    # Check if old timer exists and is enabled
    OLD_TIMER_ENABLED=false
    if systemctl is-enabled tripwire-update.timer >/dev/null 2>&1; then
        OLD_TIMER_ENABLED=true
        echo "  Detected old tripwire-update.timer enabled, will migrate..."
    fi

    # Build Environment lines for systemd service
    ENV_LINES=""
    if [ -n "$EMAIL_TO" ]; then
        ENV_LINES="${ENV_LINES}Environment=\"EMAIL_TO=$EMAIL_TO\"\n"
    fi
    if [ -n "$AUTO_ACCEPT_THRESHOLD" ]; then
        ENV_LINES="${ENV_LINES}Environment=\"AUTO_ACCEPT_THRESHOLD=$AUTO_ACCEPT_THRESHOLD\"\n"
    fi

    # Create new systemd service
    SERVICE_CONTENT="[Unit]
Description=Bananapeel Tripwire Database Update
After=multi-user.target

[Service]
Type=oneshot
User=tripwire
ExecStart=/var/lib/tripwire-service/tripwire-auto-update.sh
StandardOutput=journal
StandardError=journal
PrivateTmp=yes
ProtectSystem=full
ProtectHome=read-only
RestrictNamespaces=yes
LockPersonality=yes
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX
${ENV_LINES}
[Install]
WantedBy=multi-user.target"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would create /etc/systemd/system/bananapeel-update.service with:"
        echo "$SERVICE_CONTENT"
    else
        echo "$SERVICE_CONTENT" > /etc/systemd/system/bananapeel-update.service
    fi

    # Create timer
    TIMER_CONTENT="[Unit]
Description=Daily Bananapeel Tripwire Database Update
Documentation=man:tripwire(8)

[Timer]
OnCalendar=*-*-* 06:25:00
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would create /etc/systemd/system/bananapeel-update.timer with:"
        echo "$TIMER_CONTENT"
    else
        echo "$TIMER_CONTENT" > /etc/systemd/system/bananapeel-update.timer

        # Reload systemd
        systemctl daemon-reload

        # Disable old timer if it was enabled
        if [ "$OLD_TIMER_ENABLED" = true ]; then
            echo "  Disabling old tripwire-update.timer..."
            systemctl disable tripwire-update.timer 2>/dev/null || true
            systemctl stop tripwire-update.timer 2>/dev/null || true
        fi

        # Enable new timer
        systemctl enable bananapeel-update.timer
        systemctl start bananapeel-update.timer

        echo "✓ Timer enabled and started"
        echo ""
        echo "Next scheduled run:"
        systemctl list-timers bananapeel-update.timer --no-pager
    fi
else
    echo
    echo "Step 6: Skipping systemd timer (--no-timer specified)"
fi

# Step 7: Install log rotation
echo
echo "Step 7: Setting up log rotation..."
echo "-----------------------------------"

# Configure log rotation (skip if already exists - likely from package install)
if [ -f /etc/logrotate.d/bananapeel ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would skip logrotate config (already exists)"
    else
        echo "✓ Log rotation already configured (skipping)"
    fi
else
    LOGROTATE_CONFIG="/etc/logrotate.d/bananapeel
/var/log/bananapeel-update.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 664 tripwire tripwire
}"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would create /etc/logrotate.d/bananapeel"
    else
        echo "$LOGROTATE_CONFIG" > /etc/logrotate.d/bananapeel
        echo "✓ Log rotation configured"
    fi
fi

# Final summary
echo
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo
echo "✓ Tripwire service account created"
echo "✓ Automation script deployed"
if [ "$WITH_WRAPPER" = true ]; then
    echo "✓ Security wrapper installed"
fi
if [ "$WITH_TIMER" = true ]; then
    echo "✓ Systemd timer enabled (daily at 6:25 AM)"
fi
if [ "$WITH_APT_HOOK" = true ]; then
    echo "✓ APT hook installed"
fi
echo "✓ Log rotation configured"

if [ -n "$EMAIL_TO" ] || [ -n "$AUTO_ACCEPT_THRESHOLD" ]; then
    echo ""
    echo "Custom configuration applied:"
    [ -n "$EMAIL_TO" ] && echo "  Email reports to: $EMAIL_TO"
    [ -n "$AUTO_ACCEPT_THRESHOLD" ] && echo "  Auto-accept threshold: $AUTO_ACCEPT_THRESHOLD"
fi

# Check for legacy artifacts and warn
if [ -e /etc/systemd/system/tripwire-*.timer ] || [ -e /etc/apt/apt.conf.d/99bananapeel ] || \
   [ -L /var/log/tripwire-apt-update.log ] || [ -L /usr/local/bin/bananapeel-update ]; then
    echo
    echo "⚠ WARNING: Legacy tripwire artifacts detected on this system."
    echo "  These legacy artifacts will be removed in v0.3.0."
    echo "  Run 'bananapeel-status' for migration instructions."
fi

echo
echo "Next steps:"
if [ "$DRY_RUN" = false ]; then
    if [ ! -f /var/lib/tripwire-service/.tripwire/local-passphrase ]; then
        echo "1. Set up passphrase: sudo /var/lib/tripwire-service/setup-passphrase.sh"
    fi
    echo "1. Test automation:  sudo -u tripwire /var/lib/tripwire-service/tripwire-auto-update.sh"
    if [ "$WITH_TIMER" = true ]; then
        echo "2. Check timer:      systemctl status bananapeel-update.timer"
    fi
    echo "3. View logs:        tail -f /var/log/bananapeel-update.log"
else
    echo "This was a dry run. No changes were made."
    echo "Remove --dry-run to perform actual installation."
fi

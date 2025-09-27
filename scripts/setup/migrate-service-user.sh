#!/bin/bash
# Service User Migration Script - Migrate from 'tripwire' to 'bananapeel' user
# Part of the Bananapeel Tripwire Management Suite
#
# This script safely migrates the service user from the legacy 'tripwire' name
# to the new 'bananapeel' name, updating ownership, sudoers, and systemd units.

set -e

# Configuration
SCRIPT_NAME="$(basename "$0")"
LEGACY_USER="tripwire"
NEW_USER="bananapeel"
LEGACY_GROUP="tripwire"
NEW_GROUP="bananapeel"
SERVICE_HOME="/var/lib/tripwire-service"
LOG_FILE="/var/log/bananapeel-update.log"
LOCK_DIR="/run/bananapeel"
WRAPPER_PATH="/usr/local/lib/bananapeel/tripwire-wrapper"
SUDOERS_FILE="/etc/sudoers.d/tripwire-service"
NEW_SUDOERS_FILE="/etc/sudoers.d/bananapeel-service"
SYSTEMD_SERVICE="/etc/systemd/system/bananapeel-update.service"
BACKUP_DIR="/var/backups/bananapeel-migration-$(date +%Y%m%d-%H%M%S)"

# Flags
DRY_RUN=false
FORCE=false
VERBOSE=false
ROLLBACK=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print usage
print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Migrate service user from 'tripwire' to 'bananapeel' for the Bananapeel suite.

OPTIONS:
    --dry-run     Show what would be done without making changes
    --force       Skip confirmation prompts
    --verbose     Show detailed output
    --rollback    Rollback a previous migration (requires backup directory)
    --help        Show this help message

EXAMPLES:
    # Preview migration
    sudo $SCRIPT_NAME --dry-run

    # Perform migration
    sudo $SCRIPT_NAME

    # Rollback migration
    sudo $SCRIPT_NAME --rollback /var/backups/bananapeel-migration-YYYYMMDD-HHMMSS

NOTES:
    - This script must be run as root
    - Services will be stopped during migration
    - A backup is created automatically
    - The legacy user's UID/GID are preserved

EOF
}

# Function to run command based on dry-run mode
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            if [ -z "${2:-}" ] || [[ "$2" == --* ]]; then
                print_error "--rollback requires a backup directory path"
                exit 1
            fi
            BACKUP_DIR="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]] && [ "$DRY_RUN" = false ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if legacy user exists
    if ! id "$LEGACY_USER" &>/dev/null; then
        print_warn "Legacy user '$LEGACY_USER' does not exist"
        if [ "$ROLLBACK" = false ]; then
            print_info "Nothing to migrate. You may want to run the installer instead."
            exit 0
        fi
    fi

    # Check if new user already exists (unless rollback)
    if [ "$ROLLBACK" = false ] && id "$NEW_USER" &>/dev/null; then
        print_warn "User '$NEW_USER' already exists"

        # Check if it has the same UID as legacy user
        if id "$LEGACY_USER" &>/dev/null; then
            LEGACY_UID=$(id -u "$LEGACY_USER")
            NEW_UID=$(id -u "$NEW_USER")

            if [ "$LEGACY_UID" = "$NEW_UID" ]; then
                print_info "Users have the same UID. Migration may have been partially completed."
            else
                print_error "Both users exist with different UIDs. Manual intervention required."
                exit 1
            fi
        fi
    fi

    # Check for running services
    if systemctl is-active --quiet bananapeel-update.timer 2>/dev/null; then
        print_warn "bananapeel-update.timer is active and will be stopped"
    fi

    if systemctl is-active --quiet bananapeel-update.service 2>/dev/null; then
        print_warn "bananapeel-update.service is running and will be stopped"
    fi
}

# Function to stop services
stop_services() {
    print_info "Stopping services..."

    run_cmd systemctl stop bananapeel-update.timer 2>/dev/null || true
    run_cmd systemctl stop bananapeel-update.service 2>/dev/null || true
    run_cmd systemctl stop tripwire-update.timer 2>/dev/null || true
    run_cmd systemctl stop tripwire-update.service 2>/dev/null || true

    # Kill any remaining tripwire processes
    if [ "$DRY_RUN" = false ]; then
        pkill -u "$LEGACY_USER" 2>/dev/null || true
    else
        echo "[DRY-RUN] Would execute: pkill -u $LEGACY_USER"
    fi
}

# Function to create backup
create_backup() {
    print_info "Creating backup at $BACKUP_DIR..."

    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$BACKUP_DIR"

        # Backup sudoers
        [ -f "$SUDOERS_FILE" ] && cp -p "$SUDOERS_FILE" "$BACKUP_DIR/"

        # Backup systemd service
        [ -f "$SYSTEMD_SERVICE" ] && cp -p "$SYSTEMD_SERVICE" "$BACKUP_DIR/"

        # Save current user/group info
        if id "$LEGACY_USER" &>/dev/null; then
            echo "LEGACY_UID=$(id -u $LEGACY_USER)" > "$BACKUP_DIR/user_info.txt"
            echo "LEGACY_GID=$(id -g $LEGACY_USER)" >> "$BACKUP_DIR/user_info.txt"
            echo "LEGACY_HOME=$(getent passwd $LEGACY_USER | cut -d: -f6)" >> "$BACKUP_DIR/user_info.txt"
        fi

        # Save file ownership info
        find "$SERVICE_HOME" -ls > "$BACKUP_DIR/file_ownership.txt" 2>/dev/null || true

        print_info "Backup created successfully"
    else
        echo "[DRY-RUN] Would create backup at $BACKUP_DIR"
    fi
}

# Function to migrate user
migrate_user() {
    print_info "Migrating user from '$LEGACY_USER' to '$NEW_USER'..."

    if ! id "$LEGACY_USER" &>/dev/null; then
        print_warn "Legacy user does not exist, creating new user '$NEW_USER'"
        run_cmd useradd -r -d "$SERVICE_HOME" -s /bin/bash "$NEW_USER"
        return
    fi

    # Get legacy user's UID and GID
    LEGACY_UID=$(id -u "$LEGACY_USER")
    LEGACY_GID=$(id -g "$LEGACY_USER")

    print_info "Legacy user UID: $LEGACY_UID, GID: $LEGACY_GID"

    # Method 1: Try to rename the user and group (cleanest approach)
    if command -v usermod &>/dev/null && [ "$DRY_RUN" = false ]; then
        print_info "Attempting to rename user..."

        # Rename group first
        if groupmod -n "$NEW_GROUP" "$LEGACY_GROUP" 2>/dev/null; then
            print_info "Group renamed successfully"
        else
            print_warn "Could not rename group, will create new one"
        fi

        # Rename user
        if usermod -l "$NEW_USER" "$LEGACY_USER" 2>/dev/null; then
            print_info "User renamed successfully"

            # Update home directory if needed
            if [ -d "/home/$LEGACY_USER" ]; then
                run_cmd usermod -d "/home/$NEW_USER" -m "$NEW_USER" 2>/dev/null || true
            fi
        else
            print_warn "Could not rename user, will use alternative method"

            # Method 2: Create new user with same UID/GID
            run_cmd groupadd -g "$LEGACY_GID" "$NEW_GROUP" 2>/dev/null || true
            run_cmd useradd -u "$LEGACY_UID" -g "$LEGACY_GID" -r -d "$SERVICE_HOME" -s /bin/bash "$NEW_USER"

            # Remove old user (after new one is created to preserve UID)
            run_cmd userdel "$LEGACY_USER" 2>/dev/null || true
        fi
    elif [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would attempt to rename user $LEGACY_USER to $NEW_USER"
        echo "[DRY-RUN] Would preserve UID: $LEGACY_UID and GID: $LEGACY_GID"
    fi
}

# Function to update file ownership
update_ownership() {
    print_info "Updating file ownership..."

    # Service home directory
    if [ -d "$SERVICE_HOME" ]; then
        run_cmd chown -R "$NEW_USER:$NEW_GROUP" "$SERVICE_HOME"
    fi

    # Log file
    if [ -f "$LOG_FILE" ]; then
        run_cmd chown "$NEW_USER:$NEW_GROUP" "$LOG_FILE"
    fi

    # Lock directory
    if [ -d "$LOCK_DIR" ]; then
        run_cmd chown "$NEW_USER:$NEW_GROUP" "$LOCK_DIR"
    fi

    # Wrapper (should remain root-owned)
    if [ -f "$WRAPPER_PATH" ]; then
        run_cmd chown root:root "$WRAPPER_PATH"
        run_cmd chmod 755 "$WRAPPER_PATH"
    fi
}

# Function to update sudoers
update_sudoers() {
    print_info "Updating sudoers configuration..."

    # Create new sudoers content
    SUDOERS_CONTENT="# Bananapeel service user sudo permissions
# Allows the service user to run tripwire commands via wrapper only

# Command alias for the wrapper
Cmnd_Alias BANANAPEEL_WRAPPER = $WRAPPER_PATH

# Allow bananapeel user to run wrapper without password
$NEW_USER ALL=(root) NOPASSWD: BANANAPEEL_WRAPPER
"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would write to $NEW_SUDOERS_FILE:"
        echo "$SUDOERS_CONTENT"
        echo "[DRY-RUN] Would remove $SUDOERS_FILE if it exists"
    else
        # Write new sudoers file
        echo "$SUDOERS_CONTENT" > "$NEW_SUDOERS_FILE"
        chmod 440 "$NEW_SUDOERS_FILE"

        # Validate sudoers syntax
        if visudo -c -f "$NEW_SUDOERS_FILE"; then
            print_info "Sudoers syntax valid"

            # Remove old sudoers file
            [ -f "$SUDOERS_FILE" ] && rm -f "$SUDOERS_FILE"
        else
            print_error "Sudoers syntax invalid! Reverting..."
            rm -f "$NEW_SUDOERS_FILE"
            exit 1
        fi
    fi
}

# Function to update systemd units
update_systemd_units() {
    print_info "Updating systemd units..."

    if [ -f "$SYSTEMD_SERVICE" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] Would update User= in $SYSTEMD_SERVICE"
        else
            # Update User= line in service file
            sed -i "s/^User=$LEGACY_USER$/User=$NEW_USER/" "$SYSTEMD_SERVICE" 2>/dev/null || \
            sed -i "s/^User=tripwire$/User=$NEW_USER/" "$SYSTEMD_SERVICE" 2>/dev/null || true

            # Reload systemd
            systemctl daemon-reload
        fi
    fi
}

# Function to perform rollback
perform_rollback() {
    print_info "Performing rollback from $BACKUP_DIR..."

    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi

    # Stop services
    stop_services

    # Restore sudoers
    if [ -f "$BACKUP_DIR/$(basename $SUDOERS_FILE)" ]; then
        run_cmd cp -p "$BACKUP_DIR/$(basename $SUDOERS_FILE)" "$SUDOERS_FILE"
        run_cmd rm -f "$NEW_SUDOERS_FILE"
    fi

    # Restore systemd service
    if [ -f "$BACKUP_DIR/$(basename $SYSTEMD_SERVICE)" ]; then
        run_cmd cp -p "$BACKUP_DIR/$(basename $SYSTEMD_SERVICE)" "$SYSTEMD_SERVICE"
        run_cmd systemctl daemon-reload
    fi

    # Restore user (complex - may need manual intervention)
    print_warn "User rollback may require manual intervention"
    print_info "To manually restore the user:"
    print_info "  1. Delete current user: userdel $NEW_USER"
    print_info "  2. Recreate legacy user with original UID/GID from $BACKUP_DIR/user_info.txt"
    print_info "  3. Restore file ownership based on $BACKUP_DIR/file_ownership.txt"
}

# Function for post-migration validation
validate_migration() {
    print_info "Validating migration..."

    local ERRORS=0

    # Check new user exists
    if ! id "$NEW_USER" &>/dev/null; then
        print_error "New user '$NEW_USER' does not exist"
        ((ERRORS++))
    else
        print_info "✓ User '$NEW_USER' exists"
    fi

    # Check sudoers
    if [ -f "$NEW_SUDOERS_FILE" ]; then
        print_info "✓ Sudoers file exists"
    else
        print_error "Sudoers file missing: $NEW_SUDOERS_FILE"
        ((ERRORS++))
    fi

    # Check ownership of service home
    if [ -d "$SERVICE_HOME" ]; then
        OWNER=$(stat -c %U "$SERVICE_HOME" 2>/dev/null || stat -f %Su "$SERVICE_HOME" 2>/dev/null)
        if [ "$OWNER" = "$NEW_USER" ]; then
            print_info "✓ Service home ownership correct"
        else
            print_error "Service home owned by '$OWNER', expected '$NEW_USER'"
            ((ERRORS++))
        fi
    fi

    # Check systemd service
    if [ -f "$SYSTEMD_SERVICE" ]; then
        if grep -q "^User=$NEW_USER$" "$SYSTEMD_SERVICE"; then
            print_info "✓ Systemd service updated"
        else
            print_warn "Systemd service may need manual update"
        fi
    fi

    if [ $ERRORS -eq 0 ]; then
        print_info "✅ Migration validated successfully"
        return 0
    else
        print_error "❌ Migration validation failed with $ERRORS errors"
        return 1
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "Service User Migration Tool"
    echo "========================================="
    echo

    if [ "$ROLLBACK" = true ]; then
        print_info "Rollback mode activated"
        perform_rollback
        exit 0
    fi

    # Pre-flight checks
    check_prerequisites

    if [ "$DRY_RUN" = true ]; then
        print_info "Running in DRY-RUN mode - no changes will be made"
    fi

    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo
        print_warn "This will migrate the service user from '$LEGACY_USER' to '$NEW_USER'"
        print_warn "Services will be stopped during migration"
        read -p "Do you want to continue? (y/N): " -r CONFIRM
        if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
            print_info "Migration cancelled"
            exit 0
        fi
    fi

    # Stop services
    stop_services

    # Create backup (unless dry-run)
    create_backup

    # Perform migration steps
    migrate_user
    update_ownership
    update_sudoers
    update_systemd_units

    # Validate migration
    if [ "$DRY_RUN" = false ]; then
        echo
        validate_migration || {
            print_error "Migration validation failed!"
            print_info "Backup available at: $BACKUP_DIR"
            print_info "To rollback: $SCRIPT_NAME --rollback $BACKUP_DIR"
            exit 1
        }
    fi

    # Success message
    echo
    print_info "========================================="
    if [ "$DRY_RUN" = true ]; then
        print_info "Dry-run completed successfully"
        print_info "Run without --dry-run to perform actual migration"
    else
        print_info "Migration completed successfully!"
        print_info "Backup saved at: $BACKUP_DIR"
        print_info ""
        print_info "Next steps:"
        print_info "1. Start services: sudo systemctl start bananapeel-update.timer"
        print_info "2. Test automation: sudo -u $NEW_USER /var/lib/tripwire-service/tripwire-auto-update.sh"
        print_info "3. Monitor logs: tail -f $LOG_FILE"
        print_info ""
        print_info "To rollback if needed: $SCRIPT_NAME --rollback $BACKUP_DIR"
    fi
    print_info "========================================="
}

# Run main function
main "$@"
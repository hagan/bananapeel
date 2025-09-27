#!/bin/bash
# Tripwire automated check and update script
# Runs daily at 6:25 AM via systemd timer or on-demand
# Configurable via environment variables

set -euo pipefail

# Try to source shared library (optional)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _bp_lib in "$SCRIPT_DIR/../lib/bananapeel-lib.sh" \
               "/usr/share/bananapeel/bananapeel-lib.sh"; do
    if [ -r "$_bp_lib" ]; then
        # shellcheck source=/dev/null
        . "$_bp_lib" || true
        break
    fi
done

# Allow test override of critical paths
LOGFILE="${LOGFILE:-/var/log/bananapeel-update.log}"
LOCKFILE="${LOCK_FILE:-/run/bananapeel/update.lock}"

# Ensure lock directory exists
LOCK_DIR=$(dirname "$LOCKFILE")
[ -d "$LOCK_DIR" ] || mkdir -p "$LOCK_DIR" 2>/dev/null || true

# Prevent concurrent runs (avoids duplicate emails/updates)
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Another bananapeel run is active; exiting" >> "$LOGFILE" || true
    exit 0
fi

# Default configuration values
DEFAULT_EMAIL_TO="root"
DEFAULT_THRESHOLD="50"
DEFAULT_DRY_RUN="0"

# Source configuration file if it exists
CONFIG_FILE="/etc/bananapeel/bananapeel.conf"
if [ -r "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Configuration precedence:
# 1. Environment variables (EMAIL_TO, AUTO_ACCEPT_THRESHOLD, DRY_RUN) - highest priority
# 2. Config file variables (BANANAPEEL_EMAIL_TO, BANANAPEEL_THRESHOLD, BANANAPEEL_DRY_RUN)
# 3. Built-in defaults (DEFAULT_*) - lowest priority
# Note: LOGFILE is already defined above for early use
EMAIL_TO="${EMAIL_TO:-${BANANAPEEL_EMAIL_TO:-$DEFAULT_EMAIL_TO}}"
AUTO_ACCEPT_THRESHOLD="${AUTO_ACCEPT_THRESHOLD:-${BANANAPEEL_THRESHOLD:-$DEFAULT_THRESHOLD}}"
DRY_RUN="${DRY_RUN:-${BANANAPEEL_DRY_RUN:-$DEFAULT_DRY_RUN}}"

# Optional automation (if passphrase storage is configured)
PASSPHRASE_FILE="/var/lib/tripwire-service/.tripwire/local-passphrase"
MACHINE_KEY=$(sha256sum </etc/machine-id | cut -d' ' -f1)

# Function to escape JSON strings safely (if not provided by library)
if ! declare -F json_escape >/dev/null 2>&1; then
    json_escape() {
        # Escapes backslashes, double quotes, and newlines/carriage returns
        local s
        s=${1//\\/\\\\}
        s=${s//\"/\\\"}
        s=${s//$'\n'/ }
        s=${s//$'\r'/ }
        printf '%s' "$s"
    }
fi

# Function to log messages (tolerates missing logger/syslog)
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
    if command -v logger >/dev/null 2>&1; then
        logger -t bananapeel "$1" || true
    fi
}

# Detect mail transport (prefer PATH to allow test mocks)
MAIL_MODE="none"
SENDMAIL_CMD=""
if command -v sendmail >/dev/null 2>&1; then
    MAIL_MODE="sendmail"; SENDMAIL_CMD="$(command -v sendmail)"
elif command -v mail >/dev/null 2>&1; then
    MAIL_MODE="mail"
fi

# Helper to send a report email
send_report() {
    local status="$1"
    local summary_body="$2"
    local sample_body="$3"
    local action_text="$4"
    local latest_twr="$5"

    local subject
    subject="Bananapeel Tripwire Report - $(hostname) [$status]"

    if [ "$MAIL_MODE" = "sendmail" ]; then
        # Compose email with proper headers
        local email_content
        email_content=$(
            echo "Subject: $subject"
            echo "From: tripwire@$(hostname)"
            echo "To: $EMAIL_TO"
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo "Tripwire Integrity Check Report"
            echo "========================================="
            echo ""
            echo "Date: $(date)"
            echo "Host: $(hostname)"
            echo "Status: $status"
            echo ""
            if [ -n "$latest_twr" ]; then echo "Report file: $latest_twr"; fi
            [ -n "$action_text" ] && {
                echo ""
                echo "========================================="
                echo "ACTION REQUIRED:"
                echo "========================================="
                echo ""; echo "$action_text"; }
            [ -n "$summary_body" ] && {
                echo ""; echo "========================================="
                echo "VIOLATION SUMMARY:"; echo "========================================="
                echo "$summary_body"; }
            [ -n "$sample_body" ] && {
                echo ""; echo "========================================="
                echo "SAMPLE OF CHANGES:"; echo "========================================="
                echo "$sample_body"; }
            echo ""; echo "View recent logs:"; echo "  tail -20 /var/log/bananapeel-update.log"
        )

        # Debug: log the email if requested
        if [ "${BANANAPEEL_DEBUG_EMAIL:-0}" = "1" ]; then
            log_message "DEBUG: Email preview (first 10 lines):"
            echo "$email_content" | head -10 >> "$LOGFILE"
        fi

        # Send the email
        if ! echo "$email_content" | "$SENDMAIL_CMD" -t; then
            log_message "Email send failed via $SENDMAIL_CMD"
        fi
    elif [ "$MAIL_MODE" = "mail" ]; then
        if ! {
            echo "Tripwire Integrity Check Report"
            echo "Date: $(date)"; echo "Host: $(hostname)"; echo "Status: $status"
            if [ -n "$latest_twr" ]; then echo "Report file: $latest_twr"; fi
            [ -n "$action_text" ] && { echo ""; echo "$action_text"; }
            [ -n "$summary_body" ] && { echo ""; echo "$summary_body"; }
            [ -n "$sample_body" ] && { echo ""; echo "$sample_body"; }
        } | mail -s "$subject" "$EMAIL_TO"; then
            log_message "Email send failed via mail(1)"
        fi
    else
        log_message "No mail transport available; skipping email to $EMAIL_TO"
    fi
}

# Start scheduled check
log_message "Starting scheduled tripwire check"

# Run tripwire check with quiet and email-report (like old cron job)
TEMP_REPORT=$(mktemp)
trap 'rm -f "$TEMP_REPORT"' EXIT

log_message "Running integrity check..."

# Run the check and capture result (using wrapper for security)
# Use tee to avoid sudo/redirect lint issue and always continue
# Note: we explicitly capture and ignore errors for testing compatibility
{ sudo /usr/local/lib/bananapeel/tripwire-wrapper check --quiet --email-report 2>&1 || true; } | tee "$TEMP_REPORT" >/dev/null

# Get the latest report file that was just generated
# Note: We use a subshell to avoid pipefail issues with head closing the pipe early
LATEST_TWR=$( (find /var/lib/tripwire/report -maxdepth 1 -type f -name '*.twr' -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null | head -1) || echo "")
log_message "Generated report: $LATEST_TWR"

# Extract violation count
VIOLATIONS=$(grep "Total violations found:" "$TEMP_REPORT" 2>/dev/null | awk '{print $NF}' || echo "0")
log_message "Violations found: $VIOLATIONS"

# If no violations, we're done
if [ "$VIOLATIONS" -eq 0 ]; then
    log_message "No violations found - database is current"

    # Still send a summary email for consistency
    send_report "OK" "" "" "" "$LATEST_TWR"

    # Emit JSON summary for observability
    TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    HOSTNAME=$(hostname)
    STATUS="OK"
    SYS_CHANGES=0
    HOST_ESC=$(json_escape "$HOSTNAME")
    STATUS_ESC=$(json_escape "$STATUS")
    LATEST_ESC=$(json_escape "$LATEST_TWR")
    # JSON schema documented in README.md "JSON Schemas" section
    SUMMARY_JSON=$(printf '{"ts":"%s","host":"%s","violations":%s,"sys_changes":%s,"status":"%s","latest_twr":"%s"}' \
        "$TIMESTAMP" "$HOST_ESC" "$VIOLATIONS" "$SYS_CHANGES" "$STATUS_ESC" "$LATEST_ESC")
    echo "SUMMARY_JSON=$SUMMARY_JSON" >> "$LOGFILE"

    exit 0
fi

# We have violations - determine what to do
log_message "Processing $VIOLATIONS violations"

# Check if these look like package updates (many system files)
# Use grep -c but ensure we only get one value
SYS_CHANGES=$(grep -cE "(/usr/|/lib|/bin|/sbin)" "$TEMP_REPORT" 2>/dev/null) || SYS_CHANGES=0
log_message "System file changes: $SYS_CHANGES"

# Optional auto-accept for large system updates
AUTO_ACCEPTED=0
if [ "$AUTO_ACCEPT_THRESHOLD" -gt 0 ] && [ "$SYS_CHANGES" -gt "$AUTO_ACCEPT_THRESHOLD" ]; then
    log_message "Large system update detected (> $AUTO_ACCEPT_THRESHOLD). Considering auto-accept..."

    if [ "$DRY_RUN" = "1" ]; then
        log_message "DRY_RUN mode - skipping auto-accept"
    elif [ ! -f "$PASSPHRASE_FILE" ]; then
        log_message "No stored passphrase - skipping auto-accept"
    else
        # Decrypt passphrase and run expect to automate update
        PASSPHRASE=$(openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:"$MACHINE_KEY" 2>/dev/null < "$PASSPHRASE_FILE" || true)
        if [ -n "$PASSPHRASE" ]; then
            cat > /tmp/tw-update.$$.exp << 'EXPECT'
#!/usr/bin/expect -f
set timeout 180
set passphrase [lindex $argv 0]

spawn sudo /usr/local/lib/bananapeel/tripwire-wrapper update --twrfile [lindex $argv 1] --accept-all

expect {
    -re ".*local passphrase.*:" {
        send "$passphrase\r"
        exp_continue
    }
    eof
}
wait
EXPECT
            chmod 700 /tmp/tw-update.$$.exp
            if /tmp/tw-update.$$.exp "$PASSPHRASE" "$LATEST_TWR" >> "$LOGFILE" 2>&1; then
                AUTO_ACCEPTED=1
                log_message "Auto-accepted changes for $LATEST_TWR"
            else
                log_message "Auto-accept encountered issues; see log"
            fi
            rm -f /tmp/tw-update.$$.exp
        else
            log_message "Passphrase decryption failed; skipping auto-accept"
        fi
    fi
fi

# Determine status and action
if [ "$AUTO_ACCEPTED" -eq 1 ]; then
    STATUS="PACKAGE UPDATES AUTO-ACCEPTED"
    ACTION="Changes were auto-accepted due to large system update (>$AUTO_ACCEPT_THRESHOLD files). Review report if needed.

View full report:
  sudo twprint --print-report --twrfile $LATEST_TWR"
elif [ "$SYS_CHANGES" -gt 0 ]; then
    STATUS="PACKAGE UPDATES DETECTED"
    ACTION="Large system changes detected (likely package updates).

To accept ALL changes automatically:
  sudo tripwire --update --twrfile $LATEST_TWR --accept-all

To review changes interactively:
  sudo tripwire --update --twrfile $LATEST_TWR"
else
    STATUS="MANUAL REVIEW REQUIRED"
    ACTION="Minor changes detected. Please review carefully.

To review changes interactively:
  sudo tripwire --update --twrfile $LATEST_TWR

To accept ALL changes (use with caution):
  sudo tripwire --update --twrfile $LATEST_TWR --accept-all"
fi

# Extract summary information for email
SUMMARY=$(grep -A 20 "Rule Summary:" "$TEMP_REPORT" 2>/dev/null || echo "Unable to extract summary")

# Extract sample changes from the actual .twr file using twprint via wrapper
# This provides more reliable detail than the temp report
SAMPLE_CHANGES=""
if [ -n "$LATEST_TWR" ]; then
    SAMPLE_CHANGES="$(
        sudo /usr/local/lib/bananapeel/tripwire-wrapper print --print-report --twrfile "$LATEST_TWR" 2>/dev/null | \
        awk '
            /^(Added:|Modified:|Removed:)/ { print; insec=1; seccount=0; total++; next }
            insec && NF { print; seccount++; total++; if (seccount>=20) { insec=0 } }
            insec && NF == 0 { insec=0 }
        ' | sed -n '1,60p'
    )"

    # Log extraction result for troubleshooting
    SAMPLE_LINES=$(echo "$SAMPLE_CHANGES" | wc -l | tr -d ' ')
    [ -n "$SAMPLE_CHANGES" ] && log_message "Extracted $SAMPLE_LINES sample lines from $LATEST_TWR"
fi

# Fallback if no sample extracted
[ -z "$SAMPLE_CHANGES" ] && SAMPLE_CHANGES="No sample available (see full report: sudo twprint --print-report --twrfile $LATEST_TWR)"

# Send detailed email report
send_report "$STATUS" "$SUMMARY" "$SAMPLE_CHANGES" "$ACTION" "$LATEST_TWR"

log_message "Email report sent to $EMAIL_TO"
log_message "Daily check completed with $VIOLATIONS violations"

# Add deprecation warning for legacy artifacts (v0.3.0 removal)
# Check once daily if any legacy artifacts exist
if compgen -G "/etc/systemd/system/tripwire-*.timer" >/dev/null 2>&1 || \
   [ -f /etc/apt/apt.conf.d/99bananapeel ] || [ -f /etc/apt/apt.conf.d/99tripwire ] || \
   [ -L /var/log/tripwire-apt-update.log ] || [ -L /usr/local/bin/tripwire-status ]; then
    log_message "WARNING: Legacy tripwire artifacts detected. These will be removed in v0.3.0. Run 'bananapeel-status' for migration details."
fi

# Emit JSON summary for observability (schema documented in README.md "JSON Schemas" section)
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
HOSTNAME=$(hostname)
HOST_ESC=$(json_escape "$HOSTNAME")
STATUS_ESC=$(json_escape "$STATUS")
LATEST_ESC=$(json_escape "$LATEST_TWR")
SUMMARY_JSON=$(printf '{"ts":"%s","host":"%s","violations":%s,"sys_changes":%s,"status":"%s","latest_twr":"%s"}' \
    "$TIMESTAMP" "$HOST_ESC" "$VIOLATIONS" "$SYS_CHANGES" "$STATUS_ESC" "$LATEST_ESC")
echo "SUMMARY_JSON=$SUMMARY_JSON" >> "$LOGFILE"

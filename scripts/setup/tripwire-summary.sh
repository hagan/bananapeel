#!/bin/bash
# Tripwire Configuration Summary and Status
# Supports --json flag for machine-readable output
# Supports --check-only for exit code only
# Supports --since <duration> for time-based summaries

# Parse command line arguments
JSON_MODE=false
CHECK_ONLY=false
SINCE_TIME=""
DATE_FALLBACK_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --since)
            if [ -z "${2:-}" ]; then
                echo "Error: --since requires a time argument (e.g., 24h, 7d, 2025-09-28T00:00:00Z)" >&2
                exit 2
            fi
            SINCE_TIME="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --json        Output in JSON format
  --check-only  Exit with status code only (no output)
  --since TIME  Summarize runs since TIME (24h, 7d, or RFC3339 timestamp)
  --help        Show this help message

Exit codes:
  0 - OK or PACKAGE UPDATES AUTO-ACCEPTED (system secure)
  1 - PACKAGE UPDATES DETECTED or MANUAL REVIEW REQUIRED (attention needed)
  2 - Error or unknown status

Examples:
  $(basename "$0")                    # Human-readable status
  $(basename "$0") --json             # JSON output with exit code
  $(basename "$0") --check-only       # Exit code only
  $(basename "$0") --since 24h        # Summary of last 24 hours
  $(basename "$0") --since 7d --json  # JSON summary of last 7 days
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 2
            ;;
    esac
done

# Function to extract last JSON summary from log
get_json_summary() {
    local log_file="${LOGFILE:-/var/log/bananapeel-update.log}"
    if [ ! -f "$log_file" ]; then
        # Try legacy log path
        log_file="/var/log/tripwire-apt-update.log"
    fi

    if [ -f "$log_file" ]; then
        # Get the last SUMMARY_JSON line
        local summary_line
        summary_line=$(grep "^SUMMARY_JSON=" "$log_file" 2>/dev/null | tail -1)
        if [ -n "$summary_line" ]; then
            # Strip the SUMMARY_JSON= prefix and return the JSON
            echo "${summary_line#SUMMARY_JSON=}"
            return 0
        fi
    fi
    return 1
}

# Function to determine exit code from status
get_exit_code() {
    local status="$1"
    case "$status" in
        "OK"|"PACKAGE UPDATES AUTO-ACCEPTED")
            echo 0
            ;;
        "PACKAGE UPDATES DETECTED"|"MANUAL REVIEW REQUIRED")
            echo 1
            ;;
        *)
            echo 2
            ;;
    esac
}

# Function to parse duration into seconds ago
parse_duration_to_timestamp() {
    local duration="$1"

    # Check if it's already an RFC3339 timestamp
    if [[ "$duration" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        echo "$duration"
        return 0
    fi

    # Parse relative durations
    local seconds=0
    case "$duration" in
        [0-9]*h)
            seconds=$((${duration%h} * 3600))
            ;;
        [0-9]*d)
            seconds=$((${duration%d} * 86400))
            ;;
        [0-9]*m)
            seconds=$((${duration%m} * 60))
            ;;
        *)
            echo "Error: Invalid duration format '$duration'. Use Nh, Nd, Nm, or RFC3339 timestamp" >&2
            return 1
            ;;
    esac

    # Calculate timestamp
    # Try GNU date first
    if date -d "1 hour ago" >/dev/null 2>&1; then
        # GNU date
        date -d "$seconds seconds ago" --rfc-3339=seconds 2>/dev/null | sed 's/ /T/'
    elif date -v-1H >/dev/null 2>&1; then
        # BSD date
        date -v-${seconds}S +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null
    else
        # Fallback: unable to compute absolute timestamp
        DATE_FALLBACK_MODE=true
        echo "FALLBACK"
    fi
}

# Function to get summaries since a given time
get_summaries_since() {
    local since_time="$1"
    local log_file="${LOGFILE:-/var/log/bananapeel-update.log}"

    if [ ! -f "$log_file" ]; then
        log_file="/var/log/tripwire-apt-update.log"
    fi

    if [ ! -f "$log_file" ]; then
        return 1
    fi

    # Extract all SUMMARY_JSON lines
    if [ "$DATE_FALLBACK_MODE" = true ] || [ "$since_time" = "FALLBACK" ]; then
        # No reliable time filtering available; return all summaries
        grep "^SUMMARY_JSON=" "$log_file" 2>/dev/null | sed 's/^SUMMARY_JSON=//'
        return 0
    fi

    grep "^SUMMARY_JSON=" "$log_file" 2>/dev/null | while read -r line; do
        local json="${line#SUMMARY_JSON=}"

        # Extract timestamp from JSON
        local ts=""
        if command -v jq >/dev/null 2>&1; then
            ts=$(echo "$json" | jq -r '.ts // empty' 2>/dev/null)
        else
            # Fallback parsing
            ts=$(echo "$json" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
        fi

        # Compare timestamps
        if [ -n "$ts" ]; then
            # Simple string comparison works for RFC3339
            if [[ "$ts" > "$since_time" ]] || [[ "$ts" == "$since_time" ]]; then
                echo "$json"
            fi
        fi
    done
}

# Function to summarize status counts (JSON schema documented in README.md "JSON Schemas" section)
summarize_statuses() {
    local json_lines="$1"
    local output_json="$2"

    if [ -z "$json_lines" ]; then
        if [ "$output_json" = true ]; then
            echo '{"error":"No data in specified time range","count":0}'
        else
            echo "No runs found in the specified time range"
        fi
        return
    fi

    # Count statuses
    local count_ok=0
    local count_auto_accepted=0
    local count_package_detected=0
    local count_manual_review=0
    local count_error=0
    local latest_ts=""
    local total=0

    while IFS= read -r json; do
        [ -z "$json" ] && continue
        ((total++))

        local status ts
        if command -v jq >/dev/null 2>&1; then
            status=$(echo "$json" | jq -r '.status // empty' 2>/dev/null)
            ts=$(echo "$json" | jq -r '.ts // empty' 2>/dev/null)
        else
            status=$(echo "$json" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            ts=$(echo "$json" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
        fi

        # Update latest timestamp
        if [ -z "$latest_ts" ] || [[ "$ts" > "$latest_ts" ]]; then
            latest_ts="$ts"
        fi

        # Count by status
        case "$status" in
            "OK")
                ((count_ok++))
                ;;
            "PACKAGE UPDATES AUTO-ACCEPTED")
                ((count_auto_accepted++))
                ;;
            "PACKAGE UPDATES DETECTED")
                ((count_package_detected++))
                ;;
            "MANUAL REVIEW REQUIRED")
                ((count_manual_review++))
                ;;
            *)
                ((count_error++))
                ;;
        esac
    done <<< "$json_lines"

    if [ "$output_json" = true ]; then
        # Output as JSON
        if [ "$DATE_FALLBACK_MODE" = true ]; then
            NOTE=",\"note\":\"Limited date support; showing all runs (no time filtering)\""
        else
            NOTE=""
        fi

        cat <<EOF
{
  "since": "$SINCE_TIME",
  "total": $total,
  "counts": {
    "OK": $count_ok,
    "PACKAGE_UPDATES_AUTO_ACCEPTED": $count_auto_accepted,
    "PACKAGE_UPDATES_DETECTED": $count_package_detected,
    "MANUAL_REVIEW_REQUIRED": $count_manual_review,
    "ERROR": $count_error
  },
  "counts_raw": {
    "OK": $count_ok,
    "PACKAGE UPDATES AUTO-ACCEPTED": $count_auto_accepted,
    "PACKAGE UPDATES DETECTED": $count_package_detected,
    "MANUAL REVIEW REQUIRED": $count_manual_review,
    "ERROR": $count_error
  },
  "latest_timestamp": "$latest_ts"
${NOTE:+$NOTE}
}
EOF
    else
        # Human-readable output
        if [ "$DATE_FALLBACK_MODE" = true ]; then
            echo "Summary (no time filtering; limited date support):"
        else
            echo "Summary since $SINCE_TIME:"
        fi
        echo "  Total runs: $total"
        echo "  Status breakdown:"
        [ $count_ok -gt 0 ] && echo "    OK: $count_ok"
        [ $count_auto_accepted -gt 0 ] && echo "    PACKAGE UPDATES AUTO-ACCEPTED: $count_auto_accepted"
        [ $count_package_detected -gt 0 ] && echo "    PACKAGE UPDATES DETECTED: $count_package_detected"
        [ $count_manual_review -gt 0 ] && echo "    MANUAL REVIEW REQUIRED: $count_manual_review"
        [ $count_error -gt 0 ] && echo "    ERROR/UNKNOWN: $count_error"
        [ -n "$latest_ts" ] && echo "  Latest run: $latest_ts"
        if [ "$DATE_FALLBACK_MODE" = true ]; then
            echo "  Note: Limited date support; showing all runs"
        fi
    fi
}

# Handle --check-only mode
if [ "$CHECK_ONLY" = true ]; then
    if JSON_SUMMARY=$(get_json_summary) && [ -n "$JSON_SUMMARY" ]; then
        # Extract status for exit code
        if command -v jq >/dev/null 2>&1; then
            STATUS=$(echo "$JSON_SUMMARY" | jq -r '.status // empty')
        else
            STATUS=$(echo "$JSON_SUMMARY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        fi
        EXIT_CODE=$(get_exit_code "$STATUS")
        exit "$EXIT_CODE"
    else
        # No summary found - error status
        exit 2
    fi
fi

# Handle --since mode
if [ -n "$SINCE_TIME" ]; then
    # Parse the duration to timestamp
    SINCE_TIMESTAMP=$(parse_duration_to_timestamp "$SINCE_TIME")
    if [ $? -ne 0 ] || [ -z "$SINCE_TIMESTAMP" ]; then
        echo "Error: Failed to parse time specification '$SINCE_TIME'" >&2
        exit 2
    fi

    # Get summaries since the timestamp
    SUMMARIES=$(get_summaries_since "$SINCE_TIMESTAMP")

    # Summarize and output
    summarize_statuses "$SUMMARIES" "$JSON_MODE"

    # Exit with status of most recent run if available
    if [ -n "$SUMMARIES" ]; then
        LAST_JSON=$(echo "$SUMMARIES" | tail -1)
        if command -v jq >/dev/null 2>&1; then
            STATUS=$(echo "$LAST_JSON" | jq -r '.status // empty')
        else
            STATUS=$(echo "$LAST_JSON" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        fi
        EXIT_CODE=$(get_exit_code "$STATUS")
        exit "$EXIT_CODE"
    else
        exit 0
    fi
fi

# Handle JSON mode (existing functionality)
if [ "$JSON_MODE" = true ]; then
    if JSON_SUMMARY=$(get_json_summary) && [ -n "$JSON_SUMMARY" ]; then
        echo "$JSON_SUMMARY"
        # Extract status from JSON for exit code
        if command -v jq >/dev/null 2>&1; then
            STATUS=$(echo "$JSON_SUMMARY" | jq -r '.status // empty')
        else
            STATUS=$(echo "$JSON_SUMMARY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        fi
        EXIT_CODE=$(get_exit_code "$STATUS")
        exit "$EXIT_CODE"
    else
        # No summary found - return empty JSON with error status
        echo '{"error":"No summary available"}'
        exit 2
    fi
fi

# Function to check for legacy artifacts
check_legacy_artifacts() {
    local found_legacy=false
    local legacy_items=()

    # Check for legacy timer
    if systemctl list-unit-files tripwire-update.timer >/dev/null 2>&1; then
        legacy_items+=("tripwire-update.timer (systemd timer)")
        found_legacy=true
    fi

    # Check for legacy/deprecated APT hooks (both names are deprecated)
    if [ -f /etc/apt/apt.conf.d/99tripwire ]; then
        legacy_items+=("/etc/apt/apt.conf.d/99tripwire (APT hook)")
        found_legacy=true
    fi
    if [ -f /etc/apt/apt.conf.d/99bananapeel ]; then
        legacy_items+=("/etc/apt/apt.conf.d/99bananapeel (APT hook)")
        found_legacy=true
    fi

    # Check for legacy log symlink
    if [ -L /var/log/tripwire-apt-update.log ]; then
        legacy_items+=("/var/log/tripwire-apt-update.log (log symlink)")
        found_legacy=true
    fi

    # Check for legacy status command
    if [ -L /usr/local/bin/tripwire-status ] || [ -f /usr/local/bin/tripwire-status ]; then
        legacy_items+=("/usr/local/bin/tripwire-status (command symlink)")
        found_legacy=true
    fi

    if [ "$found_legacy" = true ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  DEPRECATION WARNING - Action Required Before v0.3.0"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  The following legacy artifacts were found:"
        for item in "${legacy_items[@]}"; do
            echo "    • $item"
        done
        echo ""
        echo "  These will be REMOVED in v0.3.0. Migrate now:"
        echo ""
        echo "  Migration commands:"
        echo "    sudo systemctl disable --now tripwire-update.timer 2>/dev/null"
        echo "    sudo rm -f /etc/apt/apt.conf.d/99tripwire"
        echo "    sudo rm -f /var/log/tripwire-apt-update.log"
        echo "    sudo rm -f /usr/local/bin/tripwire-status"
        echo "    sudo systemctl daemon-reload"
        echo ""
        echo "  New names:"
        echo "    • bananapeel-update.timer (systemd timer)"
        echo "    • bananapeel-status (status command)"
        echo "    • /etc/apt/apt.conf.d/99bananapeel (APT hook)"
        echo "    • /var/log/bananapeel-update.log (log file)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi
}

# Default mode - human readable output (existing functionality)
echo "========================================="
echo "     Tripwire Configuration Summary"
echo "========================================="
echo

# Check for legacy artifacts first
check_legacy_artifacts

# Check policy status
echo "📋 Policy Status:"
if [ -f /etc/tripwire/twpol.txt ]; then
    EXCLUSIONS=$(grep -c "^[[:space:]]*!" /etc/tripwire/twpol.txt 2>/dev/null || echo 0)
    echo "  ✓ Policy file exists with $EXCLUSIONS exclusions"

    # Check for our optimizations
    if grep -q "EXCLUSIONS ADDED TO REDUCE NOISE" /etc/tripwire/twpol.txt 2>/dev/null; then
        echo "  ✓ Noise reduction exclusions have been applied"
    else
        echo "  ⚠ Noise reduction exclusions not yet applied"
    fi
else
    echo "  ✗ Policy file not found"
fi

echo
echo "🔒 Database Status:"
# Get latest DB file using find instead of ls
DB_FILE=$(find /var/lib/tripwire -maxdepth 1 -type f -name '*.twd' -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null | head -1)
if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    DB_AGE=$(( ($(date +%s) - $(stat -c %Y "$DB_FILE")) / 60 ))
    echo "  ✓ Database exists (last updated: $DB_AGE minutes ago)"
else
    echo "  ✗ Database not initialized"
fi

echo
echo "👤 Service Account:"
if id tripwire >/dev/null 2>&1; then
    echo "  ✓ 'tripwire' service user exists"

    if [ -f /etc/sudoers.d/tripwire-service ]; then
        echo "  ✓ Sudo rules configured"
    else
        echo "  ✗ Sudo rules not found"
    fi

    if [ -f /var/lib/tripwire-service/.tripwire/local-passphrase ]; then
        echo "  ✓ Encrypted passphrase configured"
    else
        echo "  ⚠ Passphrase not configured for automation"
    fi
else
    echo "  ✗ Service account not created"
fi

echo
echo "🔧 Automation:"
if [ -f /etc/apt/apt.conf.d/99bananapeel ]; then
    echo "  ✓ APT hook installed (99bananapeel)"
elif [ -f /etc/apt/apt.conf.d/99tripwire ]; then
    echo "  ⚠ Legacy APT hook installed (99tripwire) - please update"
else
    echo "  ✗ APT hook not installed"
fi

if [ -f /var/lib/tripwire-service/tripwire-auto-update.sh ]; then
    echo "  ✓ Auto-update script exists"
else
    echo "  ✗ Auto-update script not found"
fi

if systemctl is-enabled bananapeel-update.timer >/dev/null 2>&1; then
    echo "  ✓ Systemd timer enabled (bananapeel-update.timer)"
    NEXT_RUN=$(systemctl status bananapeel-update.timer 2>/dev/null | grep "Trigger:" | sed 's/.*Trigger: //')
    if [ -n "$NEXT_RUN" ]; then
        echo "    Next run: $NEXT_RUN"
    fi
elif systemctl is-enabled tripwire-update.timer >/dev/null 2>&1; then
    echo "  ⚠ Legacy timer enabled (tripwire-update.timer) - please migrate"
    NEXT_RUN=$(systemctl status tripwire-update.timer 2>/dev/null | grep "Trigger:" | sed 's/.*Trigger: //')
    if [ -n "$NEXT_RUN" ]; then
        echo "    Next run: $NEXT_RUN"
    fi
else
    echo "  - Systemd timer not configured"
fi

echo
echo "📊 Recent Activity:"
LOG_FILE=""
# Allow environment override for testing
if [ -n "${LOGFILE:-}" ] && [ -f "$LOGFILE" ]; then
    LOG_FILE="$LOGFILE"
elif [ -f /var/log/bananapeel-update.log ]; then
    LOG_FILE="/var/log/bananapeel-update.log"
elif [ -f /var/log/tripwire-apt-update.log ]; then
    LOG_FILE="/var/log/tripwire-apt-update.log"
    echo "  ⚠ Using legacy log path - please update"
fi

if [ -n "$LOG_FILE" ]; then
    LAST_RUN=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | tail -1)
    if [ -n "$LAST_RUN" ]; then
        echo "  Last run today: $LAST_RUN"
    else
        echo "  No runs today"
    fi

    VIOLATIONS=$(grep "violations to update" "$LOG_FILE" | tail -1 | awk '{print $2}')
    if [ -n "$VIOLATIONS" ]; then
        echo "  Last violation count: $VIOLATIONS"
    fi

    # Show last summary if available
    if JSON_SUMMARY=$(get_json_summary) && [ -n "$JSON_SUMMARY" ]; then
        echo
        echo "  📈 Last Run Summary:"
        if command -v jq >/dev/null 2>&1; then
            TIMESTAMP=$(echo "$JSON_SUMMARY" | jq -r '.ts // empty')
            STATUS=$(echo "$JSON_SUMMARY" | jq -r '.status // empty')
            VIOLATIONS_JSON=$(echo "$JSON_SUMMARY" | jq -r '.violations // empty')
            SYS_CHANGES=$(echo "$JSON_SUMMARY" | jq -r '.sys_changes // empty')
        else
            # Fallback without jq
            TIMESTAMP=$(echo "$JSON_SUMMARY" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
            STATUS=$(echo "$JSON_SUMMARY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            VIOLATIONS_JSON=$(echo "$JSON_SUMMARY" | grep -o '"violations":[0-9]*' | cut -d':' -f2)
            SYS_CHANGES=$(echo "$JSON_SUMMARY" | grep -o '"sys_changes":[0-9]*' | cut -d':' -f2)
        fi

        echo "    Timestamp: $TIMESTAMP"
        echo "    Status: $STATUS"
        echo "    Violations: $VIOLATIONS_JSON"
        echo "    System changes: $SYS_CHANGES"
    fi
else
    echo "  No log file found"
fi

echo
echo "========================================="
echo "            Recommended Actions"
echo "========================================="

ACTIONS_NEEDED=0

# Check for database existence using compgen
if ! compgen -G "/var/lib/tripwire/*.twd" > /dev/null 2>&1; then
    echo "1. Initialize the database:"
    echo "   sudo tripwire --init"
    echo
    ACTIONS_NEEDED=1
fi

if ! id tripwire >/dev/null 2>&1; then
    echo "2. Run the automated setup:"
    echo "   sudo ./install-tripwire-automation.sh"
    echo
    ACTIONS_NEEDED=1
fi

if [ -f /var/lib/tripwire-service/.tripwire/local-passphrase ]; then
    if [ ! -f /etc/apt/apt.conf.d/99bananapeel ] && [ ! -f /etc/apt/apt.conf.d/99tripwire ]; then
        echo "3. Install APT hook:"
        echo "   sudo cp 99bananapeel /etc/apt/apt.conf.d/"
        echo
        ACTIONS_NEEDED=1
    fi
fi

if [ $ACTIONS_NEEDED -eq 0 ]; then
    echo "✅ All components are properly configured!"
    echo
    echo "Useful commands:"
    echo "  • Check status:     bananapeel-status"
    echo "  • Exit code only:   bananapeel-status --check-only"
    echo "  • Recent summary:   bananapeel-status --since 24h"
    echo "  • Test automation:  sudo -u tripwire /var/lib/tripwire-service/tripwire-auto-update.sh"
    echo "  • Manual check:     sudo tripwire --check"
    echo "  • View logs:        tail -f /var/log/bananapeel-update.log"
fi

echo

# Set exit code based on last status
EXIT_CODE=0
if [ -n "${JSON_SUMMARY:-}" ]; then
    STATUS=$(echo "$JSON_SUMMARY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    EXIT_CODE=$(get_exit_code "$STATUS")
fi

exit "$EXIT_CODE"

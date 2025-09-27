#!/bin/bash
# Restricted wrapper for tripwire commands
# Only allows specific operations needed by automation
# Validates all arguments strictly to prevent misuse

set -euo pipefail

# Function to show usage and exit
usage() {
    cat >&2 <<EOF
Usage: $0 [check|update|print] [options]
  check:  Run tripwire integrity check
          Options: [--quiet] [--email-report]
  update: Update tripwire database
          Required: --twrfile /var/lib/tripwire/report/<file>.twr
          Options: [--accept-all]
  print:  Print tripwire report
          Required: --print-report --twrfile /var/lib/tripwire/report/<file>.twr
EOF
    exit 2
}

# Validate that a path is within the allowed report directory
validate_report_path() {
    local path="$1"

    # Resolve real path to prevent symlink traversal attacks
    local real
    real=$(readlink -f "$path" 2>/dev/null || true)

    # Validate resolved path is within allowed directory and ends with .twr
    case "$real" in
        /var/lib/tripwire/report/*.twr)
            # Check file actually exists
            if [ ! -f "$real" ]; then
                echo "Error: Report file not found: $real" >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: Report path escapes allowed directory" >&2
            exit 1
            ;;
    esac
}

# Get command
cmd="${1:-}"
if [ -z "$cmd" ]; then
    usage
fi
shift

case "$cmd" in
    check)
        # Build arguments array
        args=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --quiet)
                    args+=("--quiet")
                    shift
                    ;;
                --email-report)
                    args+=("--email-report")
                    shift
                    ;;
                *)
                    echo "Error: Invalid argument for check: $1" >&2
                    usage
                    ;;
            esac
        done

        # Execute the check command
        exec /usr/sbin/tripwire --check "${args[@]}"
        ;;

    update)
        # Require --twrfile as first argument
        if [ "${1:-}" != "--twrfile" ]; then
            echo "Error: update requires --twrfile as first argument" >&2
            usage
        fi
        shift

        # Get and validate the report file path
        twr="${1:-}"
        if [ -z "$twr" ]; then
            echo "Error: --twrfile requires a path argument" >&2
            usage
        fi
        validate_report_path "$twr"
        shift

        # Check for optional --accept-all
        accept_all=""
        if [ "${1:-}" = "--accept-all" ]; then
            accept_all="--accept-all"
            shift
        fi

        # No more arguments allowed
        if [ $# -ne 0 ]; then
            echo "Error: Unexpected arguments after update options" >&2
            usage
        fi

        # Execute the update command
        if [ -n "$accept_all" ]; then
            exec /usr/sbin/tripwire --update --twrfile "$twr" --accept-all
        else
            exec /usr/sbin/tripwire --update --twrfile "$twr"
        fi
        ;;

    print)
        # Require --print-report as first argument
        if [ "${1:-}" != "--print-report" ]; then
            echo "Error: print requires --print-report as first argument" >&2
            usage
        fi
        shift

        # Require --twrfile as second argument
        if [ "${1:-}" != "--twrfile" ]; then
            echo "Error: print requires --twrfile as second argument" >&2
            usage
        fi
        shift

        # Get and validate the report file path
        twr="${1:-}"
        if [ -z "$twr" ]; then
            echo "Error: --twrfile requires a path argument" >&2
            usage
        fi
        validate_report_path "$twr"
        shift

        # No more arguments allowed
        if [ $# -ne 0 ]; then
            echo "Error: Unexpected arguments after print options" >&2
            usage
        fi

        # Execute the print command
        exec /usr/sbin/twprint --print-report --twrfile "$twr"
        ;;

    *)
        echo "Error: Unknown command: $cmd" >&2
        usage
        ;;
esac
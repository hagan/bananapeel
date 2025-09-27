#!/bin/bash
# Bananapeel shared shell helpers

# Do not set -euo pipefail in libraries; leave to callers

# Provide json_escape unless already defined by caller
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

# Future helpers can be added here and sourced by scripts


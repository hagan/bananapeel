#!/bin/bash
# Bananapeel status-only helper for monitoring (Nagios-style)
# Prints a single line summary and exits with 0/1/2 based on status

set -euo pipefail

# Find status command
STATUS_CMD=""
if command -v bananapeel-status >/dev/null 2>&1; then
  STATUS_CMD="bananapeel-status"
elif command -v tripwire-summary.sh >/dev/null 2>&1; then
  STATUS_CMD="tripwire-summary.sh"
elif [ -x "$(dirname "$0")/../setup/tripwire-summary.sh" ]; then
  STATUS_CMD="$(dirname "$0")/../setup/tripwire-summary.sh"
else
  echo "UNKNOWN: status helper not found"; exit 2
fi

# Get JSON and exit code
JSON_OUTPUT=""
if JSON_OUTPUT=$($STATUS_CMD --json 2>/dev/null); then
  EXIT_CODE=$?
else
  EXIT_CODE=$?
fi

# Parse fields (prefer jq)
TS=""; HOST=""; STATUS=""; VIOL=0
if command -v jq >/dev/null 2>&1; then
  TS=$(echo "$JSON_OUTPUT" | jq -r '.ts // empty' 2>/dev/null || true)
  HOST=$(echo "$JSON_OUTPUT" | jq -r '.host // empty' 2>/dev/null || true)
  STATUS=$(echo "$JSON_OUTPUT" | jq -r '.status // empty' 2>/dev/null || true)
  VIOL=$(echo "$JSON_OUTPUT" | jq -r '.violations // 0' 2>/dev/null || echo 0)
else
  TS=$(echo "$JSON_OUTPUT" | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
  HOST=$(echo "$JSON_OUTPUT" | grep -o '"host":"[^"]*"' | cut -d'"' -f4)
  STATUS=$(echo "$JSON_OUTPUT" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  VIOL=$(echo "$JSON_OUTPUT" | grep -o '"violations":[0-9]*' | cut -d':' -f2)
fi

# Map exit code to label
LABEL="UNKNOWN"
case "$EXIT_CODE" in
  0) LABEL="OK" ;;
  1) LABEL="WARNING" ;;
  2) LABEL="CRITICAL" ;;
esac

# Print single line summary
if [ -n "$TS" ] && [ -n "$STATUS" ]; then
  echo "$LABEL: $STATUS - violations=$VIOL host=${HOST:-$(hostname)} ts=$TS"
else
  echo "$LABEL: status unavailable"
fi

exit "$EXIT_CODE"


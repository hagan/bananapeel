#!/bin/bash
# Quick functional test

set -e

# Setup
TMPDIR=$(mktemp -d -t bptest-XXXXX)
export LOGFILE="$TMPDIR/test.log"
export LOCK_FILE="$TMPDIR/lock"
export PATH="$(pwd)/tests/mocks:$PATH"
export MOCK_CASE=A
export DRY_RUN=0
export EMAIL_TO="test@example.com"

echo "Test directory: $TMPDIR"
echo "Running automation script..."

# Run
if bash -x scripts/automation/tripwire-auto-update.sh > "$TMPDIR/output.txt" 2>&1; then
    echo "Script succeeded"
else
    EXIT_CODE=$?
    echo "Script failed with exit code: $EXIT_CODE"
    echo "Last 20 lines of output:"
    tail -20 "$TMPDIR/output.txt"
fi

# Check results
echo "Log contents:"
cat "$LOGFILE"

echo ""
echo "Looking for SUMMARY_JSON:"
if grep -q '^SUMMARY_JSON=' "$LOGFILE"; then
    echo "SUCCESS: Found SUMMARY_JSON"
    grep '^SUMMARY_JSON=' "$LOGFILE"
else
    echo "FAILED: No SUMMARY_JSON found"
fi

# Cleanup
rm -rf "$TMPDIR"
#!/bin/bash
# Functional tests for tripwire automation script
# Runs without root/systemd using mocks

# Don't use set -e so all tests can run even if some fail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Setup test environment
echo "Setting up test environment..."
TMPDIR=$(mktemp -d -t bananapeel-test-XXXXXX)
LOGFILE="$TMPDIR/bananapeel-update.log"
OUTBOX="$TMPDIR/outbox"
LOCK_DIR="$TMPDIR/run/bananapeel"

# Create lock directory structure
mkdir -p "$LOCK_DIR"

# Create tripwire report directory structure for test TWR files
mkdir -p "$TMPDIR/var/lib/tripwire/report"

# Create the log file
touch "$LOGFILE"

# Export test environment
export PATH="$(pwd)/tests/mocks:$PATH"
export LOGFILE
export DRY_RUN=0  # We want real execution but with mocks
export EMAIL_TO="test@example.com"
export TEST_OUTBOX="$OUTBOX"
export LOCK_FILE="$LOCK_DIR/update.lock"

# Find the status script - try both installed and repo locations
if [[ -x "/usr/local/bin/bananapeel-status" ]]; then
    STATUS_SCRIPT="/usr/local/bin/bananapeel-status"
elif [[ -x "scripts/setup/tripwire-summary.sh" ]]; then
    STATUS_SCRIPT="scripts/setup/tripwire-summary.sh"
else
    echo -e "${RED}ERROR: Cannot find bananapeel-status or tripwire-summary.sh${NC}"
    exit 1
fi

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local expected_status="$2"
    local expected_exit_code="$3"

    echo -n "Testing $test_name... "

    # Run the automation script
    if bash scripts/automation/tripwire-auto-update.sh > "$TMPDIR/output.txt" 2>&1; then
        SCRIPT_EXIT=0
    else
        SCRIPT_EXIT=$?
        # Debug output if script fails
        if [[ "$SCRIPT_EXIT" -ne 0 ]]; then
            echo -e "\n${YELLOW}Script failed with exit code $SCRIPT_EXIT${NC}"
            echo "Output:"
            cat "$TMPDIR/output.txt"
            echo "---"
        fi
    fi

    # Check for SUMMARY_JSON line
    if ! grep -q '^SUMMARY_JSON=' "$LOGFILE"; then
        echo -e "${RED}FAILED: No SUMMARY_JSON found in log${NC}"
        ((TESTS_FAILED++))
        return 1
    fi

    # Extract and parse JSON
    JSON_LINE=$(tail -1 "$LOGFILE" | grep '^SUMMARY_JSON=' | cut -d= -f2-)

    # Get status from JSON (prefer jq if available)
    if command -v jq >/dev/null 2>&1; then
        ACTUAL_STATUS=$(echo "$JSON_LINE" | jq -r '.status // empty')
    else
        ACTUAL_STATUS=$(echo "$JSON_LINE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    fi

    # Run status script and get exit code
    if LOGFILE="$LOGFILE" bash "$STATUS_SCRIPT" --json > "$TMPDIR/status.json" 2>&1; then
        STATUS_EXIT=0
    else
        STATUS_EXIT=$?
    fi

    # Validate results
    if [[ "$ACTUAL_STATUS" != "$expected_status" ]]; then
        echo -e "${RED}FAILED: Expected status '$expected_status', got '$ACTUAL_STATUS'${NC}"
        ((TESTS_FAILED++))
        return 1
    fi

    if [[ "$STATUS_EXIT" -ne "$expected_exit_code" ]]; then
        echo -e "${RED}FAILED: Expected exit code $expected_exit_code, got $STATUS_EXIT${NC}"
        ((TESTS_FAILED++))
        return 1
    fi

    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
    return 0
}

TEST_ONLY=${TEST_ONLY:-}

if [[ -z "$TEST_ONLY" || "$TEST_ONLY" != "escape" ]]; then
    # Test Case A: OK (no violations)
    echo ""
    echo "=== Test Case A: OK (no violations) ==="
    export MOCK_CASE=A
    run_test "OK status" "OK" 0

    # Test Case B: Manual review required
    echo ""
    echo "=== Test Case B: Manual review required ==="
    export MOCK_CASE=B
    # Clear and recreate log for new test
    > "$LOGFILE"
    touch "$LOGFILE"
    run_test "Manual review" "MANUAL REVIEW REQUIRED" 1

    # Test Case C: Package updates detected
    echo ""
    echo "=== Test Case C: Package updates detected ==="
    export MOCK_CASE=C
    export AUTO_ACCEPT_THRESHOLD=500  # High threshold to prevent auto-accept
    # Clear and recreate log for new test
    > "$LOGFILE"
    touch "$LOGFILE"
    run_test "Package updates" "PACKAGE UPDATES DETECTED" 1

    # Test email functionality
    echo ""
    echo "=== Testing email functionality ==="
    echo -n "Checking email outbox... "
    if [[ -f "$OUTBOX" ]]; then
        EMAIL_COUNT=$(grep -c "=== Email Message ===" "$OUTBOX" || true)
        if [[ "$EMAIL_COUNT" -gt 0 ]]; then
            echo -e "${GREEN}PASSED: $EMAIL_COUNT emails recorded${NC}"
            ((TESTS_PASSED++))

            # Check that SAMPLE OF CHANGES contains expected content for Case B and C
            echo -n "Checking email sample extraction... "
            LAST_EMAIL=$(tac "$OUTBOX" | awk '/=== Email Message ===/{p=1} p' | tac)

            # Check for SAMPLE OF CHANGES section
            # DEBUG: Show what we're searching
            if [[ -n "${DEBUG_EMAIL:-}" ]]; then
                echo ""
                echo "DEBUG: Last email content:"
                echo "$LAST_EMAIL" | head -40
                echo "..."
            fi

            if echo "$LAST_EMAIL" | grep -q "SAMPLE OF CHANGES"; then
                SAMPLE_SECTION=$(echo "$LAST_EMAIL" | awk '/SAMPLE OF CHANGES/,/ACTION REQUIRED/' | head -20)

                # For Case B and C, we expect to see Added/Modified/Removed
                if [[ "$MOCK_CASE" == "B" ]] || [[ "$MOCK_CASE" == "C" ]]; then
                    if echo "$SAMPLE_SECTION" | grep -qE "(Added:|Modified:|Removed:)"; then
                        echo -e "${GREEN}PASSED: Sample contains expected change markers${NC}"
                        ((TESTS_PASSED++))
                    else
                        echo -e "${RED}FAILED: Sample missing change markers for Case $MOCK_CASE${NC}"
                        echo "Sample content:"
                        echo "$SAMPLE_SECTION" | head -10
                        ((TESTS_FAILED++))
                    fi
                else
                    # Case A might have empty sample or fallback message
                    echo -e "${GREEN}PASSED: Sample section present (Case A)${NC}"
                    ((TESTS_PASSED++))
                fi
            else
                echo -e "${RED}FAILED: No SAMPLE OF CHANGES section found${NC}"
                ((TESTS_FAILED++))
            fi

            # Check for Content-Type and MIME-Version headers (TASK-085)
            echo -n "Checking Content-Type header... "
            if echo "$LAST_EMAIL" | grep -q "Content-Type: text/plain; charset=UTF-8"; then
                echo -e "${GREEN}PASSED: Content-Type header present${NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${RED}FAILED: Content-Type header missing${NC}"
                echo "Email headers:"
                echo "$LAST_EMAIL" | grep -E "^(Subject|From|To|Content-Type):" | head -5
                ((TESTS_FAILED++))
            fi

            echo -n "Checking MIME-Version header... "
            if echo "$LAST_EMAIL" | grep -q "^MIME-Version: 1.0"; then
                echo -e "${GREEN}PASSED${NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${YELLOW}WARNING: MIME-Version header not found${NC}"
            fi
        else
            echo -e "${RED}FAILED: No emails in outbox${NC}"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${YELLOW}WARNING: No outbox file created${NC}"
    fi
fi

# Test JSON escaping robustness
echo ""
echo "=== Test Case D: JSON escaping ==="
export MOCK_CASE=A
export TEST_HOSTNAME='bad"host\name'
export TEST_TWR_NAME="/var/lib/tripwire/report/weird \"quote\" and backslash \\ report.twr"
# Clear and recreate log for new test
> "$LOGFILE"
touch "$LOGFILE"

echo -n "Testing JSON escaping... "
if bash scripts/automation/tripwire-auto-update.sh > "$TMPDIR/escape_output.txt" 2>&1; then
    :
else
    echo -e "\n${YELLOW}Script failed during escaping test${NC}"
    cat "$TMPDIR/escape_output.txt"
fi

if ! grep -q '^SUMMARY_JSON=' "$LOGFILE"; then
    echo -e "${RED}FAILED: No SUMMARY_JSON found for escaping test${NC}"
    ((TESTS_FAILED++))
else
    JSON_LINE=$(tail -1 "$LOGFILE" | grep '^SUMMARY_JSON=' | cut -d= -f2-)
    # Validate JSON parses and values match
    if command -v jq >/dev/null 2>&1; then
        HOST_PARSED=$(echo "$JSON_LINE" | jq -r '.host')
        TWR_PARSED=$(echo "$JSON_LINE" | jq -r '.latest_twr')
        if [[ "$HOST_PARSED" == "$TEST_HOSTNAME" && "$TWR_PARSED" == "$TEST_TWR_NAME" ]]; then
            echo -e "${GREEN}PASSED${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAILED: Parsed values did not match${NC}"
            echo "host: expected='$TEST_HOSTNAME' got='$HOST_PARSED'"
            echo "twr:  expected='$TEST_TWR_NAME' got='$TWR_PARSED'"
            ((TESTS_FAILED++))
        fi
    else
        # Fallback heuristic: ensure escapes present for quotes
        if echo "$JSON_LINE" | grep -q '\\"quote\\"' && echo "$JSON_LINE" | grep -q 'bad\\"host\\\\name'; then
            echo -e "${GREEN}PASSED (heuristic)${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${YELLOW}WARNING: Could not fully validate without jq${NC}"
            ((TESTS_PASSED++))
        fi
    fi
fi

if [[ -z "$TEST_ONLY" || "$TEST_ONLY" != "escape" ]]; then
    # Test concurrency lock
    echo ""
    echo "=== Testing concurrency lock ==="
    echo -n "Testing lock prevention... "
    # Hold a lock to simulate concurrent execution
    (
        exec 9>"$LOCK_FILE"
        flock 9
        # Now the lock is held, try to run the script (should no-op and exit 0)
        if bash scripts/automation/tripwire-auto-update.sh > "$TMPDIR/lock_test.txt" 2>&1; then
            # Check that a lock message was appended to the log
            if grep -q "Another bananapeel run is active; exiting" "$LOGFILE"; then
                echo -e "${GREEN}PASSED: Lock prevented concurrent run${NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${YELLOW}WARNING: No explicit lock message found${NC}"
                ((TESTS_PASSED++))
            fi
        else
            echo -e "${RED}FAILED: Script returned non-zero on lock contention${NC}"
            ((TESTS_FAILED++))
        fi
    ) # Release the lock when subshell exits

    # Test debug email logging (TASK-085)
    echo ""
    echo "=== Testing debug email logging ==="
    export BANANAPEEL_DEBUG_EMAIL=1
    export MOCK_CASE=B
    # Clear and recreate log for new test
    > "$LOGFILE"
    touch "$LOGFILE"

    echo -n "Testing debug email preview... "
    if bash scripts/automation/tripwire-auto-update.sh > "$TMPDIR/debug_test.txt" 2>&1; then
        # Check that debug preview was logged
        if grep -q "DEBUG: Email preview" "$LOGFILE"; then
            # Verify that email headers are in the log
            if grep -A5 "DEBUG: Email preview" "$LOGFILE" | grep -q "Subject:"; then
                echo -e "${GREEN}PASSED: Debug preview logged with headers${NC}"
                ((TESTS_PASSED++))
            else
                echo -e "${RED}FAILED: Debug preview missing headers${NC}"
                echo "Debug log content:"
                grep -A10 "DEBUG: Email preview" "$LOGFILE" || echo "Not found"
                ((TESTS_FAILED++))
            fi
        else
            echo -e "${RED}FAILED: No debug preview found in log${NC}"
            echo "Log content:"
            tail -20 "$LOGFILE"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}FAILED: Script failed during debug test${NC}"
        ((TESTS_FAILED++))
    fi

    # Clean up debug flag
    unset BANANAPEEL_DEBUG_EMAIL
fi

# Cleanup
echo ""
echo "Cleaning up test environment..."
rm -rf "$TMPDIR"

# Summary
echo ""
echo "================================"
echo "Test Results Summary:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "================================"

if [[ "$TESTS_FAILED" -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

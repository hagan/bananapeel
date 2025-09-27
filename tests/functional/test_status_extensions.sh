#!/bin/bash
# Functional tests for bananapeel-status extensions (TASK-073)
# Tests --check-only and --since flags

set -e

# Test configuration
TEST_DIR=$(mktemp -d)
TEST_LOG="$TEST_DIR/test.log"
SCRIPT_PATH="${SCRIPT_PATH:-scripts/setup/tripwire-summary.sh}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local expected_exit="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))

    echo -n "Testing $test_name... "

    # Run the command and capture exit code
    local actual_exit=0
    LOGFILE="$TEST_LOG" "$@" >/dev/null 2>&1 || actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC} (expected exit $expected_exit, got $actual_exit)"
        return 1
    fi
}

# Helper to create test log with JSON summaries
create_test_log() {
    local log_file="$1"

    # Create log with various statuses and timestamps
    cat > "$log_file" <<'EOF'
2025-09-27T04:00:00Z bananapeel[1234]: Starting scheduled tripwire check
SUMMARY_JSON={"ts":"2025-09-27T04:00:00Z","host":"test1","violations":0,"sys_changes":0,"status":"OK","latest_twr":"/var/lib/tripwire/report/test1-20250927-040000.twr"}
2025-09-27T08:00:00Z bananapeel[1235]: Starting scheduled tripwire check
SUMMARY_JSON={"ts":"2025-09-27T08:00:00Z","host":"test1","violations":5,"sys_changes":3,"status":"PACKAGE UPDATES DETECTED","latest_twr":"/var/lib/tripwire/report/test1-20250927-080000.twr"}
2025-09-27T12:00:00Z bananapeel[1236]: Starting scheduled tripwire check
SUMMARY_JSON={"ts":"2025-09-27T12:00:00Z","host":"test1","violations":50,"sys_changes":48,"status":"PACKAGE UPDATES AUTO-ACCEPTED","latest_twr":"/var/lib/tripwire/report/test1-20250927-120000.twr"}
2025-09-27T16:00:00Z bananapeel[1237]: Starting scheduled tripwire check
SUMMARY_JSON={"ts":"2025-09-27T16:00:00Z","host":"test1","violations":10,"sys_changes":0,"status":"MANUAL REVIEW REQUIRED","latest_twr":"/var/lib/tripwire/report/test1-20250927-160000.twr"}
2025-09-28T04:00:00Z bananapeel[1238]: Starting scheduled tripwire check
SUMMARY_JSON={"ts":"2025-09-28T04:00:00Z","host":"test1","violations":0,"sys_changes":0,"status":"OK","latest_twr":"/var/lib/tripwire/report/test1-20250928-040000.twr"}
EOF
}

# Test setup
echo "Setting up test environment..."
create_test_log "$TEST_LOG"

echo
echo "=== Testing --check-only flag ==="

# Test 1: --check-only with OK status (last entry)
run_test "--check-only with OK status" 0 bash "$SCRIPT_PATH" --check-only

# Modify log to have MANUAL REVIEW REQUIRED as last entry
echo 'SUMMARY_JSON={"ts":"2025-09-28T05:00:00Z","host":"test1","violations":15,"sys_changes":0,"status":"MANUAL REVIEW REQUIRED","latest_twr":"/var/lib/tripwire/report/test1-20250928-050000.twr"}' >> "$TEST_LOG"

# Test 2: --check-only with MANUAL REVIEW REQUIRED status
run_test "--check-only with MANUAL REVIEW" 1 bash "$SCRIPT_PATH" --check-only

# Test 3: --check-only with empty log
> "$TEST_LOG"
run_test "--check-only with no data" 2 bash "$SCRIPT_PATH" --check-only

# Restore test log
create_test_log "$TEST_LOG"

echo
echo "=== Testing --since flag (human-readable) ==="

# Test 4: --since with data in range
OUTPUT=$(LOGFILE="$TEST_LOG" bash "$SCRIPT_PATH" --since "2025-09-27T10:00:00Z" 2>/dev/null)
if echo "$OUTPUT" | grep -q "Total runs: 3"; then
    echo -e "Testing --since with timestamp... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing --since with timestamp... ${RED}FAIL${NC}"
    echo "Expected 'Total runs: 3' in output"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 5: --since with no data in range
OUTPUT=$(LOGFILE="$TEST_LOG" bash "$SCRIPT_PATH" --since "2025-09-29T00:00:00Z" 2>/dev/null)
if echo "$OUTPUT" | grep -q "No runs found"; then
    echo -e "Testing --since with future time... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing --since with future time... ${RED}FAIL${NC}"
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo
echo "=== Testing --since flag (JSON mode) ==="

# Test 6: --since with JSON output
OUTPUT=$(LOGFILE="$TEST_LOG" bash "$SCRIPT_PATH" --since "2025-09-27T10:00:00Z" --json 2>/dev/null)
if echo "$OUTPUT" | grep -q '"total": 3'; then
    echo -e "Testing --since --json... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing --since --json... ${RED}FAIL${NC}"
    echo "Output: $OUTPUT"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 7: Verify JSON structure
if echo "$OUTPUT" | grep -q '"PACKAGE_UPDATES_AUTO_ACCEPTED": 1' && \
   echo "$OUTPUT" | grep -q '"MANUAL_REVIEW_REQUIRED": 1' && \
   echo "$OUTPUT" | grep -q '"OK": 1'; then
    echo -e "Testing JSON status counts... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing JSON status counts... ${RED}FAIL${NC}"
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo
echo "=== Testing duration parsing ==="

# Create a log with current timestamp
NOW=$(date --rfc-3339=seconds 2>/dev/null | sed 's/ /T/' || date +"%Y-%m-%dT%H:%M:%S%z")
echo "SUMMARY_JSON={\"ts\":\"$NOW\",\"host\":\"test1\",\"violations\":0,\"sys_changes\":0,\"status\":\"OK\",\"latest_twr\":\"/var/lib/tripwire/report/test1-now.twr\"}" >> "$TEST_LOG"

# Test 8: Duration format (this test may vary based on system time)
OUTPUT=$(LOGFILE="$TEST_LOG" bash "$SCRIPT_PATH" --since "1h" 2>/dev/null || true)
if echo "$OUTPUT" | grep -q "Total runs:"; then
    echo -e "Testing --since 1h duration... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing --since 1h duration... ${RED}FAIL${NC} (Note: May fail if date command doesn't support -d)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo
echo "=== Testing error handling ==="

# Test 9: Invalid duration format
if ! LOGFILE="$TEST_LOG" bash "$SCRIPT_PATH" --since "invalid" >/dev/null 2>&1; then
    echo -e "Testing invalid duration format... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing invalid duration format... ${RED}FAIL${NC} (should have failed)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 10: Missing --since argument
if ! bash "$SCRIPT_PATH" --since >/dev/null 2>&1; then
    echo -e "Testing missing --since argument... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing missing --since argument... ${RED}FAIL${NC} (should have failed)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Cleanup
rm -rf "$TEST_DIR"

# Summary
echo
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $((TESTS_RUN - TESTS_PASSED))"

if [ "$TESTS_PASSED" -eq "$TESTS_RUN" ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
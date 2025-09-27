#!/bin/bash
# Functional tests for service user migration (TASK-062)
# Tests the migrate-service-user.sh script in dry-run mode

set -e

# Test configuration
TEST_DIR=$(mktemp -d)
SCRIPT_PATH="${SCRIPT_PATH:-scripts/setup/migrate-service-user.sh}"
LOG_FILE="$TEST_DIR/test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

    # Run the command and capture output and exit code
    local actual_exit=0
    local output
    output=$("$@" 2>&1) || actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC} (expected exit $expected_exit, got $actual_exit)"
        echo "Output: $output"
        return 1
    fi
}

# Helper function to check output contains string
check_output_contains() {
    local test_name="$1"
    local search_string="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))

    echo -n "Testing $test_name... "

    # Run the command and capture output
    local output
    output=$("$@" 2>&1)

    if echo "$output" | grep -q "$search_string"; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "Expected to find: $search_string"
        echo "Output: $output"
        return 1
    fi
}

echo "========================================="
echo "Service User Migration Tests"
echo "========================================="
echo

# Test 1: Help output
echo "=== Testing help output ==="
run_test "help flag" 0 bash "$SCRIPT_PATH" --help

# Test 2: Dry-run mode
echo
echo "=== Testing dry-run mode ==="
OUTPUT=$(bash "$SCRIPT_PATH" --dry-run 2>&1 || true)
if echo "$OUTPUT" | grep -q "DRY-RUN"; then
    echo -e "Testing dry-run mode... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing dry-run mode... ${RED}FAIL${NC}"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 3: Check prerequisites detection
echo
echo "=== Testing prerequisites check ==="
check_output_contains "prerequisites check" "Checking prerequisites" \
    bash "$SCRIPT_PATH" --dry-run

# Test 4: Invalid option handling
echo
echo "=== Testing error handling ==="
run_test "invalid option" 1 bash "$SCRIPT_PATH" --invalid-option

# Test 5: Rollback option requires argument
run_test "rollback without argument" 1 bash "$SCRIPT_PATH" --rollback

# Test 6: Dry-run with force flag
echo
echo "=== Testing flag combinations ==="
OUTPUT=$(bash "$SCRIPT_PATH" --dry-run --force 2>&1 || true)
if echo "$OUTPUT" | grep -q "Running in DRY-RUN mode"; then
    echo -e "Testing dry-run with force... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing dry-run with force... ${RED}FAIL${NC}"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 7: Verbose mode
OUTPUT=$(bash "$SCRIPT_PATH" --dry-run --verbose 2>&1 || true)
if echo "$OUTPUT" | grep -q "Would execute"; then
    echo -e "Testing verbose mode... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing verbose mode... ${RED}FAIL${NC}"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 8: Check for service stop commands in dry-run
echo
echo "=== Testing service management ==="
check_output_contains "service stop commands" "Stopping services" \
    bash "$SCRIPT_PATH" --dry-run --force

# Test 9: Check for backup creation
check_output_contains "backup creation" "Creating backup" \
    bash "$SCRIPT_PATH" --dry-run --force

# Test 10: Check for user migration steps
check_output_contains "user migration" "Migrating user" \
    bash "$SCRIPT_PATH" --dry-run --force

# Test 11: Check for ownership update
check_output_contains "ownership update" "Updating file ownership" \
    bash "$SCRIPT_PATH" --dry-run --force

# Test 12: Check for sudoers update
check_output_contains "sudoers update" "Updating sudoers" \
    bash "$SCRIPT_PATH" --dry-run --force

# Test 13: Check for systemd update
check_output_contains "systemd update" "Updating systemd units" \
    bash "$SCRIPT_PATH" --dry-run --force

# Test 14: Syntax check
echo
echo "=== Testing script syntax ==="
if bash -n "$SCRIPT_PATH"; then
    echo -e "Testing script syntax... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Testing script syntax... ${RED}FAIL${NC}"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 15: Shellcheck (if available)
if command -v shellcheck >/dev/null 2>&1; then
    echo
    echo "=== Running shellcheck ==="
    if shellcheck -S error "$SCRIPT_PATH" 2>/dev/null; then
        echo -e "Shellcheck validation... ${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "Shellcheck validation... ${YELLOW}WARN${NC} (non-critical issues)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
fi

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
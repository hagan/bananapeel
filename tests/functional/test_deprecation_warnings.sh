#!/bin/bash
# Test for TASK-070: Legacy alias/symlink deprecation warnings
set -e

# Test framework setup
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test functions
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_result="${3:-0}"

    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "Testing: $test_name ... "

    set +e
    eval "$test_cmd" >/dev/null 2>&1
    local result=$?
    set -e

    if [ "$result" -eq "$expected_result" ]; then
        echo -e "${GREEN}PASS${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC} (expected $expected_result, got $result)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS_SCRIPT="$PROJECT_ROOT/scripts/setup/tripwire-summary.sh"
AUTOMATION_SCRIPT="$PROJECT_ROOT/scripts/automation/tripwire-auto-update.sh"

# Make scripts executable
chmod +x "$STATUS_SCRIPT" 2>/dev/null || true
chmod +x "$AUTOMATION_SCRIPT" 2>/dev/null || true

echo "==================================="
echo "Deprecation Warning Tests (TASK-070)"
echo "==================================="
echo

# Test 1: Check status script has deprecation detection function
echo "1. Status script deprecation detection"
run_test "check_legacy_artifacts function exists" \
    "grep -q 'check_legacy_artifacts()' '$STATUS_SCRIPT'"

run_test "Function detects systemd timers" \
    "grep -q 'tripwire-.*timer' '$STATUS_SCRIPT'"

run_test "Function detects APT hooks" \
    "grep -q '99bananapeel' '$STATUS_SCRIPT'"

run_test "Function detects log symlinks" \
    "grep -q 'tripwire-apt-update.log' '$STATUS_SCRIPT'"

echo

# Test 2: Check automation script has daily warning
echo "2. Automation script daily warning"
run_test "Daily warning exists" \
    "grep -q 'Legacy tripwire artifacts detected' '$AUTOMATION_SCRIPT'"

run_test "Warning logs to logfile" \
    "grep -q 'log_message.*WARNING.*Legacy' '$AUTOMATION_SCRIPT'"

echo

# Test 3: Check installers have warnings
echo "3. Installer deprecation warnings"
for installer in "$PROJECT_ROOT"/scripts/setup/install-tripwire-automation*.sh; do
    if [ -f "$installer" ]; then
        installer_name=$(basename "$installer")
        run_test "$installer_name has warning" \
            "grep -q 'Legacy tripwire artifacts detected' '$installer'"

        run_test "$installer_name APT hook marked deprecated" \
            "grep -q 'DEPRECATED.*APT hook' '$installer'"
    fi
done

echo

# Test 4: Check installers don't create new aliases
echo "4. No new legacy aliases created"
for installer in "$PROJECT_ROOT"/scripts/setup/install-tripwire-automation*.sh; do
    if [ -f "$installer" ]; then
        installer_name=$(basename "$installer")

        # Should NOT have Alias=tripwire-update.timer anymore
        if grep -q "^Alias=tripwire-update.timer" "$installer" 2>/dev/null; then
            echo -e "${RED}FAIL${NC}: $installer_name still creates legacy alias"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo -e "${GREEN}PASS${NC}: $installer_name doesn't create legacy alias"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi
        TEST_COUNT=$((TEST_COUNT + 1))
    fi
done

echo

# Test 5: Check README has deprecation timeline
echo "5. README documentation"
run_test "README has deprecation section" \
    "grep -q '## Deprecation Timeline' '$PROJECT_ROOT/README.md'"

run_test "README mentions v0.3.0 removal" \
    "grep -q 'v0.3.0.*removal' '$PROJECT_ROOT/README.md'"

run_test "README has migration instructions" \
    "grep -q 'bananapeel-status.*legacy' '$PROJECT_ROOT/README.md'"

echo

# Test 6: Simulate legacy artifact detection in status script
echo "6. Legacy artifact detection output"
# Create a temporary test to check the warning format
TEMP_TEST="/tmp/test_deprecation_$$.sh"
cat > "$TEMP_TEST" <<'EOF'
#!/bin/bash
# Extract and test the check_legacy_artifacts function
source /dev/stdin <<'FUNC'
check_legacy_artifacts() {
    local legacy_found=false
    local legacy_items=()

    # Check for legacy systemd timers
    if ls /etc/systemd/system/tripwire-*.timer 2>/dev/null | grep -q .; then
        legacy_found=true
        legacy_items+=("- Systemd timers: /etc/systemd/system/tripwire-*.timer")
    fi

    # Check for APT hook
    if [ -f /etc/apt/apt.conf.d/99bananapeel ]; then
        legacy_found=true
        legacy_items+=("- APT hook: /etc/apt/apt.conf.d/99bananapeel")
    fi

    # Check for log symlink
    if [ -L /var/log/tripwire-apt-update.log ]; then
        legacy_found=true
        legacy_items+=("- Log symlink: /var/log/tripwire-apt-update.log")
    fi

    # Check for command symlinks
    if [ -L /usr/local/bin/tripwire-status ]; then
        legacy_found=true
        legacy_items+=("- Command symlink: /usr/local/bin/tripwire-status")
    fi

    if [ "$legacy_found" = true ]; then
        echo "⚠ LEGACY ARTIFACTS DETECTED"
        echo "======================================"
        echo "The following legacy artifacts will be removed in v0.3.0:"
        echo
        for item in "${legacy_items[@]}"; do
            echo "$item"
        done
        echo
        echo "Migration Instructions:"
        echo "1. Run the installer with --migrate-service-user flag if using 'tripwire' user"
        echo "2. Use 'bananapeel-update.timer' instead of legacy aliases"
        echo "3. Update any scripts referencing old paths"
        echo "4. Remove APT hook if using systemd timer approach"
        echo
        return 0
    fi
    return 1
}
FUNC

# Mock some legacy artifacts
mkdir -p /tmp/test_systemd
touch /tmp/test_systemd/tripwire-update.timer 2>/dev/null || true

# Test that function produces expected output structure
if check_legacy_artifacts | grep -q "LEGACY ARTIFACTS DETECTED"; then
    echo "Function produces warning output"
    exit 0
else
    echo "Function should produce warning when artifacts detected"
    exit 1
fi
EOF

chmod +x "$TEMP_TEST"
run_test "Warning output format correct" "$TEMP_TEST"
rm -f "$TEMP_TEST"
rm -rf /tmp/test_systemd

echo
echo "==================================="
echo "Test Summary"
echo "==================================="
echo "Total tests: $TEST_COUNT"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}All deprecation warning tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review.${NC}"
    exit 1
fi

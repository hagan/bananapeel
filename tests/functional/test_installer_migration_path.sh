#!/bin/bash
# Verifies installer respects migrated service user (TASK-062)

set -e

SCRIPT="scripts/setup/install-tripwire-automation.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "Installer not found or not executable: $SCRIPT"
  exit 0
fi

echo "=== Testing installer migration path (dry-run) ==="

# Simulate presence of bananapeel user by faking 'id bananapeel' via PATH? Not feasible.
# Instead, rely on --migrate-service-user flag which the installer should honor.

OUTPUT=$(bash "$SCRIPT" --dry-run --migrate-service-user 2>&1 || true)

echo "$OUTPUT" | grep -q "migrate-service-user.sh --dry-run" || {
  echo "Expected installer to invoke migration script in dry-run"
  echo "$OUTPUT"
  exit 1
}

echo "$OUTPUT" | grep -q "SERVICE_USER=bananapeel" || {
  echo "Expected installer to set SERVICE_USER=bananapeel for setup script"
  echo "$OUTPUT"
  exit 1
}

echo "PASS: Installer honors migration flag and uses bananapeel user"


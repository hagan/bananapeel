#!/usr/bin/env bash
set -euo pipefail

echo "===> Bananapeel: Test Suite"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$ROOT_DIR"

rc=0
STRICT=${STRICT:-0}

# Collect shell scripts
mapfile -t scripts < <(find scripts -type f -name "*.sh" | sort)
echo "Found ${#scripts[@]} shell scripts"

echo "-- Syntax checking with bash -n"
for f in "${scripts[@]}"; do
  if ! bash -n "$f"; then
    echo "Syntax error: $f"
    rc=1 || true
  fi
done

echo "-- Static analysis with shellcheck (if available)"
if command -v shellcheck >/dev/null 2>&1; then
  # SC1091: allow sourcing non-existent files at build time
  if ! shellcheck -x -e SC1091 "${scripts[@]}"; then
    echo "shellcheck reported issues"
    rc=1 || true
  fi
else
  echo "shellcheck not found; skipping static analysis"
fi

echo "-- Smoke tests (non-invasive)"
# Intentionally avoid running scripts that require root or modify the system.
# Add targeted dry-run hooks to scripts before enabling functional tests.

if [[ "$STRICT" = "1" ]]; then
  if [[ $rc -eq 0 ]]; then
    echo "All checks passed (STRICT)"
    exit 0
  else
    echo "Failures detected (STRICT)"
    exit 1
  fi
else
  if [[ $rc -eq 0 ]]; then
    echo "All checks passed"
  else
    echo "Issues detected (non-fatal). Run with STRICT=1 to enforce."
  fi
  exit 0
fi

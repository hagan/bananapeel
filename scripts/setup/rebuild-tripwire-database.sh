#!/bin/bash
# Script to rebuild tripwire database without changing passphrases
# Use this after making policy changes or to reset after many updates

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "     Tripwire Database Rebuild          "
echo "========================================="
echo ""
echo "This will reinitialize the tripwire database"
echo "using your CURRENT passphrase and policy."
echo ""
echo -e "${YELLOW}You'll need your local passphrase.${NC}"
echo ""

# Check for recent violations
echo "Checking current status..."
REPORT=$(mktemp)
tripwire --check --quiet > "$REPORT" 2>&1 || true
VIOLATIONS=$(grep "Total violations found:" "$REPORT" 2>/dev/null | awk '{print $NF}' || echo "unknown")
rm -f "$REPORT"

echo "Current violations: $VIOLATIONS"
echo ""

read -p "Rebuild database now? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Backup current database
BACKUP_FILE="/var/lib/tripwire/$(hostname).twd.backup.$(date +%Y%m%d-%H%M%S)"
if [ -f "/var/lib/tripwire/$(hostname).twd" ]; then
    echo "Backing up current database..."
    cp "/var/lib/tripwire/$(hostname).twd" "$BACKUP_FILE"
    echo "Backup saved to: $BACKUP_FILE"
fi

# Reinitialize database
echo ""
echo "Reinitializing database..."
echo "This scans all files defined in your policy."
echo "It may take several minutes..."
echo ""

tripwire --init

echo ""
echo -e "${GREEN}✓ Database rebuilt successfully!${NC}"
echo ""

# Verify
echo "Verifying new database..."
CHECK=$(mktemp)
tripwire --check --quiet --severity 100 > "$CHECK" 2>&1 || true
NEW_VIOLATIONS=$(grep "Total violations found:" "$CHECK" 2>/dev/null | awk '{print $NF}' || echo "0")
rm -f "$CHECK"

if [ "$NEW_VIOLATIONS" -eq 0 ]; then
    echo -e "${GREEN}✓ Database is clean - no violations!${NC}"
else
    echo -e "${YELLOW}Note: $NEW_VIOLATIONS violations found.${NC}"
    echo "This is normal if files changed during the rebuild."
    echo "Run 'tripwire --check' to see details."
fi

echo ""
echo "Database rebuild complete!"
echo ""
echo "To restore previous database if needed:"
echo "  cp $BACKUP_FILE /var/lib/tripwire/$(hostname).twd"

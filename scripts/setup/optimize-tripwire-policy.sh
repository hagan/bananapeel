#!/bin/bash
# Tripwire Policy Optimization Script
# Analyzes tripwire reports to suggest policy exclusions

set -euo pipefail

REPORT_FILE="${1:-${HOME}/tripwire-noise.txt}"

echo "=== Tripwire Policy Optimization Tool ==="
echo ""

if [ ! -f "$REPORT_FILE" ]; then
    echo "Usage: $0 [tripwire-report-file]"
    echo "Default: ${HOME}/tripwire-noise.txt"
    exit 1
fi

echo "Analyzing report: $REPORT_FILE"
echo ""

# Analyze the most frequently changing directories
echo "=== Most Changed Directories ==="
grep -E "^\"/" "$REPORT_FILE" | sed 's/"//g' | xargs -I {} dirname {} | \
    sort | uniq -c | sort -rn | head -20

echo ""
echo "=== Suggested Exclusions for twpol.txt ==="
echo ""
echo "# Add these exclusions to reduce noise from package updates and caches:"
echo ""

# Suggest cache and temp exclusions
cat << 'EOF'
# Package manager caches (very noisy, low security value)
!/var/cache/apt ;
!/var/cache/debconf ;
!/var/cache/fontconfig ;
!/var/cache/ldconfig ;
!/var/cache/man ;
!/var/lib/apt/lists ;
!/var/lib/dpkg/updates ;
!/var/lib/dpkg/triggers ;

# Python bytecode (changes with every Python update)
!/usr/lib/python*/dist-packages ;
!/usr/lib/python*/__pycache__ ;
!/usr/local/lib/python*/dist-packages ;

# Documentation (low security value, changes often)
!/usr/share/man ;
!/usr/share/doc ;
!/usr/share/locale ;
!/usr/share/zoneinfo ;

# Systemd volatile state
!/var/lib/systemd/catalog ;
!/var/lib/systemd/coredump ;
!/run/systemd ;

# Snap packages (if using snaps)
!/var/lib/snapd/cache ;
!/var/lib/snapd/snaps ;

# Temporary build files
!/var/tmp ;
!/tmp ;

# Log files (should be monitored differently)
!/var/log/journal ;
!/var/log/apt ;
!/var/log/dpkg.log ;
!/var/log/unattended-upgrades ;
EOF

echo ""
echo "=== For High-Security Areas, Keep Monitoring But Reduce Granularity ==="
echo ""
cat << 'EOF'
# Instead of monitoring every file in /usr/lib, monitor directory changes only:
/usr/lib -> $(SEC_CRIT) (recurse = 1) ;

# For frequently updated system binaries, reduce check frequency:
/usr/bin -> $(SEC_BIN) (recurse = 1) ;
/usr/sbin -> $(SEC_BIN) (recurse = 1) ;
EOF

echo ""
echo "=== Creating Policy Update Script ==="

# Create a script to safely update the policy
cat > /tmp/update-tripwire-policy.sh << 'SCRIPT'
#!/bin/bash
# Script to update tripwire policy

set -e

echo "Backing up current policy..."
cp /etc/tripwire/twpol.txt /etc/tripwire/twpol.txt.backup.$(date +%Y%m%d-%H%M%S)

echo "Edit the policy file to add exclusions..."
echo "Opening editor in 3 seconds..."
sleep 3
nano /etc/tripwire/twpol.txt

echo ""
echo "Policy edited. Now we need to update tripwire with the new policy."
echo "You will need to enter your site and local passphrases."
echo ""

# Update the policy
twadmin --create-polfile -S /etc/tripwire/site.key /etc/tripwire/twpol.txt

echo "Policy file updated. Reinitializing database with new policy..."
echo "This will take some time..."

# Reinitialize the database with the new policy
tripwire --init

echo ""
echo "Policy update complete!"
echo "Run a test check to verify: tripwire --check"
SCRIPT

chmod +x /tmp/update-tripwire-policy.sh

echo ""
echo "=== Statistics from Current Report ==="
TOTAL_VIOLATIONS=$(grep "Total violations found:" "$REPORT_FILE" 2>/dev/null | awk '{print $NF}')
echo "Total violations in report: $TOTAL_VIOLATIONS"
echo ""

# Count violations by type
echo "Violations by area:"
grep -E "^\* " "$REPORT_FILE" | while IFS= read -r line; do
    echo "  $line"
done

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Review suggested exclusions above"
echo "2. Run the policy update script:"
echo "   sudo /tmp/update-tripwire-policy.sh"
echo "3. This will:"
echo "   - Backup your current policy"
echo "   - Open an editor to modify the policy"
echo "   - Recreate the policy file"
echo "   - Reinitialize the database"
echo ""
echo "IMPORTANT: Excluding paths reduces security monitoring!"
echo "Only exclude paths that:"
echo "- Change frequently due to normal operations"
echo "- Have low security value"
echo "- Are monitored through other means"

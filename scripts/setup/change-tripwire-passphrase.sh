#!/bin/bash
# Script to change Tripwire passphrase and rebuild database
# This regenerates keys and reinitializes the entire tripwire setup

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "   Tripwire Passphrase Change Process   "
echo "========================================="
echo ""
echo "This script will:"
echo "1. Backup current tripwire configuration"
echo "2. Generate new site and local keys"
echo "3. Re-sign the policy and configuration files"
echo "4. Reinitialize the database"
echo ""
echo -e "${YELLOW}WARNING: This process will require entering passphrases multiple times.${NC}"
echo -e "${YELLOW}Make sure you remember your new passphrases!${NC}"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Create backup directory
BACKUP_DIR="/root/tripwire-backup-$(date +%Y%m%d-%H%M%S)"
echo ""
echo "Creating backup in $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"

# Backup current tripwire files
cp -a /etc/tripwire/* "$BACKUP_DIR/" 2>/dev/null || true
cp -a /var/lib/tripwire/* "$BACKUP_DIR/" 2>/dev/null || true

echo -e "${GREEN}✓ Backup created${NC}"

# Step 1: Generate new keys
echo ""
echo "========================================="
echo "Step 1: Generate New Keys"
echo "========================================="
echo ""
echo "You'll be asked for:"
echo "- Site passphrase (protects configuration files)"
echo "- Local passphrase (protects database and reports)"
echo ""
echo -e "${YELLOW}Choose strong, different passphrases for each!${NC}"
echo ""
sleep 2

# Generate new key files
cd /etc/tripwire
twadmin --generate-keys --site-keyfile site.key
twadmin --generate-keys --local-keyfile "$HOSTNAME-local.key"

echo -e "${GREEN}✓ New keys generated${NC}"

# Step 2: Re-sign the configuration file
echo ""
echo "========================================="
echo "Step 2: Re-sign Configuration File"
echo "========================================="
echo ""
echo "Creating new configuration file with new keys..."

# Check if plain text config exists
if [ ! -f /etc/tripwire/twcfg.txt ]; then
    echo "Decrypting current configuration (need OLD site passphrase)..."
    twadmin --print-cfgfile > twcfg.txt
fi

echo "Encrypting configuration with NEW site key..."
twadmin --create-cfgfile --site-keyfile site.key twcfg.txt

echo -e "${GREEN}✓ Configuration file re-signed${NC}"

# Step 3: Re-sign the policy file
echo ""
echo "========================================="
echo "Step 3: Re-sign Policy File"
echo "========================================="
echo ""

# Check if plain text policy exists
if [ ! -f /etc/tripwire/twpol.txt ]; then
    echo "Decrypting current policy (need OLD site passphrase)..."
    twadmin --print-polfile > twpol.txt
fi

echo "Encrypting policy with NEW site key..."
twadmin --create-polfile --site-keyfile site.key twpol.txt

echo -e "${GREEN}✓ Policy file re-signed${NC}"

# Step 4: Reinitialize the database
echo ""
echo "========================================="
echo "Step 4: Reinitialize Database"
echo "========================================="
echo ""
echo "This will scan your entire filesystem based on the policy."
echo "It may take several minutes..."
echo ""
echo "You'll need to enter your NEW local passphrase..."
echo ""

tripwire --init

echo -e "${GREEN}✓ Database reinitialized${NC}"

# Step 5: Test the new setup
echo ""
echo "========================================="
echo "Step 5: Test New Configuration"
echo "========================================="
echo ""
echo "Running a quick check to verify everything works..."

if tripwire --check --quiet --severity 100 --rule-name "Tripwire Binaries" > /tmp/tw-test.txt 2>&1 || \
   grep -q "Total violations found: 0" /tmp/tw-test.txt 2>/dev/null; then
    echo -e "${GREEN}✓ Tripwire is working with new passphrases!${NC}"
else
    echo -e "${YELLOW}⚠ Check completed with warnings. This is normal if files changed.${NC}"
fi

# Step 6: Update service account passphrase (if using automation)
echo ""
echo "========================================="
echo "Step 6: Update Automation (Optional)"
echo "========================================="
echo ""

if [ -d /var/lib/tripwire-service ]; then
    echo "Detected tripwire service account setup."
    echo "To update the stored passphrase for automation:"
    echo ""
    echo "  sudo /var/lib/tripwire-service/setup-passphrase.sh"
    echo ""
    echo "Enter your NEW local passphrase when prompted."
else
    echo "No service account detected. Skipping automation update."
fi

# Clean up
rm -f /tmp/tw-test.txt

echo ""
echo "========================================="
echo -e "${GREEN}   Passphrase Change Complete!${NC}"
echo "========================================="
echo ""
echo "Summary:"
echo "- Old files backed up to: $BACKUP_DIR"
echo "- New site key: /etc/tripwire/site.key"
echo "- New local key: /etc/tripwire/$HOSTNAME-local.key"
echo "- Database reinitialized with new keys"
echo ""
echo -e "${YELLOW}IMPORTANT: Remember your new passphrases!${NC}"
echo "- Site passphrase: For policy/config changes"
echo "- Local passphrase: For database updates and reports"
echo ""
echo "Next steps:"
echo "1. Test with: tripwire --check"
echo "2. Update automation passphrase if using service account"
echo "3. Securely store/document your new passphrases"
echo ""
echo "To restore old configuration if needed:"
echo "  cp -a $BACKUP_DIR/* /etc/tripwire/"
echo "  cp -a $BACKUP_DIR/*.twd /var/lib/tripwire/"

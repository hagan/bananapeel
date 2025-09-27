# Tripwire Passphrase Management Guide

## Understanding Tripwire Passphrases

Tripwire uses TWO different passphrases:

1. **Site Passphrase** - Protects configuration and policy files
   - Used when: Changing policy, updating configuration
   - Key file: `/etc/tripwire/site.key`

2. **Local Passphrase** - Protects database and reports
   - Used when: Updating database, running checks, creating reports
   - Key file: `/etc/tripwire/$HOSTNAME-local.key`

## Common Operations

### Change Passphrases (Complete Rebuild)
```bash
# Regenerates keys and rebuilds
# From source tree:
sudo bash scripts/setup/change-tripwire-passphrase.sh
# Or after installation:
# sudo change-tripwire-passphrase.sh
```

### Rebuild Database (Keep Same Passphrase)
```bash
# Reinitialize the database with current keys
sudo bash scripts/setup/rebuild-tripwire-database.sh
# Or after installation:
# sudo rebuild-tripwire-database.sh

# Or manually:
sudo tripwire --init
```

### Update Database After Changes
```bash
# Accept all changes (after system updates)
sudo tripwire --update --accept-all

# Or review changes interactively
sudo tripwire --update
```

## Step-by-Step: Change Passphrases

### Method 1: Using Our Script (Recommended)
```bash
cd /opt/src/bananapeel
sudo bash change-tripwire-passphrase.sh
```

### Method 2: Manual Process

#### 1. Backup Current Configuration
```bash
sudo mkdir /root/tripwire-backup
sudo cp -a /etc/tripwire/* /root/tripwire-backup/
sudo cp -a /var/lib/tripwire/* /root/tripwire-backup/
```

#### 2. Generate New Keys
```bash
cd /etc/tripwire

# Generate new site key (enter NEW site passphrase)
sudo twadmin --generate-keys --site-keyfile site.key

# Generate new local key (enter NEW local passphrase)
sudo twadmin --generate-keys --local-keyfile $HOSTNAME-local.key
```

#### 3. Re-encrypt Configuration with New Keys

First, decrypt with OLD passphrase (if needed):
```bash
# If you don't have twcfg.txt
sudo twadmin --print-cfgfile > twcfg.txt

# If you don't have twpol.txt
sudo twadmin --print-polfile > twpol.txt
```

Then encrypt with NEW keys:
```bash
# Re-create config file (uses NEW site passphrase)
sudo twadmin --create-cfgfile --site-keyfile site.key twcfg.txt

# Re-create policy file (uses NEW site passphrase)
sudo twadmin --create-polfile --site-keyfile site.key twpol.txt
```

#### 4. Reinitialize Database
```bash
# Uses NEW local passphrase
sudo tripwire --init
```

## Common Issues

### "Incorrect passphrase" Error
- Make sure you're using the right passphrase (site vs local)
- Site passphrase: For policy/config operations
- Local passphrase: For database/report operations

### Lost Passphrase - Recovery Steps
If you've lost your passphrase, you cannot decrypt existing files. You must:

1. **Delete old encrypted files**:
```bash
sudo rm /etc/tripwire/*.key
sudo rm /etc/tripwire/tw.cfg
sudo rm /etc/tripwire/tw.pol
sudo rm /var/lib/tripwire/*.twd
```

2. **Reinstall/Reconfigure**:
```bash
# Generate new keys
sudo twadmin --generate-keys --site-keyfile /etc/tripwire/site.key
sudo twadmin --generate-keys --local-keyfile /etc/tripwire/$HOSTNAME-local.key

# Recreate config (you need twcfg.txt)
sudo twadmin --create-cfgfile --site-keyfile /etc/tripwire/site.key /etc/tripwire/twcfg.txt

# Recreate policy (you need twpol.txt)
sudo twadmin --create-polfile --site-keyfile /etc/tripwire/site.key /etc/tripwire/twpol.txt

# Initialize new database
sudo tripwire --init
```

## Automation Passphrase Update

If you're using the service account automation:

```bash
# Update stored passphrase after changing it
sudo /var/lib/tripwire-service/setup-passphrase.sh
# Enter your NEW local passphrase
```

## Security Best Practices

1. **Use different passphrases** for site and local keys
2. **Make them strong** - At least 15 characters with mixed case, numbers, symbols
3. **Store securely** - Use a password manager or secure documentation
4. **Rotate periodically** - Change passphrases every 90-180 days
5. **Never share** - Each system should have unique passphrases

## Quick Test After Changes

```bash
# Test that new passphrase works
sudo tripwire --check --quiet

# Should prompt for passphrase and complete without errors
```

## Emergency Restore

If something goes wrong and you need to restore:

```bash
# Restore from backup (if you made one)
sudo cp -a /root/tripwire-backup/* /etc/tripwire/
sudo cp -a /root/tripwire-backup/*.twd /var/lib/tripwire/
```

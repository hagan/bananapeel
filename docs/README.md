# Bananapeel - Documentation

This directory contains guides for installing, configuring, and maintaining Tripwire with the Bananapeel automation tools.

## Documentation Overview

### Core Guides

#### [FINAL-SETUP.md](FINAL-SETUP.md)
Complete installation and configuration guide covering:
- Service account setup with limited sudo permissions
- Systemd timer configuration (recommended approach)
- Email reporting setup
- Troubleshooting common installation issues

#### [PASSPHRASE-GUIDE.md](PASSPHRASE-GUIDE.md)
In-depth passphrase management documentation:
- Encryption methods (AES-256-CBC with PBKDF2)
- Secure storage implementation
- Changing passphrases safely
- Recovery procedures

## Problem and Solution

### The Problem
Tripwire can generate very large reports after updates because:
- Package managers update thousands of system files
- The tripwire database becomes outdated after each apt/unattended-upgrade
- Manual database updates require passphrase entry
- Using `tripwire --init` is expensive and rebuilds the entire database

### Our Solution
1. **Service Account**: Dedicated `tripwire` user with limited sudo permissions
2. **Smart Updates**: Use `tripwire --update` instead of `--init`
3. **Systemd Integration**: Predictable daily checks via timer (preferred over APT hooks)
4. **Policy Optimization**: Exclude frequently changing, low-value paths
5. **Secure Automation**: Encrypted passphrase storage tied to machine-id

## Quick Start

### Installation (from /opt/src/bananapeel)
```bash
# Install the tools system-wide
sudo make install

# Run automated setup
sudo /usr/bin/install-tripwire-automation.sh

# Enable daily timer (6:25 AM by default)
sudo systemctl enable --now tripwire-update.timer
```

### Service User
Many commands run under a dedicated service user. Newer installs use `bananapeel`; legacy systems may still use `tripwire`. Use this snippet to select the active user for all commands in this guide:

```bash
# Detect active service user (bananapeel preferred if present)
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)
```

In the examples below, replace explicit usernames with `$SERVICE_USER` where applicable.

### Key Commands
```bash
# Check timer status
systemctl status tripwire-update.timer
systemctl list-timers tripwire*

# View logs
tail -20 /var/log/bananapeel-update.log

# Clear violations after system updates
sudo tripwire --update --accept-all

# Manually trigger integrity check
sudo systemctl start tripwire-update.service

# Test the setup (detect active service user)
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)
sudo -u "$SERVICE_USER" /var/lib/tripwire-service/tripwire-auto-update.sh
```

## How It Works

### Automatic Update Flow (Timer-Based)
1. Systemd timer triggers daily at 6:25 AM
2. Service runs `tripwire-auto-update.sh` as `tripwire` user
3. Script performs integrity check (`tripwire --check`)
4. If significant changes detected (>50 system files):
   - Decrypt stored passphrase
   - Run `tripwire --update --accept-all`
   - Log results and send email
5. If minor changes: Email report with manual review instructions

### Security Model
- **Service Account**: Can only run tripwire check/update, not init or policy changes
- **Passphrase**: Encrypted at rest (AES-256-CBC with PBKDF2), decrypted only in memory
- **Sudo Rules**: Explicitly deny dangerous operations (--init, --generate-keys)
- **Logging**: All operations logged to `/var/log/bananapeel-update.log` (legacy symlink: `/var/log/tripwire-apt-update.log`)

## Reducing Noise

### Common Policy Exclusions
Add to `/etc/tripwire/twpol.txt`:
```
# Package caches
!/var/cache/apt ;
!/var/lib/apt/lists ;

# Python bytecode
!/usr/lib/python*/__pycache__ ;

# Documentation
!/usr/share/man ;
!/usr/share/doc ;

# Temporary files
!/var/tmp ;
!/tmp ;
```

### Apply Policy Changes
```bash
# Recreate policy file
sudo twadmin --create-polfile -S /etc/tripwire/site.key /etc/tripwire/twpol.txt

# Reinitialize database (required after policy change)
sudo tripwire --init
```

## Troubleshooting

### Common Issues

#### "Could not decrypt passphrase"
- Verify `/etc/machine-id` hasn't changed
- Re-run: `sudo /var/lib/tripwire-service/setup-passphrase.sh`

#### Updates not running automatically
- Check timer: `systemctl status tripwire-update.timer`
- Verify service account: `id tripwire`
- Review logs: `journalctl -u tripwire-update.service`

#### Still getting noise after optimization
- Review excluded paths in policy
- Consider excluding entire directory trees
- Use `$(recurse = 1)` to monitor directory structure only

### Verification Commands
```bash
# Check sudo permissions (detect active service user)
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)
sudo -l -U "$SERVICE_USER"

# Test passphrase decryption (PBKDF2 method)
sudo -u "$SERVICE_USER" openssl enc -aes-256-cbc -d -salt -pbkdf2 \
  -pass pass:$(cat /etc/machine-id | sha256sum | cut -d' ' -f1) \
  -in /var/lib/tripwire-service/.tripwire/local-passphrase

# Check update history
grep "violations\|completed" /var/log/bananapeel-update.log | tail -20
```

## Security Considerations

**Warning**: Storing passphrases (even encrypted) reduces security. Consider:
- Using this only on systems with automated updates
- Rotating passphrases regularly
- Monitoring the service account for unauthorized use
- Implementing additional access controls

## Alternative Approaches

1. **Manual-Only**: Don't store passphrase, require manual updates
2. **Notification-Only**: Email when updates needed, don't auto-update
3. **APT Hook Integration**: Install with `--with-apt-hook` flag (not recommended)
4. **Config Management**: Use Ansible/Puppet to manage tripwire

## Additional Resources

### Project Documentation
- [Main README](../README.md) - Project overview and features
- [AGENTS.md](../AGENTS.md) - Contributor guidelines
- [Makefile](../Makefile) - Build and installation targets

### External Resources
- [Tripwire Open Source](https://github.com/Tripwire/tripwire-open-source)
- [Systemd Timers Documentation](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [OpenSSL Encryption Reference](https://www.openssl.org/docs/man1.1.1/man1/openssl-enc.html)

---

*Note: For internal development documentation and project management, see the `.claude/` directory.*

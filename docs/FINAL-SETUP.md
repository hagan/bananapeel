# Tripwire Configuration - Final Setup Documentation

## Summary of Achievements

### Noise Reduction Summary
- Before: tens of thousands of violations
- After: under 100 (mostly dpkg/system updates)
- Result: >99% reduction

### Migration Complete
- Migrated from `/etc/cron.daily/tripwire` to a systemd timer
- Runs once daily (timer schedule configurable; defaults to `OnCalendar=daily` with randomized delay)
- Includes email reports with helpful commands

## Current Configuration

### 1. Policy Optimization (`/etc/tripwire/twpol.txt`)
Exclusions added for:
- Old kernel modules (6.8.0-79, 6.8.0-84)
- Firmware updates (`/usr/lib/firmware/`)
- Package caches (`/var/cache/apt`, `/var/lib/apt/lists`)
- Python bytecode (`__pycache__`)
- Documentation (`/usr/share/man`, `/usr/share/doc`)
- Systemd volatile state
- Log files (monitored separately)

### 2. Systemd Timer (`/etc/systemd/system/bananapeel-update.timer`)
```
OnCalendar=daily          # Daily execution
OnBootSec=30min           # Run 30 min after boot if missed
RandomizedDelaySec=1h     # Random delay to avoid load spikes
Persistent=true           # Run if system was off
```

### 3. Service Account and Automation
- User: `tripwire`
- Home: `/var/lib/tripwire-service/`
- Script: `/var/lib/tripwire-service/tripwire-auto-update.sh` (unified canonical version)
- Wrapper: `/usr/local/lib/bananapeel/tripwire-wrapper` (validates all arguments)
- Sudo: Restricted to wrapper only - no direct tripwire access
- Concurrency: Uses flock on `/var/run/bananapeel-update.lock` to prevent duplicate runs

#### Configuration Options
The automation script supports environment variable overrides:
- `EMAIL_TO`: Email recipient for reports (default: root)
- `AUTO_ACCEPT_THRESHOLD`: System files change threshold for auto-accept (default: 50, set to 0 to disable)
- `DRY_RUN`: Test mode without making changes (default: 0)

### 4. Email Report Contents
- Full Tripwire output (file details)
- Added/Modified/Removed file list
- Violation count and classification
- Exact commands to accept changes (with actual report filename)
- Rule summary with severities

## File Locations

| Component | Path |
|-----------|------|
| Policy file | `/etc/tripwire/twpol.txt` |
| Database | `/var/lib/tripwire/$(hostname -f).twd` |
| Reports | `/var/lib/tripwire/report/*.twr` |
| Automation script | `/var/lib/tripwire-service/tripwire-auto-update.sh` |
| Log file | `/var/log/bananapeel-update.log` (legacy symlink: `/var/log/tripwire-apt-update.log`) |
| Timer | `/etc/systemd/system/tripwire-update.timer` |
| Service | `/etc/systemd/system/tripwire-update.service` |
| Old cron (disabled) | `/etc/cron.daily/tripwire` |

## Daily Operations

### What Happens at 6:25 AM
1. Systemd timer triggers `tripwire-update.service`
2. Service runs as `tripwire` user
3. Executes `tripwire --check --quiet --email-report`
4. Analyzes violations:
   - 0 violations → Email: "OK"
   - <50 system files → Email: "MANUAL REVIEW REQUIRED"
   - ≥50 system files → Email: "PACKAGE UPDATES DETECTED"
5. Email includes exact commands to run

### Manual Commands

```bash
# Check current status
sudo tripwire --check

# View a specific report
sudo twprint --print-report --twrfile /var/lib/tripwire/report/[filename].twr

# Accept all changes from a report
sudo tripwire --update --twrfile /var/lib/tripwire/report/[filename].twr --accept-all

# Interactive review (accept/reject each change)
sudo tripwire --update --twrfile /var/lib/tripwire/report/[filename].twr

# Check service status
systemctl status tripwire-update.timer
bananapeel-status  # or legacy alias: tripwire-status

# View logs
tail -f /var/log/bananapeel-update.log
journalctl -u tripwire-update.service
```

## Troubleshooting

### Issue: "File system error" for remote-ips files
**Solution**: Files have been created at:
- `/var/lib/tripwire/remote-ips.txt`
- `/var/lib/tripwire/remote-ips.changes`

### Issue: Too many violations after package updates
**Solution**: Run the accept command from the email report:
```bash
sudo tripwire --update --twrfile [report_file] --accept-all
```

### Issue: No email received
**Check**:
1. Sendmail is working: `echo "test" | mail -s "test" root`
2. Timer is running: `systemctl status tripwire-update.timer`
3. Check logs: `/var/log/bananapeel-update.log`

### Issue: Timer not running
```bash
sudo systemctl daemon-reload
sudo systemctl enable tripwire-update.timer
sudo systemctl start tripwire-update.timer
```

## Security Notes

- Service account has **limited** sudo access (no --init, no policy changes)
- Passphrase storage is optional (for full automation)
- All actions logged for audit trail
- Email reports go to root by default

## Testing

To test the entire setup:
```bash
# Run as service user (safe test)
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)
sudo -u "$SERVICE_USER" /var/lib/tripwire-service/tripwire-auto-update.sh

# Check if email was sent
mail

# View the log
tail /var/log/bananapeel-update.log
```

## Success Metrics

- Noise reduction: ~99.8% fewer false positives
- Automation: daily checks via systemd
- Migration: cron → systemd completed
- Reporting: email reports with actionable commands
- Security: limited service account; no exposed credentials

## Implementation Issues Fixed

### Recent Updates
1. Service exit handling improved where implemented
2. Email content enhanced to include detailed output (like the old cron job)
3. Remote-ips files created if missing

### Working Configuration
- Service: `/etc/systemd/system/tripwire-update.service`
- Timer: `/etc/systemd/system/tripwire-update.timer` (daily with randomized delay by default)
- Script: `/var/lib/tripwire-service/tripwire-auto-update.sh` with full email reports

## Final Notes

The system is now configured to:
1. Run daily integrity checks via systemd timer (schedule configurable)
2. Email **full detailed reports** with complete file listings
3. Distinguish between package updates (>50 files) and other changes
4. Maintain low false-positive rate through smart exclusions
5. Provide exact update commands with actual report filenames

The old cron job has been disabled but preserved at `/etc/cron.daily/tripwire` with a migration note.

---
*Configuration template for production deployments*

# Bananapeel - Tripwire Management Suite

Bananapeel provides tools to automate and manage [Tripwire (Open Source)](https://github.com/Tripwire/tripwire-open-source) on Linux systems. It focuses on reliable installation, daily checks, passphrase handling, policy tuning, and packaging for distribution.

## Features

- **Installer**: Sets up Tripwire and a systemd timer
- **Passphrase management**: Encrypted storage for unattended operations
- **Daily checks**: Timer-based scheduling via systemd
- **Policy tools**: Reduce noise and tune policy rules
- **Email reporting**: Violation summaries by email
- **Auto-accept (optional)**: Threshold-based database updates during maintenance windows
- **Packaging**: Make targets and templates for Debian and RPM

## Prerequisites

- Operating System: Linux (Debian/Ubuntu, RHEL/CentOS/Fedora) or FreeBSD
- Tripwire installed (`apt-get install tripwire`, `yum install tripwire`, or `pkg install tripwire`)
- Bash 4.0 or higher
- Root/sudo access for installation
- Optional: `mailutils` or `mailx` for email notifications

## Platform Support

Bananapeel supports multiple platforms with automatic detection and configuration:

### Linux Distributions
- **Debian/Ubuntu**:
  - Scheduler: systemd timer
  - Package hook: APT (optional via --with-apt-hook)
  - Log rotation: logrotate
- **RHEL/CentOS/Fedora**:
  - Scheduler: systemd timer
  - Package hook: YUM (coming soon)
  - Log rotation: logrotate
- **Other Linux**:
  - Scheduler: systemd timer
  - Package hook: Not available
  - Log rotation: logrotate

### FreeBSD
- Scheduler: periodic(8) daily
- Package hook: Not available
- Log rotation: newsyslog

The cross-platform installer (`install-tripwire-automation-crossplatform.sh`) automatically detects your platform and configures appropriate paths, schedulers, and log rotation.

## Quick Start

### From Source

```bash
# Clone or download to /opt/src
cd /opt/src/bananapeel

# Review and customize configuration
vi config/99bananapeel

# Install system-wide
sudo make install

# Run the automated setup (timer enabled by default)
# Use the cross-platform installer for automatic platform detection:
sudo /usr/bin/install-tripwire-automation-crossplatform.sh

# Or use the standard Linux installer:
sudo /usr/bin/install-tripwire-automation.sh
```

### Building Packages

```bash
# Build Debian package
make package-deb

# Build RPM package
make package-rpm

# Build FreeBSD package (coming soon)
make package-freebsd

# Build all package types
make package-all
```

### Platform-Specific Installation

#### Debian/Ubuntu
```bash
# Install from .deb package
sudo dpkg -i bananapeel_0.2.0-1_all.deb
sudo apt-get install -f  # Fix dependencies if needed
```

#### RHEL/CentOS/Fedora
```bash
# Install from RPM
sudo rpm -ivh bananapeel-0.2.0-1.noarch.rpm
# or with yum/dnf
sudo yum install ./bananapeel-0.2.0-1.noarch.rpm
```

#### FreeBSD
```bash
# Use cross-platform installer
sudo /usr/bin/install-tripwire-automation-crossplatform.sh

# Or install from ports (coming soon)
cd /usr/ports/security/bananapeel
sudo make install
```

## Project Structure

```
/opt/src/bananapeel/
├── scripts/           # Main executable scripts
│   ├── setup/        # Installation and configuration tools
│   └── maintenance/  # Ongoing management utilities
│   └── lib/          # Shared shell helpers (sourced by scripts)
├── config/           # Default configuration files
├── docs/            # Documentation and guides
├── packaging/       # Package building templates
├── tests/           # Test suite
└── Makefile         # Build and installation automation
```

## Available Tools

### Setup Scripts
- `install-tripwire-automation.sh` - Main installer with systemd timer setup
- `setup-tripwire-service-account.sh` - Create dedicated service account with sudo permissions
- `setup-tripwire-final.sh` - Configure automation with email reporting
- `change-tripwire-passphrase.sh` - Safely update Tripwire passphrases
- `optimize-tripwire-policy.sh` - Tune policy to reduce false positives

### Maintenance Scripts
- `tripwire-summary.sh` - Generate violation summary reports
- `rebuild-tripwire-database.sh` - Reinitialize database after major changes

## Installer Flags

Both installers support the same comprehensive set of flags for customization. Note that APT hook functionality is only available on Debian/Ubuntu systems.

```bash
# Show all available options
sudo install-tripwire-automation-crossplatform.sh --help
# or
sudo install-tripwire-automation.sh --help

# Basic installation with defaults (timer-only, no APT hook)
sudo install-tripwire-automation-crossplatform.sh

# Install with APT hook for package-triggered checks (Debian/Ubuntu only)
sudo install-tripwire-automation-crossplatform.sh --with-apt-hook

# Custom email recipient
sudo install-tripwire-automation-crossplatform.sh --email admin@example.com

# Disable auto-accept for package updates
sudo install-tripwire-automation-crossplatform.sh --threshold 0

# Multiple options
sudo install-tripwire-automation-crossplatform.sh --with-apt-hook --email admin@example.com --threshold 100

# Dry run to preview changes
sudo install-tripwire-automation-crossplatform.sh --dry-run --with-apt-hook

# Install without timer (APT hook only - Debian/Ubuntu)
sudo install-tripwire-automation-crossplatform.sh --with-apt-hook --no-timer
```

### Default Configuration
- **Timer**: Enabled (daily at 6:25 AM)
- **APT Hook**: Disabled (use `--with-apt-hook` to enable)
- **Email**: root
- **Auto-Accept Threshold**: 50 system files
- **Security Wrapper**: Enabled

## Configuration

### Central Configuration File
Bananapeel uses a central configuration file at `/etc/bananapeel/bananapeel.conf` for default settings. A sample configuration is installed at `/usr/share/bananapeel/bananapeel.conf.sample` for reference. Installers seed `/etc/bananapeel/bananapeel.conf` from this sample if the file is missing and never overwrite an existing configuration.

The configuration supports a clear precedence order:

1. **Systemd Environment variables** (highest priority) - Set in the service unit
2. **Configuration file** - `/etc/bananapeel/bananapeel.conf`
3. **Built-in defaults** (lowest priority) - Hardcoded in the script

#### Configuration Keys
```bash
# /etc/bananapeel/bananapeel.conf

# Email recipient for reports (default: root)
BANANAPEEL_EMAIL_TO="admin@example.com"

# Auto-accept threshold (0 to disable, default: 50)
BANANAPEEL_THRESHOLD="50"

# Dry-run mode (0=normal, 1=test mode, default: 0)
BANANAPEEL_DRY_RUN="0"
```

**Note**: During installation, `/etc/bananapeel/bananapeel.conf` is created from the sample if it doesn't exist. Existing configurations are never overwritten to preserve local customizations.

#### Example: Override via systemd
To override configuration for a specific instance:
```bash
# Edit the service unit
sudo systemctl edit bananapeel-update.service

# Add environment overrides:
[Service]
Environment="EMAIL_TO=security@example.com"
Environment="AUTO_ACCEPT_THRESHOLD=100"
```

### Systemd Timer (Default)
By default, the installer sets up a systemd timer for daily execution at 6:25 AM:

```bash
# Check timer status
systemctl status bananapeel-update.timer

# View next scheduled run
systemctl list-timers bananapeel*
# Note: Legacy tripwire-update.timer is aliased for one release

# Manually trigger a check
sudo systemctl start bananapeel-update.service
```

### APT Hook (Optional)
For systems that need checks after package updates:
```bash
sudo install-tripwire-automation.sh --with-apt-hook
```

### Runtime Configuration
The automation script supports the following configuration precedence:
```bash
# Priority order (highest to lowest):
# 1. Environment variables (EMAIL_TO, AUTO_ACCEPT_THRESHOLD, DRY_RUN)
# 2. Config file variables (BANANAPEEL_EMAIL_TO, BANANAPEEL_THRESHOLD, BANANAPEEL_DRY_RUN)
# 3. Built-in defaults

# The script includes:
# - Concurrency lock at /var/run/bananapeel-update.lock
# - Automatic passphrase decryption for unattended updates
# - Rich email reporting with violation summaries
# - Intelligent categorization of changes (package updates vs manual changes)
```

### Shared Library
- `make install` places the shared library at `/usr/share/bananapeel/bananapeel-lib.sh`.
- Project scripts attempt to source this library when available and fall back to internal helpers when not installed.
- Packagers: include this file alongside the automation script to ensure consistent behavior.

## Branding Migration Note

The APT hook has been renamed from `99tripwire` to `99bananapeel` to align with the project branding. The legacy `99tripwire` name is still supported for one release cycle with deprecation warnings. If you have the old hook installed, it will be automatically migrated to the new name during installation.

## Monitoring

### Status Command
The `bananapeel-status` command provides comprehensive status information with multiple output modes:

```bash
# Human-readable status with full configuration summary
bananapeel-status

# JSON output for automation/monitoring
bananapeel-status --json

# Exit code only (no output) for scripting
bananapeel-status --check-only

# Summarize runs from the last 24 hours
bananapeel-status --since 24h

# Summarize runs from the last 7 days in JSON format
bananapeel-status --since 7d --json

# Summarize runs since specific timestamp
bananapeel-status --since "2025-09-27T00:00:00Z"

# Example JSON output:
# {"ts":"2025-09-27T06:25:00Z","host":"server01","violations":5,"sys_changes":2,"status":"MANUAL REVIEW REQUIRED","latest_twr":"/var/lib/tripwire/report/server01-20250927-062500.twr"}

# Example --since JSON output:
# {
#   "since": "24h",
#   "total": 4,
#   "counts": {
#     "OK": 2,
#     "PACKAGE_UPDATES_AUTO_ACCEPTED": 1,
#     "PACKAGE_UPDATES_DETECTED": 0,
#     "MANUAL_REVIEW_REQUIRED": 1,
#     "ERROR": 0
#   },
#   "counts_raw": {
#     "OK": 2,
#     "PACKAGE UPDATES AUTO-ACCEPTED": 1,
#     "PACKAGE UPDATES DETECTED": 0,
#     "MANUAL REVIEW REQUIRED": 1,
#     "ERROR": 0
#   },
#   "latest_timestamp": "2025-09-28T06:25:00Z"
# }
```

#### Command Options
- `--json` - Output in JSON format
- `--check-only` - Exit with status code only (no output)
- `--since <TIME>` - Summarize runs since TIME (formats: `24h`, `7d`, `30m`, or RFC3339 timestamp)
- `--help` - Show usage information

Notes:
- The `counts` object uses normalized keys (spaces replaced with underscores). The `counts_raw` object preserves the original status labels for convenience.
- On systems without GNU/BSD date support for relative times, `--since` falls back to including all runs and may add a note indicating limited date support.

#### Exit Codes
The status command returns appropriate exit codes for scripting:
- `0` - OK or PACKAGE UPDATES AUTO-ACCEPTED (system is secure)
- `1` - PACKAGE UPDATES DETECTED or MANUAL REVIEW REQUIRED (attention needed)
- `2` - Error or unknown status (check configuration)

### Logs and Reports
```bash
# Check recent activity
tail -f /var/log/bananapeel-update.log
# Note: Legacy log path /var/log/tripwire-apt-update.log is symlinked for one release

# Extract JSON summaries from log
grep "^SUMMARY_JSON=" /var/log/bananapeel-update.log

# Review latest report
sudo tripwire --print-report --report-file $(ls -t /var/lib/tripwire/report/*.twr | head -1)
```

### Service User
Some operational commands run under a dedicated service user. On newer installs this is `bananapeel`; on legacy systems it is `tripwire`. Use this snippet to select the active user when needed:

```bash
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)
sudo -u "$SERVICE_USER" /var/lib/tripwire-service/tripwire-auto-update.sh
```

### JSON Schemas

Bananapeel emits JSON for monitoring and integration purposes. Two types of JSON are available:

#### Run Summary (SUMMARY_JSON lines in log)

Each automation run emits a `SUMMARY_JSON=` line to `/var/log/bananapeel-update.log`:

```json
{
  "ts": "2025-09-27T06:25:00Z",
  "host": "server01",
  "violations": 5,
  "sys_changes": 2,
  "status": "MANUAL REVIEW REQUIRED",
  "latest_twr": "/var/lib/tripwire/report/server01-20250927-062500.twr"
}
```

**Fields:**
- `ts` (string): RFC3339 UTC timestamp of the check
- `host` (string): Hostname
- `violations` (number): Total violations detected
- `sys_changes` (number): System changes detected (package/kernel updates)
- `status` (string): One of:
  - `"OK"` - No violations detected
  - `"PACKAGE UPDATES AUTO-ACCEPTED"` - Changes auto-accepted via threshold
  - `"PACKAGE UPDATES DETECTED"` - Manual update needed (threshold disabled)
  - `"MANUAL REVIEW REQUIRED"` - Violations without system changes
- `latest_twr` (string): Path to latest report file, or empty if none

**String Escaping:** The JSON properly escapes quotes (`\"`), backslashes (`\\`), and newlines (`\n`) in string values.

#### Time-Window Summary (--since with --json)

The `bananapeel-status --since <TIME> --json` command outputs:

```json
{
  "since": "24h",
  "total": 4,
  "counts": {
    "OK": 2,
    "PACKAGE_UPDATES_AUTO_ACCEPTED": 1,
    "PACKAGE_UPDATES_DETECTED": 0,
    "MANUAL_REVIEW_REQUIRED": 1,
    "ERROR": 0
  },
  "counts_raw": {
    "OK": 2,
    "PACKAGE UPDATES AUTO-ACCEPTED": 1,
    "PACKAGE UPDATES DETECTED": 0,
    "MANUAL REVIEW REQUIRED": 1,
    "ERROR": 0
  },
  "latest_timestamp": "2025-09-28T06:25:00Z",
  "note": "limited date support"
}
```

**Fields:**
- `since` (string): The time input provided (duration or RFC3339)
- `total` (number): Total runs in the time window
- `counts` (object): Status counts with normalized keys (underscores)
- `counts_raw` (object): Status counts with original labels (spaces)
  Note: `counts_raw` is provided for convenience/compatibility and may be omitted in the future; prefer `counts` for integrations.
- `latest_timestamp` (string): RFC3339 timestamp of most recent run
- `note` (string, optional): Present when date parsing has limitations

**Status to Exit Code Mapping:**
- Exit 0: `"OK"`, `"PACKAGE UPDATES AUTO-ACCEPTED"` (system secure)
- Exit 1: `"PACKAGE UPDATES DETECTED"`, `"MANUAL REVIEW REQUIRED"` (attention needed)
- Exit 2: `"ERROR"` or unknown status (check configuration)

### Integration Examples
```bash
# Simple monitoring check (exit code only)
if ! bananapeel-status --check-only; then
    echo "Alert: Tripwire needs attention"
    # Send alert...
fi

# Extract last run status and violations from log
grep "^SUMMARY_JSON=" /var/log/bananapeel-update.log | tail -1 | cut -d= -f2- | \
  jq -r '"\(.status): \(.violations) violations at \(.ts)"'

# Alternative without cut: strip prefix via sed
grep "^SUMMARY_JSON=" /var/log/bananapeel-update.log | tail -1 | sed 's/^SUMMARY_JSON=//' | \
  jq -r '"[\(.ts)] \(.host) → \(.status) (\(.violations))"'

# Get current violations count
bananapeel-status --json | jq '.violations'

# Daily report with formatting
bananapeel-status --json | jq -r '"[\(.ts)] \(.host): \(.status) - \(.violations) violations"'

# Generate daily summary (human-readable)
bananapeel-status --since 24h

# Extract total runs and issue counts from last week
bananapeel-status --since 7d --json | \
  jq '{total: .total, ok: .counts.OK, manual_review: .counts.MANUAL_REVIEW_REQUIRED}'

# Get latest timestamp from log history
bananapeel-status --since 30d --json | jq -r '.latest_timestamp'

# Monitor for issues in the last week
STATUS_JSON=$(bananapeel-status --since 7d --json)
MANUAL_COUNT=$(echo "$STATUS_JSON" | jq '.counts.MANUAL_REVIEW_REQUIRED')
if [ "$MANUAL_COUNT" -gt 0 ]; then
    echo "Warning: $MANUAL_COUNT runs required manual review in the last week"
fi

# Alert on high violation rate
RECENT_JSON=$(grep "^SUMMARY_JSON=" /var/log/bananapeel-update.log | tail -1 | cut -d= -f2-)
VIOLATIONS=$(echo "$RECENT_JSON" | jq '.violations')
if [ "$VIOLATIONS" -gt 10 ]; then
    echo "ALERT: $VIOLATIONS violations detected"
fi

# Cron job for weekly summary email
# 0 9 * * 1 bananapeel-status --since 7d | mail -s "Weekly Tripwire Summary" admin@example.com

# Nagios/monitoring plugin example
#!/bin/bash
bananapeel-status --check-only
EXIT_CODE=$?
case $EXIT_CODE in
    0) echo "OK: System secure"; exit 0 ;;
    1) echo "WARNING: Review needed"; exit 1 ;;
    2) echo "CRITICAL: Error state"; exit 2 ;;
esac
```

### Status-Only Helper

For Nagios-style checks, a compact helper is provided at `scripts/maintenance/status-check.sh`:

```bash
# One-line status with correct exit code (0/1/2)
/usr/bin/status-check.sh  # after make install
# or from repo:
scripts/maintenance/status-check.sh

# Example output:
# OK: MANUAL REVIEW REQUIRED - violations=3 host=server01 ts=2025-09-28T06:25:00Z
```

This helper:
- Calls the status command in JSON mode
- Prints a single summary line and exits with monitoring-friendly codes
- Uses `jq` if available; falls back to simple parsing

## Log Rotation

The installer places a logrotate policy at `/etc/logrotate.d/bananapeel` to rotate `/var/log/bananapeel-update.log` daily (7 copies, compressed). Adjust as needed.

## Service User Migration

The project supports migrating from the legacy `tripwire` service user to the new `bananapeel` user for improved clarity and branding alignment.

### Migration Features
- **Opt-in migration**: Not automatic, requires explicit flag
- **UID/GID preservation**: Maintains same IDs for compatibility
- **Automatic backup**: Creates backup before any changes
- **Rollback support**: Can revert to previous state if needed
- **Dry-run mode**: Preview changes without applying them

### Migration Process

```bash
# Preview migration (dry-run)
sudo bash scripts/setup/migrate-service-user.sh --dry-run

# Perform migration
sudo bash scripts/setup/migrate-service-user.sh

# Or use installer flag for new installations
sudo /usr/bin/install-tripwire-automation.sh --migrate-service-user

# Rollback if needed (using backup directory)
sudo bash scripts/setup/migrate-service-user.sh --rollback /var/backups/bananapeel-migration-YYYYMMDD-HHMMSS
```

### What Gets Migrated
- Service user and group (`tripwire` → `bananapeel`)
- File ownership in `/var/lib/tripwire-service/`
- Log file ownership
- Sudoers configuration
- Systemd service units

### Migration Safety
- Services are stopped during migration
- All changes are logged
- Backup created automatically
- Validation performed after migration
- Clear rollback instructions provided

### Determine Active Service User
After migration, the service user may be `bananapeel`; on legacy systems it remains `tripwire`. Use this snippet to select the active user in commands and scripts:

```bash
# Detect active service user (bananapeel preferred if present)
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)

# Run the automation script as the service user
sudo -u "$SERVICE_USER" /var/lib/tripwire-service/tripwire-auto-update.sh
```

Tip: Setup scripts also honor `SERVICE_USER` and `SERVICE_GROUP` environment variables during installation.

## Security Considerations

- Passphrases are encrypted using AES-256-CBC with machine-specific keys
- Service account runs with minimal sudo privileges via restricted wrapper
- Wrapper script (`/usr/local/lib/bananapeel/tripwire-wrapper`) validates all arguments
- Only specific tripwire operations are allowed through the wrapper
- All scripts validate inputs and use safe practices
- Sensitive files are protected with restrictive permissions (400/600)

### Security Wrapper
The automation uses a restricted wrapper for sudo access, allowing only:
- `check`: Run integrity checks with optional `--quiet` and `--email-report`
- `update`: Update database for reports in `/var/lib/tripwire/report/`
- `print`: Print reports from `/var/lib/tripwire/report/`

Administrators can still run tripwire commands directly with appropriate privileges.

## Testing

```bash
# Run syntax and lint checks
make test

# Run with strict mode (fails on any issue)
STRICT=1 make test
```

- Functional tests (rootless, mocked)
  - `make test-functional` runs end-to-end tests using mocks for `sudo`, `tripwire`, `twprint`, `sendmail`/`mail`, `logger`, `find`, `ls`, and `hostname` — no root or systemd required.
  - Optional JSON-only check: `TEST_ONLY=escape bash tests/functional/test_automation.sh` to validate JSON escaping behavior specifically.
  - Dependencies: `bash`; `jq` is optional (tests fall back to simple parsing when missing).

- Environment overrides used in tests (also supported by the automation script):
  - `LOGFILE` — path to write run logs (default `/var/log/bananapeel-update.log`).
  - `LOCK_FILE` — path to the concurrency lock file (default `/run/bananapeel/update.lock`).
  - `EMAIL_TO`, `AUTO_ACCEPT_THRESHOLD`, `DRY_RUN` — runtime behavior controls (env > `/etc/bananapeel/bananapeel.conf` > built-ins).
  - `TEST_OUTBOX` — when set, the mail and logger mocks append messages to this file for inspection.
  - `TEST_HOSTNAME`, `TEST_TWR_NAME` — used by mocks to inject tricky values for JSON escaping tests.

Tip: To quickly smoke-test locally without the full suite, see `tests/functional/quick_test.sh`.

## Documentation

- [PASSPHRASE-GUIDE.md](docs/PASSPHRASE-GUIDE.md) - Passphrase management details
- [FINAL-SETUP.md](docs/FINAL-SETUP.md) - Complete setup walkthrough
- [CURRENT-STATUS.md](docs/CURRENT-STATUS.md) - Implementation status
- [AGENTS.md](AGENTS.md) - Contributor guidelines

## Deprecation Timeline

### Legacy Artifacts (v0.3.0 Removal)

The following legacy artifacts from the original `tripwire-update` naming are deprecated and will be removed in v0.3.0:

| Artifact | Type | Migration Path |
|----------|------|----------------|
| `/etc/systemd/system/tripwire-*.timer` | Systemd alias | Use `bananapeel-update.timer` |
| `/etc/apt/apt.conf.d/99bananapeel` | APT hook | Use systemd timer approach |
| `/var/log/tripwire-apt-update.log` | Log symlink | Use `/var/log/bananapeel-update.log` |
| `/usr/local/bin/tripwire-status` | Command symlink | Use `bananapeel-status` |

#### Detecting Legacy Artifacts

Run `bananapeel-status` to check for legacy artifacts on your system:

```bash
sudo bananapeel-status
# Look for the "⚠ LEGACY ARTIFACTS DETECTED" warning section
```

#### Timeline

- **v0.2.x** (Current): Deprecation warnings added, no functionality removed
- **v0.3.0** (Future): Complete removal of legacy artifacts
  - Installers will no longer create legacy aliases
  - Existing legacy artifacts will NOT be automatically removed
  - Manual cleanup may be required on upgraded systems

#### Recommended Actions

1. **New Installations**: Use the latest installer without `--with-apt-hook`
2. **Existing Systems**:
   - Run `bananapeel-status` to identify legacy artifacts
   - Follow the displayed migration instructions
   - Consider running the service user migration if using `tripwire` user

## Contributing

1. Review [AGENTS.md](AGENTS.md) for coding standards and guidelines
2. Test changes in a VM or container first
3. Run `make test` before submitting
4. Use conventional commits (`feat:`, `fix:`, `docs:`)
5. Include test results and security impact in PRs

## Troubleshooting

### Email Spam Issues
If receiving excessive emails:
```bash
# Quick fix - remove APT hook and kill processes
sudo rm /etc/apt/apt.conf.d/99bananapeel
# Also remove legacy hook if present
sudo rm -f /etc/apt/apt.conf.d/99tripwire
pkill -f tripwire

# Reinstall properly
sudo bash setup-tripwire-final.sh
sudo tripwire --update --accept-all
```

### Passphrase Errors
If seeing "Could not decrypt passphrase":
```bash
# Verify encryption method matches (detect active service user)
SERVICE_USER=$(getent passwd bananapeel >/dev/null 2>&1 && echo bananapeel || echo tripwire)
sudo -u "$SERVICE_USER" openssl enc -aes-256-cbc -d -salt -pbkdf2 \
  -pass pass:$(cat /etc/machine-id | sha256sum | cut -d' ' -f1) \
  -in /var/lib/tripwire-service/.tripwire/local-passphrase
```

### Timer Not Running
```bash
# Enable and start timer
sudo systemctl enable bananapeel-update.timer
sudo systemctl start bananapeel-update.timer

# Verify next run scheduled
systemctl list-timers bananapeel*
```

## Release Process

To create a new release:

1. **Update VERSION file**:
   ```bash
   echo "X.Y.Z" > VERSION
   ```

2. **Clean and build packages**:
   ```bash
   make clean
   make package-all
   ```

3. **Create and push git tag**:
   ```bash
   git add VERSION
   git commit -m "chore: bump version to X.Y.Z"
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin main
   git push --tags
   ```

4. **Locate built artifacts**:
   - **Debian**: `build/debian/bananapeel_X.Y.Z-1_all.deb`
   - **RPM**: `build/rpm/RPMS/noarch/bananapeel-X.Y.Z-1.noarch.rpm`

5. **Generate checksums** (optional):
   ```bash
   shasum -a 256 build/debian/*.deb > SHA256SUMS
   shasum -a 256 build/rpm/RPMS/noarch/*.rpm >> SHA256SUMS
   ```

6. **Upload to release page**:
   - Create GitHub release from the tag
   - Attach package files and SHA256SUMS
   - Include changelog in release notes

## Packaging

The Makefile provides preparation and build targets for Debian and RPM packages that derive versions from the `VERSION` file.

- Prep targets (no network, deterministic trees):
  - `make package-prep-deb` → prepares `build/debian/bananapeel-<VERSION>/debian/{control,rules,changelog,postinst,postrm}`
  - `make package-prep-rpm` → creates `build/rpm/SOURCES/bananapeel-<VERSION>.tar.gz` and `build/rpm/SPECS/bananapeel.spec`
- Build targets (require local tooling):
  - `make package-deb` → runs `dpkg-buildpackage` in the prepared tree
  - `make package-rpm` → runs `rpmbuild -bb` with the generated spec

CI validation:
- The workflow `.github/workflows/lint.yml` includes a `package-prep` job that:
  - Runs the prep targets and verifies Debian control files and RPM artifacts exist
  - Checks that package versions match the `VERSION` file
  - Optionally parses Debian changelog (`dpkg-parsechangelog`) and expands the RPM spec (`rpmspec -P`) when tools are available

## License

This project is licensed under the GPL-3.0 License - see [LICENSE](LICENSE) file for details.

## Roadmap

See the prioritized task board at .claude/tasks/TASKS-BOARD.md for current and upcoming work.

## Support

For issues, feature requests, or questions:
- Open an issue on the project repository
- Check existing documentation in [docs/](docs/)
- Review [.claude/issues/](.claude/issues/) for known problems

---

**Note**: This project enhances Tripwire but is not affiliated with the official Tripwire project. Always test in a non-production environment first.
## Security Wrapper

By default, automation runs tripwire commands via a restricted wrapper at `/usr/local/lib/bananapeel/tripwire-wrapper` to minimize sudo exposure. The installer flag `--no-wrapper` disables use of the wrapper and grants a minimal set of direct tripwire commands in sudoers (for debugging only). Leave the wrapper enabled for production systems.

### Sudoers Security Model

Bananapeel uses a defense-in-depth security model with two modes:

**Wrapper Mode (Default, USE_WRAPPER=1):**
- Service account `tripwire` can only execute `/usr/local/lib/bananapeel/tripwire-wrapper` via sudo
- No direct access to `/usr/sbin/tripwire` or `/usr/sbin/twprint` binaries
- Wrapper validates all arguments and restricts operations to safe subset:
  - `check`: Run integrity checks (with optional `--quiet` and `--email-report`)
  - `update`: Update database (path-constrained to `/var/lib/tripwire/report/*.twr` only)
  - `print`: Print reports (path-constrained to `/var/lib/tripwire/report/*.twr` only)
- Triple-layer environment security:
  - `env_reset`: Clears all environment variables
  - `!setenv`: Prevents setting new environment variables via sudo
  - `secure_path=/usr/sbin:/usr/bin:/bin`: Restricts $PATH to trusted directories
- Cannot perform dangerous operations like `--init`, `--generate-keys`, or `--update-policy`

**Debug Mode (USE_WRAPPER=0):**
- Service account can execute specific tripwire commands directly
- Path-constrained: All `--twrfile` arguments must be in `/var/lib/tripwire/report/*.twr`
- Only allows: `--check`, `--update`, and `twprint --print-report`
- Explicitly excludes dangerous operations (`--init`, `--generate-keys`, etc.)
- Triple-layer environment security (same as wrapper mode):
  - `env_reset`: Clears all environment variables
  - `!setenv`: Prevents setting new environment variables
  - `secure_path=/usr/sbin:/usr/bin:/bin`: Restricts $PATH to trusted directories
- Use only for debugging; wrapper mode is recommended for production

See `scripts/setup/setup-tripwire-service-account.sh` and `scripts/wrappers/tripwire-wrapper.sh` for implementation details. CI validates sudoers syntax and security patterns on every commit.

# PDriveBackup

![Platform](https://img.shields.io/badge/platform-Windows_10%2F11-blue)
![Language](https://img.shields.io/badge/language-Batch-green)
![Version](https://img.shields.io/badge/version-v1.0-orange)
![Status](https://img.shields.io/badge/status-Stable-success)
![Robocopy](https://img.shields.io/badge/engine-Robocopy-informational)


PDriveBackup is a Windows batch-based backup utility built around Robocopy. It is designed to provide fast, reliable, and verifiable backups of important data while remaining lightweight, portable, and easy to maintain.

Unlike a simple Robocopy script, PDriveBackup adds verification, scheduling, logging, lock protection, and self-testing to create a more robust backup solution.

---
## Current Release

**Version:** 1.1.0

### Features

- Daily mirror backup (P: → D:)
- Weekly mirror backup (P: → E:)
- Weekly retained backup to iCloud Drive
- Backup verification
- Automatic logging
- Lock file protection
- FORCEWEEKLY test mode
- 
# Features

* Daily mirrored backups using Robocopy (`/MIR`)
* Weekly mirrored backup to a secondary drive
* Weekly retained backup to iCloud Drive
* Post-backup verification to ensure mirrors match the source
* Automatic weekly scheduling
* Self-test mode (no files copied)
* Lock protection to prevent multiple simultaneous executions
* Detailed timestamped log files
* Runtime status and final summary
* Automatic lock cleanup
* Exit codes suitable for Task Scheduler or automation

---

# Backup Strategy

## Daily Backup

Every run performs mirrored backups from:

```
P:\Documents
P:\Pictures
```

to

```
D:\Documents
D:\Pictures
```

using Robocopy mirror mode.

Immediately after each mirror operation, a verification pass confirms that the destination matches the source.

---

## Weekly Backup

Once every seven days, the script also performs mirrored backups to:

```
E:\Documents
E:\Pictures
```

This provides an additional local backup copy.

---

## Weekly iCloud Backup

During the weekly cycle, retained (non-mirrored) copies are also written to:

```
C:\Users\<username>\iCloudDrive\Backups
```

These copies preserve older files instead of deleting them, providing an off-computer cloud backup.

---

# Verification

Every daily mirror is followed by a verification-only Robocopy pass.

The verification checks for:

* missing files
* extra files
* copy failures
* mismatches

A backup is only reported as successful after verification passes.

---

# Self-Test Mode

Run:

```cmd
PDriveBackup.bat /TEST
```

The self-test validates:

* source folders
* destination drives
* iCloud location
* logging folders
* state folders
* weekly schedule calculation

No files are copied, deleted, or modified.

---

# Lock Protection

To prevent accidental concurrent execution, PDriveBackup creates a lock directory while running.

If another instance is already active, the script exits safely instead of allowing two backups to operate simultaneously.

Successful completion automatically removes the lock.

---

# Logging

Each execution creates a timestamped log containing:

* backup mode
* free disk space
* Robocopy results
* verification results
* weekly scheduling decision
* elapsed time
* final exit code
* lock cleanup status

Example:

```
backup_20260721_143234_666.log
```

Millisecond timestamps ensure unique filenames even when backups are started close together.

---

# Exit Codes

| Exit Code | Meaning                  |
| --------- | ------------------------ |
| 0         | Success                  |
| 41        | Lock cleanup failed      |
| Other     | Robocopy or script error |

---

# Repository Structure

```
PDriveBackup/
│
├── PDriveBackup.bat
├── README.md
├── .gitignore
│
├── PDriveBackupLogs/
└── PDriveBackupState/
```

The `PDriveBackupLogs` and `PDriveBackupState` directories are generated automatically at runtime and are excluded from source control.

---

# Requirements

* Windows 10 / Windows 11
* Robocopy (included with Windows)
* PowerShell (used for scheduling calculations)
* Local or mapped backup drives
* Optional iCloud for Windows

---

# Typical Usage

Normal backup:

```cmd
PDriveBackup.bat
```

Run self-test:

```cmd
PDriveBackup.bat /TEST
```

---

# Design Goals

PDriveBackup was built with the following priorities:

* Reliability
* Data integrity
* Simple deployment
* Readable logging
* Minimal dependencies
* Easy maintenance
* Compatibility with Windows Task Scheduler

---

# License

This project is provided as-is for personal and educational use. Modify and distribute as needed.

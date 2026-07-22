# PDriveBackup

![Platform](https://img.shields.io/badge/platform-Windows_10%2F11-blue)
![Language](https://img.shields.io/badge/language-Batch-green)
![Version](https://img.shields.io/badge/version-v1.2.0-orange)
![Status](https://img.shields.io/badge/status-Stable-success)
![Robocopy](https://img.shields.io/badge/engine-Robocopy-informational)

PDriveBackup is a Windows batch-based backup utility built around Robocopy. It is designed to provide fast, reliable, and verifiable backups of important data while remaining lightweight, portable, and easy to maintain.

Unlike a simple Robocopy script, PDriveBackup adds verification, scheduling, logging, destination-drive identity validation, stale-lock recovery, and self-testing to create a more robust backup solution.

---

## Current Release

**Version:** 1.2.0

### Features

- Daily mirror backup (`P:` → `D:`)
- Weekly mirror backup (`P:` → `E:`)
- Weekly retained backup to iCloud Drive
- Post-backup verification
- Verification-only mode (`/VERIFY`)
- Self-test mode (`/TEST`)
- Forced weekly mode (`/FORCEWEEKLY`)
- Destination-drive identity protection
- Single-instance lock protection
- Automatic stale-lock recovery
- Detailed timestamped logging
- Exit codes suitable for Task Scheduler and automation

---

# Backup Strategy

## Daily Backup

Every normal run performs mirrored backups from:

```text
P:\Documents
P:\Pictures
```

to:

```text
D:\Documents
D:\Pictures
```

Robocopy `/MIR` mode is used. Immediately after each mirror operation, a verification pass confirms that the destination matches the source.

> **Warning:** The daily destinations are dedicated mirrors. Files present at the destination but no longer present in the corresponding source may be deleted by `/MIR`.

---

## Weekly Backup

Once every seven days, the script also performs mirrored backups to:

```text
E:\Documents
E:\Pictures
```

This provides an additional local backup copy.

The weekly cycle runs only after the daily backup and verification succeed. It may also be started manually with `/FORCEWEEKLY`.

> **Warning:** The weekly `E:` destinations are dedicated mirrors and are also subject to `/MIR` deletion behavior.

---

## Weekly iCloud Backup

During the weekly cycle, retained, non-mirrored copies are written to:

```text
C:\Users\<username>\iCloudDrive\Backups\Documents
C:\Users\<username>\iCloudDrive\Backups\Pictures
```

The iCloud jobs use recursive copy behavior rather than `/MIR`, so deleting an item from `P:` does not automatically delete the retained local iCloud copy.

PDriveBackup verifies the local iCloud Drive folders. iCloud for Windows uploads those files asynchronously afterward.

The weekly-success marker is updated only after both `E:` mirrors and both local iCloud copies verify successfully.

---

# Safety Features

PDriveBackup is intentionally conservative. Before a mirror operation is allowed, it verifies:

- Required source folders exist
- The destination drive has the expected identity marker
- Another backup instance is not already active
- The weekly schedule state is valid

Every mirror operation is followed by verification before it is reported as successful.

These safeguards reduce the risk of accidental data loss while allowing unattended operation through Windows Task Scheduler.

---

# Drive Identity Protection

Drive letters can be reassigned by Windows. Running `/MIR` against the wrong device could therefore delete or overwrite unrelated files.

PDriveBackup prevents this by requiring a hidden marker file and exact identity token on each mirror destination.

## Daily backup drive

File:

```text
D:\.pdrivebackup_id
```

Required contents:

```text
PDRIVEBACKUP_DAILY_V1
```

## Weekly backup drive

File:

```text
E:\.pdrivebackup_id
```

Required contents:

```text
PDRIVEBACKUP_WEEKLY_V1
```

If a marker file is missing or its contents do not exactly match the configured token, the script aborts before Robocopy performs a mirror or mirror-verification operation.

The marker files should remain hidden and should not be renamed, moved, or duplicated onto unrelated drives.

---

# Verification

Every completed mirror is followed by a verification-only Robocopy pass.

Verification checks for:

- Missing files
- Copy failures
- File mismatches
- Unexpected source-side differences

Mirror verification uses `/XX`, so destination-only system or retained items are intentionally ignored. Robocopy exit code `2` is accepted in that specific verification context because it represents destination-only items excluded by `/XX`.

A backup is reported as successful only after verification passes.

---

# Command-Line Modes

## Normal backup

```cmd
PDriveBackup.bat
```

Runs the daily `D:` mirror and verification. If the weekly cycle is due, it also runs the `E:` mirror and retained iCloud backup.

## Self-test

```cmd
PDriveBackup.bat /TEST
```

Validates:

- Source folders
- Destination-drive identity markers
- Local iCloud Drive location
- Log directory
- State directory
- Weekly schedule calculation

No Robocopy copy or delete operation is executed.

## Verify only

```cmd
PDriveBackup.bat /VERIFY
```

Compares the source folders with the current `D:`, `E:`, and local iCloud destinations.

No files are copied, changed, or deleted.

## Force weekly

```cmd
PDriveBackup.bat /FORCEWEEKLY
```

Runs the normal daily backup and then performs the weekly `E:` and iCloud jobs regardless of the weekly marker age.

The weekly-success marker is still updated only if all weekly operations verify successfully.

---

# Lock Protection and Recovery

PDriveBackup uses a lock directory to prevent overlapping runs.

When the lock is acquired, `RunInfo.txt` records:

- Script version
- Owning CMD process ID
- Owning process start time in UTC
- Run start time
- Computer name
- Operating mode
- Script path

If a lock already exists, Version 22 checks whether the recorded process is still active and whether its start time matches.

- An active lock is preserved and the new run exits safely.
- A confirmed stale lock is removed automatically and lock acquisition is retried.
- A legacy or malformed lock is handled conservatively and is removed only when the fallback checks confirm that it is stale.
- A lock that cannot be safely classified is left in place.

Completed lock-acquisition failures are copied to `Latest.log` so the most recent operational problem remains visible.

Normal completion removes the lock automatically and reports whether cleanup succeeded.

---

# Logging

Each execution creates a timestamped log containing:

- Script version
- Operating mode
- Source and destination information
- Free disk space
- Drive identity results
- Robocopy results
- Verification results
- Weekly scheduling decision
- Stale-lock recovery status, when applicable
- Elapsed time
- Final exit code
- Lock cleanup status

Example:

```text
backup_20260721_180026_529.log
```

Millisecond timestamps ensure unique filenames even when runs begin close together.

`Latest.log` is refreshed with the newest completed run, including runs that stop because an active or unclassified lock prevents startup.

Timestamped logs older than the configured retention period are removed automatically.

---

# Exit Codes

| Exit Code | Meaning |
| ---: | --- |
| `0` | Success |
| `2` | Invalid command-line option |
| `10` | Required source folder missing |
| `13` | Local iCloud Drive path unavailable |
| `14` | iCloud backup destination could not be created |
| `20` | Daily `D:` backup or verification failure |
| `21` | Weekly `E:` backup or verification failure |
| `22` | Weekly local iCloud copy or verification failure |
| `30` | Weekly-success marker update failure |
| `40` | Lock acquisition failed or an existing lock could not be safely cleared |
| `41` | Lock cleanup failed |
| `42` | Daily `D:` drive identity validation failed |
| `43` | Weekly `E:` drive identity validation failed |
| `50` | Self-test failure |

Robocopy return codes are interpreted internally. The script emits the normalized exit codes above for Task Scheduler, shell scripts, and other automation.

---

# Repository Structure

```text
PDriveBackup/
│
├── PDriveBackup.bat
├── README.md
├── CHANGELOG.md
├── .gitignore
│
├── PDriveBackupLogs/
└── PDriveBackupState/
```

`PDriveBackupLogs` and `PDriveBackupState` are generated automatically at runtime and should be excluded from source control.

---

# Requirements

- Windows 10 or Windows 11
- Robocopy, included with Windows
- PowerShell
- Local or mapped source and backup drives
- Correct drive identity marker files on `D:` and `E:`
- Optional iCloud for Windows for the retained cloud copy

---

# Tested Release Status

Version 22 was validated on July 21, 2026 with:

```cmd
PDriveBackup.bat /TEST
PDriveBackup.bat /VERIFY
```

Both completed successfully with final exit code `0`.

The verification run confirmed:

- `D:\Documents`
- `D:\Pictures`
- `E:\Documents`
- `E:\Pictures`
- Local iCloud Documents
- Local iCloud Pictures
- Successful lock cleanup

The `E:\Pictures` verification returned Robocopy code `2`, which was correctly accepted because `/XX` intentionally ignores destination-only items.

---

# Design Goals

PDriveBackup was built with the following priorities:

- Reliability
- Data integrity
- Conservative failure handling
- Safe unattended operation
- Simple deployment
- Readable logging
- Minimal dependencies
- Easy maintenance
- Compatibility with Windows Task Scheduler

---

# License

This project is provided as-is for personal and educational use. Modify and distribute as needed.

# PDriveBackup

![Platform](https://img.shields.io/badge/platform-Windows_10%2F11-blue)
![Language](https://img.shields.io/badge/language-Batch-green)
![Release](https://img.shields.io/badge/release-v2.0.0-orange)
![Script](https://img.shields.io/badge/script-v26-informational)
![Status](https://img.shields.io/badge/status-Stable-success)
![Backup](https://img.shields.io/badge/engines-Robocopy%20%2B%20restic-informational)

PDriveBackup is a Windows backup utility that combines a directly browsable Robocopy mirror with a versioned restic repository.

Version 2.0 changes the design from a removable-drive-centered backup workflow to a **C:-based master with independent local, versioned, and offline protection**.

---

## Current Release

**Release:** 2.0.0
**Script version:** 26

### Backup architecture

```text
C:  LIVE MASTER
    %USERPROFILE%\Documents
    %USERPROFILE%\Pictures
            |
            +--> D: DAILY MIRROR
            |    D:\Documents
            |    D:\Pictures
            |
            +--> E: DAILY VERSIONED BACKUP
                 E:\ResticBackup

P:  REMOVABLE OFFLINE MIRROR
    Updated only with /OFFLINE
```

The two automatic backup paths have different jobs:

- **D:** fast, immediately browsable current-state recovery.
- **E:** version history for deleted, overwritten, or changed files.
- **P:** manually updated removable copy that can remain disconnected between backups.

This avoids making every backup an identical mirror that would immediately reproduce an accidental deletion.

---

# Normal Backup

Run:

```cmd
PDriveBackup.bat
```

A normal run:

1. Validates the source folders.
2. Acquires the single-instance lock.
3. Validates the identity of the `D:` mirror drive.
4. Mirrors Documents and Pictures from `C:` to `D:` with Robocopy `/MIR`.
5. Verifies both mirrors with a non-writing Robocopy pass.
6. Validates the identity of the `E:` versioned-backup drive.
7. Opens the restic repository using the configured password file.
8. Creates a restic snapshot of Documents and Pictures.
9. Applies the retention policy.
10. Writes a detailed log and records the latest successful/failed normal run.

The `D:` and `E:` jobs are independent. A failure on one backup path is logged without turning the other backup path into a destructive fallback.

---

# Backup Destinations

## D: current-state mirror

Sources:

```text
%USERPROFILE%\Documents
%USERPROFILE%\Pictures
```

Destinations:

```text
D:\Documents
D:\Pictures
```

The mirror uses Robocopy `/MIR`.

> **Warning:** `/MIR` deletes destination items that no longer exist in the source. `D:` is intentionally a current-state mirror, not version history.

Every mirror is followed by a read-only verification pass.

---

## E: versioned restic repository

Repository:

```text
E:\ResticBackup
```

The repository receives a daily snapshot of:

```text
%USERPROFILE%\Documents
%USERPROFILE%\Pictures
```

Configured retention policy:

```text
30 daily
12 weekly
12 monthly
3 yearly
```

restic deduplicates unchanged data, so retained snapshots do not create a complete second copy of every unchanged file.

Daily backup runs apply the retention policy but do not perform an expensive prune. Repository maintenance is handled separately with `/MAINTENANCE`.

---

## P: removable offline mirror

`P:` is not part of a normal scheduled run.

To update the removable backup intentionally:

```cmd
PDriveBackup.bat /OFFLINE
```

The script requires the dedicated `P:` identity marker before any mirror operation is allowed.

Keeping `P:` disconnected between updates provides protection against failures or malware that can reach always-mounted storage.

---

# Command-Line Modes

## Normal backup

```cmd
PDriveBackup.bat
```

Runs the `C:` → `D:` mirror and the `C:` → `E:` restic snapshot/retention workflow.

## Health check

```cmd
PDriveBackup.bat /HEALTH
```

Performs a non-destructive diagnostic check, including:

- required Windows commands
- source folders
- `D:` and `E:` identity markers
- write access
- restic executable availability
- restic password-file availability
- restic repository access
- lock ownership
- status of the removable `P:` drive
- age/status of the latest completed normal backup
- destination free space

A normal backup older than the configured health threshold is reported as a warning.

`/TEST` is retained as an alias for `/HEALTH`.

## Verify only

```cmd
PDriveBackup.bat /VERIFY
```

Performs non-destructive verification of the current backup state.

It verifies the `D:` mirror and checks the restic repository without creating a new backup snapshot.

## Offline backup

```cmd
PDriveBackup.bat /OFFLINE
```

Updates the removable `P:` mirror after validating its identity marker.

This mode is intended to be run manually when the removable SSD is connected.

## Repository maintenance

```cmd
PDriveBackup.bat /MAINTENANCE
```

Runs periodic restic repository maintenance, including repository checking and pruning.

This is intentionally separate from the daily backup so routine backups remain relatively fast.

---

# Drive Identity Protection

Windows can reassign drive letters. Running `/MIR` against the wrong device could delete unrelated data.

PDriveBackup requires a marker file with an exact token before using protected destination drives.

## D: daily mirror

File:

```text
D:\.pdrivebackup_id
```

Contents:

```text
PDRIVEBACKUP_DAILY_V1
```

## E: versioned backup

File:

```text
E:\.pdrivebackup_id
```

Contents:

```text
PDRIVEBACKUP_WEEKLY_V1
```

The legacy token name is intentionally retained for compatibility with the existing `E:` drive marker even though `E:` is no longer a weekly mirror.

## P: removable offline mirror

File:

```text
P:\.pdrivebackup_id
```

Contents:

```text
PDRIVEBACKUP_OFFLINE_V1
```

Do not automatically create identity markers. They are intended to be placed manually on known drives so the script cannot accidentally "approve" the wrong device.

---

# restic Configuration

PDriveBackup expects restic to be installed and available in `PATH`.

Example Windows installation:

```powershell
winget install --exact --id restic.restic --scope Machine
```

Repository:

```text
E:\ResticBackup
```

Password file:

```text
C:\ProgramData\PDriveBackup\restic-password.txt
```

The password file should contain only the repository password and should be restricted to the backup account and `SYSTEM`.

Example ACL configuration:

```powershell
$pwfile = "C:\ProgramData\PDriveBackup\restic-password.txt"
$account = "$env:USERDOMAIN\$env:USERNAME"

icacls $pwfile /inheritance:r
icacls $pwfile /grant:r "${account}:(R)" "SYSTEM:(R)"
```

Verify unattended repository access with:

```powershell
restic -r "E:\ResticBackup" `
    --password-file "C:\ProgramData\PDriveBackup\restic-password.txt" `
    snapshots
```

> **Important:** Loss of the restic repository password makes the encrypted repository unrecoverable. Store the password securely outside the repository.

---

# Restoring Data

## From D:

`D:` is a normal filesystem mirror. Files can be copied directly from:

```text
D:\Documents
D:\Pictures
```

## From E:

List snapshots:

```powershell
restic -r "E:\ResticBackup" `
    --password-file "C:\ProgramData\PDriveBackup\restic-password.txt" `
    snapshots
```

Restore the latest snapshot to a separate folder:

```powershell
restic -r "E:\ResticBackup" `
    --password-file "C:\ProgramData\PDriveBackup\restic-password.txt" `
    restore latest `
    --target "C:\ResticRestore"
```

Restore to a separate location first and verify the recovered data before replacing live files.

---

# Verification and Integrity

PDriveBackup uses different verification methods for each backup type.

### D: Robocopy mirror

The mirror is followed by a Robocopy list-only comparison using the same copy/exclusion semantics. A clean verification produces no source-side copy candidates.

### E: restic repository

`/VERIFY` checks repository accessibility and integrity without creating a new snapshot.

For a deeper manual check that reads stored pack data:

```powershell
restic -r "E:\ResticBackup" `
    --password-file "C:\ProgramData\PDriveBackup\restic-password.txt" `
    check --read-data
```

A successful restore test is still the strongest practical validation that a backup can actually be recovered.

---

# Lock Protection

PDriveBackup prevents overlapping executions with a lock directory.

The lock records information such as:

- script version
- owning process ID
- process start time
- computer name
- operating mode
- script path

If an existing lock belongs to a live process, a second run exits safely.

Confirmed stale locks are recovered automatically. Locks that cannot be classified safely are left in place rather than risking overlapping backup operations.

---

# Logging

Each run creates a timestamped log in:

```text
PDriveBackupLogs\
```

Logs include:

- script version and mode
- source and destination paths
- free space
- identity-check results
- Robocopy results
- mirror verification
- restic results
- retention/maintenance status
- offline-backup status
- lock status
- elapsed time
- final exit code

`Latest.log` is maintained for quick access to the newest completed run.

The script also tracks the latest completed normal backup independently so health checks do not overwrite the operational status they are evaluating.

Runtime logs and state are excluded from source control.

---

# Task Scheduler

A normal backup can be run unattended from Windows Task Scheduler.

The tested configuration uses:

- a daily trigger
- `Run with highest privileges`
- `Start the task as soon as possible after a scheduled start is missed`
- S4U logon for a local-only backup workflow

Using S4U avoids storing a Windows password with the task, so changing the Windows account password does not invalidate the scheduled backup.

Example task action:

```text
C:\Git\PDriveBackup\PDriveBackup.bat
```

The script returns a nonzero exit code when an operation fails so Task Scheduler can record failures.

---

# Requirements

- Windows 10 or Windows 11
- Robocopy
- PowerShell
- restic
- NTFS/local storage for the configured backup drives
- valid `D:` and `E:` identity markers
- restic repository initialized at `E:\ResticBackup`
- protected restic password file
- optional removable `P:` drive with its offline identity marker

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
├── PDriveBackupLogs/      # generated
└── PDriveBackupState/     # generated
```

---

# Version 2.0 Validation

Version 26 was validated on October 5, 2026 with:

```cmd
PDriveBackup.bat /HEALTH
PDriveBackup.bat /VERIFY
PDriveBackup.bat
```

All completed with exit code `0`.

The versioned backup repository was also validated independently with:

- a full initial restic snapshot
- a deduplicated incremental snapshot
- `restic check`
- `restic check --read-data`
- an actual restore of the Lightroom catalog
- SHA-256 comparison of the restored catalog against the source

The restored file matched the source hash.

The production script was then launched through Windows Task Scheduler using S4U and completed successfully.

---

# Design Goals

PDriveBackup prioritizes:

- conservative failure handling
- verifiable recovery
- protection against accidental deletion
- safe unattended execution
- independent backup paths
- readable logging
- straightforward disaster recovery
- limited external dependencies

---

# License

This project is provided as-is for personal and educational use. Modify and distribute as needed.

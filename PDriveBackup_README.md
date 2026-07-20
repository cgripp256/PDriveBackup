# PDriveBackup

**Current Version:** 8  
**Created:** February 2026  
**Last Updated:** July 2026

---

## Purpose

Back up the following folders from the P: drive:

- P:\Documents
- P:\Pictures

The script performs multiple verified backups to provide redundancy while
remaining simple, transparent, and easy to restore from.

---

## Backup Schedule

### Daily

Mirror to:

- D:\Documents
- D:\Pictures

### Weekly

Mirror to:

- E:\Documents
- E:\Pictures

Copy (retained backup) to:

- %USERPROFILE%\iCloudDrive\Backups\Documents
- %USERPROFILE%\iCloudDrive\Backups\Pictures

---

## Features

- Daily verified mirror to D:
- Weekly verified mirror to E:
- Weekly retained copy to iCloud Drive
- Robocopy verification after every backup
- Verify-only mode (`/VERIFY`)
- Single-instance lock protection
- Automatic log cleanup (365 days)
- Latest.log for quick review
- Weekly marker file
- Elapsed-time logging
- Free-space logging
- Robocopy exit-code checking
- Detailed timestamped logs

---

## Folder Structure

```text
C:\Scripts\
    PDriveBackup.bat
    PDriveBackup_README.md
```

Logs:

```text
PDriveBackupLogs\
    Latest.log
    backup_YYYYMMDD_HHMMSS.log
```

State:

```text
PDriveBackupState\
    LastSuccessfulWeeklyBackup.marker
```

---

## Task Scheduler

Runs daily at **1:00 AM**.

Recommended configuration:

- Run whether user is logged on or not
- Run with highest privileges
- Do not start a new instance
- Run as soon as possible after a scheduled start is missed

---

## Manual Operation

### Run a normal backup

```text
PDriveBackup.bat
```

### Verify existing backups without copying files

```text
PDriveBackup.bat /VERIFY
```

---

## Exit Codes

| Code | Meaning |
|------:|---------|
| 0 | Success |
| 2 | Invalid command-line option |
| 10 | Source folder missing |
| 11 | D: destination unavailable |
| 12 | E: destination unavailable |
| 13 | iCloud destination unavailable |
| 20 | D: verification failed |
| 21 | E: verification failed |
| 22 | iCloud verification failed |
| 30 | Weekly marker update failed |
| 40 | Another backup instance is already running |

---

## Restore

Files can be restored from any of the following:

- D:\Documents
- D:\Pictures
- E:\Documents
- E:\Pictures
- %USERPROFILE%\iCloudDrive\Backups\Documents
- %USERPROFILE%\iCloudDrive\Backups\Pictures

---

## Design Philosophy

This script favors **reliability over speed**.

Every backup is verified before being considered successful.

The weekly marker file is updated only after successful verification of both:

- the weekly E: mirror
- the local iCloud backup copies

The script uses multiple independent backup destinations and detailed logging so that backup failures are easy to identify and troubleshoot.

The goal is to provide a backup solution that is:

- Reliable
- Transparent
- Easy to restore from
- Easy to maintain
- Simple enough to troubleshoot with standard Windows tools

---

## Revision History

### Version 8 (July 2026)

- Added single-instance lock protection
- Added `/VERIFY` mode
- Added Robocopy exit-code checking
- Added script version and operating mode to logs

### Version 7

- Improved free-space reporting
- Added verified weekly marker updates

### Version 6

- Added Latest.log
- Added elapsed-time logging
- Added free-space logging
- Added automatic log cleanup
- Skips weekly backups if the daily backup fails

---

**Author:** Christopher Gripp
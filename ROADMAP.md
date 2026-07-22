# PDriveBackup Roadmap

This file tracks planned improvements that are not part of the current stable release.

Current stable release: **v1.2.0 / Version 22**

---

## Planned Work

### 1. Source Drive Identity Validation

**Priority:** High  
**Status:** Planned  
**Target:** v1.3.0

Add a hidden identity marker to the source drive:

```text
P:\.pdrivebackup_id
```

Required token:

```text
PDRIVEBACKUP_SOURCE_V1
```

The script should validate the source-drive marker before any backup or verification operation begins.

Purpose:

- Prevent the wrong device from being treated as the `P:` source
- Prevent valid backups from being overwritten with data from an unintended source drive
- Extend the same drive-authentication model already used for `D:` and `E:`

Suggested exit code:

```text
44 = Source drive identity validation failed
```

---

### 2. Write-Access Testing

**Priority:** Medium  
**Status:** Planned  
**Target:** v1.3.0

Extend `/TEST` or the future `/HEALTH` mode to verify actual write access rather than checking only that paths exist.

Candidate locations:

- `D:\`
- `E:\`
- Local iCloud backup root
- Log directory
- State directory

The test should create a uniquely named temporary file, confirm it exists, delete it, and report failure if creation or deletion fails.

---

### 3. Rebuild `/HEALTH`

**Priority:** Medium  
**Status:** Deferred  
**Target:** v1.3.0 or later

Rebuild `/HEALTH` incrementally from the stable Version 22 baseline.

Do not continue development from experimental Versions 23–25.

Proposed checks:

- Required commands are available
- Source folders exist
- Source and destination identity markers pass
- Write-access tests pass
- Current lock is valid or safely recoverable
- Weekly marker is readable and has a reasonable age
- Free-space information is available
- A recent operational backup or verification log exists
- Latest operational run completed successfully

Health runs must not overwrite or invalidate the latest operational backup status.

---

### 4. Unattended Failure Alerting

**Priority:** Medium  
**Status:** Design Decision Pending  
**Target:** External integration

Add a notification path for failed scheduled runs.

Preferred architecture:

- Keep notification logic outside the core backup script
- Use PDriveBackup's normalized exit codes
- Let Windows Task Scheduler or a companion script generate alerts

Possible methods:

- Windows Event Log
- Email
- Pushover
- ntfy
- PowerShell notification script
- Task Scheduler event-triggered follow-up task

---

## Deferred / Not Currently Planned

### Pre-flight Capacity Prediction

PDriveBackup logs destination free space but does not attempt to predict exact required capacity before Robocopy runs.

Reason:

- Total source size is not the same as required incremental space
- Accurate prediction would require a separate difference scan
- Robocopy already detects and reports insufficient-space failures

Revisit only if real-world capacity failures become frequent.

### Direct iCloud Server Verification

PDriveBackup verifies the local iCloud staging folders but does not confirm that Apple has completed the cloud upload.

Reason:

- iCloud synchronization is asynchronous
- Waiting for server synchronization could make backup runs unpredictable or extremely long
- Cloud transport remains the responsibility of iCloud for Windows

The console and documentation should continue to describe this as:

```text
LOCAL COPY VERIFIED
```

---

## Completed Safety Work

### v1.2.0 / Version 22

- Destination identity validation for `D:` and `E:`
- PID and process-start-time lock ownership
- Confirmed stale-lock recovery
- Conservative handling of unclassified locks
- `Latest.log` refresh on lock-acquisition failure
- `/TEST`
- `/VERIFY`
- `/FORCEWEEKLY`
- Daily, weekly, and local iCloud verification
- Expanded exit-code documentation

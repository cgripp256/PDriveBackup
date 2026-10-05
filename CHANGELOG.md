# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog, and the project follows Semantic Versioning where practical.

---

## [2.0.0] - 2026-10-05

### Summary

Version 2.0 is a major redesign of the backup architecture.

The live master moved from the removable `P:` drive to the local Windows profile on `C:`. The former second mirror on `E:` was replaced with a versioned restic repository, and `P:` was reassigned as an intentionally manual removable/offline backup.

### Added

- Daily versioned restic backup to:
  - `E:\ResticBackup`
- restic retention policy:
  - 30 daily snapshots
  - 12 weekly snapshots
  - 12 monthly snapshots
  - 3 yearly snapshots
- Protected restic password-file support:
  - `C:\ProgramData\PDriveBackup\restic-password.txt`
- `/HEALTH` comprehensive non-destructive diagnostic mode.
- `/TEST` alias for `/HEALTH`.
- `/OFFLINE` mode for intentional removable-drive backups to `P:`.
- `/MAINTENANCE` mode for periodic restic checking and pruning.
- Offline-drive identity marker:
  - `P:\.pdrivebackup_id`
  - `PDRIVEBACKUP_OFFLINE_V1`
- restic executable, repository, and password-file checks.
- Health reporting for the latest completed normal backup.
- Health warning when the removable `P:` drive is connected without the expected offline identity marker.
- Separate tracking of normal-backup status so health checks do not overwrite the operational state they evaluate.

### Changed

- Primary source data changed from:
  - `P:\Documents`
  - `P:\Pictures`

  to:

  - `%USERPROFILE%\Documents`
  - `%USERPROFILE%\Pictures`

- `D:` remains the directly browsable current-state mirror.
- `E:` changed from a weekly Robocopy mirror to a daily versioned restic repository.
- `P:` changed from the primary source drive to a removable/offline mirror.
- Normal backups now protect `D:` and `E:` as separate backup paths.
- Daily restic backups apply retention without pruning on every run.
- Expensive repository maintenance is separated from the normal backup path.
- Health mode now distinguishes warnings from failures.
- The latest normal backup is checked independently of health/verify invocations.
- Documentation and operating model were updated for the new architecture.

### Removed

- `P:` as the normal backup source.
- Weekly `E:` mirror workflow.
- Weekly-success marker scheduling model.
- `/FORCEWEEKLY`.
- iCloud from the core scheduled backup path.
- Dependency of the versioned backup on a successful `D:` mirror.

### Preserved

- Destination-drive identity validation.
- Conservative Robocopy `/MIR` protection.
- Post-mirror verification.
- `/VERIFY` non-destructive verification mode.
- Single-instance locking.
- Process-aware stale-lock recovery.
- Timestamped logging.
- Log retention and latest-log handling.
- Task Scheduler-compatible exit status behavior.

### Compatibility

The existing `E:` identity token was intentionally retained:

```text
PDRIVEBACKUP_WEEKLY_V1
```

Although the token name is historical, retaining it avoided unnecessarily replacing the already-established identity marker on the known `E:` backup drive.

### Validation

Version 26 was validated on October 5, 2026.

Completed successfully:

- `/HEALTH` with exit code `0`
- `/VERIFY` with exit code `0`
- normal v26 backup with exit code `0`
- scheduled execution through Windows Task Scheduler with exit code `0`

restic validation included:

- initial snapshot of Documents and Pictures
- incremental deduplicated snapshot
- retention-policy execution
- `restic check`
- `restic check --read-data`
- actual restore of the Lightroom catalog
- SHA-256 comparison of restored and source catalog files

The restored catalog matched the source hash.

The production Task Scheduler configuration was changed to S4U so the local-only backup task no longer depends on a stored Windows account password.

---

## [1.2.0] - 2026-07-21

### Added

- Destination-drive identity verification using required marker files and exact identity tokens.
- Daily-drive marker requirement:
  - `D:\.pdrivebackup_id`
  - `PDRIVEBACKUP_DAILY_V1`
- Weekly-drive marker requirement:
  - `E:\.pdrivebackup_id`
  - `PDRIVEBACKUP_WEEKLY_V1`
- Drive identity validation in normal, `/TEST`, and `/VERIFY` modes.
- Exit code `42` for daily `D:` drive identity failure.
- Exit code `43` for weekly `E:` drive identity failure.
- Lock ownership tracking in `RunInfo.txt`, including the CMD process ID and process start time.
- Automatic recovery from confirmed stale locks.
- Conservative stale-lock fallback handling for legacy or malformed lock metadata.

### Changed

- Lock acquisition now validates whether the recorded owner process is still active.
- Confirmed stale locks are removed and lock acquisition is retried automatically.
- Active and unclassified locks remain in place to prevent overlapping backup runs.
- Lock-acquisition failures refresh `Latest.log`.
- Backup and mirror-verification operations are blocked until the applicable destination drive passes identity validation.
- Documentation includes supported command-line modes, drive marker setup, lock recovery behavior, and normalized script exit codes.

### Fixed

- Prevented `/MIR` from running against an unrelated device after Windows drive-letter reassignment.
- Prevented confirmed abandoned lock directories from blocking future scheduled backups indefinitely.
- Preserved conservative failure behavior when an existing lock cannot be safely classified.
- Maintained correct handling of mirror-verification Robocopy code `2` when `/XX` ignores destination-only items.

### Validation

- `/TEST` completed successfully with exit code `0`.
- `/VERIFY` completed successfully with exit code `0`.
- Daily and weekly destination identity checks passed.
- Daily, weekly, and local iCloud destinations verified successfully.
- Lock cleanup completed successfully.

---

## [1.1.0] - 2026-07-21

### Added

- Weekly retained backup to iCloud Drive.
- `/FORCEWEEKLY` command-line option for manually running weekly backups.
- End-to-end verification of daily, weekly, and iCloud backup destinations.
- Lock file protection to prevent concurrent executions.
- Detailed timestamped logging.

### Changed

- Improved backup status reporting.
- Improved weekly backup state handling.
- Improved verification workflow.
- Repository maintained using Git version control with tagged releases.

### Fixed

- Fixed weekly summary incorrectly reporting `SKIPPED` after an unsuccessful weekly cycle.
- Fixed verification logic to correctly interpret Robocopy exit code `2` during mirror verification.
- Fixed several edge cases affecting weekly completion status and exit codes.

---

## [1.0.0] - 2026-07-20

### Added

- Automated daily mirror backup from `P:` to `D:`.
- Weekly mirror backup from `P:` to `E:`.
- Verification pass after each backup.
- Weekly backup scheduling using marker files.
- Robocopy-based mirroring with detailed logging.
- Git repository and initial public release.

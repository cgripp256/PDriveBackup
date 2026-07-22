# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

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
- Lock-acquisition failures now refresh `Latest.log`.
- Backup and mirror-verification operations are blocked until the applicable destination drive passes identity validation.
- Documentation now includes all supported command-line modes, drive marker setup, lock recovery behavior, and normalized script exit codes.

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
- Improved backup status reporting and end-of-run summary.
- Improved weekly backup state handling.
- Improved verification workflow and overall reliability.
- Repository now maintained using Git version control with tagged releases.

### Fixed
- Fixed weekly summary incorrectly reporting **"SKIPPED"** after an unsuccessful weekly cycle.
- Fixed verification logic to correctly interpret Robocopy exit code `2` during mirror verification.
- Fixed several edge cases affecting weekly completion status and exit codes.

---

## [1.0.0] - 2026-07-20

### Added
- Automated daily mirror backup from P: to D:.
- Weekly mirror backup from P: to E:.
- Verification pass after each backup.
- Weekly backup scheduling using marker files.
- Robocopy-based mirroring with detailed logging.
- Git repository and initial public release.

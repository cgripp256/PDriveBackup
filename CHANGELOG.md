# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

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

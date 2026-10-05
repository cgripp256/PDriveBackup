@echo off
REM ============================================================
REM PDriveBackup
REM
REM Author: Christopher Gripp
REM Current Version: 26
REM Created: February 2026
REM Last Updated: October 2026
REM
REM Primary data:   C:\Users\<user>\Documents and Pictures
REM Daily mirror:   D:\Documents and D:\Pictures
REM Versioned copy: E:\ResticBackup (restic)
REM Offline mirror: P:\Documents and P:\Pictures via /OFFLINE only
REM ============================================================

setlocal EnableExtensions EnableDelayedExpansion

title PDriveBackup v26

REM ============================================================
REM PDriveBackup.bat
REM Version 26
REM
REM Version 26 redesign:
REM - Changes the authoritative source from P: to the user's C: profile.
REM - Keeps D: as the daily exact Robocopy mirror.
REM - Replaces the former weekly E: mirror with daily restic snapshots.
REM - Applies restic retention: 30 daily, 12 weekly, 12 monthly, 3 yearly.
REM - Adds /OFFLINE for an explicitly connected removable P: mirror.
REM - Adds /MAINTENANCE for restic check + prune + post-check.
REM - Retains /VERIFY and comprehensive /HEALTH modes.
REM - Keeps destination identity markers, single-instance locking,
REM   stale-lock recovery, verification, logging, and exit codes.
REM - Restic and D: are independent: failure of one does not prevent
REM   the other backup from being attempted.
REM - LatestOperational.log tracks the latest NORMAL BACKUP only, so
REM   health checks and manual verify/maintenance runs cannot mask a
REM   stale or missed scheduled backup.
REM
REM IMPORTANT:
REM - D: is a mirror. /MIR deletes D: items that no longer exist on C:.
REM - P: is also a mirror, but ONLY when /OFFLINE is explicitly invoked.
REM - E: is versioned storage managed by restic; do not edit repository
REM   files manually.
REM - iCloud is intentionally outside v26 while the offsite strategy is
REM   being redesigned.
REM ============================================================

REM ===== Configuration =====
set "SCRIPT_VERSION=26"

set "SRC_DOCS=%USERPROFILE%\Documents"
set "SRC_PICS=%USERPROFILE%\Pictures"

set "DEST_D_DOCS=D:\Documents"
set "DEST_D_PICS=D:\Pictures"

set "DEST_P_DOCS=P:\Documents"
set "DEST_P_PICS=P:\Pictures"

REM Unique marker files manually placed on the intended backup drives.
REM Never create these automatically; that could bless the wrong device.
set "D_ID_FILE=D:\.pdrivebackup_id"
set "D_ID_TOKEN=PDRIVEBACKUP_DAILY_V1"

REM E retains its existing legacy marker token. The marker still uniquely
REM identifies the intended physical E: backup drive even though its role
REM changed from weekly mirror to restic repository.
set "E_ID_FILE=E:\.pdrivebackup_id"
set "E_ID_TOKEN=PDRIVEBACKUP_WEEKLY_V1"

REM P gets a NEW marker before /OFFLINE is ever used.
set "P_ID_FILE=P:\.pdrivebackup_id"
set "P_ID_TOKEN=PDRIVEBACKUP_OFFLINE_V1"

set "RESTIC_CMD=restic.exe"
set "RESTIC_REPO=E:\ResticBackup"
set "RESTIC_PASSWORD_FILE=C:\ProgramData\PDriveBackup\restic-password.txt"
set "KEEP_DAILY=30"
set "KEEP_WEEKLY=12"
set "KEEP_MONTHLY=12"
set "KEEP_YEARLY=3"

set "LOG_RETENTION_DAYS=365"
set "STALE_LOCK_HOURS=24"
set "MAX_BACKUP_AGE_HOURS=48"

REM ===== Paths based on this BAT file's folder =====
set "BASEDIR=%~dp0"
set "LOGDIR=%BASEDIR%PDriveBackupLogs"
set "STATEDIR=%BASEDIR%PDriveBackupState"
set "LOCKDIR=%STATEDIR%\PDriveBackup.lock"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%STATEDIR%" mkdir "%STATEDIR%"

REM ===== Locale-independent timestamp =====
for /f %%I in (
    'powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"'
) do set "STAMP=%%I"

set "LOGFILE=%LOGDIR%\backup_%STAMP%.log"
set "LATEST_LOG=%LOGDIR%\Latest.log"
set "LATEST_OPERATION_LOG=%LOGDIR%\LatestOperational.log"

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "TOTAL_START=%%I"

REM ===== Mode parsing =====
set "RUN_MODE=BACKUP"
set "MODE_VALID=1"

if not "%~1"=="" set "MODE_VALID=0"

if /I "%~1"=="/VERIFY" set "RUN_MODE=VERIFY ONLY"& set "MODE_VALID=1"
if /I "%~1"=="-VERIFY" set "RUN_MODE=VERIFY ONLY"& set "MODE_VALID=1"
if /I "%~1"=="--VERIFY" set "RUN_MODE=VERIFY ONLY"& set "MODE_VALID=1"

if /I "%~1"=="/HEALTH" set "RUN_MODE=HEALTH CHECK"& set "MODE_VALID=1"
if /I "%~1"=="-HEALTH" set "RUN_MODE=HEALTH CHECK"& set "MODE_VALID=1"
if /I "%~1"=="--HEALTH" set "RUN_MODE=HEALTH CHECK"& set "MODE_VALID=1"
if /I "%~1"=="/TEST" set "RUN_MODE=HEALTH CHECK"& set "MODE_VALID=1"
if /I "%~1"=="-TEST" set "RUN_MODE=HEALTH CHECK"& set "MODE_VALID=1"
if /I "%~1"=="--TEST" set "RUN_MODE=HEALTH CHECK"& set "MODE_VALID=1"

if /I "%~1"=="/OFFLINE" set "RUN_MODE=OFFLINE BACKUP"& set "MODE_VALID=1"
if /I "%~1"=="-OFFLINE" set "RUN_MODE=OFFLINE BACKUP"& set "MODE_VALID=1"
if /I "%~1"=="--OFFLINE" set "RUN_MODE=OFFLINE BACKUP"& set "MODE_VALID=1"

if /I "%~1"=="/MAINTENANCE" set "RUN_MODE=MAINTENANCE"& set "MODE_VALID=1"
if /I "%~1"=="-MAINTENANCE" set "RUN_MODE=MAINTENANCE"& set "MODE_VALID=1"
if /I "%~1"=="--MAINTENANCE" set "RUN_MODE=MAINTENANCE"& set "MODE_VALID=1"

if "%MODE_VALID%"=="0" (
    call :Log "ERROR: Unknown option: %~1"
    call :Log "Usage:"
    call :Log "  %~nx0"
    call :Log "  %~nx0 /VERIFY"
    call :Log "  %~nx0 /HEALTH"
    call :Log "  %~nx0 /TEST   alias for /HEALTH"
    call :Log "  %~nx0 /OFFLINE"
    call :Log "  %~nx0 /MAINTENANCE"
    copy /Y "%LOGFILE%" "%LATEST_LOG%" >nul 2>&1
    endlocal & exit /b 2
)

REM ===== Single-instance lock =====
set "LOCK_ACQUIRED=0"
set "LOCK_RECOVERED=0"

:AcquireLock
mkdir "%LOCKDIR%" >nul 2>&1
if errorlevel 1 (
    call :InspectExistingLock

    if "!LOCK_STATUS!"=="STALE" (
        call :Log "WARNING: A stale PDriveBackup lock was detected."
        call :Log "Lock location:"
        call :Log "  %LOCKDIR%"
        call :Log "The recorded owner is no longer running. Removing the stale lock."
        rmdir /S /Q "%LOCKDIR%" >nul 2>&1

        if exist "%LOCKDIR%" (
            call :Log "ERROR: The stale lock could not be removed."
            call :Log "Final exit code: 40"
            copy /Y "%LOGFILE%" "%LATEST_LOG%" >nul 2>&1
            endlocal & exit /b 40
        )

        set "LOCK_RECOVERED=1"
        goto :AcquireLock
    )

    if "!LOCK_STATUS!"=="ACTIVE" (
        call :Log "ERROR: Another PDriveBackup instance is still running."
    ) else (
        call :Log "ERROR: An existing PDriveBackup lock could not be safely classified as stale."
    )
    call :Log "Lock location:"
    call :Log "  %LOCKDIR%"
    if defined LOCK_PID call :Log "Recorded PID: !LOCK_PID!"
    if defined LOCK_STARTED call :Log "Recorded start: !LOCK_STARTED!"
    call :Log "The existing lock was left in place to avoid overlapping backup runs."
    call :Log "Final exit code: 40"
    copy /Y "%LOGFILE%" "%LATEST_LOG%" >nul 2>&1
    endlocal & exit /b 40
)
set "LOCK_ACQUIRED=1"

set "LOCK_OWNER_PID="
set "LOCK_OWNER_START_UTC="
for /f "tokens=1,2 delims=|" %%A in ('powershell.exe -NoProfile -Command "$parentPid=(Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID)).ParentProcessId; $proc=Get-Process -Id $parentPid -ErrorAction Stop; Write-Output ($parentPid.ToString() + '|' + $proc.StartTime.ToUniversalTime().ToString('o'))"') do (
    set "LOCK_OWNER_PID=%%A"
    set "LOCK_OWNER_START_UTC=%%B"
)

> "%LOCKDIR%\RunInfo.txt" (
    echo PDriveBackup Version %SCRIPT_VERSION%
    echo PID=!LOCK_OWNER_PID!
    echo ProcessStartUtc=!LOCK_OWNER_START_UTC!
    echo Started=%DATE% %TIME%
    echo Computer=%COMPUTERNAME%
    echo Mode=%RUN_MODE%
    echo Script=%~f0
)

if "!LOCK_RECOVERED!"=="1" (
    call :Log "Stale lock recovery: SUCCESS - a new lock was acquired."
)

REM ===== Result initialization =====
set "FINALCODE=0"

set "D_DOCS_RESULT=SKIPPED"
set "D_PICS_RESULT=SKIPPED"
set "D_RESULT=SKIPPED"
set "D_ELAPSED=NOT RUN"

set "RESTIC_BACKUP_RESULT=SKIPPED"
set "RESTIC_RETENTION_RESULT=SKIPPED"
set "RESTIC_RESULT=SKIPPED"
set "RESTIC_ELAPSED=NOT RUN"

set "P_DOCS_RESULT=SKIPPED"
set "P_PICS_RESULT=SKIPPED"
set "P_RESULT=SKIPPED"
set "P_ELAPSED=NOT RUN"

set "MAINT_RESULT=SKIPPED"
set "MAINT_ELAPSED=NOT RUN"

call :Log "======================================"
call :Log "PDriveBackup Version %SCRIPT_VERSION%"
call :Log "Mode: %RUN_MODE%"
call :Log "Started: %DATE% %TIME%"
call :Log "Sources:"
call :Log "  %SRC_DOCS%"
call :Log "  %SRC_PICS%"
call :Log "Daily mirror root: D:\"
call :Log "Restic repository: %RESTIC_REPO%"
call :Log "Offline mirror root: P:\ - manual /OFFLINE only"
call :Log "======================================"

call :BlankLine
call :Log "========== FREE SPACE =========="
call :LogFreeSpace "C:"
call :LogFreeSpace "D:"
call :LogFreeSpace "E:"
if exist "P:\" call :LogFreeSpace "P:"

REM ===== Dispatch =====
if /I "%RUN_MODE%"=="HEALTH CHECK" (
    call :RunHealthCheck
    goto :Finalize
)

if /I "%RUN_MODE%"=="VERIFY ONLY" (
    call :RunVerifyMode
    goto :Finalize
)

if /I "%RUN_MODE%"=="OFFLINE BACKUP" (
    call :RunOfflineBackup
    goto :Finalize
)

if /I "%RUN_MODE%"=="MAINTENANCE" (
    call :RunMaintenance
    goto :Finalize
)

call :RunNormalBackup
goto :Finalize

REM ============================================================
REM NORMAL BACKUP
REM ============================================================

:RunNormalBackup
call :ValidateSources
if "!SOURCES_OK!"=="0" (
    call :SetFinalCode 10
    exit /b 0
)

REM ----- D daily mirror -----
for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "D_START=%%I"

call :CheckDriveIdentity "D:\" "%D_ID_FILE%" "%D_ID_TOKEN%" "Daily mirror drive D"
if "!DRIVE_ID_OK!"=="1" (
    call :BlankLine
    call :Log "========== DAILY MIRROR TO D:\ =========="

    call :RunMirror "%SRC_DOCS%" "%DEST_D_DOCS%" "D Documents"
    set "D_DOCS_RC=!JOB_RC!"
    set "D_DOCS_RESULT=!JOB_RESULT!"

    call :RunMirror "%SRC_PICS%" "%DEST_D_PICS%" "D Pictures"
    set "D_PICS_RC=!JOB_RC!"
    set "D_PICS_RESULT=!JOB_RESULT!"

    if "!D_DOCS_RC!"=="0" if "!D_PICS_RC!"=="0" (
        set "D_RESULT=SUCCESS - BOTH FOLDERS VERIFIED"
    ) else (
        set "D_RESULT=FAILED OR INCOMPLETE"
        call :SetFinalCode 20
    )
) else (
    set "D_DOCS_RESULT=FAILED - drive identity check failed"
    set "D_PICS_RESULT=FAILED - drive identity check failed"
    set "D_RESULT=FAILED - drive identity check failed"
    call :SetFinalCode 42
    call :Log "ERROR: D:\ failed its identity check. Mirror operation blocked."
)

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "D_END=%%I"
call :FormatElapsed !D_START! !D_END! D_ELAPSED

REM ----- E restic snapshot -----
for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "RESTIC_START=%%I"

call :CheckDriveIdentity "E:\" "%E_ID_FILE%" "%E_ID_TOKEN%" "Versioned backup drive E"
if "!DRIVE_ID_OK!"=="1" (
    call :ValidateResticConfig
    if "!RESTIC_CONFIG_OK!"=="1" (
        call :RunResticSnapshot
        if "!RESTIC_BACKUP_RC!"=="0" (
            call :ApplyResticRetention
            if "!RESTIC_RETENTION_RC!"=="0" (
                set "RESTIC_RESULT=SUCCESS - SNAPSHOT SAVED AND RETENTION APPLIED"
            ) else (
                set "RESTIC_RESULT=SNAPSHOT SAVED - RETENTION FAILED"
                call :SetFinalCode 22
            )
        ) else (
            set "RESTIC_RETENTION_RESULT=SKIPPED - snapshot failed"
            set "RESTIC_RESULT=FAILED - snapshot not completed"
            call :SetFinalCode 21
        )
    ) else (
        set "RESTIC_RESULT=FAILED - restic configuration invalid"
    )
) else (
    set "RESTIC_BACKUP_RESULT=FAILED - drive identity check failed"
    set "RESTIC_RETENTION_RESULT=SKIPPED"
    set "RESTIC_RESULT=FAILED - drive identity check failed"
    call :SetFinalCode 43
    call :Log "ERROR: E:\ failed its identity check. Restic operation blocked."
)

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "RESTIC_END=%%I"
call :FormatElapsed !RESTIC_START! !RESTIC_END! RESTIC_ELAPSED

exit /b 0

REM ============================================================
REM VERIFY MODE - NO COPY OR DELETE
REM ============================================================

:RunVerifyMode
call :ValidateSources
if "!SOURCES_OK!"=="0" (
    call :SetFinalCode 10
    exit /b 0
)

call :BlankLine
call :Log "========== VERIFY D MIRROR =========="
call :CheckDriveIdentity "D:\" "%D_ID_FILE%" "%D_ID_TOKEN%" "Daily mirror drive D"
if "!DRIVE_ID_OK!"=="1" (
    call :VerifyMirror "%SRC_DOCS%" "%DEST_D_DOCS%" "D Documents"
    set "D_DOCS_VERIFY_RC=!VERIFY_RC!"
    call :SetVerifyResult !D_DOCS_VERIFY_RC! "VERIFIED" D_DOCS_RESULT

    call :VerifyMirror "%SRC_PICS%" "%DEST_D_PICS%" "D Pictures"
    set "D_PICS_VERIFY_RC=!VERIFY_RC!"
    call :SetVerifyResult !D_PICS_VERIFY_RC! "VERIFIED" D_PICS_RESULT

    if "!D_DOCS_VERIFY_RC!"=="0" if "!D_PICS_VERIFY_RC!"=="0" (
        set "D_RESULT=SUCCESS - BOTH FOLDERS VERIFIED"
    ) else (
        set "D_RESULT=VERIFICATION FAILED OR INCOMPLETE"
        call :SetFinalCode 20
    )
) else (
    set "D_DOCS_RESULT=FAILED - drive identity check failed"
    set "D_PICS_RESULT=FAILED - drive identity check failed"
    set "D_RESULT=FAILED - drive identity check failed"
    call :SetFinalCode 42
)

call :BlankLine
call :Log "========== VERIFY RESTIC REPOSITORY =========="
call :CheckDriveIdentity "E:\" "%E_ID_FILE%" "%E_ID_TOKEN%" "Versioned backup drive E"
if "!DRIVE_ID_OK!"=="1" (
    call :ValidateResticConfig
    if "!RESTIC_CONFIG_OK!"=="1" (
        call :VerifyResticRepository
        if "!RESTIC_VERIFY_RC!"=="0" (
            set "RESTIC_RESULT=SUCCESS - REPOSITORY CHECK PASSED"
        ) else (
            set "RESTIC_RESULT=FAILED - REPOSITORY CHECK FAILED"
            call :SetFinalCode 23
        )
    ) else (
        set "RESTIC_RESULT=FAILED - restic configuration invalid"
    )
) else (
    set "RESTIC_RESULT=FAILED - drive identity check failed"
    call :SetFinalCode 43
)

exit /b 0

REM ============================================================
REM OFFLINE MIRROR MODE - MANUAL ONLY
REM ============================================================

:RunOfflineBackup
call :ValidateSources
if "!SOURCES_OK!"=="0" (
    call :SetFinalCode 10
    exit /b 0
)

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "P_START=%%I"

call :BlankLine
call :Log "========== OFFLINE MIRROR TO P:\ =========="
call :Log "This mode is manual and destructive to destination-only files on P:."

call :CheckDriveIdentity "P:\" "%P_ID_FILE%" "%P_ID_TOKEN%" "Offline mirror drive P"
if "!DRIVE_ID_OK!"=="1" (
    call :RunMirror "%SRC_DOCS%" "%DEST_P_DOCS%" "P Documents"
    set "P_DOCS_RC=!JOB_RC!"
    set "P_DOCS_RESULT=!JOB_RESULT!"

    call :RunMirror "%SRC_PICS%" "%DEST_P_PICS%" "P Pictures"
    set "P_PICS_RC=!JOB_RC!"
    set "P_PICS_RESULT=!JOB_RESULT!"

    if "!P_DOCS_RC!"=="0" if "!P_PICS_RC!"=="0" (
        set "P_RESULT=SUCCESS - BOTH FOLDERS VERIFIED"
    ) else (
        set "P_RESULT=FAILED OR INCOMPLETE"
        call :SetFinalCode 48
    )
) else (
    set "P_DOCS_RESULT=FAILED - drive identity check failed"
    set "P_PICS_RESULT=FAILED - drive identity check failed"
    set "P_RESULT=FAILED - drive identity check failed"
    call :SetFinalCode 44
)

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "P_END=%%I"
call :FormatElapsed !P_START! !P_END! P_ELAPSED

exit /b 0

REM ============================================================
REM RESTIC MAINTENANCE MODE
REM ============================================================

:RunMaintenance
for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "MAINT_START=%%I"

call :BlankLine
call :Log "========== RESTIC MAINTENANCE =========="
call :CheckDriveIdentity "E:\" "%E_ID_FILE%" "%E_ID_TOKEN%" "Versioned backup drive E"
if "!DRIVE_ID_OK!"=="0" (
    set "MAINT_RESULT=FAILED - drive identity check failed"
    call :SetFinalCode 43
    goto :MaintenanceDone
)

call :ValidateResticConfig
if "!RESTIC_CONFIG_OK!"=="0" (
    set "MAINT_RESULT=FAILED - restic configuration invalid"
    goto :MaintenanceDone
)

call :Log "Pre-maintenance repository check..."
"%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" check >>"%LOGFILE%" 2>&1
set "MAINT_PRECHECK_RC=!ERRORLEVEL!"
if not "!MAINT_PRECHECK_RC!"=="0" (
    call :Log "ERROR: Pre-maintenance restic check failed with exit code !MAINT_PRECHECK_RC!."
    set "MAINT_RESULT=FAILED - PRE-CHECK FAILED; PRUNE NOT RUN"
    call :SetFinalCode 23
    goto :MaintenanceDone
)

call :Log "Applying retention and pruning unreferenced repository data..."
"%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" forget ^
    --keep-daily %KEEP_DAILY% ^
    --keep-weekly %KEEP_WEEKLY% ^
    --keep-monthly %KEEP_MONTHLY% ^
    --keep-yearly %KEEP_YEARLY% ^
    --prune >>"%LOGFILE%" 2>&1
set "MAINT_PRUNE_RC=!ERRORLEVEL!"
if not "!MAINT_PRUNE_RC!"=="0" (
    call :Log "ERROR: Restic forget/prune failed with exit code !MAINT_PRUNE_RC!."
    set "MAINT_RESULT=FAILED - PRUNE FAILED"
    call :SetFinalCode 49
    goto :MaintenanceDone
)

call :Log "Post-maintenance repository check..."
"%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" check >>"%LOGFILE%" 2>&1
set "MAINT_POSTCHECK_RC=!ERRORLEVEL!"
if "!MAINT_POSTCHECK_RC!"=="0" (
    set "MAINT_RESULT=SUCCESS - CHECK, PRUNE, AND POST-CHECK PASSED"
) else (
    call :Log "ERROR: Post-maintenance restic check failed with exit code !MAINT_POSTCHECK_RC!."
    set "MAINT_RESULT=FAILED - POST-CHECK FAILED"
    call :SetFinalCode 23
)

:MaintenanceDone
for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "MAINT_END=%%I"
call :FormatElapsed !MAINT_START! !MAINT_END! MAINT_ELAPSED
exit /b 0

REM ============================================================
REM NON-COPYING HEALTH CHECK
REM ============================================================

:RunHealthCheck
set "HEALTH_ISSUES=0"
set "HEALTH_WARNINGS=0"

call :BlankLine
call :Log "========== HEALTH CHECK =========="
call :Log "No Robocopy copy/delete or restic backup/prune operation will run."
call :Log "Temporary files are created and removed only to verify write access."

call :BlankLine
call :Log "CORE COMMANDS"
call :TestCommand "robocopy.exe" "Robocopy"
call :TestCommand "powershell.exe" "PowerShell"
call :TestCommand "findstr.exe" "Findstr"
call :TestCommand "forfiles.exe" "Forfiles"
call :TestCommand "%RESTIC_CMD%" "Restic"

call :BlankLine
call :Log "SOURCE PATHS"
call :HealthPath "%SRC_DOCS%" "Source Documents folder" 1
call :HealthPath "%SRC_PICS%" "Source Pictures folder" 1

call :BlankLine
call :Log "BACKUP DRIVE IDENTITIES"
call :CheckDriveIdentity "D:\" "%D_ID_FILE%" "%D_ID_TOKEN%" "Daily mirror drive D"
if "!DRIVE_ID_OK!"=="0" set /a HEALTH_ISSUES+=1
call :CheckDriveIdentity "E:\" "%E_ID_FILE%" "%E_ID_TOKEN%" "Versioned backup drive E"
if "!DRIVE_ID_OK!"=="0" set /a HEALTH_ISSUES+=1

call :BlankLine
call :Log "WRITE ACCESS"
call :TestWritableDirectory "D:\" "Daily mirror drive root" 1
call :TestWritableDirectory "E:\" "Versioned backup drive root" 1
call :TestWritableDirectory "%LOGDIR%" "Log directory" 1
call :TestWritableDirectory "%STATEDIR%" "State directory" 1

call :BlankLine
call :Log "RESTIC CONFIGURATION"
call :HealthPath "%RESTIC_REPO%" "Restic repository" 1
call :HealthPath "%RESTIC_PASSWORD_FILE%" "Restic password file" 1
where "%RESTIC_CMD%" >nul 2>&1
if errorlevel 1 (
    call :Log "FAIL: Restic is unavailable; repository access test skipped."
    set /a HEALTH_ISSUES+=1
) else if exist "%RESTIC_REPO%\" if exist "%RESTIC_PASSWORD_FILE%" (
    set "RESTIC_HEALTH_TEMP=%TEMP%\PDriveResticHealth_%STAMP%_%RANDOM%.txt"
    "%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" snapshots --latest 1 >"!RESTIC_HEALTH_TEMP!" 2>&1
    set "RESTIC_HEALTH_RC=!ERRORLEVEL!"
    if "!RESTIC_HEALTH_RC!"=="0" (
        call :Log "PASS: Restic repository opened and snapshot listing succeeded."
    ) else (
        call :Log "FAIL: Restic repository could not be opened/listed. Exit code !RESTIC_HEALTH_RC!."
        set /a HEALTH_ISSUES+=1
    )
    if exist "!RESTIC_HEALTH_TEMP!" (
        type "!RESTIC_HEALTH_TEMP!">>"%LOGFILE%"
        del /q "!RESTIC_HEALTH_TEMP!" >nul 2>&1
    )
)

call :BlankLine
call :Log "OFFLINE P STATUS"
if exist "P:\" (
    if not exist "%P_ID_FILE%" (
        call :Log "WARNING: P: is connected but the offline identity marker is not present."
        set /a HEALTH_WARNINGS+=1
    ) else (
        set "HEALTH_P_ID_ACTUAL="
        set /p "HEALTH_P_ID_ACTUAL="<"%P_ID_FILE%"
        if "!HEALTH_P_ID_ACTUAL!"=="%P_ID_TOKEN%" (
            call :Log "PASS: Offline P: is connected and has the expected identity marker."
        ) else (
            call :Log "WARNING: P: is connected but its offline identity token does not match."
            set /a HEALTH_WARNINGS+=1
        )
    )
) else (
    call :Log "PASS: Offline P: is disconnected, which is an expected normal state."
)

call :BlankLine
call :Log "LOCK STATUS"
if "!LOCK_ACQUIRED!"=="1" (
    call :Log "PASS: Current health-check instance owns the lock."
    if "!LOCK_RECOVERED!"=="1" (
        call :Log "WARNING: A stale lock was recovered at startup."
        set /a HEALTH_WARNINGS+=1
    )
) else (
    call :Log "FAIL: Current health-check instance does not own the lock."
    set /a HEALTH_ISSUES+=1
)

call :BlankLine
call :Log "LATEST NORMAL BACKUP"
call :ReadLatestOperationalStatus

call :BlankLine
call :Log "DESTINATION FREE SPACE"
call :LogFreeSpace "D:"
call :LogFreeSpace "E:"
if exist "P:\" call :LogFreeSpace "P:"

set "D_DOCS_RESULT=NOT RUN - HEALTH CHECK"
set "D_PICS_RESULT=NOT RUN - HEALTH CHECK"
set "D_RESULT=NOT RUN - HEALTH CHECK"
set "RESTIC_BACKUP_RESULT=NOT RUN - HEALTH CHECK"
set "RESTIC_RETENTION_RESULT=NOT RUN - HEALTH CHECK"
set "RESTIC_RESULT=NOT RUN - HEALTH CHECK"
set "P_DOCS_RESULT=NOT RUN - HEALTH CHECK"
set "P_PICS_RESULT=NOT RUN - HEALTH CHECK"
set "P_RESULT=NOT RUN - HEALTH CHECK"
set "MAINT_RESULT=NOT RUN - HEALTH CHECK"

call :BlankLine
if !HEALTH_ISSUES! EQU 0 (
    if !HEALTH_WARNINGS! EQU 0 (
        call :Log "Overall health: PASS."
    ) else (
        call :Log "Overall health: PASS WITH WARNINGS."
    )
) else (
    call :Log "Overall health: FAIL - !HEALTH_ISSUES! issues, !HEALTH_WARNINGS! warnings."
    call :SetFinalCode 50
)

exit /b 0

REM ============================================================
REM FINAL SUMMARY AND HOUSEKEEPING
REM ============================================================

:Finalize
for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "TOTAL_END=%%I"

if defined TOTAL_START if defined TOTAL_END (
    call :FormatElapsed !TOTAL_START! !TOTAL_END! TOTAL_ELAPSED
) else (
    set "TOTAL_ELAPSED=UNKNOWN"
)

call :BlankLine
call :Log "======================================"
call :Log "PDriveBackup Version: %SCRIPT_VERSION%"
call :Log "Mode: %RUN_MODE%"
call :Log "Finished: %DATE% %TIME%"
call :Log ""
call :Log "D MIRROR RESULTS"
call :Log "  Documents: !D_DOCS_RESULT!"
call :Log "  Pictures:  !D_PICS_RESULT!"
call :Log "  Overall:   !D_RESULT!"
call :Log "  Elapsed:   !D_ELAPSED!"
call :Log ""
call :Log "E RESTIC RESULTS"
call :Log "  Snapshot:  !RESTIC_BACKUP_RESULT!"
call :Log "  Retention: !RESTIC_RETENTION_RESULT!"
call :Log "  Overall:   !RESTIC_RESULT!"
call :Log "  Elapsed:   !RESTIC_ELAPSED!"
call :Log ""
call :Log "P OFFLINE RESULTS"
call :Log "  Documents: !P_DOCS_RESULT!"
call :Log "  Pictures:  !P_PICS_RESULT!"
call :Log "  Overall:   !P_RESULT!"
call :Log "  Elapsed:   !P_ELAPSED!"
call :Log ""
call :Log "MAINTENANCE"
call :Log "  Overall:   !MAINT_RESULT!"
call :Log "  Elapsed:   !MAINT_ELAPSED!"
call :Log ""
call :Log "Total elapsed: !TOTAL_ELAPSED!"
call :Log "Log file: !LOGFILE!"

call :ReleaseLock
if "!LOCK_RELEASED!"=="1" (
    call :Log "Lock cleanup: SUCCESS - !LOCKDIR! removed."
) else if "!LOCK_ACQUIRED!"=="0" (
    call :Log "Lock cleanup: NOT REQUIRED - this run did not acquire the lock."
) else (
    call :Log "Lock cleanup: FAILED - !LOCKDIR! still exists."
    call :SetFinalCode 41
)

call :Log "Final exit code: !FINALCODE!"
call :Log "======================================"

REM Delete only timestamped logs older than the retention period.
forfiles /P "%LOGDIR%" /M "backup_*.log" /D -%LOG_RETENTION_DAYS% /C "cmd /c del /q @path" >nul 2>&1

REM Latest.log = newest completed run of any mode.
copy /Y "%LOGFILE%" "%LATEST_LOG%" >nul 2>&1

REM LatestOperational.log = newest NORMAL BACKUP only. This deliberately
REM excludes HEALTH, VERIFY, OFFLINE, and MAINTENANCE runs so they cannot
REM make a stale scheduled backup look current.
if /I "%RUN_MODE%"=="BACKUP" (
    copy /Y "%LOGFILE%" "%LATEST_OPERATION_LOG%" >nul 2>&1
)

set "SCRIPT_EXIT_CODE=!FINALCODE!"
goto :ScriptEnd

REM ============================================================
REM SOURCE VALIDATION
REM ============================================================

:ValidateSources
set "SOURCES_OK=1"
if not exist "%SRC_DOCS%\" (
    call :Log "ERROR: Source folder was not found: %SRC_DOCS%"
    set "SOURCES_OK=0"
)
if not exist "%SRC_PICS%\" (
    call :Log "ERROR: Source folder was not found: %SRC_PICS%"
    set "SOURCES_OK=0"
)
if "!SOURCES_OK!"=="0" call :Log "Backup operation blocked because a required source is missing."
exit /b 0

REM ============================================================
REM RESTIC HELPERS
REM ============================================================

:ValidateResticConfig
set "RESTIC_CONFIG_OK=1"
where "%RESTIC_CMD%" >nul 2>&1
if errorlevel 1 (
    call :Log "ERROR: Restic was not found in PATH: %RESTIC_CMD%"
    set "RESTIC_CONFIG_OK=0"
    call :SetFinalCode 46
)

if not exist "%RESTIC_PASSWORD_FILE%" (
    call :Log "ERROR: Restic password file was not found:"
    call :Log "  %RESTIC_PASSWORD_FILE%"
    set "RESTIC_CONFIG_OK=0"
    call :SetFinalCode 45
)

if not exist "%RESTIC_REPO%\" (
    call :Log "ERROR: Restic repository was not found:"
    call :Log "  %RESTIC_REPO%"
    set "RESTIC_CONFIG_OK=0"
    call :SetFinalCode 47
)

if "!RESTIC_CONFIG_OK!"=="1" call :Log "Restic configuration: PASS."
exit /b 0

:RunResticSnapshot
set "RESTIC_BACKUP_RC=1"
set "RESTIC_BACKUP_RESULT=FAILED"

call :BlankLine
call :Log "========== DAILY RESTIC SNAPSHOT TO E:\ =========="
call :Log "Repository: %RESTIC_REPO%"
call :Log "Backing up:"
call :Log "  %SRC_DOCS%"
call :Log "  %SRC_PICS%"

"%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" backup ^
    "%SRC_DOCS%" "%SRC_PICS%" >>"%LOGFILE%" 2>&1
set "RESTIC_BACKUP_RC=!ERRORLEVEL!"

if "!RESTIC_BACKUP_RC!"=="0" (
    set "RESTIC_BACKUP_RESULT=SUCCESS - SNAPSHOT SAVED"
    call :Log "Restic backup: PASS."
    call :Log "Latest snapshot:"
    "%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" snapshots --latest 1 >>"%LOGFILE%" 2>&1
) else (
    set "RESTIC_BACKUP_RESULT=FAILED - exit code !RESTIC_BACKUP_RC!"
    call :Log "ERROR: Restic backup failed with exit code !RESTIC_BACKUP_RC!."
)
exit /b 0

:ApplyResticRetention
set "RESTIC_RETENTION_RC=1"
set "RESTIC_RETENTION_RESULT=FAILED"

call :Log "Applying restic retention policy: %KEEP_DAILY% daily, %KEEP_WEEKLY% weekly, %KEEP_MONTHLY% monthly, %KEEP_YEARLY% yearly."
"%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" forget ^
    --keep-daily %KEEP_DAILY% ^
    --keep-weekly %KEEP_WEEKLY% ^
    --keep-monthly %KEEP_MONTHLY% ^
    --keep-yearly %KEEP_YEARLY% >>"%LOGFILE%" 2>&1
set "RESTIC_RETENTION_RC=!ERRORLEVEL!"

if "!RESTIC_RETENTION_RC!"=="0" (
    set "RESTIC_RETENTION_RESULT=SUCCESS"
    call :Log "Restic retention: PASS."
) else (
    set "RESTIC_RETENTION_RESULT=FAILED - exit code !RESTIC_RETENTION_RC!"
    call :Log "ERROR: Restic retention failed with exit code !RESTIC_RETENTION_RC!."
)
exit /b 0

:VerifyResticRepository
set "RESTIC_VERIFY_RC=1"
call :Log "Running restic repository check..."
"%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" check >>"%LOGFILE%" 2>&1
set "RESTIC_VERIFY_RC=!ERRORLEVEL!"
if "!RESTIC_VERIFY_RC!"=="0" (
    call :Log "Restic repository check: PASS."
    call :Log "Latest snapshot:"
    "%RESTIC_CMD%" -r "%RESTIC_REPO%" --password-file "%RESTIC_PASSWORD_FILE%" snapshots --latest 1 >>"%LOGFILE%" 2>&1
) else (
    call :Log "ERROR: Restic repository check failed with exit code !RESTIC_VERIFY_RC!."
)
exit /b 0

REM ============================================================
REM HEALTH-CHECK HELPERS
REM ============================================================

:TestCommand
where "%~1" >nul 2>&1
if errorlevel 1 (
    call :Log "FAIL: %~2 was not found in PATH."
    set /a HEALTH_ISSUES+=1
) else (
    call :Log "PASS: %~2 is available."
)
exit /b 0

:HealthPath
set "HEALTH_PATH=%~1"
set "HEALTH_LABEL=%~2"
set "HEALTH_REQUIRED=%~3"
if exist "%HEALTH_PATH%" (
    call :Log "PASS: %HEALTH_LABEL% - %HEALTH_PATH%"
) else if "%HEALTH_REQUIRED%"=="1" (
    call :Log "FAIL: %HEALTH_LABEL% not found - %HEALTH_PATH%"
    set /a HEALTH_ISSUES+=1
) else (
    call :Log "WARNING: %HEALTH_LABEL% not found - %HEALTH_PATH%"
    set /a HEALTH_WARNINGS+=1
)
exit /b 0

:TestWritableDirectory
set "WRITE_PATH=%~1"
set "WRITE_LABEL=%~2"
set "WRITE_REQUIRED=%~3"
if not exist "%WRITE_PATH%" (
    if "%WRITE_REQUIRED%"=="1" (
        call :Log "FAIL: %WRITE_LABEL% not found - %WRITE_PATH%"
        set /a HEALTH_ISSUES+=1
    ) else (
        call :Log "WARNING: %WRITE_LABEL% not found - %WRITE_PATH%"
        set /a HEALTH_WARNINGS+=1
    )
    exit /b 0
)

set "WRITE_TEST_NAME=.pdrivebackup_write_test_%STAMP%_%RANDOM%.tmp"
pushd "%WRITE_PATH%" >nul 2>&1
if errorlevel 1 (
    call :Log "FAIL: %WRITE_LABEL% could not be opened - %WRITE_PATH%"
    set /a HEALTH_ISSUES+=1
    exit /b 0
)

> "%WRITE_TEST_NAME%" echo PDriveBackup write test
if not exist "%WRITE_TEST_NAME%" (
    popd
    call :Log "FAIL: %WRITE_LABEL% is not writable - %WRITE_PATH%"
    set /a HEALTH_ISSUES+=1
    exit /b 0
)

del /Q "%WRITE_TEST_NAME%" >nul 2>&1
if exist "%WRITE_TEST_NAME%" (
    popd
    call :Log "FAIL: %WRITE_LABEL% write-test file could not be removed - %WRITE_PATH%"
    set /a HEALTH_ISSUES+=1
) else (
    popd
    call :Log "PASS: %WRITE_LABEL% is writable - %WRITE_PATH%"
)
exit /b 0

:ReadLatestOperationalStatus
set "LATEST_EXIT_CODE="
set "LATEST_FINISHED="
set "LATEST_MODE="
set "LATEST_AGE_HOURS="

if not exist "%LATEST_OPERATION_LOG%" (
    call :Log "WARNING: No completed normal backup has been recorded by v26 yet."
    set /a HEALTH_WARNINGS+=1
    exit /b 0
)

for /f "tokens=1,* delims=:" %%A in ('findstr /B /C:"Mode:" /C:"Finished:" /C:"Final exit code:" "%LATEST_OPERATION_LOG%" 2^>nul') do (
    if /I "%%A"=="Mode" set "LATEST_MODE=%%B"
    if /I "%%A"=="Finished" set "LATEST_FINISHED=%%B"
    if /I "%%A"=="Final exit code" set "LATEST_EXIT_CODE=%%B"
)
for /f "tokens=*" %%A in ("!LATEST_MODE!") do set "LATEST_MODE=%%A"
for /f "tokens=*" %%A in ("!LATEST_FINISHED!") do set "LATEST_FINISHED=%%A"
for /f "tokens=*" %%A in ("!LATEST_EXIT_CODE!") do set "LATEST_EXIT_CODE=%%A"

for /f %%I in ('powershell.exe -NoProfile -Command "try { [math]::Floor(((Get-Date)-(Get-Item -LiteralPath '%LATEST_OPERATION_LOG%').LastWriteTime).TotalHours) } catch { '' }"') do set "LATEST_AGE_HOURS=%%I"

if defined LATEST_MODE call :Log "  Mode: !LATEST_MODE!"
if defined LATEST_FINISHED call :Log "  Finished: !LATEST_FINISHED!"
if defined LATEST_AGE_HOURS call :Log "  Age: !LATEST_AGE_HOURS! hours"

if not defined LATEST_EXIT_CODE (
    call :Log "FAIL: LatestOperational.log does not contain a final exit code."
    set /a HEALTH_ISSUES+=1
) else if "!LATEST_EXIT_CODE!"=="0" (
    call :Log "PASS: Latest normal backup exit code was 0."
) else (
    call :Log "FAIL: Latest normal backup exit code was !LATEST_EXIT_CODE!."
    set /a HEALTH_ISSUES+=1
)

if not defined LATEST_AGE_HOURS (
    call :Log "WARNING: Could not determine age of LatestOperational.log."
    set /a HEALTH_WARNINGS+=1
) else if !LATEST_AGE_HOURS! GTR %MAX_BACKUP_AGE_HOURS% (
    call :Log "FAIL: Latest normal backup is older than %MAX_BACKUP_AGE_HOURS% hours."
    set /a HEALTH_ISSUES+=1
) else (
    call :Log "PASS: Latest normal backup is within %MAX_BACKUP_AGE_HOURS% hours."
)
exit /b 0

REM ============================================================
REM VERIFY BACKUP-DRIVE IDENTITY
REM ============================================================

:CheckDriveIdentity
set "DRIVE_ID_ROOT=%~1"
set "DRIVE_ID_FILE=%~2"
set "DRIVE_ID_EXPECTED=%~3"
set "DRIVE_ID_LABEL=%~4"
set "DRIVE_ID_ACTUAL="
set "DRIVE_ID_OK=0"

if not exist "%DRIVE_ID_ROOT%" (
    call :Log "ERROR: %DRIVE_ID_LABEL% is unavailable at %DRIVE_ID_ROOT%."
    exit /b 0
)

if not exist "%DRIVE_ID_FILE%" (
    call :Log "ERROR: %DRIVE_ID_LABEL% identity marker is missing:"
    call :Log "  %DRIVE_ID_FILE%"
    call :Log "Mirror/repository operation blocked to protect any unrelated device using this drive letter."
    exit /b 0
)

set /p "DRIVE_ID_ACTUAL="<"%DRIVE_ID_FILE%"
if not "%DRIVE_ID_ACTUAL%"=="%DRIVE_ID_EXPECTED%" (
    call :Log "ERROR: %DRIVE_ID_LABEL% identity token does not match."
    call :Log "  Marker: %DRIVE_ID_FILE%"
    call :Log "  Expected: %DRIVE_ID_EXPECTED%"
    call :Log "  Found: %DRIVE_ID_ACTUAL%"
    call :Log "Operation blocked to protect the mounted device."
    exit /b 0
)

set "DRIVE_ID_OK=1"
call :Log "%DRIVE_ID_LABEL% identity: PASS."
exit /b 0

REM ============================================================
REM INSPECT AN EXISTING SINGLE-INSTANCE LOCK
REM ============================================================

:InspectExistingLock
set "LOCK_STATUS=UNKNOWN"
set "LOCK_PID="
set "LOCK_PROCESS_START_UTC="
set "LOCK_STARTED="
set "LOCK_AGE_HOURS="

if exist "%LOCKDIR%\RunInfo.txt" (
    for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"PID=" /C:"ProcessStartUtc=" /C:"Started=" "%LOCKDIR%\RunInfo.txt" 2^>nul') do (
        if /I "%%A"=="PID" set "LOCK_PID=%%B"
        if /I "%%A"=="ProcessStartUtc" set "LOCK_PROCESS_START_UTC=%%B"
        if /I "%%A"=="Started" set "LOCK_STARTED=%%B"
    )
)

if defined LOCK_PID if defined LOCK_PROCESS_START_UTC (
    for /f %%I in ('powershell.exe -NoProfile -Command "$p=Get-Process -Id !LOCK_PID! -ErrorAction SilentlyContinue; if ($null -eq $p) { 'STALE' } elseif ($p.StartTime.ToUniversalTime().ToString('o') -eq '!LOCK_PROCESS_START_UTC!') { 'ACTIVE' } else { 'STALE' }"') do set "LOCK_STATUS=%%I"
    exit /b 0
)

for /f %%I in ('powershell.exe -NoProfile -Command "try { [math]::Floor(((Get-Date)-(Get-Item -LiteralPath '%LOCKDIR%').LastWriteTime).TotalHours) } catch { '' }"') do set "LOCK_AGE_HOURS=%%I"

if defined LOCK_AGE_HOURS (
    if !LOCK_AGE_HOURS! GEQ %STALE_LOCK_HOURS% set "LOCK_STATUS=STALE"
)
exit /b 0

REM ============================================================
REM RELEASE SINGLE-INSTANCE LOCK
REM ============================================================

:ReleaseLock
set "LOCK_RELEASED=0"
if "%LOCK_ACQUIRED%"=="0" exit /b 0
if exist "%LOCKDIR%" rmdir /S /Q "%LOCKDIR%" >nul 2>&1
if not exist "%LOCKDIR%" set "LOCK_RELEASED=1"
exit /b 0

REM ============================================================
REM RUN AND VERIFY A MIRROR JOB
REM ============================================================

:RunMirror
set "JOB_SOURCE=%~1"
set "JOB_DEST=%~2"
set "JOB_NAME=%~3"
set "JOB_RC=1"
set "JOB_RESULT=FAILED"

call :BlankLine
call :Log "---- %JOB_NAME% mirror ----"
call :Log "Source: %JOB_SOURCE%"
call :Log "Destination: %JOB_DEST%"

if not exist "%JOB_DEST%\" mkdir "%JOB_DEST%" >>"%LOGFILE%" 2>&1
if not exist "%JOB_DEST%\" (
    set "JOB_RESULT=FAILED - destination could not be created"
    call :Log "ERROR: Destination could not be created."
    exit /b 0
)

robocopy "%JOB_SOURCE%" "%JOB_DEST%" ^
    /MIR ^
    /R:3 ^
    /W:5 ^
    /COPY:DAT ^
    /DCOPY:DAT ^
    /FFT ^
    /XJ ^
    /XA:SH ^
    /XD "$RECYCLE.BIN" "System Volume Information" "%JOB_SOURCE%\$RECYCLE.BIN" "%JOB_SOURCE%\System Volume Information" "%JOB_DEST%\$RECYCLE.BIN" "%JOB_DEST%\System Volume Information" ^
    /MT:16 ^
    /LOG+:"%LOGFILE%" ^
    /NP

set "COPY_RC=!ERRORLEVEL!"
if !COPY_RC! GEQ 8 (
    set "JOB_RESULT=FAILED - Robocopy code !COPY_RC!"
    call :Log "ERROR: %JOB_NAME% failed with Robocopy exit code !COPY_RC!."
    exit /b 0
)

call :Log "%JOB_NAME% completed with Robocopy exit code !COPY_RC!."
call :VerifyMirror "%JOB_SOURCE%" "%JOB_DEST%" "%JOB_NAME%"
set "VERIFY_JOB_RC=!VERIFY_RC!"

if !VERIFY_JOB_RC! EQU 0 (
    set "JOB_RC=0"
    set "JOB_RESULT=SUCCESS - VERIFIED"
    call :Log "%JOB_NAME% verification: PASS."
) else if !VERIFY_JOB_RC! GEQ 8 (
    set "JOB_RESULT=BACKUP COMPLETED - VERIFICATION ERROR !VERIFY_JOB_RC!"
    call :Log "ERROR: %JOB_NAME% verification could not complete. Robocopy code !VERIFY_JOB_RC!."
) else (
    set "JOB_RESULT=BACKUP COMPLETED - VERIFICATION FAILED"
    call :Log "ERROR: %JOB_NAME% verification found differences. Robocopy code !VERIFY_JOB_RC!."
)
exit /b 0

REM ============================================================
REM VERIFY A MIRROR
REM ============================================================

:VerifyMirror
set "VERIFY_SOURCE=%~1"
set "VERIFY_DEST=%~2"
set "VERIFY_NAME=%~3"
set "VERIFY_REPORT=%TEMP%\PDriveMirrorVerify_%STAMP%_%RANDOM%.log"

call :BlankLine
call :Log "---- Verifying %VERIFY_NAME% ----"

robocopy "%VERIFY_SOURCE%" "%VERIFY_DEST%" ^
    /MIR ^
    /L ^
    /XX ^
    /R:0 ^
    /W:0 ^
    /COPY:DAT ^
    /DCOPY:DAT ^
    /FFT ^
    /XJ ^
    /XA:SH ^
    /XD "$RECYCLE.BIN" "System Volume Information" "%VERIFY_SOURCE%\$RECYCLE.BIN" "%VERIFY_SOURCE%\System Volume Information" "%VERIFY_DEST%\$RECYCLE.BIN" "%VERIFY_DEST%\System Volume Information" ^
    /NFL ^
    /NDL ^
    /NJH ^
    /NP ^
    /LOG:"%VERIFY_REPORT%"

set "VERIFY_RAW_RC=!ERRORLEVEL!"
set "VERIFY_RC=!VERIFY_RAW_RC!"
call :Log "%VERIFY_NAME% verification Robocopy exit code: !VERIFY_RAW_RC!."

REM /XX ignores destination-only items. Robocopy code 2 therefore represents
REM only ignored extras and is accepted as success.
if "!VERIFY_RAW_RC!"=="2" (
    set "VERIFY_RC=0"
    call :Log "%VERIFY_NAME% verification note: code 2 accepted because /XX ignores destination-only items."
)

if exist "%VERIFY_REPORT%" (
    type "%VERIFY_REPORT%">>"%LOGFILE%"
    del /q "%VERIFY_REPORT%" >nul 2>&1
)
exit /b 0

REM ============================================================
REM CONVERT A VERIFICATION EXIT CODE TO A RESULT STRING
REM ============================================================

:SetVerifyResult
set "RESULT_RC=%~1"
set "RESULT_SUCCESS=%~2"
set "RESULT_VARIABLE=%~3"

if "%RESULT_RC%"=="0" (
    set "%RESULT_VARIABLE%=SUCCESS - %RESULT_SUCCESS%"
) else if %RESULT_RC% GEQ 8 (
    set "%RESULT_VARIABLE%=FAILED - VERIFICATION ERROR %RESULT_RC%"
) else (
    set "%RESULT_VARIABLE%=FAILED - DIFFERENCES FOUND, ROBOCOPY CODE %RESULT_RC%"
)
exit /b 0

REM ============================================================
REM SET FIRST NONZERO FINAL EXIT CODE
REM ============================================================

:SetFinalCode
if "!FINALCODE!"=="0" set "FINALCODE=%~1"
exit /b 0

REM ============================================================
REM LOG DRIVE FREE SPACE
REM ============================================================

:LogFreeSpace
set "SPACE_DRIVE=%~1"
if not exist "%SPACE_DRIVE%\" (
    call :Log "  %SPACE_DRIVE% unavailable"
    exit /b 0
)

for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "$d=[System.IO.DriveInfo]::new('%SPACE_DRIVE%\'); '{0} {1:N2} GiB free of {2:N2} GiB' -f $d.Name.TrimEnd('\'),($d.AvailableFreeSpace/1GB),($d.TotalSize/1GB)"') do (
    call :Log "  %%I"
)
exit /b 0

REM ============================================================
REM FORMAT ELAPSED SECONDS
REM ============================================================

:FormatElapsed
set /a "ELAPSED_SECONDS=%~2-%~1"
if !ELAPSED_SECONDS! LSS 0 set "ELAPSED_SECONDS=0"

set /a "ELAPSED_HOURS=ELAPSED_SECONDS/3600"
set /a "ELAPSED_MINUTES=(ELAPSED_SECONDS%%3600)/60"
set /a "ELAPSED_REMAINDER=ELAPSED_SECONDS%%60"

if !ELAPSED_HOURS! GTR 0 (
    set "ELAPSED_TEXT=!ELAPSED_HOURS!h !ELAPSED_MINUTES!m !ELAPSED_REMAINDER!s"
) else if !ELAPSED_MINUTES! GTR 0 (
    set "ELAPSED_TEXT=!ELAPSED_MINUTES!m !ELAPSED_REMAINDER!s"
) else (
    set "ELAPSED_TEXT=!ELAPSED_REMAINDER!s"
)
set "%~3=!ELAPSED_TEXT!"
exit /b 0

REM ============================================================
REM LOG HELPERS
REM ============================================================

:Log
if "%~1"=="" (
    echo.
    >>"%LOGFILE%" echo.
) else (
    echo(%~1
    >>"%LOGFILE%" echo(%~1
)
exit /b 0

:BlankLine
echo.
echo.>>"%LOGFILE%"
exit /b 0

:ScriptEnd
endlocal & exit /b %SCRIPT_EXIT_CODE%

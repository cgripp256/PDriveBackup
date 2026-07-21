@echo off

REM ============================================================
REM PDriveBackup
REM
REM Author: Christopher Gripp
REM Current Version: 18
REM Created: February 2026
REM Last Updated: July 2026
REM
REM Daily mirror to D:
REM Weekly mirror to E:
REM Weekly retained copy to iCloud
REM ============================================================

setlocal EnableExtensions EnableDelayedExpansion

title PDriveBackup v18

REM ============================================================
REM PDriveBackup.bat
REM Version 16
REM
REM Changes in Version 16:
REM - Rebuilds from the known-good Version 14 source
REM - Adds /TEST mode for non-copying configuration and schedule checks
REM - Funnels all post-lock exits through one finalization path
REM - Adds explicit lock-release success or failure to each completed log
REM - Consolidates lock cleanup in the ReleaseLock subroutine
REM
REM Changes in Version 14:
REM - Fixes CMD parsing failure caused by parentheses in day(s) messages
REM - Removes the UTF-8 byte-order mark that appeared as garbled characters
REM
REM Changes in Version 13:
REM - Fixes premature termination after the daily D: verification
REM - Avoids a numeric GEQ comparison when WEEKLY_AGE is undefined
REM - Allows finalization to run and release the single-instance lock
REM
REM Changes in Version 12:
REM - Adds a definitive main-program exit before all subroutine labels
REM - Prevents accidental fall-through into backup subroutines after finalization
REM - Uses millisecond timestamps to prevent two runs sharing one log filename
REM
REM Changes retained from Version 11:
REM - Mirror verification now uses /XX to ignore destination-only items
REM - Prevents Windows-created folders such as $RECYCLE.BIN from
REM   causing an otherwise valid mirror verification to fail
REM
REM Changes retained from Version 10:
REM - Excludes full source and destination paths for $RECYCLE.BIN
REM   and System Volume Information during mirror and verification
REM - Prevents Windows system folders from causing Robocopy code 2
REM
REM Changes retained from Version 9:
REM - Fixes false iCloud verification failures caused by iCloud metadata changes
REM - iCloud verification now checks that every source item exists locally
REM - Fixes blank log lines displaying "ECHO is off."
REM
REM Changes retained from Version 8:
REM - Prevents overlapping runs with a single-instance lock
REM - Adds /VERIFY mode to check D:, E:, and local iCloud without copying
REM - Logs the script version and operating mode in every run
REM - Explicitly checks and logs Robocopy copy and verification exit codes
REM
REM Changes retained from Version 7:
REM - Rewrites free-space reporting to avoid unsafe nested command quoting
REM - Verifies the weekly marker is successfully written and replaced
REM
REM Changes retained from Version 6:
REM - Creates Latest.log as a copy of the newest completed run log
REM - Skips the weekly E: and iCloud jobs if the daily D: backup fails
REM - Logs free space on P:, D:, and E: before backup work begins
REM - Logs elapsed time for the daily, weekly E:, iCloud, and total run
REM - Deletes timestamped backup logs older than 365 days
REM
REM BACKED-UP SOURCE FOLDERS:
REM   P:\Documents
REM   P:\Pictures
REM
REM DAILY:
REM   Mirrors both source folders to:
REM     D:\Documents
REM     D:\Pictures
REM   Then verifies both mirrors.
REM
REM WEEKLY:
REM   Mirrors both source folders to:
REM     E:\Documents
REM     E:\Pictures
REM   Copies both source folders to:
REM     %USERPROFILE%\iCloudDrive\Backups\Documents
REM     %USERPROFILE%\iCloudDrive\Backups\Pictures
REM
REM   The E: jobs use /MIR.
REM   The iCloud jobs use /E, not /MIR, so deletions from P:
REM   do not automatically delete retained files in iCloud.
REM
REM The weekly marker updates only after BOTH E: folders and BOTH
REM local iCloud folders verify successfully.
REM
REM IMPORTANT:
REM   D:\Documents, D:\Pictures, E:\Documents, and E:\Pictures
REM   are treated as dedicated mirrors. /MIR deletes destination
REM   items that no longer exist in the corresponding source.
REM
REM   The script verifies the local iCloud Drive folders only.
REM   iCloud for Windows uploads them asynchronously afterward.
REM ============================================================

REM ===== Configuration =====
set "SRC_DOCS=P:\Documents"
set "SRC_PICS=P:\Pictures"

set "DEST_D_DOCS=D:\Documents"
set "DEST_D_PICS=D:\Pictures"

set "DEST_E_DOCS=E:\Documents"
set "DEST_E_PICS=E:\Pictures"

set "ICLOUD_ROOT=%USERPROFILE%\iCloudDrive"
set "ICLOUD_BACKUP_ROOT=%ICLOUD_ROOT%\Backups"
set "DEST_ICLOUD_DOCS=%ICLOUD_BACKUP_ROOT%\Documents"
set "DEST_ICLOUD_PICS=%ICLOUD_BACKUP_ROOT%\Pictures"

set "WEEKLY_DAYS=7"
set "LOG_RETENTION_DAYS=365"
set "SCRIPT_VERSION=18"

REM ===== Paths based on this BAT file's folder =====
set "BASEDIR=%~dp0"
set "LOGDIR=%BASEDIR%PDriveBackupLogs"
set "STATEDIR=%BASEDIR%PDriveBackupState"
set "WEEKLY_MARKER=%STATEDIR%\LastSuccessfulWeeklyBackup.marker"
set "WEEKLY_MARKER_TEMP=%STATEDIR%\LastSuccessfulWeeklyBackup.tmp"
set "LOCKDIR=%STATEDIR%\PDriveBackup.lock"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%STATEDIR%" mkdir "%STATEDIR%"

REM ===== Locale-independent timestamp =====
for /f %%I in (
    'powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"'
) do set "STAMP=%%I"

set "LOGFILE=%LOGDIR%\backup_%STAMP%.log"
set "LATEST_LOG=%LOGDIR%\Latest.log"

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "TOTAL_START=%%I"

set "DAILY_ELAPSED=NOT RUN"
set "E_ELAPSED=NOT RUN"
set "ICLOUD_ELAPSED=NOT RUN"
set "TOTAL_ELAPSED=UNKNOWN"

set "RUN_MODE=BACKUP"
if /I "%~1"=="/VERIFY" set "RUN_MODE=VERIFY ONLY"
if /I "%~1"=="-VERIFY" set "RUN_MODE=VERIFY ONLY"
if /I "%~1"=="--VERIFY" set "RUN_MODE=VERIFY ONLY"
if /I "%~1"=="/TEST" set "RUN_MODE=SELF TEST"
if /I "%~1"=="-TEST" set "RUN_MODE=SELF TEST"
if /I "%~1"=="--TEST" set "RUN_MODE=SELF TEST"

if not "%~1"=="" if /I not "%~1"=="/VERIFY" if /I not "%~1"=="-VERIFY" if /I not "%~1"=="--VERIFY" if /I not "%~1"=="/TEST" if /I not "%~1"=="-TEST" if /I not "%~1"=="--TEST" (
    call :Log "ERROR: Unknown option: %~1"
    call :Log "Usage:"
    call :Log "  %~nx0"
    call :Log "  %~nx0 /VERIFY"
    call :Log "  %~nx0 /TEST"
    copy /Y "%LOGFILE%" "%LATEST_LOG%" >nul 2>&1
    endlocal & exit /b 2
)

set "LOCK_ACQUIRED=0"
mkdir "%LOCKDIR%" >nul 2>&1
if errorlevel 1 (
    call :Log "ERROR: Another PDriveBackup instance appears to be running."
    call :Log "Lock location:"
    call :Log "  %LOCKDIR%"
    call :Log "If no backup is running, delete that lock directory manually and run again."
    endlocal & exit /b 40
)
set "LOCK_ACQUIRED=1"
> "%LOCKDIR%\RunInfo.txt" (
    echo PDriveBackup Version %SCRIPT_VERSION%
    echo Started: %DATE% %TIME%
    echo Computer: %COMPUTERNAME%
    echo Mode: %RUN_MODE%
)


set "FINALCODE=0"
set "D_DOCS_RESULT=SKIPPED"
set "D_PICS_RESULT=SKIPPED"
set "D_RESULT=SKIPPED"

set "E_DOCS_RESULT=SKIPPED"
set "E_PICS_RESULT=SKIPPED"
set "E_RESULT=SKIPPED"

set "ICLOUD_DOCS_RESULT=SKIPPED"
set "ICLOUD_PICS_RESULT=SKIPPED"
set "ICLOUD_RESULT=SKIPPED"

set "WEEKLY_RESULT=SKIPPED"

call :Log "======================================"
call :Log "PDriveBackup Version %SCRIPT_VERSION%"
call :Log "Mode: %RUN_MODE%"
call :Log "Backup started: %DATE% %TIME%"
call :Log "Sources:"
call :Log "  %SRC_DOCS%"
call :Log "  %SRC_PICS%"
call :Log "Daily destination root: D:\"
call :Log "Weekly destination root: E:\"
call :Log "Weekly iCloud root: %ICLOUD_BACKUP_ROOT%"
call :Log "======================================"

call :BlankLine
call :Log "========== FREE SPACE BEFORE BACKUP =========="
call :LogFreeSpace "P:"
call :LogFreeSpace "D:"
call :LogFreeSpace "E:"

REM ============================================================
REM SELF-TEST MODE
REM ============================================================

if /I "%RUN_MODE%"=="SELF TEST" (
    call :RunSelfTest
    goto :Finalize
)

REM ============================================================
REM VERIFY SOURCE FOLDERS
REM ============================================================

if not exist "%SRC_DOCS%\" (
    call :Log "ERROR: Source folder was not found: %SRC_DOCS%"
    call :Log "Backup aborted."
    set "FINALCODE=10"
    goto :Finalize
)

if not exist "%SRC_PICS%\" (
    call :Log "ERROR: Source folder was not found: %SRC_PICS%"
    call :Log "Backup aborted."
    set "FINALCODE=10"
    goto :Finalize
)

if /I "%RUN_MODE%"=="VERIFY ONLY" (
    call :BlankLine
    call :Log "========== VERIFY-ONLY MODE =========="
    call :Log "No files will be copied, changed, or deleted."

    if exist "D:\" (
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
            if !FINALCODE! EQU 0 set "FINALCODE=20"
        )
    ) else (
        set "D_DOCS_RESULT=FAILED - D drive not found"
        set "D_PICS_RESULT=FAILED - D drive not found"
        set "D_RESULT=FAILED - D drive not found"
        if !FINALCODE! EQU 0 set "FINALCODE=11"
    )

    if exist "E:\" (
        call :VerifyMirror "%SRC_DOCS%" "%DEST_E_DOCS%" "E Documents"
        set "E_DOCS_VERIFY_RC=!VERIFY_RC!"
        call :SetVerifyResult !E_DOCS_VERIFY_RC! "VERIFIED" E_DOCS_RESULT

        call :VerifyMirror "%SRC_PICS%" "%DEST_E_PICS%" "E Pictures"
        set "E_PICS_VERIFY_RC=!VERIFY_RC!"
        call :SetVerifyResult !E_PICS_VERIFY_RC! "VERIFIED" E_PICS_RESULT

        if "!E_DOCS_VERIFY_RC!"=="0" if "!E_PICS_VERIFY_RC!"=="0" (
            set "E_RESULT=SUCCESS - BOTH FOLDERS VERIFIED"
        ) else (
            set "E_RESULT=VERIFICATION FAILED OR INCOMPLETE"
            if !FINALCODE! EQU 0 set "FINALCODE=21"
        )
    ) else (
        set "E_DOCS_RESULT=FAILED - E drive not found"
        set "E_PICS_RESULT=FAILED - E drive not found"
        set "E_RESULT=FAILED - E drive not found"
        if !FINALCODE! EQU 0 set "FINALCODE=12"
    )

    if exist "%ICLOUD_ROOT%\" (
        call :VerifyCloudCopy "%SRC_DOCS%" "%DEST_ICLOUD_DOCS%" "iCloud Documents"
        set "ICLOUD_DOCS_VERIFY_RC=!VERIFY_RC!"
        call :SetVerifyResult !ICLOUD_DOCS_VERIFY_RC! "LOCAL COPY VERIFIED" ICLOUD_DOCS_RESULT

        call :VerifyCloudCopy "%SRC_PICS%" "%DEST_ICLOUD_PICS%" "iCloud Pictures"
        set "ICLOUD_PICS_VERIFY_RC=!VERIFY_RC!"
        call :SetVerifyResult !ICLOUD_PICS_VERIFY_RC! "LOCAL COPY VERIFIED" ICLOUD_PICS_RESULT

        if "!ICLOUD_DOCS_VERIFY_RC!"=="0" if "!ICLOUD_PICS_VERIFY_RC!"=="0" (
            set "ICLOUD_RESULT=SUCCESS - BOTH LOCAL COPIES VERIFIED"
        ) else (
            set "ICLOUD_RESULT=VERIFICATION FAILED OR INCOMPLETE"
            if !FINALCODE! EQU 0 set "FINALCODE=22"
        )
    ) else (
        set "ICLOUD_DOCS_RESULT=FAILED - iCloud Drive folder not found"
        set "ICLOUD_PICS_RESULT=FAILED - iCloud Drive folder not found"
        set "ICLOUD_RESULT=FAILED - iCloud Drive folder not found"
        if !FINALCODE! EQU 0 set "FINALCODE=13"
    )

    set "WEEKLY_RESULT=NOT APPLICABLE - VERIFY-ONLY MODE"
    goto :Finalize
)

REM ============================================================
REM DAILY BACKUP: P:\Documents and P:\Pictures to D:\
REM ============================================================

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "DAILY_START=%%I"

if exist "D:\" (
    call :BlankLine
    call :Log "========== DAILY BACKUP TO D:\ =========="

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

        if !FINALCODE! EQU 0 set "FINALCODE=20"
    )
) else (
    set "D_DOCS_RESULT=FAILED - D drive not found"
    set "D_PICS_RESULT=FAILED - D drive not found"
    set "D_RESULT=FAILED - D drive not found"
    set "FINALCODE=11"
    call :Log "ERROR: Daily destination drive D:\ was not found."
)

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "DAILY_END=%%I"
call :FormatElapsed !DAILY_START! !DAILY_END! DAILY_ELAPSED

if /I not "!D_RESULT!"=="SUCCESS - BOTH FOLDERS VERIFIED" (
    set "E_DOCS_RESULT=SKIPPED - daily D backup failed"
    set "E_PICS_RESULT=SKIPPED - daily D backup failed"
    set "E_RESULT=SKIPPED - daily D backup failed"
    set "ICLOUD_DOCS_RESULT=SKIPPED - daily D backup failed"
    set "ICLOUD_PICS_RESULT=SKIPPED - daily D backup failed"
    set "ICLOUD_RESULT=SKIPPED - daily D backup failed"
    set "WEEKLY_RESULT=SKIPPED - daily D backup failed"
    call :BlankLine
    call :Log "WARNING: Weekly E: and iCloud jobs skipped because the daily D: backup did not verify."
    goto :Finalize
)

REM ============================================================
REM DETERMINE WHETHER WEEKLY E + ICLOUD CYCLE IS DUE
REM ============================================================

set "RUN_WEEKLY=0"
set "WEEKLY_AGE="

if not exist "%WEEKLY_MARKER%" (
    set "RUN_WEEKLY=1"
    call :BlankLine
    call :Log "No successful weekly-backup marker exists. Weekly cycle is due."
) else (
    for /f %%I in (
        'powershell.exe -NoProfile -Command "$age=[math]::Floor(((Get-Date)-(Get-Item -LiteralPath '%WEEKLY_MARKER%').LastWriteTime).TotalDays); Write-Output $age"'
    ) do set "WEEKLY_AGE=%%I"

    if not defined WEEKLY_AGE (
        set "RUN_WEEKLY=1"
        call :BlankLine
        call :Log "WARNING: Could not determine weekly marker age. Weekly cycle will run."
    ) else (
        if !WEEKLY_AGE! GEQ %WEEKLY_DAYS% (
            set "RUN_WEEKLY=1"
            call :BlankLine
            call :Log "Last fully successful weekly cycle was !WEEKLY_AGE! days ago. Weekly cycle is due."
        ) else (
            set "RUN_WEEKLY=0"
            set "E_DOCS_RESULT=SKIPPED - weekly cycle completed !WEEKLY_AGE! days ago"
            set "E_PICS_RESULT=SKIPPED - weekly cycle completed !WEEKLY_AGE! days ago"
            set "E_RESULT=SKIPPED - weekly cycle completed !WEEKLY_AGE! days ago"

            set "ICLOUD_DOCS_RESULT=SKIPPED - weekly cycle completed !WEEKLY_AGE! days ago"
            set "ICLOUD_PICS_RESULT=SKIPPED - weekly cycle completed !WEEKLY_AGE! days ago"
            set "ICLOUD_RESULT=SKIPPED - weekly cycle completed !WEEKLY_AGE! days ago"

            set "WEEKLY_RESULT=SKIPPED - last success !WEEKLY_AGE! days ago"

            call :BlankLine
            call :Log "Weekly E and iCloud jobs skipped. Last fully successful weekly cycle was !WEEKLY_AGE! days ago."
        )
    )
)

REM ============================================================
REM WEEKLY CYCLE
REM ============================================================

if "!RUN_WEEKLY!"=="1" (
    set "E_WEEKLY_OK=0"
    set "ICLOUD_WEEKLY_OK=0"

    REM --------------------------------------------------------
    REM WEEKLY MIRRORS TO E:\
    REM --------------------------------------------------------

    for /f %%I in (
        'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
    ) do set "E_START=%%I"

    if exist "E:\" (
        call :BlankLine
        call :Log "========== WEEKLY BACKUP TO E:\ =========="

        call :RunMirror "%SRC_DOCS%" "%DEST_E_DOCS%" "E Documents"
        set "E_DOCS_RC=!JOB_RC!"
        set "E_DOCS_RESULT=!JOB_RESULT!"

        call :RunMirror "%SRC_PICS%" "%DEST_E_PICS%" "E Pictures"
        set "E_PICS_RC=!JOB_RC!"
        set "E_PICS_RESULT=!JOB_RESULT!"

        if "!E_DOCS_RC!"=="0" if "!E_PICS_RC!"=="0" (
            set "E_RESULT=SUCCESS - BOTH FOLDERS VERIFIED"
            set "E_WEEKLY_OK=1"
        ) else (
            set "E_RESULT=FAILED OR INCOMPLETE"

            if !FINALCODE! EQU 0 set "FINALCODE=21"
        )
    ) else (
        set "E_DOCS_RESULT=FAILED - E drive not found"
        set "E_PICS_RESULT=FAILED - E drive not found"
        set "E_RESULT=FAILED - E drive not found"
        call :Log "ERROR: Weekly destination drive E:\ was not found."

        if !FINALCODE! EQU 0 set "FINALCODE=12"
    )

    for /f %%I in (
        'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
    ) do set "E_END=%%I"
    call :FormatElapsed !E_START! !E_END! E_ELAPSED

    REM --------------------------------------------------------
    REM WEEKLY RETAINED COPIES TO ICLOUD
    REM --------------------------------------------------------

    call :BlankLine
    call :Log "========== WEEKLY BACKUP TO ICLOUD =========="

    for /f %%I in (
        'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
    ) do set "ICLOUD_START=%%I"

    if not exist "%ICLOUD_ROOT%\" (
        set "ICLOUD_DOCS_RESULT=FAILED - iCloud Drive folder not found"
        set "ICLOUD_PICS_RESULT=FAILED - iCloud Drive folder not found"
        set "ICLOUD_RESULT=FAILED - iCloud Drive folder not found"

        call :Log "ERROR: iCloud Drive folder was not found at:"
        call :Log "  %ICLOUD_ROOT%"

        if !FINALCODE! EQU 0 set "FINALCODE=13"
    ) else (
        if not exist "%ICLOUD_BACKUP_ROOT%\" (
            call :Log "Creating iCloud backup root:"
            call :Log "  %ICLOUD_BACKUP_ROOT%"

            mkdir "%ICLOUD_BACKUP_ROOT%" >>"%LOGFILE%" 2>&1
        )

        if not exist "%ICLOUD_BACKUP_ROOT%\" (
            set "ICLOUD_DOCS_RESULT=FAILED - backup root could not be created"
            set "ICLOUD_PICS_RESULT=FAILED - backup root could not be created"
            set "ICLOUD_RESULT=FAILED - backup root could not be created"

            call :Log "ERROR: Could not create the iCloud backup root."

            if !FINALCODE! EQU 0 set "FINALCODE=14"
        ) else (
            call :RunCloudCopy "%SRC_DOCS%" "%DEST_ICLOUD_DOCS%" "iCloud Documents"
            set "ICLOUD_DOCS_RC=!JOB_RC!"
            set "ICLOUD_DOCS_RESULT=!JOB_RESULT!"

            call :RunCloudCopy "%SRC_PICS%" "%DEST_ICLOUD_PICS%" "iCloud Pictures"
            set "ICLOUD_PICS_RC=!JOB_RC!"
            set "ICLOUD_PICS_RESULT=!JOB_RESULT!"

            if "!ICLOUD_DOCS_RC!"=="0" if "!ICLOUD_PICS_RC!"=="0" (
                set "ICLOUD_RESULT=SUCCESS - BOTH LOCAL COPIES VERIFIED"
                set "ICLOUD_WEEKLY_OK=1"
                call :Log "NOTE: iCloud for Windows uploads the verified local folders asynchronously."
            ) else (
                set "ICLOUD_RESULT=FAILED OR INCOMPLETE"

                if !FINALCODE! EQU 0 set "FINALCODE=22"
            )
        )
    )

    for /f %%I in (
        'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
    ) do set "ICLOUD_END=%%I"
    call :FormatElapsed !ICLOUD_START! !ICLOUD_END! ICLOUD_ELAPSED

    REM --------------------------------------------------------
    REM UPDATE SHARED WEEKLY MARKER ONLY IF EVERYTHING PASSED
    REM --------------------------------------------------------

    if "!E_WEEKLY_OK!"=="1" if "!ICLOUD_WEEKLY_OK!"=="1" (
        del /q "%WEEKLY_MARKER_TEMP%" >nul 2>&1
        >"%WEEKLY_MARKER_TEMP%" echo Last successful E and iCloud backup: %DATE% %TIME%
        set "MARKER_WRITE_RC=!ERRORLEVEL!"

        if not "!MARKER_WRITE_RC!"=="0" (
            set "WEEKLY_RESULT=FAILED - weekly marker could not be written"
            if !FINALCODE! EQU 0 set "FINALCODE=30"

            call :BlankLine
            call :Log "ERROR: Weekly backups verified, but the temporary marker file could not be written."
            call :Log "The weekly marker was not updated."
            call :Log "  %WEEKLY_MARKER_TEMP%"
        ) else if not exist "%WEEKLY_MARKER_TEMP%" (
            set "WEEKLY_RESULT=FAILED - temporary weekly marker is missing"
            if !FINALCODE! EQU 0 set "FINALCODE=30"

            call :BlankLine
            call :Log "ERROR: Weekly backups verified, but the temporary marker file is missing."
            call :Log "The weekly marker was not updated."
            call :Log "  %WEEKLY_MARKER_TEMP%"
        ) else (
            move /Y "%WEEKLY_MARKER_TEMP%" "%WEEKLY_MARKER%" >nul 2>&1
            set "MARKER_MOVE_RC=!ERRORLEVEL!"

            if not "!MARKER_MOVE_RC!"=="0" (
                set "WEEKLY_RESULT=FAILED - weekly marker could not be replaced"
                if !FINALCODE! EQU 0 set "FINALCODE=30"

                call :BlankLine
                call :Log "ERROR: Weekly backups verified, but the weekly marker could not be replaced."
                call :Log "The weekly marker was not updated."
                call :Log "  %WEEKLY_MARKER%"
            ) else if not exist "%WEEKLY_MARKER%" (
                set "WEEKLY_RESULT=FAILED - weekly marker is missing after replacement"
                if !FINALCODE! EQU 0 set "FINALCODE=30"

                call :BlankLine
                call :Log "ERROR: Weekly backups verified, but the weekly marker is missing after replacement."
                call :Log "  %WEEKLY_MARKER%"
            ) else (
                set "WEEKLY_RESULT=SUCCESS - E AND ICLOUD VERIFIED"

                call :BlankLine
                call :Log "Weekly cycle: PASS."
                call :Log "Documents and Pictures verified on E: and in the local iCloud folders."
                call :Log "Updated weekly marker file:"
                call :Log "  %WEEKLY_MARKER%"
            )
        )
    ) else (
        set "WEEKLY_RESULT=FAILED OR INCOMPLETE - marker not updated"

        call :BlankLine
        call :Log "WARNING: Weekly cycle was not fully successful."
        call :Log "The weekly marker was not updated."
        call :Log "All weekly jobs will be attempted again the next time the script runs."
    )
)

REM ============================================================
REM FINAL SUMMARY AND HOUSEKEEPING
REM ============================================================

:Finalize

for /f %%I in (
    'powershell.exe -NoProfile -Command "[int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())"'
) do set "TOTAL_END=%%I"

if defined TOTAL_START if defined TOTAL_END (
    call :FormatElapsed !TOTAL_START! !TOTAL_END! TOTAL_ELAPSED
)

call :BlankLine
call :Log "======================================"
call :Log "PDriveBackup Version: %SCRIPT_VERSION%"
call :Log "Mode: %RUN_MODE%"
call :Log "Backup finished: %DATE% %TIME%"
call :Log ""
call :Log "DAILY D RESULTS"
call :Log "  Documents: !D_DOCS_RESULT!"
call :Log "  Pictures:  !D_PICS_RESULT!"
call :Log "  Overall:   !D_RESULT!"
call :Log "  Elapsed:   !DAILY_ELAPSED!"
call :Log ""
call :Log "WEEKLY E RESULTS"
call :Log "  Documents: !E_DOCS_RESULT!"
call :Log "  Pictures:  !E_PICS_RESULT!"
call :Log "  Overall:   !E_RESULT!"
call :Log "  Elapsed:   !E_ELAPSED!"
call :Log ""
call :Log "WEEKLY ICLOUD RESULTS"
call :Log "  Documents: !ICLOUD_DOCS_RESULT!"
call :Log "  Pictures:  !ICLOUD_PICS_RESULT!"
call :Log "  Overall:   !ICLOUD_RESULT!"
call :Log "  Elapsed:   !ICLOUD_ELAPSED!"
call :Log ""
call :Log "Weekly cycle: !WEEKLY_RESULT!"
call :Log "Total elapsed: !TOTAL_ELAPSED!"
call :Log "Log file: !LOGFILE!"

REM Every path after lock acquisition reaches this single cleanup point.
call :ReleaseLock
if "!LOCK_RELEASED!"=="1" (
    call :Log "Lock cleanup: SUCCESS - !LOCKDIR! removed."
) else if "!LOCK_ACQUIRED!"=="0" (
    call :Log "Lock cleanup: NOT REQUIRED - this run did not acquire the lock."
) else (
    call :Log "Lock cleanup: FAILED - !LOCKDIR! still exists."
    if !FINALCODE! EQU 0 set "FINALCODE=41"
)
echo Final exit code: !FINALCODE!
echo Final exit code: !FINALCODE!>>"!LOGFILE!"
call :Log "======================================"

REM Delete only timestamped logs older than the retention period.
REM Latest.log is not matched by backup_*.log and is retained.
forfiles /P "%LOGDIR%" /M "backup_*.log" /D -%LOG_RETENTION_DAYS% /C "cmd /c del /q @path" >nul 2>&1

REM Maintain one easy-to-find copy of the newest completed run log.
copy /Y "%LOGFILE%" "%LATEST_LOG%" >nul 2>&1

REM Capture the final code before ENDLOCAL, then terminate the main program.
REM The explicit GOTO prevents execution from ever falling through into the
REM subroutine labels below.
set "SCRIPT_EXIT_CODE=!FINALCODE!"
goto :ScriptEnd

REM ============================================================
REM NON-COPYING SELF TEST
REM ============================================================

:RunSelfTest
set "TEST_ISSUES=0"
set "TEST_WEEKLY_STATUS=UNKNOWN"

call :BlankLine
call :Log "========== SELF TEST =========="
call :Log "No Robocopy copy or delete operation will be executed."

call :TestPath "%SRC_DOCS%" "Source Documents folder" 1
call :TestPath "%SRC_PICS%" "Source Pictures folder" 1
call :TestPath "D:\" "Daily destination drive D" 1
call :TestPath "E:\" "Weekly destination drive E" 0
call :TestPath "%ICLOUD_ROOT%" "Local iCloud Drive folder" 0
call :TestPath "%LOGDIR%" "Log directory" 1
call :TestPath "%STATEDIR%" "State directory" 1

if not exist "%WEEKLY_MARKER%" (
    set "TEST_WEEKLY_STATUS=DUE - no successful marker exists"
    call :Log "Weekly schedule: DUE - no successful weekly marker exists."
) else (
    set "TEST_WEEKLY_AGE="
    for /f %%I in (
        'powershell.exe -NoProfile -Command "$age=[math]::Floor(((Get-Date)-(Get-Item -LiteralPath '%WEEKLY_MARKER%').LastWriteTime).TotalDays); Write-Output $age"'
    ) do set "TEST_WEEKLY_AGE=%%I"

    if not defined TEST_WEEKLY_AGE (
        set "TEST_WEEKLY_STATUS=DUE - marker age could not be determined"
        set /a TEST_ISSUES+=1
        call :Log "Weekly schedule: WARNING - marker exists but its age could not be determined."
    ) else (
        if !TEST_WEEKLY_AGE! GEQ %WEEKLY_DAYS% (
            set "TEST_WEEKLY_STATUS=DUE - last success !TEST_WEEKLY_AGE! days ago"
            call :Log "Weekly schedule: DUE - last success !TEST_WEEKLY_AGE! days ago."
        ) else (
            set "TEST_WEEKLY_STATUS=NOT DUE - last success !TEST_WEEKLY_AGE! days ago"
            call :Log "Weekly schedule: NOT DUE - last success !TEST_WEEKLY_AGE! days ago."
        )
    )
)

set "D_DOCS_RESULT=NOT RUN - SELF TEST"
set "D_PICS_RESULT=NOT RUN - SELF TEST"
set "D_RESULT=NOT RUN - SELF TEST"
set "E_DOCS_RESULT=NOT RUN - SELF TEST"
set "E_PICS_RESULT=NOT RUN - SELF TEST"
set "E_RESULT=NOT RUN - SELF TEST"
set "ICLOUD_DOCS_RESULT=NOT RUN - SELF TEST"
set "ICLOUD_PICS_RESULT=NOT RUN - SELF TEST"
set "ICLOUD_RESULT=NOT RUN - SELF TEST"
set "WEEKLY_RESULT=!TEST_WEEKLY_STATUS!"

if !TEST_ISSUES! EQU 0 (
    call :Log "Self test: PASS."
) else (
    call :Log "Self test: FAIL - !TEST_ISSUES! required check or warning condition detected."
    if !FINALCODE! EQU 0 set "FINALCODE=50"
)
exit /b 0


:TestPath
set "TEST_PATH=%~1"
set "TEST_LABEL=%~2"
set "TEST_REQUIRED=%~3"
if exist "%TEST_PATH%" (
    call :Log "PASS: %TEST_LABEL% - %TEST_PATH%"
) else if "%TEST_REQUIRED%"=="1" (
    call :Log "FAIL: %TEST_LABEL% not found - %TEST_PATH%"
    set /a TEST_ISSUES+=1
) else (
    call :Log "WARNING: %TEST_LABEL% not found - %TEST_PATH%"
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
REM
REM Usage:
REM   call :RunMirror "source" "destination" "display name"
REM
REM Robocopy copy codes 0-7 are nonfatal; 8 or higher is failure.
REM Verification requires code 0; any nonzero code means differences
REM or a verification error.
REM
REM Returns:
REM   JOB_RC=0   Copy and verification succeeded
REM   JOB_RC=1   Copy or verification failed
REM   JOB_RESULT contains a readable status
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

if not exist "%JOB_DEST%\" (
    mkdir "%JOB_DEST%" >>"%LOGFILE%" 2>&1
)

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
REM RUN AND VERIFY AN ICLOUD RETAINED-COPY JOB
REM
REM Uses /E instead of /MIR. Destination-only files are retained.
REM ============================================================

:RunCloudCopy
set "JOB_SOURCE=%~1"
set "JOB_DEST=%~2"
set "JOB_NAME=%~3"
set "JOB_RC=1"
set "JOB_RESULT=FAILED"

call :BlankLine
call :Log "---- %JOB_NAME% retained copy ----"
call :Log "Source: %JOB_SOURCE%"
call :Log "Destination: %JOB_DEST%"

if not exist "%JOB_DEST%\" (
    mkdir "%JOB_DEST%" >>"%LOGFILE%" 2>&1
)

if not exist "%JOB_DEST%\" (
    set "JOB_RESULT=FAILED - destination could not be created"
    call :Log "ERROR: Destination could not be created."
    exit /b 0
)

robocopy "%JOB_SOURCE%" "%JOB_DEST%" ^
    /E ^
    /Z ^
    /R:10 ^
    /W:10 ^
    /COPY:DAT ^
    /DCOPY:DAT ^
    /FFT ^
    /XJ ^
    /XA:SH ^
    /XD "$RECYCLE.BIN" "System Volume Information" ^
    /LOG+:"%LOGFILE%" ^
    /NP

set "COPY_RC=!ERRORLEVEL!"

if !COPY_RC! GEQ 8 (
    set "JOB_RESULT=FAILED - Robocopy code !COPY_RC!"
    call :Log "ERROR: %JOB_NAME% failed with Robocopy exit code !COPY_RC!."
    exit /b 0
)

call :Log "%JOB_NAME% completed with Robocopy exit code !COPY_RC!."

call :VerifyCloudCopy "%JOB_SOURCE%" "%JOB_DEST%" "%JOB_NAME%"
set "VERIFY_JOB_RC=!VERIFY_RC!"

if !VERIFY_JOB_RC! EQU 0 (
    set "JOB_RC=0"
    set "JOB_RESULT=SUCCESS - LOCAL COPY VERIFIED"
    call :Log "%JOB_NAME% verification: PASS."
) else if !VERIFY_JOB_RC! GEQ 8 (
    set "JOB_RESULT=COPY COMPLETED - VERIFICATION ERROR !VERIFY_JOB_RC!"
    call :Log "ERROR: %JOB_NAME% verification could not complete. Robocopy code !VERIFY_JOB_RC!."
) else (
    set "JOB_RESULT=COPY COMPLETED - VERIFICATION FAILED"
    call :Log "ERROR: %JOB_NAME% verification found source items still needing copy."
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

set "VERIFY_RC=!ERRORLEVEL!"
call :Log "%VERIFY_NAME% verification Robocopy exit code: !VERIFY_RC!."

if exist "%VERIFY_REPORT%" (
    type "%VERIFY_REPORT%">>"%LOGFILE%"
    del /q "%VERIFY_REPORT%" >nul 2>&1
)

exit /b 0


REM ============================================================
REM VERIFY AN ICLOUD RETAINED COPY
REM
REM /XX ignores destination-only files, which are intentionally
REM retained. /XO /XN /XC ignore iCloud-managed timestamp, size,
REM and metadata differences for items that already exist locally.
REM A source item that is completely missing from the local iCloud
REM folder remains a Robocopy copy candidate and causes verification
REM to return a nonzero code.
REM ============================================================

:VerifyCloudCopy
set "VERIFY_SOURCE=%~1"
set "VERIFY_DEST=%~2"
set "VERIFY_NAME=%~3"
set "VERIFY_REPORT=%TEMP%\PDriveCloudVerify_%STAMP%_%RANDOM%.log"

call :BlankLine
call :Log "---- Verifying %VERIFY_NAME% ----"

robocopy "%VERIFY_SOURCE%" "%VERIFY_DEST%" ^
    /E ^
    /L ^
    /XX ^
    /XO ^
    /XN ^
    /XC ^
    /R:0 ^
    /W:0 ^
    /COPY:DAT ^
    /DCOPY:DAT ^
    /FFT ^
    /XJ ^
    /XA:SH ^
    /XD "$RECYCLE.BIN" "System Volume Information" ^
    /NFL ^
    /NDL ^
    /NJH ^
    /NP ^
    /LOG:"%VERIFY_REPORT%"

set "VERIFY_RC=!ERRORLEVEL!"
call :Log "%VERIFY_NAME% verification Robocopy exit code: !VERIFY_RC!."

if exist "%VERIFY_REPORT%" (
    type "%VERIFY_REPORT%">>"%LOGFILE%"
    del /q "%VERIFY_REPORT%" >nul 2>&1
)

exit /b 0


REM ============================================================
REM CONVERT A VERIFICATION EXIT CODE TO A RESULT STRING
REM
REM Usage:
REM   call :SetVerifyResult exitCode "success text" outputVariable
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
    echo.>>"%LOGFILE%"
) else (
    echo %~1
    echo %~1>>"%LOGFILE%"
)
exit /b 0

:BlankLine
echo.
echo.>>"%LOGFILE%"
exit /b 0


:ScriptEnd
endlocal & exit /b %SCRIPT_EXIT_CODE%

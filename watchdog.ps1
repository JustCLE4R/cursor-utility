<#
.SYNOPSIS
    Watchdog for Cursor Utility: starts it, and restarts it if it crashes or stops responding.
    run.vbs starts this. Exiting Cursor Utility from its tray icon stops the watchdog too.

.DESCRIPTION
    - Crash: Cursor Utility exits with a non-zero code. Restarted after a pause.
    - Hang: its heartbeat file hasn't changed for [watchdog] hang_seconds. Stopped and restarted.
    - Normal exit (code 0: Exit from the tray, disabled in config, already running): the watchdog stops.
    - Too many restarts within 10 minutes ([watchdog] max_restarts): it gives up, logs why and shows a notice.
    With [watchdog] enabled=false, it starts Cursor Utility once and stops watching.
    Its own log is logs\watchdog.log, so the two processes never write to the same file.

.PARAMETER Config
    Passed on to cursor-utility.ps1. Default: config.ini next to this script.

.PARAMETER DryRun
    Passed on to cursor-utility.ps1.

.PARAMETER RunOnce
    Passed on to cursor-utility.ps1. One cycle is run and never restarted.

.PARAMETER Overlay
    Passed on to cursor-utility.ps1.
#>
param(
    [Alias("Config")]
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$RunOnce,
    [switch]$Overlay
)

$ErrorActionPreference = "Stop"

$BaseDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir     = Join-Path $BaseDir "modules"
$AppScript     = Join-Path $BaseDir "cursor-utility.ps1"
$LogDir        = Join-Path $BaseDir "logs"
$LogFile       = Join-Path $LogDir "watchdog.log"
$LogMaxBytes   = 1MB
$HeartbeatFile = Join-Path $LogDir "heartbeat.txt"
# The app runs hidden, so its error output would otherwise be lost; copied into the log on a crash
$AppErrorFile  = Join-Path $LogDir "app-errors.txt"

# Restarts are counted over this window for max_restarts
$RestartWindowMinutes = 10
# How often the app is checked
$CheckSeconds = 5

if ($ConfigPath) {
    $ConfigFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
}
else {
    $ConfigFile = Join-Path $BaseDir "config.ini"
}

. (Join-Path $ModuleDir "Log.ps1")
. (Join-Path $ModuleDir "Config.ps1")

# Defaults until the config has been read
$LogEnabled      = $true
$WatchdogEnabled = $true
$HangSeconds     = 180
$MaxRestarts     = 5

# ============================================================
# Helpers
# ============================================================

# Re-read before every start, so config changes apply to the next restart.
# If the config can't be read, the previous values are kept.
function Import-WatchdogSettings {

    try {
        if (-not (Test-Path -LiteralPath $ConfigFile)) {
            # Same default the app would create on its first start
            New-DefaultConfig $ConfigFile
        }

        Import-Settings $ConfigFile
    }
    catch {
        Write-Log "Watchdog: couldn't read $ConfigFile ($($_.Exception.Message)). Using the previous settings."
    }
}

# Arguments for cursor-utility.ps1. Start-Process doesn't quote array items
# in PowerShell 5.1, so paths are quoted here.
function Get-AppArguments {

    $arguments = @(
        "-NoProfile", "-STA", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
        "-File", "`"$AppScript`"",
        "-Config", "`"$ConfigFile`"",
        "-HeartbeatFile", "`"$HeartbeatFile`""
    )

    if ($DryRun)  { $arguments += "-DryRun" }
    if ($RunOnce) { $arguments += "-RunOnce" }
    if ($Overlay) { $arguments += "-Overlay" }

    return $arguments
}

# Seconds since the app last showed a sign of life (heartbeat or start)
function Get-SilentSeconds {
    param(
        [datetime]$Started
    )

    $last = $Started

    if (Test-Path -LiteralPath $HeartbeatFile) {
        $beat = (Get-Item -LiteralPath $HeartbeatFile).LastWriteTime
        if ($beat -gt $last) {
            $last = $beat
        }
    }

    return ((Get-Date) - $last).TotalSeconds
}

# Copies what the app wrote to its error output into the log, so a crash shows its reason
function Write-AppErrors {

    if (-not (Test-Path -LiteralPath $AppErrorFile)) {
        return
    }

    $lines = @(Get-Content -LiteralPath $AppErrorFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })

    if ($lines.Count -eq 0) {
        Write-Log "Watchdog: (Cursor Utility wrote no error output)"
        return
    }

    Write-Log "Watchdog: Cursor Utility's error output:"
    foreach ($line in ($lines | Select-Object -First 15)) {
        Write-Log "    $line"
    }
}

function Show-GiveUpNotice {

    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing

        $notice = New-Object System.Windows.Forms.NotifyIcon
        $notice.Icon = [System.Drawing.SystemIcons]::Error
        $notice.Visible = $true
        $notice.ShowBalloonTip(10000, "Cursor Utility stopped",
            "It kept crashing, so the watchdog stopped restarting it. See logs\watchdog.log.",
            [System.Windows.Forms.ToolTipIcon]::Error)

        # Keep the balloon up for a while; it needs messages processed to show
        for ($i = 0; $i -lt 500; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 20
        }

        $notice.Visible = $false
        $notice.Dispose()
    }
    catch {
        # The log already says why; the notice is a bonus
    }
}

# ============================================================
# Start
# ============================================================

Import-WatchdogSettings

# One watchdog at a time. Like the app, a dry run or -RunOnce may run next to one.
$WatchdogMutex = New-Object System.Threading.Mutex($false, "Local\CursorUtility-Watchdog")
$HasMutex = $false

try {
    $HasMutex = $WatchdogMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    # The previous watchdog was killed without releasing it; it's ours now
    $HasMutex = $true
}

if (-not $HasMutex -and -not $DryRun -and -not $RunOnce) {
    Write-Log "Watchdog: another watchdog is already running. Exiting."
    exit 0
}

Write-Log "========================================"
Write-Log "Watchdog started (pid $PID). Restarts on crash, or after $HangSeconds s without a heartbeat; gives up after $MaxRestarts restarts in $RestartWindowMinutes min."

$restarts = New-Object System.Collections.ArrayList
$ExitCode = 0

try {
    while ($true) {

        Import-WatchdogSettings

        Remove-Item -LiteralPath $HeartbeatFile -ErrorAction SilentlyContinue

        $app = Start-Process powershell.exe -ArgumentList (Get-AppArguments) -WindowStyle Hidden -PassThru -RedirectStandardError $AppErrorFile
        # Without touching Handle now, ExitCode can come back empty later (PowerShell 5.1)
        $null = $app.Handle
        $started = Get-Date

        Write-Log "Watchdog: started Cursor Utility (pid $($app.Id))."

        if ($RunOnce) {
            Write-Log "Watchdog: single cycle (-RunOnce), so not restarting it. Watchdog stopping."
            break
        }

        if (-not $WatchdogEnabled) {
            Write-Log "Watchdog: disabled in config ([watchdog] enabled=false), so not watching it. Watchdog stopping."
            break
        }

        # Watch until it exits or goes quiet
        $reason = $null

        while (-not $app.HasExited) {

            Start-Sleep -Seconds $CheckSeconds

            if ($app.HasExited) {
                break
            }

            $silent = Get-SilentSeconds $started

            if ($silent -gt $HangSeconds) {
                $reason = "stopped responding (no heartbeat for $([int]$silent) s)"
                Write-Log "Watchdog: Cursor Utility $reason. Stopping pid $($app.Id)."
                Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
                $app.WaitForExit(10000) | Out-Null
                break
            }
        }

        if (-not $reason) {
            $code = $app.ExitCode

            if ($code -eq 0) {
                Write-Log "Watchdog: Cursor Utility exited normally. Watchdog stopping."
                break
            }

            $reason = "exited with code $code"
            Write-AppErrors
        }

        # Count restarts in the last 10 minutes
        $now = Get-Date
        [void]$restarts.Add($now)

        foreach ($old in @($restarts | Where-Object { ($now - $_).TotalMinutes -gt $RestartWindowMinutes })) {
            $restarts.Remove($old)
        }

        if ($restarts.Count -gt $MaxRestarts) {
            Write-Log "Watchdog: Cursor Utility $reason, and has needed $($restarts.Count - 1) restarts in $RestartWindowMinutes min. Giving up; fix the cause and start it again."
            $ExitCode = 1
            Show-GiveUpNotice
            break
        }

        # 5 s, 10 s, 20 s, 40 s, then 60 s: don't hammer a start that keeps failing
        $delay = [int][Math]::Min(60, 5 * [Math]::Pow(2, $restarts.Count - 1))

        Write-Log "Watchdog: Cursor Utility $reason. Restarting in $delay s (restart $($restarts.Count) of $MaxRestarts allowed in $RestartWindowMinutes min)."
        Start-Sleep -Seconds $delay
    }
}
finally {
    Remove-Item -LiteralPath $HeartbeatFile -ErrorAction SilentlyContinue

    if ($HasMutex) {
        $WatchdogMutex.ReleaseMutex()
    }
    $WatchdogMutex.Dispose()
}

exit $ExitCode

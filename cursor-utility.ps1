<#
.SYNOPSIS
    Cursor Utility: clicks the screen corners while you are idle, controlled from a tray icon.

.PARAMETER Config
    Path to the config file. Default: config.ini next to this script.
    A commented default config is created if the file does not exist.

.PARAMETER DryRun
    Log what would happen without moving the cursor or clicking.
    Same as [debug] dry_run=true.

.PARAMETER RunOnce
    Run one cycle immediately, ignoring the schedule and idle time, then exit.

.PARAMETER Overlay
    Show red markers where each click will land. Same as [debug] overlay=true.

.EXAMPLE
    .\cursor-utility.ps1 -RunOnce -DryRun -Overlay
#>
param(
    [Alias("Config")]
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$RunOnce,
    [switch]$Overlay
)

$ErrorActionPreference = "Stop"

$BaseDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir   = Join-Path $BaseDir "modules"
$LogDir      = Join-Path $BaseDir "logs"
$LogFile     = Join-Path $LogDir "cursor-utility.log"
$LogMaxBytes = 1MB

if ($ConfigPath) {
    $ConfigFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
}
else {
    $ConfigFile = Join-Path $BaseDir "config.ini"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $ModuleDir "Log.ps1")
. (Join-Path $ModuleDir "Config.ps1")
. (Join-Path $ModuleDir "Random.ps1")
. (Join-Path $ModuleDir "Schedule.ps1")
. (Join-Path $ModuleDir "Input.ps1")
. (Join-Path $ModuleDir "Tray.ps1")
. (Join-Path $ModuleDir "Overlay.ps1")
. (Join-Path $ModuleDir "Actions.ps1")

# ============================================================
# Startup
# ============================================================

$ConfigCreated = $false

if (-not (Test-Path -LiteralPath $ConfigFile)) {
    New-DefaultConfig $ConfigFile
    $ConfigCreated = $true
}

Import-Settings $ConfigFile

if (-not $Enabled) {
    Write-Host "Cursor Utility is disabled in $ConfigFile."
    exit 0
}

Initialize-Tray
Update-Tray "starting"

Write-Log "========================================"
Write-Log "Cursor Utility started"
if ($ConfigCreated) {
    Write-Log "Config not found. Created a default one: $ConfigFile"
}
if ($ConfigPath) {
    Write-Log "Config: $ConfigFile"
}
if ($IsDryRun) {
    Write-Log "Mode: dry run (no cursor movement or clicks)"
}
Write-Log "Interval: $MinInterval-$MaxInterval seconds"
Write-Log "Idle before start: $IdleSeconds seconds"
Write-Log "Corner delay: $CornerDelayMin-$CornerDelayMax ms"
Write-Log "========================================"

# ============================================================
# Main loop
# ============================================================

$script:NextRunAt = $null
$state = ""

function Set-State {
    param(
        [string]$NewState,
        [string]$LogMessage
    )

    # Log only on state change to keep the log small
    if ($script:state -ne $NewState) {
        $script:state = $NewState
        Write-Log $LogMessage
    }
}

try {
    if ($RunOnce) {
        Write-Log "Run once: one cycle now, ignoring schedule and idle time."
        Update-Tray "clicking"
        Invoke-CornerClicks
    }

    while (-not $RunOnce -and -not $ExitRequested) {

        try {

            Wait-Responsive 1000

            Import-Settings $ConfigFile
            Update-UserActivity

            if (-not $Enabled) {
                Write-Log "Disabled in config.ini. Exiting."
                break
            }

            if ($Paused) {
                Set-State "paused" "Paused."
                Update-Tray
                continue
            }

            if (-not (Test-ScheduleActive $Ini)) {
                Set-State "schedule" "Outside active schedule."
                $script:NextRunAt = $null
                Update-Tray "outside schedule"
                continue
            }

            $idle = Get-UserIdleSeconds

            if ($idle -lt $IdleSeconds) {
                Set-State "user" "User active. Waiting for $IdleSeconds seconds of idle."
                $script:NextRunAt = $null
                Update-Tray "you are active (idle ${idle}s/${IdleSeconds}s)"
                continue
            }

            if ($null -eq $NextRunAt) {
                $delay = Get-NaturalRandom $MinInterval $MaxInterval
                $script:NextRunAt = (Get-Date).AddSeconds($delay)
                Set-State "idle" "User idle. Running."
                Write-Log "Next cycle in $delay seconds."
            }

            $remaining = [int]($NextRunAt - (Get-Date)).TotalSeconds

            if ($remaining -gt 0) {
                Update-Tray "next click in ${remaining}s"
                continue
            }

            Update-Tray "clicking"
            Invoke-CornerClicks
            $script:NextRunAt = $null
        }
        catch {

            Write-Log "ERROR: $($_.Exception.Message)"

            Wait-Responsive 30000
        }
    }
}
finally {
    Write-Log "Cursor Utility stopped."
    Remove-Tray
}

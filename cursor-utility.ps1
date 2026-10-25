<#
.SYNOPSIS
    Cursor Utility: keeps the session active while you are idle, controlled from a tray icon.
    Clicks the screen corners, or runs your own steps from an actions file.

.PARAMETER Config
    Path to the config file. Default: config.ini next to this script.
    A commented default config is created if the file does not exist.

.PARAMETER DryRun
    Log what would happen without moving the cursor, clicking, pressing keys
    or switching windows. Same as [debug] dry_run=true.

.PARAMETER RunOnce
    Run one cycle immediately, ignoring the schedule, idle time and breaks, then exit.

.PARAMETER Overlay
    Show red markers where each click will land. Same as [debug] overlay=true.

.PARAMETER HeartbeatFile
    Set by watchdog.ps1: a file that gets the current time every 10 s or so,
    so the watchdog can tell the script is still responding.

.PARAMETER StartedAt
    Set by watchdog.ps1: when it first started the script (yyyy-MM-ddTHH:mm:ss),
    so a restart keeps the shift it started in for [general] stop_after_shift. Default: now.

.EXAMPLE
    .\cursor-utility.ps1 -RunOnce -DryRun -Overlay
#>
param(
    [Alias("Config")]
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$RunOnce,
    [switch]$Overlay,
    [string]$HeartbeatFile,
    [string]$StartedAt
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
. (Join-Path $ModuleDir "ActionScript.ps1")
. (Join-Path $ModuleDir "Input.ps1")
. (Join-Path $ModuleDir "Tray.ps1")
. (Join-Path $ModuleDir "Overlay.ps1")
. (Join-Path $ModuleDir "Browser.ps1")
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

# Single instance: two copies would fight over the mouse. A dry run or
# -RunOnce may still start next to a running copy, for testing.
$InstanceMutex = New-Object System.Threading.Mutex($false, "Local\CursorUtility")
$HasMutex = $false

try {
    $HasMutex = $InstanceMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    # The previous copy crashed without releasing it; it's ours now
    $HasMutex = $true
}

if (-not $HasMutex -and -not $RunOnce -and -not $IsDryRun) {
    Write-Log "Another copy is already running. Exiting."
    Show-AlreadyRunningNotice
    exit 0
}

# Shared state shown in the tray (see docs/architecture.md)
$script:NextRunAt    = $null
$script:NextRunTotal = 0
$script:BreakUntil   = $null
$script:BreakTotal   = 0
$script:ShiftText    = ""
$script:ActionsText  = ""
$script:LastDisplay  = Get-DisplaySignature
$script:ExitCode     = 0
$script:Stats        = @{ Day = (Get-Date).Date; Done = 0; Cancelled = 0; LastTime = $null; LastResult = "" }

# stop_after_shift uses the shift of this time. Under the watchdog it's the first start, so a restart keeps it.
$script:StartTime = Get-Date
$parsedStart = [datetime]::MinValue

if ($StartedAt -and [datetime]::TryParseExact($StartedAt, "s", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedStart)) {
    $script:StartTime = $parsedStart
}

# ============================================================
# Helpers
# ============================================================

function Get-ActionsDescription {

    if ($ActionsPath) {
        $name = Split-Path -Leaf $ActionsPath
        if ($ActionError) {
            return "$name has an error"
        }
        return "$name ($(@($ActionSteps).Count) steps)"
    }

    return "corners, $($ClickOrder -replace '_', ' ')"
}

function Get-BreakDescription {

    if (-not $BreakEnabled) {
        return "off"
    }

    return "$BreakChance% chance after each cycle, $BreakMinMinutes-$BreakMaxMinutes minutes"
}

# The steps for the next cycle: the actions file, or the corner clicks.
# Emits the steps one by one; call it as @(Get-CycleSteps).
function Get-CycleSteps {

    if ($ActionsPath) {
        return $ActionSteps
    }

    $order = $ClickOrder

    if ($order -eq "random") {
        $order = if ($Random.Next(2) -eq 0) { "bottom_first" } else { "top_first" }
    }

    $steps = Get-CornerSteps $order $CornerDelayMin $CornerDelayMax
    return $steps
}

function Update-Stats {
    param(
        [string]$Result
    )

    $today = (Get-Date).Date

    if ($Stats.Day -ne $today) {
        $script:Stats = @{ Day = $today; Done = 0; Cancelled = 0; LastTime = $null; LastResult = "" }
    }

    if ($Result -eq "done") {
        $Stats.Done++
    }
    else {
        $Stats.Cancelled++
    }

    $Stats.LastTime = Get-Date
    $Stats.LastResult = $Result
}

# Now and then, after a finished cycle, start a longer break
function Start-BreakMaybe {

    if (-not $BreakEnabled -or $BreakChance -le 0) {
        return
    }

    if ($Random.NextDouble() * 100 -ge $BreakChance) {
        return
    }

    $minutes = Get-NaturalRandom $BreakMinMinutes $BreakMaxMinutes
    $script:BreakUntil = (Get-Date).AddMinutes($minutes)
    $script:BreakTotal = $minutes * 60

    $unit = if ($minutes -eq 1) { "minute" } else { "minutes" }
    Write-Log "Taking a break for $minutes $unit (until $($BreakUntil.ToString('HH:mm')))."
}

function Invoke-Cycle {

    $steps = @(Get-CycleSteps)

    Update-Tray "clicking" "Running a cycle ($($steps.Count) steps)"
    Invoke-ActionCycle $steps
    Update-Stats $LastCycleResult
}

# Logs resolution, layout and monitor changes. Coordinates are worked out
# again at the start of every cycle, so nothing else needs to change.
function Update-Display {

    $display = Get-DisplaySignature

    if ($display -ne $LastDisplay) {
        Write-Log "Display changed: $LastDisplay -> $display"
        $script:LastDisplay = $display
    }
}

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

# ============================================================
# Start
# ============================================================

Write-Log "========================================"
Write-Log "Cursor Utility started"
if ($ConfigCreated) {
    Write-Log "Config not found. Created a default one: $ConfigFile"
}
if ($ConfigPath) {
    Write-Log "Config: $ConfigFile"
}
if ($IsDryRun) {
    Write-Log "Mode: dry run (no cursor movement, clicks, keys or window switching)"
}
if (-not $HasMutex) {
    Write-Log "Another copy is running; continuing because this is a dry run or a single cycle."
}

Sync-ActionScript
$script:ActionsText = "Actions: $(Get-ActionsDescription)"

Initialize-Tray
Update-Tray "starting" "Starting"

Write-Log "Interval: $MinInterval-$MaxInterval seconds"
Write-Log "Idle before start: $IdleSeconds seconds"
Write-Log "Actions: $(Get-ActionsDescription)"
if (-not $ActionsPath) {
    Write-Log "Corner delay: $CornerDelayMin-$CornerDelayMax ms"
}
Write-Log "Breaks: $(Get-BreakDescription)"
if ($StopAfterShift) {
    $startShift = Get-ShiftWindow $Ini $StartTime
    if ($startShift) {
        Write-Log "Stops at $($startShift.End.AddMinutes($StopExtraMinutes).ToString('yyyy-MM-dd HH:mm')): shift $($startShift.Name) ends $($startShift.End.ToString('HH:mm')), plus $StopExtraMinutes min"
    }
    else {
        Write-Log "Stop after shift: no shift is enabled, so no stop time."
    }
}
Write-Log "Display: $LastDisplay"
Write-Log "========================================"

# ============================================================
# Main loop
# ============================================================

try {
    if ($RunOnce) {
        if ($ActionsPath -and $ActionError) {
            Write-Log "Run once: not running, the actions file has an error."
            $script:ExitCode = 1
        }
        else {
            Write-Log "Run once: one cycle now, ignoring schedule, idle time and breaks."
            Invoke-Cycle
            Write-Log "Run once: $LastCycleResult"
        }
    }

    while (-not $RunOnce -and -not $ExitRequested) {

        try {

            Wait-Responsive 1000

            Import-Settings $ConfigFile
            Sync-ActionScript
            Update-UserActivity
            Update-Display

            $shift = Get-ActiveShift $Ini
            $stopAt = $null
            if ($StopAfterShift) {
                $stopAt = Get-StopTime $Ini $StartTime $StopExtraMinutes
            }

            if ($shift) {
                $script:ShiftText = "Shift: $($shift.Name), $($shift.Start)-$($shift.End)"
            }
            else {
                $script:ShiftText = "Shift: none active now"
            }

            if ($stopAt) {
                $script:ShiftText += ", stops at $($stopAt.ToString('HH:mm'))"
            }

            $script:ActionsText = "Actions: $(Get-ActionsDescription)"

            if (-not $Enabled) {
                Write-Log "Disabled in $(Split-Path -Leaf $ConfigFile). Exiting."
                break
            }

            # A normal exit (code 0), so the watchdog stops too
            if ($stopAt -and (Get-Date) -ge $stopAt) {
                Write-Log "Shift over plus $StopExtraMinutes min (stop_after_shift). Exiting."
                break
            }

            if ($Paused) {
                Set-State "paused" "Paused."
                Update-Tray "paused" "Off. Click the icon to turn on."
                continue
            }

            if ($ActionsPath -and $ActionError) {
                Set-State "actions" "Waiting for the actions file to be fixed."
                $script:NextRunAt = $null
                Update-Tray "error" "Actions file error: $ActionError"
                continue
            }

            if (-not $shift) {
                Set-State "schedule" "Outside active schedule."
                $script:NextRunAt = $null
                Update-Tray "schedule" "Outside schedule"
                continue
            }

            if ($BreakUntil) {

                $left = ($BreakUntil - (Get-Date)).TotalSeconds

                if ($left -gt 0) {
                    Set-State "break" "On a break."
                    $script:NextRunAt = $null
                    $progress = 1 - ($left / [Math]::Max(1, $BreakTotal))
                    Update-Tray "break" "On a break, back in $(Format-Duration $left)" $progress "Break ends at $($BreakUntil.ToString('HH:mm'))"
                    continue
                }

                $script:BreakUntil = $null
                Write-Log "Break over."
            }

            $idle = Get-UserIdleSeconds

            if ($idle -lt $IdleSeconds) {
                Set-State "user" "User active. Waiting for $IdleSeconds seconds of idle."
                $script:NextRunAt = $null
                $progress = $idle / [Math]::Max(1, $IdleSeconds)
                Update-Tray "user" "You are active (idle $(Format-Duration $idle) of $(Format-Duration $IdleSeconds))" $progress
                continue
            }

            if ($null -eq $NextRunAt) {
                $delay = Get-NaturalRandom $MinInterval $MaxInterval
                $script:NextRunAt = (Get-Date).AddSeconds($delay)
                $script:NextRunTotal = $delay
                Set-State "idle" "User idle. Running."
                Write-Log "Next cycle in $delay seconds."
            }

            $remaining = ($NextRunAt - (Get-Date)).TotalSeconds

            if ($remaining -gt 0) {
                $progress = 1 - ($remaining / [Math]::Max(1, $NextRunTotal))
                Update-Tray "idle" "Next cycle in $(Format-Duration $remaining)" $progress "Next cycle at $($NextRunAt.ToString('HH:mm:ss'))"
                continue
            }

            Invoke-Cycle
            $script:NextRunAt = $null

            if ($LastCycleResult -eq "done") {
                Start-BreakMaybe
            }
        }
        catch {

            Write-Log "ERROR: $($_.Exception.Message)"

            Update-Tray "error" "Error, retrying in 30s: $($_.Exception.Message)"
            Wait-Responsive 30000
        }
    }
}
finally {
    Write-Log "Cursor Utility stopped."
    Remove-Tray

    if ($HasMutex) {
        $InstanceMutex.ReleaseMutex()
    }
    $InstanceMutex.Dispose()
}

exit $ExitCode

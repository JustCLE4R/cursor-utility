# ============================================================
# INI reader
# ============================================================

function Read-Ini {
    param(
        [string]$Path
    )

    $ini = @{}
    $section = ""

    foreach ($line in Get-Content -LiteralPath $Path) {

        $line = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.StartsWith("#") -or $line.StartsWith(";")) {
            continue
        }

        if ($line -match '^\[(.+)\]$') {
            $section = $matches[1].Trim()
            continue
        }

        if ($line -match '^([^=]+)=(.*)$') {

            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            $ini["$section.$key"] = $value
        }
    }

    return $ini
}

function Get-IniValue {
    param(
        [hashtable]$Ini,
        [string]$Key,
        [string]$Default
    )

    if ($Ini.ContainsKey($Key)) {
        return $Ini[$Key]
    }

    return $Default
}

function Get-IniBool {
    param(
        [hashtable]$Ini,
        [string]$Key,
        [bool]$Default
    )

    $value = Get-IniValue $Ini $Key $Default.ToString()

    return (@("true", "yes", "1", "on") -contains $value.ToLower())
}

function Get-IniInt {
    param(
        [hashtable]$Ini,
        [string]$Key,
        [int]$Default
    )

    $value = Get-IniValue $Ini $Key $Default.ToString()

    $number = 0

    if ([int]::TryParse($value, [ref]$number)) {
        return $number
    }

    return $Default
}

# ============================================================
# Default config (written when the config file is missing)
# ============================================================

$DefaultConfigText = @"
[general]
enabled=true
log_enabled=true

[activity]
# Seconds between each corner-click cycle
min_interval_seconds=15
max_interval_seconds=60
# Only run after you have not touched mouse/keyboard for this long
idle_seconds=120
# Move cursor back to where it was after clicking
return_after_move=true
# Glide along a curved path instead of jumping instantly
smooth_move=true

[click]
# Pause between the first and the second corner click
corner_delay_min_ms=700
corner_delay_max_ms=2200
# Which corner to click first: top_first, bottom_first or random (picked each cycle)
order=bottom_first

[actions]
# Your own steps instead of the corner clicks above, e.g. file=actions.txt
# (relative to this config file). Leave empty for the corner clicks.
# See actions.txt for the commands: move, click, key, scroll, wait, focus.
file=
# After a "focus" step, switch back to the window (and tab) you had in front
restore_focus=false
# Programs searched by "focus tab NAME" (process names, comma-separated)
browsers=msedge, chrome, brave, opera, firefox, vivaldi

[break]
# Now and then take a longer break, like a person getting coffee
enabled=true
# Chance of a break after each cycle, in percent (0-100)
chance_percent=1
# Break length in minutes
min_minutes=5
max_minutes=20

[watchdog]
# Restart Cursor Utility if it crashes or stops responding (when started with run.bat)
enabled=true
# Restart it if it hasn't checked in for this many seconds (minimum 30)
hang_seconds=180
# Give up after this many restarts within 10 minutes
max_restarts=5

[schedule]
# Note: these three shifts overlap and cover all 24 hours.
# Disable a shift or narrow the times to pause outside work hours.
subuh_enabled=true
subuh_start=00:00
subuh_end=08:30

pagi_enabled=true
pagi_start=08:00
pagi_end=16:30

malam_enabled=true
malam_start=16:00
malam_end=00:30

[debug]
# Log what would happen without moving the cursor or clicking
dry_run=false
# Show red markers where each click will land
overlay=false
"@

function New-DefaultConfig {
    param(
        [string]$Path
    )

    $dir = Split-Path -Parent $Path

    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $DefaultConfigText -Encoding UTF8
}

$DefaultBrowsers = "msedge, chrome, brave, opera, firefox, vivaldi"

# "msedge, Chrome.exe  firefox" -> @("msedge", "chrome", "firefox").
# Empty falls back to the default list, so "focus tab" always has somewhere to look.
function ConvertTo-ProcessList {
    param(
        [string]$Text
    )

    $names = @($Text -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { ($_.ToLower()) -replace '\.exe$', '' })

    if ($names.Count -eq 0) {
        return ConvertTo-ProcessList $DefaultBrowsers
    }

    return $names
}

# ============================================================
# Settings (reloaded every cycle, so config edits apply live)
# ============================================================

# -DryRun and -Overlay from the command line force these on;
# otherwise the [debug] section decides.
function Import-Settings {
    param(
        [string]$Path
    )

    $script:Ini = Read-Ini $Path

    $script:Enabled         = Get-IniBool $Ini "general.enabled" $true
    $script:LogEnabled      = Get-IniBool $Ini "general.log_enabled" $true

    $script:MinInterval     = Get-IniInt  $Ini "activity.min_interval_seconds" 60
    $script:MaxInterval     = Get-IniInt  $Ini "activity.max_interval_seconds" 120
    $script:IdleSeconds     = Get-IniInt  $Ini "activity.idle_seconds" 120
    $script:ReturnAfterMove = Get-IniBool $Ini "activity.return_after_move" $true
    $script:SmoothMove      = Get-IniBool $Ini "activity.smooth_move" $true

    $script:CornerDelayMin  = Get-IniInt  $Ini "click.corner_delay_min_ms" 700
    $script:CornerDelayMax  = Get-IniInt  $Ini "click.corner_delay_max_ms" 2200
    $script:ClickOrder      = (Get-IniValue $Ini "click.order" "top_first").ToLower()

    $script:ActionsFile     = Get-IniValue $Ini "actions.file" ""
    $script:RestoreFocus    = Get-IniBool  $Ini "actions.restore_focus" $true
    $script:Browsers        = ConvertTo-ProcessList (Get-IniValue $Ini "actions.browsers" $DefaultBrowsers)

    $script:BreakEnabled    = Get-IniBool  $Ini "break.enabled" $false
    $script:BreakChance     = Get-IniInt   $Ini "break.chance_percent" 5
    $script:BreakMinMinutes = Get-IniInt   $Ini "break.min_minutes" 5
    $script:BreakMaxMinutes = Get-IniInt   $Ini "break.max_minutes" 20

    $script:WatchdogEnabled = Get-IniBool  $Ini "watchdog.enabled" $true
    $script:HangSeconds     = Get-IniInt   $Ini "watchdog.hang_seconds" 180
    $script:MaxRestarts     = Get-IniInt   $Ini "watchdog.max_restarts" 5

    $script:IsDryRun        = [bool]$DryRun -or (Get-IniBool $Ini "debug.dry_run" $false)
    $script:ShowOverlay     = [bool]$Overlay -or (Get-IniBool $Ini "debug.overlay" $false)

    # Validation

    if ($MinInterval -lt 1) { $script:MinInterval = 1 }
    if ($MaxInterval -lt $MinInterval) { $script:MaxInterval = $MinInterval }
    if ($IdleSeconds -lt 0) { $script:IdleSeconds = 0 }
    if ($CornerDelayMin -lt 50) { $script:CornerDelayMin = 50 }
    if ($CornerDelayMax -lt $CornerDelayMin) { $script:CornerDelayMax = $CornerDelayMin }
    if (@("top_first", "bottom_first", "random") -notcontains $ClickOrder) { $script:ClickOrder = "top_first" }
    if ($BreakChance -lt 0) { $script:BreakChance = 0 }
    if ($BreakChance -gt 100) { $script:BreakChance = 100 }
    if ($BreakMinMinutes -lt 1) { $script:BreakMinMinutes = 1 }
    if ($BreakMaxMinutes -lt $BreakMinMinutes) { $script:BreakMaxMinutes = $BreakMinMinutes }
    # Below 30 s the heartbeat (every 10 s) could look late during normal work
    if ($HangSeconds -lt 30) { $script:HangSeconds = 30 }
    if ($MaxRestarts -lt 1) { $script:MaxRestarts = 1 }

    # The actions file is relative to the config file's folder
    $script:ActionsPath = ""

    if ($ActionsFile) {
        if ([System.IO.Path]::IsPathRooted($ActionsFile)) {
            $script:ActionsPath = $ActionsFile
        }
        else {
            $configDir = Split-Path -Parent $Path
            if (-not $configDir) { $configDir = "." }
            $script:ActionsPath = Join-Path $configDir $ActionsFile
        }
    }
}

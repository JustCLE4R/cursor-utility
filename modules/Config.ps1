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
min_interval_seconds=60
max_interval_seconds=120
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
order=top_first

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

    $script:IsDryRun        = [bool]$DryRun -or (Get-IniBool $Ini "debug.dry_run" $false)
    $script:ShowOverlay     = [bool]$Overlay -or (Get-IniBool $Ini "debug.overlay" $false)

    # Validation

    if ($MinInterval -lt 1) { $script:MinInterval = 1 }
    if ($MaxInterval -lt $MinInterval) { $script:MaxInterval = $MinInterval }
    if ($IdleSeconds -lt 0) { $script:IdleSeconds = 0 }
    if ($CornerDelayMin -lt 50) { $script:CornerDelayMin = 50 }
    if ($CornerDelayMax -lt $CornerDelayMin) { $script:CornerDelayMax = $CornerDelayMin }
    if (@("top_first", "bottom_first", "random") -notcontains $ClickOrder) { $script:ClickOrder = "top_first" }
}

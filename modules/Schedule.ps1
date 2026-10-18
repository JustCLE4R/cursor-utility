# ============================================================
# Schedule
# ============================================================

# Name, default start, default end
$DefaultShifts = @(
    @("subuh", "00:00", "08:30"),
    @("pagi",  "08:00", "16:30"),
    @("malam", "16:00", "00:30")
)

function Convert-ToMinutes {
    param(
        [string]$Time
    )

    $parsed = [TimeSpan]::Parse($Time)

    return ($parsed.Hours * 60) + $parsed.Minutes
}

function Test-ShiftActive {
    param(
        [bool]$Enabled,
        [int]$Start,
        [int]$End,
        [int]$Current
    )

    if (-not $Enabled) {
        return $false
    }

    # Normal shift
    if ($Start -le $End) {
        return ($Current -ge $Start -and $Current -le $End)
    }

    # Shift crosses midnight
    return ($Current -ge $Start -or $Current -le $End)
}

# The first enabled shift that covers $Now, as @{ Name; Start; End }, or $null
function Get-ActiveShift {
    param(
        [hashtable]$Ini,
        [datetime]$Now = (Get-Date)
    )

    $currentMinutes = ($Now.Hour * 60) + $Now.Minute

    foreach ($shift in $DefaultShifts) {

        $name = $shift[0]

        $enabled = Get-IniBool $Ini "schedule.$($name)_enabled" $true
        $startText = Get-IniValue $Ini "schedule.$($name)_start" $shift[1]
        $endText = Get-IniValue $Ini "schedule.$($name)_end" $shift[2]

        $start = Convert-ToMinutes $startText
        $end = Convert-ToMinutes $endText

        if (Test-ShiftActive $enabled $start $end $currentMinutes) {
            return @{ Name = $name; Start = $startText; End = $endText }
        }
    }

    return $null
}

function Test-ScheduleActive {
    param(
        [hashtable]$Ini,
        [datetime]$Now = (Get-Date)
    )

    return ($null -ne (Get-ActiveShift $Ini $Now))
}

# 42 -> "42s", 750 -> "12m 30s", 4000 -> "1h 06m"
function Format-Duration {
    param(
        [double]$Seconds
    )

    $total = [int][Math]::Max(0, [Math]::Ceiling($Seconds))

    if ($total -lt 60) {
        return "${total}s"
    }

    if ($total -lt 3600) {
        return "{0}m {1:00}s" -f [Math]::Floor($total / 60), ($total % 60)
    }

    return "{0}h {1:00}m" -f [Math]::Floor($total / 3600), [Math]::Floor(($total % 3600) / 60)
}

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

function Test-ScheduleActive {
    param(
        [hashtable]$Ini,
        [datetime]$Now = (Get-Date)
    )

    $currentMinutes = ($Now.Hour * 60) + $Now.Minute

    foreach ($shift in $DefaultShifts) {

        $name = $shift[0]

        $enabled = Get-IniBool $Ini "schedule.$($name)_enabled" $true
        $start = Convert-ToMinutes (Get-IniValue $Ini "schedule.$($name)_start" $shift[1])
        $end = Convert-ToMinutes (Get-IniValue $Ini "schedule.$($name)_end" $shift[2])

        if (Test-ShiftActive $enabled $start $end $currentMinutes) {
            return $true
        }
    }

    return $false
}

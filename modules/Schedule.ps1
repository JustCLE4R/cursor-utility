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

# The shift a run starting at $Now belongs to, as @{ Name; Start; End } with full dates.
# The shifts overlap, so the one that started most recently wins: at 08:15 that's
# pagi (from 08:00), not subuh. Outside every shift it's the next one to start.
# $null if no shift is enabled.
function Get-ShiftWindow {
    param(
        [hashtable]$Ini,
        [datetime]$Now = (Get-Date)
    )

    $current = $null
    $next = $null

    foreach ($shift in $DefaultShifts) {

        $name = $shift[0]

        if (-not (Get-IniBool $Ini "schedule.$($name)_enabled" $true)) {
            continue
        }

        $startMinutes = Convert-ToMinutes (Get-IniValue $Ini "schedule.$($name)_start" $shift[1])
        $endMinutes = Convert-ToMinutes (Get-IniValue $Ini "schedule.$($name)_end" $shift[2])

        # The latest start at or before now
        $start = $Now.Date.AddMinutes($startMinutes)
        if ($start -gt $Now) {
            $start = $start.AddDays(-1)
        }

        $end = $start.Date.AddMinutes($endMinutes)
        if ($endMinutes -lt $startMinutes) {
            # Crosses midnight
            $end = $end.AddDays(1)
        }

        # The end minute is still part of the shift
        if ($Now -lt $end.AddMinutes(1)) {
            if (-not $current -or $start -gt $current.Start) {
                $current = @{ Name = $name; Start = $start; End = $end }
            }
        }
        elseif (-not $next -or $start.AddDays(1) -lt $next.Start) {
            $next = @{ Name = $name; Start = $start.AddDays(1); End = $end.AddDays(1) }
        }
    }

    if ($current) {
        return $current
    }

    return $next
}

# When a run that started at $Start should stop ([general] stop_after_shift):
# $ExtraMinutes after its shift ends. $null if no shift is enabled.
function Get-StopTime {
    param(
        [hashtable]$Ini,
        [datetime]$Start,
        [int]$ExtraMinutes
    )

    $window = Get-ShiftWindow $Ini $Start

    if (-not $window) {
        return $null
    }

    return $window.End.AddMinutes($ExtraMinutes)
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

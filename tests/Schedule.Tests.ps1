# Run with: Invoke-Pester .\tests   (Pester 3.4+)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "..\modules\Config.ps1")
. (Join-Path $here "..\modules\Schedule.ps1")

function Get-TestTime {
    param(
        [string]$Time
    )

    return [datetime]::ParseExact("2026-10-18 $Time", "yyyy-MM-dd HH:mm", $null)
}

# All shifts off, except the ones given as name = @(start, end)
function New-ScheduleIni {
    param(
        [hashtable]$Shifts = @{}
    )

    $ini = @{
        "schedule.subuh_enabled" = "false"
        "schedule.pagi_enabled"  = "false"
        "schedule.malam_enabled" = "false"
    }

    foreach ($name in $Shifts.Keys) {
        $ini["schedule.$($name)_enabled"] = "true"
        $ini["schedule.$($name)_start"] = $Shifts[$name][0]
        $ini["schedule.$($name)_end"] = $Shifts[$name][1]
    }

    return $ini
}

Describe "Convert-ToMinutes" {

    It "converts HH:mm to minutes since midnight" {
        Convert-ToMinutes "00:00" | Should Be 0
        Convert-ToMinutes "08:30" | Should Be 510
        Convert-ToMinutes "16:00" | Should Be 960
        Convert-ToMinutes "23:59" | Should Be 1439
    }

    It "accepts a single-digit hour" {
        Convert-ToMinutes "8:05" | Should Be 485
    }

    It "throws on invalid times" {
        { Convert-ToMinutes "abc" } | Should Throw
        { Convert-ToMinutes "" } | Should Throw
    }
}

Describe "Test-ShiftActive" {

    Context "normal shift 08:00-16:30" {

        It "is active inside the shift, including both ends" {
            Test-ShiftActive $true 480 990 480 | Should Be $true
            Test-ShiftActive $true 480 990 720 | Should Be $true
            Test-ShiftActive $true 480 990 990 | Should Be $true
        }

        It "is inactive outside the shift" {
            Test-ShiftActive $true 480 990 479 | Should Be $false
            Test-ShiftActive $true 480 990 991 | Should Be $false
        }
    }

    Context "shift crossing midnight 16:00-00:30" {

        It "is active late evening and just after midnight" {
            Test-ShiftActive $true 960 30 960 | Should Be $true
            Test-ShiftActive $true 960 30 1439 | Should Be $true
            Test-ShiftActive $true 960 30 0 | Should Be $true
            Test-ShiftActive $true 960 30 30 | Should Be $true
        }

        It "is inactive during the day" {
            Test-ShiftActive $true 960 30 31 | Should Be $false
            Test-ShiftActive $true 960 30 720 | Should Be $false
            Test-ShiftActive $true 960 30 959 | Should Be $false
        }
    }

    It "is never active when disabled" {
        Test-ShiftActive $false 0 1439 720 | Should Be $false
    }
}

Describe "Get-ActiveShift" {

    It "names the matching shift with its times" {
        $ini = New-ScheduleIni @{ pagi = @("09:00", "17:00") }

        $shift = Get-ActiveShift $ini (Get-TestTime "10:00")

        $shift.Name | Should Be "pagi"
        $shift.Start | Should Be "09:00"
        $shift.End | Should Be "17:00"
    }

    It "returns the first match when shifts overlap" {
        $shift = Get-ActiveShift @{} (Get-TestTime "08:15")

        $shift.Name | Should Be "subuh"
    }

    It "returns null outside every shift" {
        $ini = New-ScheduleIni @{ pagi = @("09:00", "17:00") }

        Get-ActiveShift $ini (Get-TestTime "20:00") | Should BeNullOrEmpty
    }
}

Describe "Get-ShiftWindow" {

    # The default shifts: they overlap and cover all 24 hours
    $defaults = @{}

    It "picks the shift that started most recently when shifts overlap" {
        $window = Get-ShiftWindow $defaults (Get-TestTime "08:15")

        $window.Name | Should Be "pagi"
        $window.Start | Should Be (Get-TestTime "08:00")
        $window.End | Should Be (Get-TestTime "16:30")
    }

    It "gives a shift that crosses midnight its end on the next day" {
        $window = Get-ShiftWindow $defaults (Get-TestTime "16:10")

        $window.Name | Should Be "malam"
        $window.End | Should Be (Get-TestTime "00:30").AddDays(1)
    }

    It "finds a midnight shift that started the day before" {
        $ini = New-ScheduleIni @{ malam = @("16:00", "00:30") }
        $window = Get-ShiftWindow $ini (Get-TestTime "00:20")

        $window.Name | Should Be "malam"
        $window.Start | Should Be (Get-TestTime "16:00").AddDays(-1)
        $window.End | Should Be (Get-TestTime "00:30")
    }

    It "counts the end minute as part of the shift" {
        $ini = New-ScheduleIni @{ pagi = @("08:00", "16:30") }

        (Get-ShiftWindow $ini (Get-TestTime "16:30").AddSeconds(59)).Start | Should Be (Get-TestTime "08:00")
    }

    It "uses the next shift when started outside every shift" {
        $ini = New-ScheduleIni @{ pagi = @("08:00", "16:30") }

        (Get-ShiftWindow $ini (Get-TestTime "06:00")).Start | Should Be (Get-TestTime "08:00")
        (Get-ShiftWindow $ini (Get-TestTime "18:00")).Start | Should Be (Get-TestTime "08:00").AddDays(1)
    }

    It "returns nothing when no shift is enabled" {
        Get-ShiftWindow (New-ScheduleIni) (Get-TestTime "12:00") | Should Be $null
    }
}

Describe "Get-StopTime" {

    It "adds the extra minutes to the end of the start's shift" {
        Get-StopTime @{} (Get-TestTime "08:15") 60 | Should Be (Get-TestTime "17:30")
    }

    It "returns nothing when no shift is enabled" {
        Get-StopTime (New-ScheduleIni) (Get-TestTime "08:15") 60 | Should Be $null
    }
}

Describe "Format-Duration" {

    It "formats seconds, minutes and hours" {
        Format-Duration 0 | Should Be "0s"
        Format-Duration 42 | Should Be "42s"
        Format-Duration 60 | Should Be "1m 00s"
        Format-Duration 750 | Should Be "12m 30s"
        Format-Duration 3600 | Should Be "1h 00m"
        Format-Duration 4000 | Should Be "1h 06m"
    }

    It "rounds part seconds up and never goes negative" {
        Format-Duration 41.2 | Should Be "42s"
        Format-Duration -5 | Should Be "0s"
    }
}

Describe "Test-ScheduleActive" {

    It "is always active with the default shifts" {
        foreach ($time in @("00:00", "04:00", "08:15", "12:00", "16:15", "20:00", "23:59")) {
            Test-ScheduleActive @{} (Get-TestTime $time) | Should Be $true
        }
    }

    It "is never active with every shift disabled" {
        $ini = New-ScheduleIni

        Test-ScheduleActive $ini (Get-TestTime "12:00") | Should Be $false
        Test-ScheduleActive $ini (Get-TestTime "00:00") | Should Be $false
    }

    It "follows a single enabled shift" {
        $ini = New-ScheduleIni @{ pagi = @("09:00", "17:00") }

        Test-ScheduleActive $ini (Get-TestTime "08:59") | Should Be $false
        Test-ScheduleActive $ini (Get-TestTime "09:00") | Should Be $true
        Test-ScheduleActive $ini (Get-TestTime "17:00") | Should Be $true
        Test-ScheduleActive $ini (Get-TestTime "17:01") | Should Be $false
    }

    It "is active if any enabled shift matches" {
        $ini = New-ScheduleIni @{ subuh = @("01:00", "02:00"); malam = @("22:00", "00:30") }

        Test-ScheduleActive $ini (Get-TestTime "01:30") | Should Be $true
        Test-ScheduleActive $ini (Get-TestTime "23:00") | Should Be $true
        Test-ScheduleActive $ini (Get-TestTime "00:15") | Should Be $true
        Test-ScheduleActive $ini (Get-TestTime "12:00") | Should Be $false
    }

    It "throws on an invalid shift time" {
        $ini = New-ScheduleIni @{ pagi = @("nine", "17:00") }

        { Test-ScheduleActive $ini (Get-TestTime "12:00") } | Should Throw
    }
}

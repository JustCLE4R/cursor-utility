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

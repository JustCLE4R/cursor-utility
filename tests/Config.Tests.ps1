# Run with: Invoke-Pester .\tests   (Pester 3.4+)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "..\modules\Config.ps1")

function New-TestIni {
    param(
        [string[]]$Lines
    )

    $path = Join-Path $TestDrive ("test-" + [guid]::NewGuid() + ".ini")
    Set-Content -LiteralPath $path -Value $Lines
    return $path
}

Describe "Read-Ini" {

    It "stores keys as section.key" {
        $ini = Read-Ini (New-TestIni @("[general]", "enabled=true", "[activity]", "idle_seconds=30"))

        $ini["general.enabled"] | Should Be "true"
        $ini["activity.idle_seconds"] | Should Be "30"
    }

    It "trims spaces around sections, keys and values" {
        $ini = Read-Ini (New-TestIni @("  [ click ]  ", "  corner_delay_min_ms  =  500  "))

        $ini["click.corner_delay_min_ms"] | Should Be "500"
    }

    It "skips comments and blank lines" {
        $ini = Read-Ini (New-TestIni @("# comment", "; other comment", "", "[a]", "# x=1", "y=2"))

        $ini.Count | Should Be 1
        $ini["a.y"] | Should Be "2"
    }

    It "keeps everything after the first = in the value" {
        $ini = Read-Ini (New-TestIni @("[a]", "key=b=c"))

        $ini["a.key"] | Should Be "b=c"
    }

    It "allows empty values" {
        $ini = Read-Ini (New-TestIni @("[a]", "key="))

        $ini.ContainsKey("a.key") | Should Be $true
        $ini["a.key"] | Should Be ""
    }

    It "uses an empty section for keys before the first section" {
        $ini = Read-Ini (New-TestIni @("top=1", "[a]", "key=2"))

        $ini[".top"] | Should Be "1"
    }

    It "lets a later duplicate key win" {
        $ini = Read-Ini (New-TestIni @("[a]", "key=1", "key=2"))

        $ini["a.key"] | Should Be "2"
    }
}

Describe "Get-IniBool" {

    foreach ($text in @("true", "TRUE", "yes", "1", "on", "On")) {
        It "reads '$text' as true" {
            Get-IniBool @{ "a.b" = $text } "a.b" $false | Should Be $true
        }
    }

    foreach ($text in @("false", "no", "0", "off", "nope", "")) {
        It "reads '$text' as false" {
            Get-IniBool @{ "a.b" = $text } "a.b" $true | Should Be $false
        }
    }

    It "returns the default when the key is missing" {
        Get-IniBool @{} "a.b" $true | Should Be $true
        Get-IniBool @{} "a.b" $false | Should Be $false
    }
}

Describe "Get-IniInt" {

    It "parses integers" {
        Get-IniInt @{ "a.b" = "42" } "a.b" 0 | Should Be 42
        Get-IniInt @{ "a.b" = "-5" } "a.b" 0 | Should Be -5
    }

    It "returns the default for invalid numbers" {
        Get-IniInt @{ "a.b" = "abc" } "a.b" 7 | Should Be 7
        Get-IniInt @{ "a.b" = "1.5" } "a.b" 7 | Should Be 7
        Get-IniInt @{ "a.b" = "" } "a.b" 7 | Should Be 7
    }

    It "returns the default when the key is missing" {
        Get-IniInt @{} "a.b" 7 | Should Be 7
    }
}

Describe "New-DefaultConfig" {

    It "creates the file, including missing folders" {
        $path = Join-Path $TestDrive "new\sub\config.ini"

        New-DefaultConfig $path

        Test-Path -LiteralPath $path | Should Be $true
    }

    It "writes a config that loads with the built-in defaults" {
        $path = Join-Path $TestDrive "defaults.ini"
        New-DefaultConfig $path

        Import-Settings $path

        $Enabled | Should Be $true
        $LogEnabled | Should Be $true
        $StopAfterShift | Should Be $true
        $StopExtraMinutes | Should Be 60
        $MinInterval | Should Be 15
        $MaxInterval | Should Be 60
        $IdleSeconds | Should Be 120
        $ReturnAfterMove | Should Be $true
        $SmoothMove | Should Be $true
        $CornerDelayMin | Should Be 700
        $CornerDelayMax | Should Be 2200
        $ClickOrder | Should Be "bottom_first"
        $ActionsFile | Should Be ""
        $ActionsPath | Should Be ""
        $RestoreFocus | Should Be $false
        $BreakEnabled | Should Be $true
        $BreakChance | Should Be 1
        $BreakMinMinutes | Should Be 5
        $BreakMaxMinutes | Should Be 20
        $IsDryRun | Should Be $false
        $ShowOverlay | Should Be $false
    }

    It "includes every schedule key" {
        $path = Join-Path $TestDrive "schedule.ini"
        New-DefaultConfig $path

        $ini = Read-Ini $path

        foreach ($name in @("subuh", "pagi", "malam")) {
            foreach ($suffix in @("enabled", "start", "end")) {
                $ini.ContainsKey("schedule.$($name)_$suffix") | Should Be $true
            }
        }
    }
}

Describe "Import-Settings" {

    It "uses defaults for an empty file" {
        Import-Settings (New-TestIni @(""))

        $MinInterval | Should Be 15
        $CornerDelayMax | Should Be 2200
    }

    It "clamps out-of-range values" {
        Import-Settings (New-TestIni @(
            "[activity]",
            "min_interval_seconds=0",
            "max_interval_seconds=-10",
            "idle_seconds=-5",
            "[click]",
            "corner_delay_min_ms=10",
            "corner_delay_max_ms=20"
        ))

        $MinInterval | Should Be 1
        $MaxInterval | Should Be 1
        $IdleSeconds | Should Be 0
        $CornerDelayMin | Should Be 50
        $CornerDelayMax | Should Be 50
    }

    It "stops 60 minutes after the shift by default" {
        Import-Settings (New-TestIni @(""))

        $StopAfterShift | Should Be $true
        $StopExtraMinutes | Should Be 60
    }

    It "reads the stop settings and raises negative extra minutes to 0" {
        Import-Settings (New-TestIni @("[general]", "stop_after_shift=false", "stop_extra_minutes=15"))
        $StopAfterShift | Should Be $false
        $StopExtraMinutes | Should Be 15

        Import-Settings (New-TestIni @("[general]", "stop_extra_minutes=-3"))
        $StopExtraMinutes | Should Be 0
    }

    foreach ($order in @("top_first", "bottom_first", "random")) {
        It "accepts click order '$order'" {
            Import-Settings (New-TestIni @("[click]", "order=$order"))

            $ClickOrder | Should Be $order
        }
    }

    It "reads the click order case-insensitively" {
        Import-Settings (New-TestIni @("[click]", "order=Bottom_First"))

        $ClickOrder | Should Be "bottom_first"
    }

    It "falls back to bottom_first for a missing or unknown click order" {
        Import-Settings (New-TestIni @(""))
        $ClickOrder | Should Be "bottom_first"

        Import-Settings (New-TestIni @("[click]", "order=sideways"))
        $ClickOrder | Should Be "bottom_first"
    }

    It "resolves the actions file next to the config file" {
        $path = New-TestIni @("[actions]", "file=my-actions.txt")

        Import-Settings $path

        $ActionsPath | Should Be (Join-Path (Split-Path -Parent $path) "my-actions.txt")
    }

    It "keeps an absolute actions path as it is" {
        Import-Settings (New-TestIni @("[actions]", "file=C:\somewhere\steps.txt"))

        $ActionsPath | Should Be "C:\somewhere\steps.txt"
    }

    It "searches the common browsers for tabs by default" {
        Import-Settings (New-TestIni @(""))

        ($Browsers -join ",") | Should Be "msedge,chrome,brave,opera,firefox,vivaldi"
    }

    It "reads the browser list with commas or spaces, any case, with or without .exe" {
        Import-Settings (New-TestIni @("[actions]", "browsers=MSEdge.exe,  chrome firefox"))

        ($Browsers -join ",") | Should Be "msedge,chrome,firefox"
    }

    It "falls back to the default browsers for an empty list" {
        Import-Settings (New-TestIni @("[actions]", "browsers= , "))

        ($Browsers -join ",") | Should Be "msedge,chrome,brave,opera,firefox,vivaldi"
    }

    It "uses watchdog defaults for an empty file" {
        Import-Settings (New-TestIni @(""))

        $WatchdogEnabled | Should Be $true
        $HangSeconds | Should Be 180
        $MaxRestarts | Should Be 5
    }

    It "reads and clamps the watchdog section" {
        Import-Settings (New-TestIni @("[watchdog]", "enabled=false", "hang_seconds=90", "max_restarts=3"))

        $WatchdogEnabled | Should Be $false
        $HangSeconds | Should Be 90
        $MaxRestarts | Should Be 3

        Import-Settings (New-TestIni @("[watchdog]", "hang_seconds=5", "max_restarts=0"))

        $HangSeconds | Should Be 30
        $MaxRestarts | Should Be 1
    }

    It "reads the break section" {
        Import-Settings (New-TestIni @("[break]", "enabled=true", "chance_percent=12", "min_minutes=3", "max_minutes=9"))

        $BreakEnabled | Should Be $true
        $BreakChance | Should Be 12
        $BreakMinMinutes | Should Be 3
        $BreakMaxMinutes | Should Be 9
    }

    It "clamps break values" {
        Import-Settings (New-TestIni @("[break]", "chance_percent=250", "min_minutes=0", "max_minutes=-4"))

        $BreakChance | Should Be 100
        $BreakMinMinutes | Should Be 1
        $BreakMaxMinutes | Should Be 1

        Import-Settings (New-TestIni @("[break]", "chance_percent=-3"))

        $BreakChance | Should Be 0
    }

    It "reads the debug section" {
        Import-Settings (New-TestIni @("[debug]", "dry_run=true", "overlay=yes"))

        $IsDryRun | Should Be $true
        $ShowOverlay | Should Be $true
    }

    It "lets the -DryRun and -Overlay switches override the config" {
        $DryRun = $true
        $Overlay = $true

        Import-Settings (New-TestIni @("[debug]", "dry_run=false", "overlay=false"))

        $IsDryRun | Should Be $true
        $ShowOverlay | Should Be $true
    }
}

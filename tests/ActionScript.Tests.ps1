# Run with: Invoke-Pester .\tests   (Pester 3.4+)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "..\modules\ActionScript.ps1")

function New-TestScript {
    param(
        [string[]]$Lines,
        [string]$Name = "actions.txt"
    )

    $dir = Join-Path $TestDrive ([guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir | Out-Null
    $path = Join-Path $dir $Name
    Set-Content -LiteralPath $path -Value $Lines
    return $path
}

# Pester 3 has no "Should Throw <message>" that matches part of the text,
# so read the message ourselves
function Get-ErrorMessage {
    param(
        [scriptblock]$Block
    )

    try {
        & $Block | Out-Null
    }
    catch {
        return $_.Exception.Message
    }

    return ""
}

Describe "Resolve-ActionCoordinate" {

    It "passes pixels through, including negative ones" {
        Resolve-ActionCoordinate "0" "x" 1920 | Should Be 0
        Resolve-ActionCoordinate "1234" "x" 1920 | Should Be 1234
        Resolve-ActionCoordinate "-300" "y" 1080 | Should Be -300
    }

    It "maps percentages onto the first to last pixel" {
        Resolve-ActionCoordinate "0%" "x" 1920 | Should Be 0
        Resolve-ActionCoordinate "50%" "x" 1921 | Should Be 960
        Resolve-ActionCoordinate "100%" "y" 1080 | Should Be 1079
        Resolve-ActionCoordinate "12.5%" "x" 801 | Should Be 100
    }

    It "maps words to edges and the centre" {
        Resolve-ActionCoordinate "left" "x" 1920 | Should Be 0
        Resolve-ActionCoordinate "right" "x" 1920 | Should Be 1919
        Resolve-ActionCoordinate "center" "x" 1920 | Should Be 959
        Resolve-ActionCoordinate "middle" "y" 1080 | Should Be 539
        Resolve-ActionCoordinate "top" "y" 1080 | Should Be 0
        Resolve-ActionCoordinate "bottom" "y" 1080 | Should Be 1079
    }

    It "applies offsets to words" {
        Resolve-ActionCoordinate "right-10" "x" 1920 | Should Be 1909
        Resolve-ActionCoordinate "top+25" "y" 1080 | Should Be 25
        Resolve-ActionCoordinate "center+100" "x" 1920 | Should Be 1059
    }

    It "is case-insensitive" {
        Resolve-ActionCoordinate "Bottom-5" "y" 1080 | Should Be 1074
    }

    It "rejects words for the wrong axis" {
        { Resolve-ActionCoordinate "top" "x" 1920 } | Should Throw
        { Resolve-ActionCoordinate "left" "y" 1080 } | Should Throw
    }

    It "rejects nonsense and percentages over 100" {
        { Resolve-ActionCoordinate "abc" "x" 1920 } | Should Throw
        { Resolve-ActionCoordinate "150%" "x" 1920 } | Should Throw
        { Resolve-ActionCoordinate "" "x" 1920 } | Should Throw
    }
}

Describe "ConvertTo-KeyCombo" {

    It "reads a single key" {
        $keys = ConvertTo-KeyCombo "f15"

        $keys.Count | Should Be 1
        $keys[0].Code | Should Be 0x7E
        $keys[0].Extended | Should Be $false
    }

    It "reads combos in order" {
        $keys = ConvertTo-KeyCombo "ctrl+shift+a"

        ($keys | ForEach-Object { $_.Code }) -join "," | Should Be "17,16,65"
    }

    It "reads letters, digits and f1-f24" {
        (ConvertTo-KeyCombo "z")[0].Code | Should Be 0x5A
        (ConvertTo-KeyCombo "7")[0].Code | Should Be 0x37
        (ConvertTo-KeyCombo "f1")[0].Code | Should Be 0x70
        (ConvertTo-KeyCombo "f24")[0].Code | Should Be 0x87
    }

    It "accepts aliases and any case" {
        (ConvertTo-KeyCombo "Control")[0].Code | Should Be 0x11
        (ConvertTo-KeyCombo "ESCAPE")[0].Code | Should Be 0x1B
        (ConvertTo-KeyCombo "scroll")[0].Code | Should Be 0x91
    }

    It "flags extended keys" {
        (ConvertTo-KeyCombo "delete")[0].Extended | Should Be $true
        (ConvertTo-KeyCombo "up")[0].Extended | Should Be $true
        (ConvertTo-KeyCombo "a")[0].Extended | Should Be $false
    }

    It "rejects unknown keys" {
        { ConvertTo-KeyCombo "f25" } | Should Throw
        { ConvertTo-KeyCombo "ctrl+banana" } | Should Throw
        { ConvertTo-KeyCombo "ctrl++" } | Should Throw
    }
}

Describe "ConvertFrom-ActionLine" {

    It "reads move" {
        $step = ConvertFrom-ActionLine "move center 40%"

        $step.Command | Should Be "move"
        $step.X | Should Be "center"
        $step.Y | Should Be "40%"
        $step.HasPoint | Should Be $true
    }

    It "reads every form of click" {
        $plain = ConvertFrom-ActionLine "click"
        $plain.Button | Should Be "left"
        $plain.HasPoint | Should Be $false

        $typed = ConvertFrom-ActionLine "click right"
        $typed.Button | Should Be "right"
        $typed.HasPoint | Should Be $false

        $point = ConvertFrom-ActionLine "click 100 200"
        $point.Button | Should Be "left"
        $point.X | Should Be "100"

        $full = ConvertFrom-ActionLine "CLICK Right-10 Bottom-10 Double"
        $full.Button | Should Be "double"
        $full.X | Should Be "right-10"
        $full.Y | Should Be "bottom-10"
    }

    It "reads key" {
        $step = ConvertFrom-ActionLine "key Ctrl+Shift+F15"

        $step.Combo | Should Be "ctrl+shift+f15"
        $step.Keys.Count | Should Be 3
    }

    It "reads scroll with and without a count" {
        $one = ConvertFrom-ActionLine "scroll down"
        $one.Direction | Should Be "down"
        $one.Count | Should Be 1

        $three = ConvertFrom-ActionLine "scroll left 3"
        $three.Direction | Should Be "left"
        $three.Count | Should Be 3
    }

    It "reads wait as a fixed time or a range" {
        $fixed = ConvertFrom-ActionLine "wait 500"
        $fixed.Min | Should Be 500
        $fixed.Max | Should Be 500

        $range = ConvertFrom-ActionLine "wait 700-2200"
        $range.Min | Should Be 700
        $range.Max | Should Be 2200
    }

    It "reads focus with spaces and quotes" {
        (ConvertFrom-ActionLine "focus notepad").Target | Should Be "notepad"
        (ConvertFrom-ActionLine "focus   Microsoft Teams  ").Target | Should Be "Microsoft Teams"
        (ConvertFrom-ActionLine 'focus "Visual Studio Code"').Target | Should Be "Visual Studio Code"
    }

    It "reads focus as a window by default" {
        (ConvertFrom-ActionLine "focus notepad").Mode | Should Be "window"
    }

    It "reads focus tab" {
        $step = ConvertFrom-ActionLine "focus tab whatsapp"

        $step.Mode | Should Be "tab"
        $step.Target | Should Be "whatsapp"
    }

    It "reads focus tab with spaces, quotes and any case" {
        $quoted = ConvertFrom-ActionLine 'focus tab "WhatsApp Web"'
        $quoted.Mode | Should Be "tab"
        $quoted.Target | Should Be "WhatsApp Web"

        $spaced = ConvertFrom-ActionLine "FOCUS  TAB   Inbox (3)  "
        $spaced.Mode | Should Be "tab"
        $spaced.Target | Should Be "Inbox (3)"
    }

    It "doesn't mistake window names that start with 'tab' for tabs" {
        $step = ConvertFrom-ActionLine "focus Tableau"

        $step.Mode | Should Be "window"
        $step.Target | Should Be "Tableau"
    }

    $bad = @{
        "clik left top"          = "unknown command"
        "move 10"                = "move needs X and Y"
        "move top left"          = "can't be used for X"
        "click 1 2 3 4"          = "at most"
        "click left top sideways" = "unknown click type"
        "key"                    = "key needs"
        "key ctrl + c"           = "key needs"
        "scroll sideways"        = "unknown scroll direction"
        "scroll down 0"          = "scroll count"
        "scroll down 51"         = "scroll count"
        "wait"                   = "wait needs"
        "wait 2s"                = "wait needs"
        "wait 900-100"           = "backwards"
        "wait 3600001"           = "1 hour"
        "focus"                  = "focus needs"
        "focus tab"              = "focus tab needs"
        'focus tab ""'           = "focus tab needs"
    }

    foreach ($line in $bad.Keys) {
        It "rejects '$line'" {
            $message = Get-ErrorMessage { ConvertFrom-ActionLine $line }

            $message | Should Match ([regex]::Escape($bad[$line]))
        }
    }
}

Describe "Read-ActionScript" {

    It "reads steps and skips comments and blank lines" {
        $path = New-TestScript @(
            "# comment",
            "; other comment",
            "",
            "click left top",
            "   wait 100-200   ",
            "key f15"
        )

        $steps = Read-ActionScript $path

        $steps.Count | Should Be 3
        $steps[0].Command | Should Be "click"
        $steps[1].Command | Should Be "wait"
        $steps[2].Command | Should Be "key"
    }

    It "remembers the line number of each step" {
        $steps = Read-ActionScript (New-TestScript @("# header", "", "move 0 0", "click"))

        $steps[0].Line | Should Be 3
        $steps[1].Line | Should Be 4
    }

    It "returns an array even for one step" {
        $steps = Read-ActionScript (New-TestScript @("key f15"))

        $steps.Count | Should Be 1
        $steps[0].Command | Should Be "key"
    }

    It "names the file and line in errors" {
        $path = New-TestScript @("click", "# fine", "clik") "mine.txt"

        Get-ErrorMessage { Read-ActionScript $path } | Should Match "^mine\.txt line 3: unknown command 'clik'"
    }

    It "rejects a file with no steps" {
        $path = New-TestScript @("# only comments", "")

        Get-ErrorMessage { Read-ActionScript $path } | Should Match "has no steps"
    }

    It "reports a missing file" {
        Get-ErrorMessage { Read-ActionScript (Join-Path $TestDrive "nope.txt") } | Should Match "nope\.txt not found"
    }

    It "reads the example actions.txt shipped with the project" {
        $steps = Read-ActionScript (Join-Path $here "..\actions.txt")

        $steps.Count -gt 0 | Should Be $true
    }
}

Describe "Get-CornerSteps" {

    It "clicks top then bottom for top_first" {
        $steps = Get-CornerSteps "top_first" 700 2200

        $steps.Count | Should Be 3
        $steps[0].Y | Should Be "top"
        $steps[1].Command | Should Be "wait"
        $steps[1].Min | Should Be 700
        $steps[1].Max | Should Be 2200
        $steps[2].Y | Should Be "bottom"
    }

    It "clicks bottom then top for bottom_first" {
        $steps = Get-CornerSteps "bottom_first" 50 50

        $steps[0].Y | Should Be "bottom"
        $steps[2].Y | Should Be "top"
    }

    It "uses left clicks on the left edge" {
        foreach ($step in @((Get-CornerSteps "top_first" 1 2)[0], (Get-CornerSteps "top_first" 1 2)[2])) {
            $step.Command | Should Be "click"
            $step.Button | Should Be "left"
            $step.X | Should Be "left"
        }
    }
}

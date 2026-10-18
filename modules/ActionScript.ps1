# ============================================================
# Action script: parses the actions file (see docs/actions.md)
# ============================================================

# Pure module: no WinForms or Win32, so the tests can load it directly.

# Virtual-key codes by name. Letters, digits and f1-f24 are worked out
# in ConvertTo-KeyCombo, so they are not listed here.
$KeyCodes = @{
    "shift"       = 0x10
    "ctrl"        = 0x11
    "alt"         = 0x12
    "win"         = 0x5B
    "apps"        = 0x5D
    "esc"         = 0x1B
    "enter"       = 0x0D
    "tab"         = 0x09
    "space"       = 0x20
    "backspace"   = 0x08
    "insert"      = 0x2D
    "delete"      = 0x2E
    "home"        = 0x24
    "end"         = 0x23
    "pageup"      = 0x21
    "pagedown"    = 0x22
    "up"          = 0x26
    "down"        = 0x28
    "left"        = 0x25
    "right"       = 0x27
    "capslock"    = 0x14
    "numlock"     = 0x90
    "scrolllock"  = 0x91
    "pause"       = 0x13
    "printscreen" = 0x2C
    "volumemute"  = 0xAD
    "volumedown"  = 0xAE
    "volumeup"    = 0xAF
    "playpause"   = 0xB3
}

$KeyAliases = @{
    "control" = "ctrl"
    "escape"  = "esc"
    "return"  = "enter"
    "del"     = "delete"
    "ins"     = "insert"
    "pgup"    = "pageup"
    "pgdn"    = "pagedown"
    "scroll"  = "scrolllock"
    "caps"    = "capslock"
    "prtsc"   = "printscreen"
    "menu"    = "apps"
    "windows" = "win"
    "mute"    = "volumemute"
}

# Keys that Windows expects with the "extended key" flag
$ExtendedKeys = @(
    "insert", "delete", "home", "end", "pageup", "pagedown",
    "up", "down", "left", "right", "numlock", "win", "apps", "printscreen",
    "volumemute", "volumedown", "volumeup", "playpause"
)

$ActionCommands = @("move", "click", "key", "scroll", "wait", "focus")
$ClickTypes     = @("left", "right", "middle", "double")
$ScrollWays     = @("up", "down", "left", "right")
$MaxWaitMs      = 3600000
$MaxScrollCount = 50

# Turns "ctrl+shift+f15" into a list of @{ Name; Code; Extended }
function ConvertTo-KeyCombo {
    param(
        [string]$Combo
    )

    $keys = @()

    foreach ($part in ($Combo.ToLower() -split '\+')) {

        $name = $part.Trim()

        if ($KeyAliases.ContainsKey($name)) {
            $name = $KeyAliases[$name]
        }

        if ($KeyCodes.ContainsKey($name)) {
            $code = $KeyCodes[$name]
        }
        elseif ($name -match '^[a-z0-9]$') {
            $code = [int][char]$name.ToUpper()
        }
        elseif ($name -match '^f([1-9]|1[0-9]|2[0-4])$') {
            $code = 0x6F + [int]$matches[1]
        }
        else {
            throw "unknown key '$part'"
        }

        $keys += @{ Name = $name; Code = $code; Extended = ($ExtendedKeys -contains $name) }
    }

    return ,$keys
}

# Turns an X or Y token into pixels on a screen of the given size:
#   123        pixels (may be negative, for monitors left of or above the primary one)
#   50%        percent of the size, 0% = first pixel, 100% = last pixel
#   left / center / right (X), top / center / bottom (Y), optionally +N or -N
function Resolve-ActionCoordinate {
    param(
        [string]$Token,
        [ValidateSet("x", "y")]
        [string]$Axis,
        [int]$Size
    )

    $text = $Token.ToLower()

    if ($text -match '^-?\d+$') {
        return [int]$text
    }

    if ($text -match '^(\d+(\.\d+)?)%$') {

        $percent = [double]$matches[1]

        if ($percent -gt 100) {
            throw "'$Token' is more than 100%"
        }

        return [int][Math]::Round(($Size - 1) * $percent / 100)
    }

    if ($text -match '^(left|right|top|bottom|center|middle)([+-]\d+)?$') {

        $word = $matches[1]
        $offset = 0

        if ($matches[2]) {
            $offset = [int]$matches[2]
        }

        if ($Axis -eq "x") {
            $valid = @("left", "center", "middle", "right")
        }
        else {
            $valid = @("top", "center", "middle", "bottom")
        }

        if ($valid -notcontains $word) {
            throw "'$word' can't be used for $($Axis.ToUpper())"
        }

        if ($word -eq "left" -or $word -eq "top") {
            $base = 0
        }
        elseif ($word -eq "center" -or $word -eq "middle") {
            $base = [int][Math]::Floor(($Size - 1) / 2)
        }
        else {
            $base = $Size - 1
        }

        return $base + $offset
    }

    throw "invalid $($Axis.ToUpper()) '$Token' (use pixels, a percentage, or a word like left/center/right)"
}

function Set-StepPoint {
    param(
        [hashtable]$Step,
        [string]$X,
        [string]$Y
    )

    # Validate now so mistakes show up when the file is loaded, not mid-cycle
    Resolve-ActionCoordinate $X "x" 1920 | Out-Null
    Resolve-ActionCoordinate $Y "y" 1080 | Out-Null

    $Step.X = $X.ToLower()
    $Step.Y = $Y.ToLower()
    $Step.HasPoint = $true
}

# Parses one non-comment line into a step hashtable. Throws a readable message on errors.
function ConvertFrom-ActionLine {
    param(
        [string]$Line
    )

    $text = $Line.Trim()
    $tokens = @($text -split '\s+')
    $command = $tokens[0].ToLower()

    $rest = @()
    if ($tokens.Count -gt 1) {
        $rest = @($tokens[1..($tokens.Count - 1)])
    }

    $step = @{ Command = $command; Text = $text; HasPoint = $false }

    if ($command -eq "move") {

        if ($rest.Count -ne 2) {
            throw "move needs X and Y, e.g. 'move center center'"
        }

        Set-StepPoint $step $rest[0] $rest[1]
    }
    elseif ($command -eq "click") {

        # click | click TYPE | click X Y | click X Y TYPE
        if ($rest.Count -eq 0) {
            $step.Button = "left"
        }
        elseif ($rest.Count -eq 1) {
            $step.Button = $rest[0].ToLower()
        }
        elseif ($rest.Count -eq 2 -or $rest.Count -eq 3) {
            Set-StepPoint $step $rest[0] $rest[1]
            $step.Button = "left"
            if ($rest.Count -eq 3) {
                $step.Button = $rest[2].ToLower()
            }
        }
        else {
            throw "click takes at most X, Y and a type, e.g. 'click right-10 bottom-10 right'"
        }

        if ($ClickTypes -notcontains $step.Button) {
            throw "unknown click type '$($step.Button)' (use left, right, middle or double)"
        }
    }
    elseif ($command -eq "key") {

        if ($rest.Count -ne 1) {
            throw "key needs one key or combo without spaces, e.g. 'key f15' or 'key ctrl+shift+f15'"
        }

        $step.Combo = $rest[0].ToLower()
        $step.Keys = ConvertTo-KeyCombo $rest[0]
    }
    elseif ($command -eq "scroll") {

        if ($rest.Count -lt 1 -or $rest.Count -gt 2) {
            throw "scroll needs a direction and an optional count, e.g. 'scroll down 3'"
        }

        $step.Direction = $rest[0].ToLower()

        if ($ScrollWays -notcontains $step.Direction) {
            throw "unknown scroll direction '$($rest[0])' (use up, down, left or right)"
        }

        $step.Count = 1

        if ($rest.Count -eq 2) {
            if ($rest[1] -notmatch '^\d+$' -or [int]$rest[1] -lt 1 -or [int]$rest[1] -gt $MaxScrollCount) {
                throw "scroll count must be a number from 1 to $MaxScrollCount"
            }
            $step.Count = [int]$rest[1]
        }
    }
    elseif ($command -eq "wait") {

        if ($rest.Count -ne 1) {
            throw "wait needs milliseconds, e.g. 'wait 500' or 'wait 700-2200'"
        }

        if ($rest[0] -match '^(\d+)$') {
            $step.Min = [int]$matches[1]
            $step.Max = $step.Min
        }
        elseif ($rest[0] -match '^(\d+)-(\d+)$') {
            $step.Min = [int]$matches[1]
            $step.Max = [int]$matches[2]
        }
        else {
            throw "wait needs milliseconds, e.g. 'wait 500' or 'wait 700-2200'"
        }

        if ($step.Min -gt $step.Max) {
            throw "wait range '$($rest[0])' is backwards"
        }

        if ($step.Max -gt $MaxWaitMs) {
            throw "wait can't be longer than 1 hour ($MaxWaitMs ms)"
        }
    }
    elseif ($command -eq "focus") {

        # Everything after the command, so window titles may contain spaces
        $target = $text.Substring($tokens[0].Length).Trim()
        $step.Mode = "window"

        # "focus tab TEXT" looks for a browser tab instead of a window
        if ($target -match '^tab(\s+(.*))?$') {
            $step.Mode = "tab"
            $target = "$($matches[2])".Trim()

            if (-not $target.Trim('"').Trim("'").Trim()) {
                throw "focus tab needs part of a tab title, e.g. 'focus tab whatsapp'"
            }
        }

        $target = $target.Trim('"').Trim("'").Trim()

        if (-not $target) {
            throw "focus needs a process name or part of a window title, e.g. 'focus notepad'"
        }

        $step.Target = $target
    }
    else {
        throw "unknown command '$($tokens[0])' (use $($ActionCommands -join ', '))"
    }

    return $step
}

# Reads an actions file into a list of steps. Errors name the file and line.
function Read-ActionScript {
    param(
        [string]$Path
    )

    $name = Split-Path -Leaf $Path

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$name not found"
    }

    $steps = @()
    $number = 0

    foreach ($line in Get-Content -LiteralPath $Path) {

        $number++
        $text = $line.Trim()

        if (-not $text -or $text.StartsWith("#") -or $text.StartsWith(";")) {
            continue
        }

        try {
            $step = ConvertFrom-ActionLine $text
        }
        catch {
            throw "$name line ${number}: $($_.Exception.Message)"
        }

        $step.Line = $number
        $steps += $step
    }

    if ($steps.Count -eq 0) {
        throw "$name has no steps"
    }

    return ,$steps
}

# The built-in corner clicks, as steps
function Get-CornerSteps {
    param(
        [ValidateSet("top_first", "bottom_first")]
        [string]$Order,
        [int]$DelayMin,
        [int]$DelayMax
    )

    $top    = ConvertFrom-ActionLine "click left top"
    $bottom = ConvertFrom-ActionLine "click left bottom"
    $wait   = ConvertFrom-ActionLine "wait $DelayMin-$DelayMax"

    if ($Order -eq "bottom_first") {
        return ,@($bottom, $wait, $top)
    }

    return ,@($top, $wait, $bottom)
}

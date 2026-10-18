# ============================================================
# Action cycle: runs a list of steps (see docs/actions.md)
# ============================================================

# Steps loaded from the actions file, or the error that stopped them loading
$script:ActionSteps     = @()
$script:ActionError     = $null
$script:ActionStamp     = ""
$script:LastCycleResult = ""
$script:FocusRestore    = [IntPtr]::Zero

# Reloads the actions file when its path, size or time stamp changes.
# Logs once per change, so a broken file doesn't flood the log.
function Sync-ActionScript {

    if (-not $ActionsPath) {
        $script:ActionSteps = @()
        $script:ActionError = $null
        $script:ActionStamp = ""
        return
    }

    $stamp = "missing|$ActionsPath"

    if (Test-Path -LiteralPath $ActionsPath) {
        $item = Get-Item -LiteralPath $ActionsPath
        $stamp = "$ActionsPath|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    }

    if ($stamp -eq $ActionStamp) {
        return
    }

    $script:ActionStamp = $stamp

    try {
        $script:ActionSteps = Read-ActionScript $ActionsPath
        $script:ActionError = $null
        Write-Log "Loaded $($ActionSteps.Count) steps from $ActionsPath"
    }
    catch {
        $script:ActionSteps = @()
        $script:ActionError = $_.Exception.Message
        Write-Log "Actions file error: $ActionError. Cycles are paused until it is fixed."
    }
}

function Invoke-FocusStep {
    param(
        [hashtable]$Step,
        [string]$Tag
    )

    $hWnd = [MouseApi]::FindWindowByText($Step.Target)

    if ($hWnd -eq [IntPtr]::Zero) {
        $script:InterruptDetail = "no open window matches '$($Step.Target)'"
        throw "FocusFailed"
    }

    $title = [MouseApi]::GetWindowTitle($hWnd)

    if (-not $IsDryRun) {

        # Remember the window that was in front before the first focus step
        if ($FocusRestore -eq [IntPtr]::Zero) {
            $script:FocusRestore = [MouseApi]::GetForeground()
        }

        if (-not [MouseApi]::FocusWindow($hWnd)) {
            $script:InterruptDetail = "Windows did not bring '$title' to the front"
            throw "FocusFailed"
        }
    }

    Write-Log "${Tag}Focus: '$title'"

    # Give the window a moment to come up before the next step
    Wait-Action (Get-NaturalRandom 150 400)
}

function Invoke-ActionStep {
    param(
        [hashtable]$Step,
        [hashtable]$Screen,
        [string]$Tag
    )

    if ($Step.HasPoint) {
        $x = Resolve-ActionCoordinate $Step.X "x" $Screen.Width
        $y = Resolve-ActionCoordinate $Step.Y "y" $Screen.Height

        # Where the cursor would be now; in a dry run it never really moves
        $script:CyclePoint = @($x, $y)
    }

    if ($Step.Command -eq "move") {
        Move-CursorTo $x $y
    }
    elseif ($Step.Command -eq "click") {

        if ($Step.HasPoint) {
            Move-CursorTo $x $y
            Wait-Action (Get-NaturalRandom 80 250)
            $where = "($x,$y)"
        }
        elseif ($IsDryRun -and $CyclePoint) {
            $where = "($($CyclePoint[0]),$($CyclePoint[1]))"
        }
        else {
            $pos = Get-CursorPosition
            $where = "($($pos.X),$($pos.Y))"
        }

        Invoke-MouseClick $Step.Button
        Write-Log "${Tag}Click: $($Step.Button) at $where"
    }
    elseif ($Step.Command -eq "key") {
        Invoke-KeyCombo $Step.Keys
        Write-Log "${Tag}Key: $($Step.Combo)"
    }
    elseif ($Step.Command -eq "scroll") {

        for ($i = 1; $i -le $Step.Count; $i++) {
            Invoke-Scroll $Step.Direction
            if ($i -lt $Step.Count) {
                Wait-Action (Get-NaturalRandom 40 120)
            }
        }

        Write-Log "${Tag}Scroll: $($Step.Direction) x$($Step.Count)"
    }
    elseif ($Step.Command -eq "wait") {
        Wait-Action (Get-NaturalRandom $Step.Min $Step.Max)
    }
    elseif ($Step.Command -eq "focus") {
        Invoke-FocusStep $Step $Tag
    }
}

# Runs one cycle. The outcome goes in $LastCycleResult: "done", "stopped"
# (turned off or exit), or "cancelled: <reason>".
function Invoke-ActionCycle {
    param(
        [array]$Steps
    )

    $tag = if ($IsDryRun) { "[dry-run] " } else { "" }

    $screen = Get-ScreenSize
    $original = Get-CursorPosition
    $script:ExpectedX = $original.X
    $script:ExpectedY = $original.Y

    $script:CycleDisplay = Get-DisplaySignature
    $script:CyclePoint = $null
    $script:FocusRestore = [IntPtr]::Zero
    $script:LastCycleResult = "done"
    $script:InAction = $true

    try {
        if ($ShowOverlay) {
            $points = New-Object System.Collections.ArrayList

            foreach ($step in $Steps) {
                if ($step.HasPoint) {
                    $x = Resolve-ActionCoordinate $step.X "x" $screen.Width
                    $y = Resolve-ActionCoordinate $step.Y "y" $screen.Height
                    [void]$points.Add(@($x, $y))
                }
            }

            if ($points.Count -gt 0) {
                Show-ClickMarkers $points.ToArray()
            }
        }

        foreach ($step in $Steps) {
            Invoke-ActionStep $step $screen $tag
        }

        if ($ReturnAfterMove) {
            Wait-Action (Get-NaturalRandom 150 500)
            Move-CursorTo $original.X $original.Y
        }
    }
    catch {
        $reason = $_.Exception.Message

        if ($reason -eq "UserMoved") {
            # The user took over the mouse: back off immediately
            Write-Log "User moved the mouse: $InterruptDetail. Cycle cancelled."
            $script:LastUserInput = [MouseApi]::Now()
            $script:LastCycleResult = "cancelled: you moved the mouse"
        }
        elseif ($reason -eq "CursorBlocked") {
            # Not the user, so the idle timer is left alone
            Write-Log "Windows blocked the cursor: $InterruptDetail. Cycle cancelled."
            $script:LastCycleResult = "cancelled: cursor blocked"
        }
        elseif ($reason -eq "DisplayChanged") {
            Write-Log "Display changed during the cycle ($InterruptDetail). Cycle cancelled."
            $script:LastCycleResult = "cancelled: display changed"
        }
        elseif ($reason -eq "FocusFailed") {
            Write-Log "Focus failed: $InterruptDetail. Cycle cancelled."
            $script:LastCycleResult = "cancelled: window not focused"
        }
        elseif ($reason -eq "Interrupted") {
            $script:LastCycleResult = "stopped"
        }
        else {
            $script:LastCycleResult = "error"
            throw
        }
    }
    finally {
        Hide-ClickMarkers

        if ($RestoreFocus -and $FocusRestore -ne [IntPtr]::Zero) {
            [MouseApi]::FocusWindow($FocusRestore) | Out-Null
        }

        $script:FocusRestore = [IntPtr]::Zero
        $script:CycleDisplay = $null
        $script:InAction = $false
        $script:IgnoreInputBefore = [MouseApi]::Now()
    }
}

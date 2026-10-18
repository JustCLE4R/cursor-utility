# ============================================================
# Action cycle: runs a list of steps (see docs/actions.md)
# ============================================================

# Steps loaded from the actions file, or the error that stopped them loading
$script:ActionSteps     = @()
$script:ActionError     = $null
$script:ActionStamp     = ""
$script:LastCycleResult = ""
$script:FocusRestore    = [IntPtr]::Zero
$script:TabRestore      = $null

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

# Brings a window to the front, remembering the previous one the first time
function Set-FocusWindow {
    param(
        [IntPtr]$Handle,
        [string]$Title
    )

    if ($FocusRestore -eq [IntPtr]::Zero) {
        $script:FocusRestore = [MouseApi]::GetForeground()
    }

    if (-not [MouseApi]::FocusWindow($Handle)) {
        $script:InterruptDetail = "Windows did not bring '$Title' to the front"
        throw "FocusFailed"
    }
}

# focus tab NAME: find the browser tab, bring its window to the front, select the tab.
# Selecting uses UI Automation (no input); if the tab doesn't support that, it is clicked.
function Invoke-FocusTabStep {
    param(
        [hashtable]$Step,
        [string]$Tag
    )

    try {
        $tab = Find-BrowserTab $Step.Target $Browsers
    }
    catch {
        $script:InterruptDetail = "couldn't read browser tabs: $($_.Exception.Message)"
        throw "FocusFailed"
    }

    if (-not $tab) {
        $script:InterruptDetail = "no open tab matches '$($Step.Target)' in $($Browsers -join ', ')"
        throw "FocusFailed"
    }

    $where = "'$($tab.Name)' in '$($tab.WindowTitle)'"

    if ($IsDryRun) {
        $note = if ($tab.IsSelected) { "already selected" } else { "would select" }
        Write-Log "${Tag}Focus tab: $where ($note)"
        Wait-Action (Get-NaturalRandom 150 400)
        return
    }

    Set-FocusWindow $tab.WindowHandle $tab.WindowTitle
    Wait-Action (Get-NaturalRandom 150 400)

    $how = "already selected"

    if (-not $tab.IsSelected) {

        # Remember the tab that was showing, to switch back at the end of the cycle
        if (-not $TabRestore) {
            $script:TabRestore = Get-SelectedTabInWindow $tab $Browsers
        }

        $how = $null

        try {
            $how = [TabFinder]::Select($tab.Element)
        }
        catch {
            # E.g. ElementNotAvailableException when the tab was just closed
            $script:InterruptDetail = "couldn't select tab ${where}: $($_.Exception.Message)"
            throw "FocusFailed"
        }

        Wait-Action (Get-NaturalRandom 100 250)

        # Some tabs report a selection method but ignore it; clicking always works
        if (-not $how -or -not [TabFinder]::IsSelected($tab.Element)) {

            $center = [TabFinder]::GetCenter($tab.Element)

            if (-not $center) {
                $script:InterruptDetail = "tab $where can't be selected and isn't on screen to click"
                throw "FocusFailed"
            }

            Move-CursorTo $center[0] $center[1]
            Wait-Action (Get-NaturalRandom 80 250)
            Invoke-MouseClick "left"
            $how = "click"
        }
    }

    Write-Log "${Tag}Focus tab: $where ($how)"

    # Give the page a moment to show before the next step
    Wait-Action (Get-NaturalRandom 150 400)
}

function Invoke-FocusStep {
    param(
        [hashtable]$Step,
        [string]$Tag
    )

    if ($Step.Mode -eq "tab") {
        Invoke-FocusTabStep $Step $Tag
        return
    }

    $hWnd = [MouseApi]::FindWindowByText($Step.Target)

    if ($hWnd -eq [IntPtr]::Zero) {
        $script:InterruptDetail = "no open window matches '$($Step.Target)'"
        throw "FocusFailed"
    }

    $title = [MouseApi]::GetWindowTitle($hWnd)

    if (-not $IsDryRun) {
        Set-FocusWindow $hWnd $title
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
    $script:TabRestore = $null
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

        # Switch the browser back to the tab it was showing. Only without
        # input: a click here could no longer be cancelled by the user.
        if ($RestoreFocus -and $TabRestore) {
            try {
                [TabFinder]::Select($TabRestore.Element) | Out-Null
            }
            catch {
                Write-Log "Couldn't switch back to tab '$($TabRestore.Name)': $($_.Exception.Message)"
            }
        }

        if ($RestoreFocus -and $FocusRestore -ne [IntPtr]::Zero) {
            [MouseApi]::FocusWindow($FocusRestore) | Out-Null
        }

        $script:TabRestore = $null
        $script:FocusRestore = [IntPtr]::Zero
        $script:CycleDisplay = $null
        $script:InAction = $false
        $script:IgnoreInputBefore = [MouseApi]::Now()
    }
}

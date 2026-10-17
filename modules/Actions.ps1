# ============================================================
# Corner-click cycle
# ============================================================

function Invoke-CornerClicks {

    $tag = if ($IsDryRun) { "[dry-run] " } else { "" }

    $original = Get-CursorPosition
    $script:ExpectedX = $original.X
    $script:ExpectedY = $original.Y

    $screenHeight = [MouseApi]::GetSystemMetrics([MouseApi]::SM_CYSCREEN)
    $bottom = $screenHeight - 1

    $script:InAction = $true

    try {
        if ($ShowOverlay) {
            Show-ClickMarkers @(@(0, 0), @(0, $bottom))
        }

        # Top-left corner
        Move-CursorTo 0 0
        Wait-Action (Get-NaturalRandom 80 250)
        Invoke-LeftClick
        Write-Log "${tag}Click: top-left (0,0)"

        # Natural pause before the next corner
        $pause = Get-NaturalRandom $CornerDelayMin $CornerDelayMax
        Wait-Action $pause

        # Bottom-left corner
        Move-CursorTo 0 $bottom
        Wait-Action (Get-NaturalRandom 80 250)
        Invoke-LeftClick
        Write-Log "${tag}Click: bottom-left (0,$bottom) after $pause ms"

        if ($ReturnAfterMove) {
            Wait-Action (Get-NaturalRandom 150 500)
            Move-CursorTo $original.X $original.Y
        }
    }
    catch {
        if ($_.Exception.Message -eq "UserMoved") {
            # The user took over the mouse: back off immediately
            Write-Log "User moved the mouse: $InterruptDetail. Cycle cancelled."
            $script:LastUserInput = [MouseApi]::Now()
        }
        elseif ($_.Exception.Message -eq "CursorBlocked") {
            # Not the user, so the idle timer is left alone
            Write-Log "Windows blocked the cursor: $InterruptDetail. Cycle cancelled."
        }
        elseif ($_.Exception.Message -ne "Interrupted") {
            throw
        }
    }
    finally {
        Hide-ClickMarkers
        $script:InAction = $false
        $script:IgnoreInputBefore = [MouseApi]::Now()
    }
}

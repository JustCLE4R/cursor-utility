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

    $topLeft    = @{ Name = "top-left";    X = 0; Y = 0 }
    $bottomLeft = @{ Name = "bottom-left"; X = 0; Y = $bottom }

    $bottomFirst = ($ClickOrder -eq "bottom_first") -or ($ClickOrder -eq "random" -and $Random.Next(2) -eq 0)

    if ($bottomFirst) {
        $first, $second = $bottomLeft, $topLeft
    }
    else {
        $first, $second = $topLeft, $bottomLeft
    }

    $script:InAction = $true

    try {
        if ($ShowOverlay) {
            Show-ClickMarkers @(@($first.X, $first.Y), @($second.X, $second.Y))
        }

        # First corner
        Move-CursorTo $first.X $first.Y
        Wait-Action (Get-NaturalRandom 80 250)
        Invoke-LeftClick
        Write-Log "${tag}Click: $($first.Name) ($($first.X),$($first.Y))"

        # Natural pause before the next corner
        $pause = Get-NaturalRandom $CornerDelayMin $CornerDelayMax
        Wait-Action $pause

        # Second corner
        Move-CursorTo $second.X $second.Y
        Wait-Action (Get-NaturalRandom 80 250)
        Invoke-LeftClick
        Write-Log "${tag}Click: $($second.Name) ($($second.X),$($second.Y)) after $pause ms"

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

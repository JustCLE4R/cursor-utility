# ============================================================
# Tray icon: state icons, tooltip and info menu
# ============================================================

$script:Paused        = $false
$script:ExitRequested = $false

# Icon colour per state. See docs/architecture.md for when each is used.
$StateColors = @{
    "starting" = [System.Drawing.Color]::Silver
    "paused"   = [System.Drawing.Color]::Gray
    "schedule" = [System.Drawing.Color]::SteelBlue
    "user"     = [System.Drawing.Color]::Orange
    "idle"     = [System.Drawing.Color]::LimeGreen
    "clicking" = [System.Drawing.Color]::DeepSkyBlue
    "break"    = [System.Drawing.Color]::MediumPurple
    "error"    = [System.Drawing.Color]::Red
}

# Progress is shown in 12 steps, so at most 13 icons per state are ever made
$IconSteps = 12
$script:IconCache = @{}

# A dot in the state colour. With Progress (0-1) it is a ring that fills
# clockwise like a clock. A white badge at the bottom right means dry run.
function Get-StateIcon {
    param(
        [string]$State,
        [double]$Progress = -1,
        [bool]$DryRunBadge = $false
    )

    $bucket = -1
    if ($Progress -ge 0) {
        # 1.0, not 1: with an int first argument PowerShell picks Math.Min(int, int)
        $bucket = [int][Math]::Round([Math]::Min(1.0, $Progress) * $IconSteps)
    }

    $key = "$State|$bucket|$DryRunBadge"

    if ($IconCache.ContainsKey($key)) {
        return $IconCache[$key]
    }

    $color = $StateColors[$State]
    if (-not $color) { $color = [System.Drawing.Color]::White }

    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    $penWidth = [Math]::Max(1.5, $size / 8)
    $inset = $penWidth / 2 + 0.5
    $rect = New-Object System.Drawing.RectangleF $inset, $inset, ($size - 2 * $inset), ($size - 2 * $inset)

    $bitmap = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $brush = New-Object System.Drawing.SolidBrush $color
    $faint = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, $color))
    $pen = New-Object System.Drawing.Pen $color, $penWidth

    if ($bucket -lt 0) {
        $graphics.FillEllipse($brush, $rect)
    }
    else {
        $graphics.FillEllipse($faint, $rect)
        if ($bucket -gt 0) {
            $graphics.FillPie($brush, $rect.X, $rect.Y, $rect.Width, $rect.Height, -90, 360 * $bucket / $IconSteps)
        }
        $graphics.DrawEllipse($pen, $rect)
    }

    if ($DryRunBadge) {
        $badge = [Math]::Round($size * 0.45)
        $badgeRect = New-Object System.Drawing.RectangleF ($size - $badge - 0.5), ($size - $badge - 0.5), $badge, $badge
        $graphics.FillEllipse([System.Drawing.Brushes]::White, $badgeRect)
        $graphics.DrawEllipse([System.Drawing.Pens]::Black, $badgeRect)
    }

    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())

    $pen.Dispose()
    $faint.Dispose()
    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()

    # Cached for the life of the process, so the icon handles are never leaked
    $IconCache[$key] = $icon
    return $icon
}

# Disabled menu item used as an info line
function New-InfoItem {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Enabled = $false
    return $item
}

function Initialize-Tray {

    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $Tray.Icon = Get-StateIcon "starting" -1 $IsDryRun
    $Tray.Visible = $true

    $script:MenuStatus  = New-InfoItem
    $script:MenuNext    = New-InfoItem
    $script:MenuShift   = New-InfoItem
    $script:MenuActions = New-InfoItem
    $script:MenuToday   = New-InfoItem
    $script:MenuLast    = New-InfoItem

    $script:MenuToggle   = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuEndBreak = New-Object System.Windows.Forms.ToolStripMenuItem "End break now"
    $script:MenuExit     = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    foreach ($item in @($MenuStatus, $MenuNext, $MenuShift, $MenuActions, $MenuToday, $MenuLast)) {
        $menu.Items.Add($item) | Out-Null
    }

    $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
    $menu.Items.Add($MenuToggle) | Out-Null
    $menu.Items.Add($MenuEndBreak) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
    $menu.Items.Add($MenuExit) | Out-Null
    $Tray.ContextMenuStrip = $menu

    $MenuEndBreak.Visible = $false

    $MenuToggle.add_Click({ Switch-Paused })
    $MenuExit.add_Click({ $script:ExitRequested = $true })
    $MenuEndBreak.add_Click({
        $script:BreakUntil = $null
        Write-Log "Break ended from tray."
    })

    $Tray.add_MouseClick({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Switch-Paused
        }
    })
}

function Remove-Tray {
    if ($Tray) {
        $Tray.Visible = $false
        $Tray.Dispose()
    }
}

# NotifyIcon.Text is capped at 63 characters in .NET Framework, but Windows
# allows 127. Set the private field directly so 3 lines fit, and fall back to
# the public property if that ever stops working.
function Set-TrayText {
    param(
        [string]$Text
    )

    if ($Text.Length -gt 127) {
        $Text = $Text.Substring(0, 127)
    }

    try {
        $flags = [System.Reflection.BindingFlags]"NonPublic, Instance"
        $type = [System.Windows.Forms.NotifyIcon]

        $type.GetField("text", $flags).SetValue($Tray, $Text)

        if ($type.GetField("added", $flags).GetValue($Tray)) {
            $type.GetMethod("UpdateIcon", $flags).Invoke($Tray, @($true)) | Out-Null
        }
    }
    catch {
        if ($Text.Length -gt 63) {
            $Text = $Text.Substring(0, 63)
        }
        $Tray.Text = $Text
    }
}

function Get-TodayText {
    return "Today: $($Stats.Done) done, $($Stats.Cancelled) cancelled"
}

# State: one of the keys of $StateColors. Status: one short line.
# Progress: 0-1 for the ring, or -1 for a solid dot. Next: optional menu line.
function Update-Tray {
    param(
        [string]$State,
        [string]$Status,
        [double]$Progress = -1,
        [string]$Next = ""
    )

    $Tray.Icon = Get-StateIcon $State $Progress $IsDryRun

    $title = if ($Paused) { "Cursor Utility: OFF" } else { "Cursor Utility: ON" }
    if ($IsDryRun) {
        $title = "$title (dry run)"
    }

    Set-TrayText "$title`n$Status`n$(Get-TodayText)"

    # Info lines in the right-click menu
    $MenuStatus.Text = $Status
    $MenuNext.Text = $Next
    $MenuNext.Visible = [bool]$Next
    $MenuShift.Text = $ShiftText
    $MenuActions.Text = $ActionsText
    $MenuToday.Text = Get-TodayText

    if ($Stats.LastTime) {
        $MenuLast.Text = "Last cycle: $($Stats.LastTime.ToString('HH:mm:ss')), $($Stats.LastResult)"
    }
    else {
        $MenuLast.Text = "Last cycle: none yet"
    }

    $MenuToggle.Text = if ($Paused) { "Turn ON" } else { "Turn OFF" }
    $MenuEndBreak.Visible = ($null -ne $BreakUntil)
}

function Switch-Paused {

    $script:Paused = -not $Paused
    $script:NextRunAt = $null

    if ($Paused) {
        Write-Log "Turned OFF from tray."
        Update-Tray "paused" "Off. Click the icon to turn on."
    }
    else {
        Write-Log "Turned ON from tray."
        Update-Tray "starting" "Turned on"
    }
}

# Shown by a second copy before it exits, so starting it twice isn't silent
function Show-AlreadyRunningNotice {

    $notice = New-Object System.Windows.Forms.NotifyIcon
    $notice.Icon = Get-StateIcon "starting"
    $notice.Visible = $true
    $notice.ShowBalloonTip(4000, "Cursor Utility", "Already running. Use its tray icon to turn it on or off.", [System.Windows.Forms.ToolTipIcon]::Info)

    Wait-Responsive 4000

    $notice.Visible = $false
    $notice.Dispose()
}

# Sleep while keeping the tray icon responsive. Returns early when Exit is
# clicked, so quitting never waits out a long pause (e.g. the 30 s error wait).
function Wait-Responsive {
    param(
        [int]$Milliseconds
    )

    $start = [MouseApi]::Now()

    while ([MouseApi]::Since($start) -lt $Milliseconds) {
        [System.Windows.Forms.Application]::DoEvents()
        Update-Heartbeat

        if ($ExitRequested) {
            return
        }

        Start-Sleep -Milliseconds 20
    }
}

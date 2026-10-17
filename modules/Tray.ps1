# ============================================================
# Tray icon (on/off button)
# ============================================================

$script:Paused        = $false
$script:ExitRequested = $false

function New-DotIcon {
    param(
        [System.Drawing.Color]$Color
    )

    $bitmap = New-Object System.Drawing.Bitmap 16, 16
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $brush = New-Object System.Drawing.SolidBrush $Color
    $graphics.FillEllipse($brush, 1, 1, 14, 14)
    $graphics.Dispose()
    $brush.Dispose()

    return [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
}

function Initialize-Tray {

    $script:IconOn  = New-DotIcon ([System.Drawing.Color]::LimeGreen)
    $script:IconOff = New-DotIcon ([System.Drawing.Color]::Gray)

    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $Tray.Visible = $true

    $script:MenuToggle = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:MenuExit   = New-Object System.Windows.Forms.ToolStripMenuItem "Exit"

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Items.Add($MenuToggle) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
    $menu.Items.Add($MenuExit) | Out-Null
    $Tray.ContextMenuStrip = $menu

    $MenuToggle.add_Click({ Switch-Paused })
    $MenuExit.add_Click({ $script:ExitRequested = $true })

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

function Update-Tray {
    param(
        [string]$Status
    )

    if ($Paused) {
        $Tray.Icon = $IconOff
        $MenuToggle.Text = "Turn ON"
        $text = "Cursor Utility: OFF"
    }
    else {
        $Tray.Icon = $IconOn
        $MenuToggle.Text = "Turn OFF"
        $text = "Cursor Utility: ON"
    }

    if ($IsDryRun) {
        $text = "$text (dry run)"
    }

    if ($Status) {
        $text = "$text - $Status"
    }

    # Tooltip text is limited to 63 characters
    if ($text.Length -gt 63) {
        $text = $text.Substring(0, 63)
    }

    $Tray.Text = $text
}

function Switch-Paused {

    $script:Paused = -not $Paused
    $script:NextRunAt = $null

    if ($Paused) {
        Write-Log "Turned OFF from tray."
    }
    else {
        Write-Log "Turned ON from tray."
    }

    Update-Tray
}

# Sleep while keeping the tray icon responsive
function Wait-Responsive {
    param(
        [int]$Milliseconds
    )

    $start = [MouseApi]::Now()

    while ([MouseApi]::Since($start) -lt $Milliseconds) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 20
    }
}

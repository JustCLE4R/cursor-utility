# ============================================================
# Debug overlay: red markers where each click will land
# ============================================================

# A small borderless, topmost window per marker. It never takes focus
# and lets clicks pass straight through, so the real click is unaffected.
$OverlaySource = @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class OverlayMarker : Form
{
    const int WS_EX_TOPMOST     = 0x00000008;
    const int WS_EX_TRANSPARENT = 0x00000020;
    const int WS_EX_TOOLWINDOW  = 0x00000080;
    const int WS_EX_LAYERED     = 0x00080000;
    const int WS_EX_NOACTIVATE  = 0x08000000;

    public OverlayMarker(int x, int y, int size)
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        Bounds = new Rectangle(x - size / 2, y - size / 2, size, size);
    }

    protected override bool ShowWithoutActivation
    {
        get { return true; }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE;
            return cp;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        using (Pen pen = new Pen(Color.Red, 3))
        {
            int w = Width - 1;
            int h = Height - 1;
            e.Graphics.DrawEllipse(pen, 2, 2, w - 4, h - 4);
            e.Graphics.DrawLine(pen, w / 2, 0, w / 2, h);
            e.Graphics.DrawLine(pen, 0, h / 2, w, h / 2);
        }
    }
}
"@

$script:OverlayMarkers = @()
$OverlayMarkerSize = 40

# Points: array of @(x, y)
function Show-ClickMarkers {
    param(
        [array]$Points
    )

    # Compile on first use only, so normal runs start faster
    if (-not ("OverlayMarker" -as [type])) {
        # The form only overrides protected members, which Add-Type warns about
        Add-Type -TypeDefinition $OverlaySource -ReferencedAssemblies System.Windows.Forms, System.Drawing -WarningAction SilentlyContinue
    }

    Hide-ClickMarkers

    foreach ($point in $Points) {
        $marker = New-Object OverlayMarker -ArgumentList $point[0], $point[1], $OverlayMarkerSize
        $marker.Show()
        $script:OverlayMarkers += $marker
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Hide-ClickMarkers {

    foreach ($marker in $OverlayMarkers) {
        $marker.Close()
        $marker.Dispose()
    }

    $script:OverlayMarkers = @()
}

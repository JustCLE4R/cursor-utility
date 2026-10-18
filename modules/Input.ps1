# ============================================================
# Win32 mouse / input API
# ============================================================

Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class MouseApi
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;

    // Bounding box of all monitors
    public const int SM_XVIRTUALSCREEN  = 76;
    public const int SM_YVIRTUALSCREEN  = 77;
    public const int SM_CXVIRTUALSCREEN = 78;
    public const int SM_CYVIRTUALSCREEN = 79;
    public const int SM_CMONITORS       = 80;

    public const uint MOUSEEVENTF_LEFTDOWN   = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP     = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN  = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP    = 0x0010;
    public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    public const uint MOUSEEVENTF_MIDDLEUP   = 0x0040;

    const uint MOUSEEVENTF_WHEEL     = 0x0800;
    const uint MOUSEEVENTF_HWHEEL    = 0x1000;
    const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    const uint KEYEVENTF_KEYUP       = 0x0002;
    const byte VK_MENU               = 0x12;
    const int  SW_RESTORE            = 9;

    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    static extern int GetWindowTextLength(IntPtr hWnd);

    // Wheel notches: delta is +/-120 per notch. Up and right are positive.
    public static void Wheel(bool horizontal, int delta)
    {
        mouse_event(horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL, 0, 0, unchecked((uint)delta), UIntPtr.Zero);
    }

    public static void Key(byte vk, bool extended, bool up)
    {
        uint flags = (extended ? KEYEVENTF_EXTENDEDKEY : 0) | (up ? KEYEVENTF_KEYUP : 0);
        keybd_event(vk, (byte)MapVirtualKey(vk, 0), flags, UIntPtr.Zero);
    }

    public static IntPtr GetForeground()
    {
        return GetForegroundWindow();
    }

    public static string GetWindowTitle(IntPtr hWnd)
    {
        StringBuilder title = new StringBuilder(512);
        GetWindowText(hWnd, title, title.Capacity);
        return title.ToString();
    }

    // A visible window whose process name equals text (e.g. "notepad"),
    // otherwise the first whose title contains it. Case-insensitive.
    public static IntPtr FindWindowByText(string text)
    {
        IntPtr byProcess = IntPtr.Zero;
        IntPtr byTitle = IntPtr.Zero;

        EnumWindows(delegate (IntPtr hWnd, IntPtr lParam)
        {
            if (!IsWindowVisible(hWnd) || GetWindowTextLength(hWnd) == 0)
            {
                return true;
            }

            if (byTitle == IntPtr.Zero && GetWindowTitle(hWnd).IndexOf(text, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                byTitle = hWnd;
            }

            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);

            try
            {
                if (String.Equals(Process.GetProcessById((int)processId).ProcessName, text, StringComparison.OrdinalIgnoreCase))
                {
                    byProcess = hWnd;
                    return false;
                }
            }
            catch (ArgumentException)
            {
                // The process exited while we were looking
            }

            return true;
        }, IntPtr.Zero);

        return byProcess != IntPtr.Zero ? byProcess : byTitle;
    }

    // Brings a window to the front, restoring it if minimized.
    public static bool FocusWindow(IntPtr hWnd)
    {
        if (!IsWindow(hWnd))
        {
            return false;
        }

        if (IsIconic(hWnd))
        {
            ShowWindow(hWnd, SW_RESTORE);
        }

        if (SetForegroundWindow(hWnd))
        {
            return true;
        }

        // Windows only lets the process that sent the latest input change the
        // foreground window. A quick Alt tap makes that us.
        Key(VK_MENU, false, false);
        Key(VK_MENU, false, true);

        return SetForegroundWindow(hWnd) || GetForegroundWindow() == hWnd;
    }

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    // 0 on success, otherwise the Win32 error code. Windows can refuse the move,
    // e.g. when an elevated (admin) window is in front of a non-elevated script.
    public static int TrySetCursorPos(int x, int y)
    {
        if (SetCursorPos(x, y))
        {
            return 0;
        }

        int error = Marshal.GetLastWin32Error();
        return error == 0 ? -1 : error;
    }

    // 'Title' (pid N) of the foreground window, for log messages
    public static string DescribeForegroundWindow()
    {
        IntPtr hWnd = GetForegroundWindow();

        if (hWnd == IntPtr.Zero)
        {
            return "none";
        }

        StringBuilder title = new StringBuilder(256);
        GetWindowText(hWnd, title, title.Capacity);

        uint processId;
        GetWindowThreadProcessId(hWnd, out processId);

        return String.Format("'{0}' (pid {1})", title, processId);
    }

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    // Tick (ms since boot) of the last keyboard/mouse input, from any source
    public static uint GetLastInputTick()
    {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        GetLastInputInfo(ref info);
        return info.dwTime;
    }

    public static uint Now()
    {
        return unchecked((uint)Environment.TickCount);
    }

    // Milliseconds elapsed since a tick (wrap-safe)
    public static uint Since(uint tick)
    {
        return unchecked(Now() - tick);
    }

    // True if tick a is later than tick b (wrap-safe)
    public static bool IsAfter(uint a, uint b)
    {
        return unchecked((int)(a - b)) > 0;
    }
}
"@

# Use real pixel coordinates so (0,0) and the bottom edge are the true corners
# even with display scaling enabled.
[MouseApi]::SetProcessDPIAware() | Out-Null

# ============================================================
# User activity detection
# ============================================================

# Our own clicks also count as "input" to Windows, so any input that
# happened before $IgnoreInputBefore (the end of our last action) is ours.
$script:LastUserInput     = [MouseApi]::Now()
$script:IgnoreInputBefore = [MouseApi]::Now()
$script:InAction          = $false

function Update-UserActivity {

    if ($InAction) {
        return
    }

    $lastInput = [MouseApi]::GetLastInputTick()

    if ([MouseApi]::IsAfter($lastInput, $IgnoreInputBefore) -and
        [MouseApi]::IsAfter($lastInput, $LastUserInput)) {

        $script:LastUserInput = $lastInput
    }
}

function Get-UserIdleSeconds {
    return [int]([MouseApi]::Since($LastUserInput) / 1000)
}

# ============================================================
# Cursor movement and clicks
# ============================================================

function Get-CursorPosition {

    $point = New-Object MouseApi+POINT

    if (-not [MouseApi]::GetCursorPos([ref]$point)) {
        throw "GetCursorPos failed."
    }

    return $point
}

# Sets the cursor and remembers where we put it, so a user move can be spotted.
# Throws "CursorBlocked" if Windows refuses, so it isn't mistaken for the user.
function Set-Cursor {
    param(
        [int]$X,
        [int]$Y
    )

    $code = [MouseApi]::TrySetCursorPos($X, $Y)

    if ($code -ne 0) {
        $script:InterruptDetail = "Windows error $code moving to ($X,$Y), foreground window $([MouseApi]::DescribeForegroundWindow())"
        throw "CursorBlocked"
    }

    $script:ExpectedX = $X
    $script:ExpectedY = $Y
}

# Throws if the user moved the mouse or turned the script off mid-action
function Assert-NotInterrupted {

    [System.Windows.Forms.Application]::DoEvents()

    if ($Paused -or $ExitRequested) {
        throw "Interrupted"
    }

    # Checked before the position: a resolution change moves the cursor too
    if ($CycleDisplay) {
        $display = Get-DisplaySignature
        if ($display -ne $CycleDisplay) {
            $script:InterruptDetail = "now $display"
            throw "DisplayChanged"
        }
    }

    $pos = Get-CursorPosition

    if ([Math]::Abs($pos.X - $ExpectedX) -gt 2 -or [Math]::Abs($pos.Y - $ExpectedY) -gt 2) {
        $script:InterruptDetail = "expected ($ExpectedX,$ExpectedY), cursor at ($($pos.X),$($pos.Y)), foreground window $([MouseApi]::DescribeForegroundWindow())"
        throw "UserMoved"
    }
}

function Wait-Action {
    param(
        [int]$Milliseconds
    )

    $start = [MouseApi]::Now()

    while ([MouseApi]::Since($start) -lt $Milliseconds) {
        Assert-NotInterrupted
        Update-Heartbeat
        Start-Sleep -Milliseconds 15
    }
}

# Moves the cursor along a slightly curved, eased path instead of teleporting.
# In dry-run mode the cursor stays put, so a real user move is still detected.
function Move-CursorTo {
    param(
        [int]$X,
        [int]$Y
    )

    if ($IsDryRun) {
        return
    }

    # Windows keeps the cursor on the desktop and would pull it back from
    # anywhere outside, which looks like a user move. So the target and
    # every point on the way stay inside.
    $desktop = Get-DesktopBounds
    $X = [Math]::Max($desktop.MinX, [Math]::Min($desktop.MaxX, $X))
    $Y = [Math]::Max($desktop.MinY, [Math]::Min($desktop.MaxY, $Y))

    if (-not $SmoothMove) {
        Set-Cursor $X $Y
        return
    }

    $start = Get-CursorPosition

    $distance = [Math]::Sqrt([Math]::Pow($X - $start.X, 2) + [Math]::Pow($Y - $start.Y, 2))

    # Longer distance takes longer, with some variation
    $durationMs = Get-NaturalRandom (200 + $distance * 0.25) (450 + $distance * 0.45)
    $steps = [Math]::Max(10, [int]($durationMs / 10))

    # Random control point for a gentle curve (quadratic Bezier)
    $bend = $distance * 0.15
    $ctrlX = ($start.X + $X) / 2 + ($Random.NextDouble() * 2 - 1) * $bend
    $ctrlY = ($start.Y + $Y) / 2 + ($Random.NextDouble() * 2 - 1) * $bend

    for ($i = 1; $i -le $steps; $i++) {

        $t = $i / $steps

        # Ease in-out: slow start, fast middle, slow finish
        $e = if ($t -lt 0.5) { 2 * $t * $t } else { 1 - [Math]::Pow(-2 * $t + 2, 2) / 2 }

        $px = [Math]::Pow(1 - $e, 2) * $start.X + 2 * (1 - $e) * $e * $ctrlX + [Math]::Pow($e, 2) * $X
        $py = [Math]::Pow(1 - $e, 2) * $start.Y + 2 * (1 - $e) * $e * $ctrlY + [Math]::Pow($e, 2) * $Y

        # The curve can bulge past an edge when the target is a corner
        $px = [Math]::Max($desktop.MinX, [Math]::Min($desktop.MaxX, $px))
        $py = [Math]::Max($desktop.MinY, [Math]::Min($desktop.MaxY, $py))

        Set-Cursor ([int]$px) ([int]$py)

        Wait-Action ([int]($durationMs / $steps))
    }

    # Land exactly on target
    Set-Cursor $X $Y
}

function Send-MouseButton {
    param(
        [uint32]$Down,
        [uint32]$Up,
        [int]$HoldMin = 60,
        [int]$HoldMax = 140
    )

    [MouseApi]::mouse_event($Down, 0, 0, 0, [UIntPtr]::Zero)

    # Human click hold time
    Start-Sleep -Milliseconds (Get-NaturalRandom $HoldMin $HoldMax)

    [MouseApi]::mouse_event($Up, 0, 0, 0, [UIntPtr]::Zero)
}

# Type: left, right, middle or double (two quick left clicks)
function Invoke-MouseClick {
    param(
        [string]$Type = "left"
    )

    if ($IsDryRun) {
        return
    }

    $leftDown = [MouseApi]::MOUSEEVENTF_LEFTDOWN
    $leftUp   = [MouseApi]::MOUSEEVENTF_LEFTUP

    if ($Type -eq "right") {
        Send-MouseButton ([MouseApi]::MOUSEEVENTF_RIGHTDOWN) ([MouseApi]::MOUSEEVENTF_RIGHTUP)
    }
    elseif ($Type -eq "middle") {
        Send-MouseButton ([MouseApi]::MOUSEEVENTF_MIDDLEDOWN) ([MouseApi]::MOUSEEVENTF_MIDDLEUP)
    }
    elseif ($Type -eq "double") {
        # Short holds and gap, to stay well inside the double-click time
        Send-MouseButton $leftDown $leftUp 40 90
        Start-Sleep -Milliseconds (Get-NaturalRandom 60 120)
        Send-MouseButton $leftDown $leftUp 40 90
    }
    else {
        Send-MouseButton $leftDown $leftUp
    }
}

# One wheel notch: up, down, left or right
function Invoke-Scroll {
    param(
        [string]$Direction
    )

    if ($IsDryRun) {
        return
    }

    $horizontal = ($Direction -eq "left" -or $Direction -eq "right")
    $delta = if ($Direction -eq "up" -or $Direction -eq "right") { 120 } else { -120 }

    [MouseApi]::Wheel($horizontal, $delta)
}

# Presses keys in order, holds briefly, releases in reverse (like a person
# pressing Ctrl+Shift+F15). Keys come from ConvertTo-KeyCombo.
function Invoke-KeyCombo {
    param(
        [array]$Keys
    )

    if ($IsDryRun) {
        return
    }

    foreach ($key in $Keys) {
        [MouseApi]::Key([byte]$key.Code, [bool]$key.Extended, $false)
        Start-Sleep -Milliseconds (Get-NaturalRandom 20 60)
    }

    Start-Sleep -Milliseconds (Get-NaturalRandom 50 120)

    for ($i = $Keys.Count - 1; $i -ge 0; $i--) {
        [MouseApi]::Key([byte]$Keys[$i].Code, [bool]$Keys[$i].Extended, $true)
        Start-Sleep -Milliseconds (Get-NaturalRandom 10 40)
    }
}

# ============================================================
# Display
# ============================================================

# Size of the primary monitor; action coordinates are relative to it
function Get-ScreenSize {
    return @{
        Width  = [MouseApi]::GetSystemMetrics([MouseApi]::SM_CXSCREEN)
        Height = [MouseApi]::GetSystemMetrics([MouseApi]::SM_CYSCREEN)
    }
}

# Bounding box of all monitors, in pixels (inclusive)
function Get-DesktopBounds {
    $minX = [MouseApi]::GetSystemMetrics([MouseApi]::SM_XVIRTUALSCREEN)
    $minY = [MouseApi]::GetSystemMetrics([MouseApi]::SM_YVIRTUALSCREEN)

    return @{
        MinX = $minX
        MinY = $minY
        MaxX = $minX + [MouseApi]::GetSystemMetrics([MouseApi]::SM_CXVIRTUALSCREEN) - 1
        MaxY = $minY + [MouseApi]::GetSystemMetrics([MouseApi]::SM_CYVIRTUALSCREEN) - 1
    }
}

# Short text that changes whenever resolution, layout or monitor count changes
function Get-DisplaySignature {
    $size = Get-ScreenSize
    $desktop = Get-DesktopBounds
    $monitors = [MouseApi]::GetSystemMetrics([MouseApi]::SM_CMONITORS)

    return "{0}x{1} primary, {2} monitor(s), desktop {3},{4} to {5},{6}" -f
        $size.Width, $size.Height, $monitors, $desktop.MinX, $desktop.MinY, $desktop.MaxX, $desktop.MaxY
}

# Set while a cycle runs, so Assert-NotInterrupted can spot a display change
$script:CycleDisplay = $null

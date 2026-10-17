# ============================================================
# Win32 mouse / input API
# ============================================================

Add-Type @"
using System;
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

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP   = 0x0004;

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

    # The curve can bulge past a screen edge when the target is a corner.
    # Windows would pull the cursor back onto the screen, which looks like
    # a user move, so keep every point on screen.
    $minX = [MouseApi]::GetSystemMetrics([MouseApi]::SM_XVIRTUALSCREEN)
    $minY = [MouseApi]::GetSystemMetrics([MouseApi]::SM_YVIRTUALSCREEN)
    $maxX = $minX + [MouseApi]::GetSystemMetrics([MouseApi]::SM_CXVIRTUALSCREEN) - 1
    $maxY = $minY + [MouseApi]::GetSystemMetrics([MouseApi]::SM_CYVIRTUALSCREEN) - 1

    for ($i = 1; $i -le $steps; $i++) {

        $t = $i / $steps

        # Ease in-out: slow start, fast middle, slow finish
        $e = if ($t -lt 0.5) { 2 * $t * $t } else { 1 - [Math]::Pow(-2 * $t + 2, 2) / 2 }

        $px = [Math]::Pow(1 - $e, 2) * $start.X + 2 * (1 - $e) * $e * $ctrlX + [Math]::Pow($e, 2) * $X
        $py = [Math]::Pow(1 - $e, 2) * $start.Y + 2 * (1 - $e) * $e * $ctrlY + [Math]::Pow($e, 2) * $Y

        $px = [Math]::Max($minX, [Math]::Min($maxX, $px))
        $py = [Math]::Max($minY, [Math]::Min($maxY, $py))

        Set-Cursor ([int]$px) ([int]$py)

        Wait-Action ([int]($durationMs / $steps))
    }

    # Land exactly on target
    Set-Cursor $X $Y
}

function Invoke-LeftClick {

    if ($IsDryRun) {
        return
    }

    [MouseApi]::mouse_event([MouseApi]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)

    # Human click hold time
    Start-Sleep -Milliseconds (Get-NaturalRandom 60 140)

    [MouseApi]::mouse_event([MouseApi]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

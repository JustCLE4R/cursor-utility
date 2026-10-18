# Cursor Utility: Feature Ideas

Everything that could be added to Cursor Utility, grouped by area.
⭐ = recommended first.

## Top picks

1. Hotkey on/off toggle
2. Pause when the screen is locked
3. Safe-click check (stops accidental Start/Widgets clicks)
4. Days-of-week schedule
5. Keep-awake via `SetThreadExecutionState`

## Control and tray

- [ ] ⭐ **Global hotkey** to turn it on/off (e.g. `Ctrl+Alt+P`) without touching the tray
- [ ] ⭐ **Remember on/off state** across restarts
- [ ] **Pause for a set time** from the tray menu: 15 min / 30 min / 1 h / 2 h / until tomorrow
- [ ] **"Run now"** menu item: fire one cycle immediately for testing
- [ ] **Auto-resume** after a timed pause
- [ ] **Double-click the tray icon** to open settings
- [ ] **Tray menu shortcuts:** open config, open log, reload config, open folder
- [x] **More icon states:** green running, yellow waiting for idle, blue outside schedule, gray off
- [x] **Countdown on the icon:** seconds until the next click (as a ring that fills, plus the tooltip)
- [x] **Single instance:** block a second copy from launching
- [ ] **Restart** from the tray

## Settings window

- [ ] ⭐ **Settings GUI** (WinForms): sliders and checkboxes instead of editing `config.ini`
- [ ] **Live preview** of click positions on screen
- [ ] **Validation messages** for wrong values (e.g. bad time format)
- [ ] **Reset to defaults** button
- [ ] **Profiles:** Work, Night shift, Meeting, each with its own settings

## Actions

- [x] ⭐ **Custom point list:** any number of points with x, y and action, instead of fixed corners
- [x] **Click types:** left, right, middle, double-click, or move only
- [x] **Key presses:** Shift, F15, Scroll Lock or any key, instead of or as well as clicks
- [x] **Scroll wheel** up/down
- [ ] **Random order** of points each cycle
- [ ] **Random offset** of a few pixels around each point
- [ ] **Skip a click sometimes** (e.g. 10% of cycles do nothing)
- [ ] **Monitor selection:** primary, a specific monitor, or the whole virtual desktop
- [ ] **Window-relative points** (e.g. "click inside app X")
- [x] **Focus a window** before clicking, then restore the previous one
- [ ] **Safe-click check:** look at what is under the cursor (Start, Widgets, a close button) and skip if risky
- [ ] **Press Esc after clicking** to close any menu the click opened
- [ ] **Macro recorder:** record a mouse/keyboard sequence and replay it

## Timing and natural behaviour

- [ ] **Time-of-day patterns:** less activity at lunch, more in the morning
- [x] **Occasional long breaks**, like a person getting coffee
- [ ] **Per-session speed variation**
- [ ] **Overshoot and correction** at the end of a movement
- [ ] **Tiny jitter** during movement
- [ ] **More random** click hold and double-click timing
- [ ] **Per-point delays**, configurable for each point

## Idle and presence detection

- [ ] ⭐ **Pause when the screen is locked** (Win+L) or the PC is going to sleep
- [ ] ⭐ **Pause in fullscreen apps:** games, presentations, videos
- [ ] **App blacklist:** pause when specific apps are focused
- [ ] **App whitelist:** only run while specific apps are open (e.g. Teams, Slack)
- [ ] **Meeting detection:** mic or camera in use, or a Teams/Zoom call window
- [ ] **Separate idle times** for keyboard and mouse
- [ ] **Low-level keyboard hook:** typing cancels a cycle instantly
- [ ] **Pause on remote desktop** or a disconnected session
- [ ] **Pause on battery** or below X% battery

## Schedule

- [ ] ⭐ **Days of the week:** work days only, or weekends off
- [ ] **Holiday list** of dates to skip (incl. Indonesian national holidays)
- [ ] **Any number of shifts** instead of the fixed subuh, pagi and malam
- [ ] **Overlap warning** when shifts overlap
- [ ] **Rotating shifts:** week A morning, week B night
- [ ] **Timed auto-stop:** "run for the next 3 hours, then stop"
- [ ] **Calendar sync:** pause during Outlook/Google Calendar events

## Keep-awake

- [ ] ⭐ **Prevent sleep and screen-off** with `SetThreadExecutionState`, no mouse movement needed
- [ ] **Prevent sleep only**, screen can still turn off
- [ ] **Restore** the normal power state on exit

## Logging and stats

- [ ] **Daily log files** (`2026-10-18.log`) with automatic deletion after N days
- [ ] **Log levels:** quiet, normal, debug
- [ ] **Stats:** clicks today, active time, idle time, cycles cancelled
- [ ] **HTML report** with activity charts per hour and per day
- [ ] **CSV export**
- [ ] **Last action time** shown in the tray tooltip

## Notifications (optional, off by default)

- [ ] **Sound** on start, stop or error
- [ ] **Toast** on errors only
- [ ] **Telegram, Discord or email message** on stop or crash
- [ ] **Daily summary message**

## Reliability

- [ ] **Watchdog:** auto-restart after a crash
- [ ] **Scheduled task** at logon instead of the Startup folder
- [x] **Display change handling:** re-read the screen size when monitors or resolution change
- [ ] **Per-monitor DPI** (`SetProcessDpiAwarenessContext`) for mixed scaling
- [ ] **`SendInput`** instead of the legacy `mouse_event`
- [ ] **Config backup** and recovery if `config.ini` is corrupted
- [ ] **Self-test command:** check APIs, screen size and config, then exit
- [ ] **Graceful shutdown** on logoff or shutdown

## Packaging and setup

- [ ] **Single `.exe`** (ps2exe or a C# rewrite): no PowerShell, no `.vbs`
- [ ] **Installer/uninstaller:** shortcut, startup entry, clean removal
- [ ] **Custom app icon**
- [ ] **Auto-update** from GitHub releases
- [ ] **Portable mode:** everything in one folder
- [x] **README** with usage and config docs
- [ ] **Git repo** for version history

## Code quality

- [x] **Split into modules:** config, input, schedule, tray, actions
- [x] **Pester unit tests** for the schedule, INI parsing and random helpers
- [x] **Dry-run mode:** log actions without moving or clicking
- [x] **Debug overlay:** draw markers where it will click
- [x] **Generate a commented config** automatically when missing
- [x] **Command-line options:** `-RunOnce`, `-DryRun`, `-Config <path>`

## Safety

- [ ] **Emergency stop:** slam the mouse into a corner, or press a key, to kill it instantly
- [ ] **Click cap** per hour
- [ ] **Never click** Start, Widgets or a window's close/system menu
- [ ] **Skip elevated (admin) windows**, where clicks can fail or behave oddly

# Cursor Utility: Known Problems

Problems found in the code and the log. Ordered by impact.
Last checked 2026-10-18, after the code was split into modules.

## 1. Bottom-left click hits the Start button

- **Where:** `modules/Actions.ps1`, `Invoke-CornerClicks` (the clicks at lines 36–48)
- **What happens:** on a default Windows 10 taskbar, (0, 1079) is the Start button, so every cycle (in any `click.order`) probably opens the Start menu and leaves it open. The top-left click at (0, 0) can hit a maximized window's system menu or File menu.
- **Fix options:**
  - Click safer points, or move without clicking
  - Check what is under the cursor before clicking (see the safe-click idea in `ideas.md`)
  - Press Esc after clicking
  - Replace clicking with keep-awake via `SetThreadExecutionState`

## 2. Typing during a cycle is ignored

- **Where:** `modules/Actions.ps1`, the `finally` block (line 61)
- **What happens:** after each cycle, `IgnoreInputBefore` is set to the current time, so any input during the 3–5 second action counts as the script's own. Mouse movement cancels the cycle (`UserMoved`), but keystrokes don't. The script carries on as if you were still idle and clicks again on the next cycle.
- **Fix:** set `IgnoreInputBefore` right after each synthetic move or click instead of at the end of the cycle, and check `GetLastInputInfo` inside `Assert-NotInterrupted` (`modules/Input.ps1` line 187). Or use a low-level keyboard hook.

## 3. Exit can lag by up to 30 seconds after an error

- **Where:** `cursor-utility.ps1` line 179 (`Wait-Responsive 30000`); `Wait-Responsive` is in `modules/Tray.ps1` line 106
- **What happens:** `Wait-Responsive` doesn't check `ExitRequested`, so after any error, clicking Exit in the tray does nothing for up to 30 seconds.
- **Fix:** make `Wait-Responsive` return early when `$ExitRequested` is set.

## 4. Cursor left in a corner when paused or exited mid-cycle

- **Where:** `modules/Actions.ps1`, the `Interrupted` path (line 54)
- **What happens:** turning the utility off or exiting during a cycle stops it immediately and skips moving the cursor back. This also applies to `-RunOnce`. It doesn't happen with `-DryRun`, because the cursor never moves.
- **Fix:** on `Interrupted` (not `UserMoved`), move the cursor back to `$original` when `return_after_move=true`.

## 5. Config reading is fragile

- **Where:** `Read-Ini` in `modules/Config.ps1` (line 5), `Convert-ToMinutes` in `modules/Schedule.ps1` (line 12), the first `Import-Settings` call in `cursor-utility.ps1` (line 68)
- **What happens:**
  - The config is read every second. If an editor is saving it at the same moment, `Get-Content` can fail. The log shows this once: `[2026-10-17 20:21:05] ERROR: Stream was not readable.`
  - An invalid time such as `24:00`, `8.30` or an empty value makes `TimeSpan.Parse` throw. Every loop tick then fails and waits 30 seconds. The tests confirm this: `Schedule.Tests.ps1` "throws on an invalid shift time".
  - **At startup** the first `Import-Settings` runs outside any `try`. If it fails there, the hidden process exits with no tray icon, no message box and no log line, because logging isn't set up yet.
- **Fix:**
  - Retry the read, or keep the last good settings when it fails
  - Parse times with `TryParseExact("hh\:mm")`, log a warning once and fall back to the default
  - Wrap the startup read and show a message box when it fails

## 6. Only the primary monitor, and no single-instance guard

- **Where:** `modules/Actions.ps1` line 13 (`SM_CYSCREEN`); startup in `cursor-utility.ps1`
- **What happens:**
  - The corners are worked out from the primary monitor only.
  - Running `run.bat` twice starts two copies that click independently, with two tray icons. The copies can also use different `-Config` files.
- **Fix:**
  - Use a named mutex at startup to block a second copy (decide whether `-RunOnce` should bypass it)
  - Make the monitor configurable (see the monitor selection idea in `ideas.md`)

## Minor

- **Wrong file name in a log message:** `cursor-utility.ps1` line 131 logs "Disabled in config.ini." even when `-Config` points at a different file. Fix: use `$ConfigFile`.
- **`Get-NaturalRandom` can round outside its range** with non-integer bounds. It clamps to `[Min, Max]` and then rounds, so `Get-NaturalRandom 0 0.6` can return 1 (`modules/Random.ps1` line 25). Only `Move-CursorTo` passes fractional bounds, for its movement duration, so the effect is harmless. Fix: clamp after rounding, to `[ceil(Min), floor(Max)]`.
- **The overlay compiles on first use:** `modules/Overlay.ps1` line 71 runs inside the cycle's `try`. If compiling the C# ever fails, every cycle errors and no clicks happen while the overlay is on.

## Log observations

- From 2026-09-23 to the refactor on 2026-10-18 there were 15 starts and only 7 completed click cycles, all on 2026-10-17. Six of those ran under an older version of the script, which logged "Active schedule. Waiting N seconds". Only one cycle (20:22) ran under the single-file code.
- Many sessions log "User idle. Running." and then "User active" about 30–50 seconds later with no click in between. The interval had already been picked, so the idle check reset the countdown before the click came. This is either real use or another program sending input.
- Lines tagged `[dry-run]` from 2026-10-18 01:38 onward come from smoke tests, not real clicks.
- Up to 2026-10-18 02:09, "User moved the mouse. Cycle cancelled." lines are often false alarms. The curved path to a corner could bulge 1–3 px off-screen, Windows pulled the cursor back onto the screen, and the 2 px check took that for the user. The logs show it, e.g. `expected (-3,15), cursor at (0,15)`. Fixed on 2026-10-18 by keeping every path point on screen (`Move-CursorTo` in `modules/Input.ps1`).

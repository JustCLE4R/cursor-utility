# Architecture

## Load order

`cursor-utility.ps1` loads the WinForms and Drawing assemblies, then dot-sources the modules in this order:

| # | Module | Needs at call time | Side effects when loaded |
|---|---|---|---|
| 1 | `Log.ps1` | `$LogDir`, `$LogFile`, `$LogMaxBytes`, `$LogEnabled` | none |
| 2 | `Config.ps1` | `$DryRun`, `$Overlay` (optional) | defines `$DefaultConfigText` |
| 3 | `Random.ps1` | none | creates `$Random` |
| 4 | `Schedule.ps1` | `Get-IniBool` and `Get-IniValue` from Config | defines `$DefaultShifts` |
| 5 | `Input.ps1` | WinForms, `$Random`, `Get-NaturalRandom`, `$Paused`, `$ExitRequested`, `$IsDryRun`, `$SmoothMove` | compiles `MouseApi`, calls `SetProcessDPIAware`, sets the idle-detection state |
| 6 | `Tray.ps1` | `MouseApi`, `Write-Log` | sets `$Paused` and `$ExitRequested` (the icon is created later by `Initialize-Tray`) |
| 7 | `Overlay.ps1` | WinForms | none (the C# type is compiled on first `Show-ClickMarkers`) |
| 8 | `Actions.ps1` | everything above | none |

Because the modules are dot-sourced, functions find each other's variables at call time through PowerShell's dynamic scoping. The load order only matters for side effects that happen at load time.

## Shared state

Everything lives in the entry script's scope. Write it as `$script:X = ...` inside functions.

| Variable | Owner | Meaning |
|---|---|---|
| `$ConfigFile` | entry | full path of the config in use |
| `$DryRun`, `$RunOnce`, `$Overlay` | entry (params) | raw command-line switches |
| `$Ini` | Config | parsed config hashtable, keys `section.key` |
| `$Enabled`, `$LogEnabled` | Config | `[general]` |
| `$MinInterval`, `$MaxInterval`, `$IdleSeconds`, `$ReturnAfterMove`, `$SmoothMove` | Config | `[activity]`, already validated |
| `$CornerDelayMin`, `$CornerDelayMax` | Config | `[click]` |
| `$IsDryRun`, `$ShowOverlay` | Config | switch OR `[debug]` setting; **use these, not `$DryRun`/`$Overlay`** |
| `$LastUserInput` | Input | tick of the last input the user made themselves |
| `$IgnoreInputBefore` | Input | input before this tick counts as the script's own |
| `$InAction` | Input | true while a cycle is running |
| `$ExpectedX`, `$ExpectedY` | Input | where the script last put the cursor |
| `$Paused`, `$ExitRequested` | Tray | set from tray clicks while `DoEvents` runs |
| `$Tray`, `$MenuToggle`, `$IconOn`, `$IconOff` | Tray | UI objects |
| `$NextRunAt` | entry | `[datetime]` of the next cycle, or `$null` |
| `$state` | entry | last logged state, used by `Set-State` |

## Main loop

The loop ticks once a second, using `Wait-Responsive 1000` so the tray stays responsive.

```
reload config -> update idle tracking
  disabled in config?         -> log, exit
  paused from tray?           -> state "paused"
  outside every shift?        -> state "schedule", clear NextRunAt
  idle < idle_seconds?        -> state "user", clear NextRunAt
  NextRunAt not set?          -> pick a random interval, state "idle"
  NextRunAt in the future?    -> update the tooltip countdown
  otherwise                   -> Invoke-CornerClicks, clear NextRunAt
any exception -> log "ERROR: ...", wait 30 s
```

With `-RunOnce`, the loop is skipped: one `Invoke-CornerClicks` runs, then the script exits.

## One cycle (`Invoke-CornerClicks`)

1. Remember the cursor position. Pick the corner order from `$ClickOrder`: top-left (0, 0) then bottom-left (0, screen height − 1), or the reverse. `random` flips a coin each cycle. Set `$InAction`, and show the overlay markers if `$ShowOverlay` is set.
2. Move to the first corner, wait 80–250 ms, click.
3. Wait `corner_delay_min_ms`–`corner_delay_max_ms`.
4. Move to the second corner, wait, click.
5. If `return_after_move` is on, move back to the remembered position.
6. `finally`: hide the markers, clear `$InAction`, set `$IgnoreInputBefore = now`.

Every wait goes through `Wait-Action`, which calls `Assert-NotInterrupted`:
- If the tray was turned off or Exit was clicked, it throws `"Interrupted"`. The cycle stops silently.
- If the cursor is more than 2 px from `$ExpectedX`/`$ExpectedY`, it throws `"UserMoved"`. The script logs the expected and actual position and the foreground window, and treats the user as active.
- If `SetCursorPos` fails (called from `Set-Cursor`), it throws `"CursorBlocked"`. The script logs the Win32 error and the foreground window, and leaves the idle timer alone. UIPI causes this when an elevated window is in front of a non-elevated script.

`$InterruptDetail` holds the text for these log lines.
- Any other exception goes up to the main loop's error handler.

**Dry run:** `Move-CursorTo` and `Invoke-LeftClick` return early, so `$ExpectedX`/`$ExpectedY` stay at the starting position. The timing is the same, and a real mouse move still cancels the cycle.

## Idle detection

Windows' `GetLastInputInfo` also reports the script's own synthetic input. A new last-input tick counts as the user's only if it's later than both `$IgnoreInputBefore` (the end of the last cycle) and `$LastUserInput`. `Update-UserActivity` is skipped while `$InAction` is set. Limitation: keyboard input during a cycle is treated as the script's own (`problems.md` #2).

Tick maths uses `MouseApi.Now/Since/IsAfter`, which handle the 49.7-day `TickCount` wrap. Use these, not plain subtraction.

## Win32 and WinForms notes

- **DPI:** `SetProcessDPIAware()` runs at load time, so all coordinates are physical pixels. The overlay forms rely on this.
- **Screen size:** only the primary monitor is used (`SM_CYSCREEN`).
- **Clicks:** use the legacy `mouse_event`. `SendInput` is on the backlog.
- **Thread:** the process must be STA. `run.vbs` passes `-STA`; PowerShell 5.1 consoles are STA by default.
- **Overlay:** `OverlayMarker` is a borderless `Form` with `WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_NOACTIVATE`, so clicks pass through and it never takes focus. Magenta is the transparency key.

## Adding a module

1. Create `modules/<Name>.ps1` with a `# ===` banner. Put only definitions at the top level, plus side effects that can't wait.
2. Dot-source it in `cursor-utility.ps1`, after everything it needs at load time.
3. If it has pure logic, keep that in functions that take parameters, and add `tests/<Name>.Tests.ps1`.
4. Update the layout in `AGENTS.md` and the tables above.

# Architecture

## Load order

`cursor-utility.ps1` loads the WinForms and Drawing assemblies, then dot-sources the modules in this order:

| # | Module | Pure? | Needs at call time | Side effects when loaded |
|---|---|---|---|---|
| 1 | `Log.ps1` | — | `$LogDir`, `$LogFile`, `$LogMaxBytes`, `$LogEnabled` | none |
| 2 | `Config.ps1` | yes | `$DryRun`, `$Overlay` (optional) | defines `$DefaultConfigText` |
| 3 | `Random.ps1` | yes | none | creates `$Random` |
| 4 | `Schedule.ps1` | yes | `Get-IniBool` and `Get-IniValue` from Config | defines `$DefaultShifts` |
| 5 | `ActionScript.ps1` | yes | none | defines the key tables (`$KeyCodes`, `$KeyAliases`, `$ExtendedKeys`) |
| 6 | `Input.ps1` | no | WinForms, `$Random`, `Get-NaturalRandom`, `$Paused`, `$ExitRequested`, `$IsDryRun`, `$SmoothMove` | compiles `MouseApi`, calls `SetProcessDPIAware`, sets the idle-detection state |
| 7 | `Tray.ps1` | no | `MouseApi`, `Write-Log`, the status variables below | sets `$Paused`, `$ExitRequested` and the icon colours (the icon is created later by `Initialize-Tray`) |
| 8 | `Overlay.ps1` | no | WinForms | none (the C# type is compiled on first `Show-ClickMarkers`) |
| 9 | `Actions.ps1` | no | everything above | sets the action-file state |

**Pure** modules load without WinForms, Win32 or the tray, so the tests dot-source them directly.

Because the modules are dot-sourced, functions find each other's variables at call time through PowerShell's dynamic scoping. The load order only matters for side effects that happen at load time.

## Startup

1. Resolve `-Config`, creating the file if it's missing. Run `Import-Settings`, and exit if `enabled=false`.
2. **Single instance:** take the named mutex `Local\CursorUtility`.
   - If another copy holds it and this run is neither a dry run nor `-RunOnce`, log, show a 4-second tray balloon (`Show-AlreadyRunningNotice`) and exit.
   - Dry runs and `-RunOnce` may run next to a copy that's already going, so the smoke tests work.
   - An `AbandonedMutexException` (the previous copy crashed) counts as owning the mutex.
3. Log the start banner and load the actions file (`Sync-ActionScript`). Create the tray and log the settings summary, including the display layout.

## Shared state

Everything lives in the entry script's scope. Write it as `$script:X = ...` inside functions.

| Variable | Owner | Meaning |
|---|---|---|
| `$ConfigFile` | entry | full path of the config in use |
| `$DryRun`, `$RunOnce`, `$Overlay` | entry (params) | raw command-line switches |
| `$HasMutex`, `$InstanceMutex` | entry | single-instance lock |
| `$Ini` | Config | parsed config hashtable, keys `section.key` |
| `$Enabled`, `$LogEnabled` | Config | `[general]` |
| `$MinInterval`, `$MaxInterval`, `$IdleSeconds`, `$ReturnAfterMove`, `$SmoothMove` | Config | `[activity]`, already validated |
| `$CornerDelayMin`, `$CornerDelayMax`, `$ClickOrder` | Config | `[click]` |
| `$ActionsFile`, `$ActionsPath`, `$RestoreFocus` | Config | `[actions]`; `$ActionsPath` is resolved against the config folder, `""` = corners |
| `$BreakEnabled`, `$BreakChance`, `$BreakMinMinutes`, `$BreakMaxMinutes` | Config | `[break]` |
| `$IsDryRun`, `$ShowOverlay` | Config | switch OR `[debug]` setting; **use these, not `$DryRun`/`$Overlay`** |
| `$ActionSteps`, `$ActionError`, `$ActionStamp` | Actions | loaded steps, or the load error; the stamp (path, size, time) avoids reloading |
| `$LastCycleResult` | Actions | `done`, `stopped`, `error` or `cancelled: <reason>` |
| `$FocusRestore`, `$CyclePoint` | Actions | window to restore after a cycle; dry-run cursor position |
| `$LastUserInput`, `$IgnoreInputBefore`, `$InAction` | Input | idle detection (see below) |
| `$ExpectedX`, `$ExpectedY` | Input | where the script last put the cursor |
| `$CycleDisplay` | Input | display signature while a cycle runs, otherwise `$null` |
| `$Paused`, `$ExitRequested` | Tray | set from tray clicks while `DoEvents` runs |
| `$Tray`, `$Menu*`, `$IconCache` | Tray | UI objects; generated icons are cached for the process lifetime |
| `$NextRunAt`, `$NextRunTotal` | entry | next cycle time, and its full delay for the progress ring |
| `$BreakUntil`, `$BreakTotal` | entry | end of the current break (`$null` = none), and its length |
| `$ShiftText`, `$ActionsText` | entry | info lines for the tray menu |
| `$LastDisplay` | entry | last logged display signature |
| `$Stats` | entry | `Day`, `Done`, `Cancelled`, `LastTime`, `LastResult`; resets at midnight |
| `$state` | entry | last logged state, used by `Set-State` |

## Main loop

The loop ticks once a second, using `Wait-Responsive 1000` so the tray stays responsive.

```
reload config -> reload actions file if changed -> update idle tracking
-> log display changes -> work out the active shift
  disabled in config?        -> log, exit
  paused from tray?          -> state "paused"
  actions file has an error? -> state "actions" (tray: error), clear NextRunAt
  outside every shift?       -> state "schedule", clear NextRunAt
  on a break?                -> state "break", clear NextRunAt (ends by itself or from the tray)
  idle < idle_seconds?       -> state "user", clear NextRunAt
  NextRunAt not set?         -> pick a random interval, state "idle"
  NextRunAt in the future?   -> update the countdown
  otherwise                  -> Invoke-Cycle, clear NextRunAt, maybe start a break
any exception -> log "ERROR: ...", tray error state, wait 30 s
```

- **`Invoke-Cycle`:** builds the steps with `Get-CycleSteps`, runs `Invoke-ActionCycle` and records the result in `$Stats`.
- **`Get-CycleSteps`:** returns either the actions file's steps or `Get-CornerSteps` for the configured order. For `random` it flips a coin each cycle. It emits the steps one by one, so call it as `@(Get-CycleSteps)`.
- **Breaks:** after a cycle that finished (`done`), `Start-BreakMaybe` starts a break with probability `chance_percent`. The length is a bell-curve random between `min_minutes` and `max_minutes`.
- **`-RunOnce`:** the loop is skipped. One cycle runs, ignoring the schedule, idle time and breaks, and the script exits with 0. It exits with 1 if the actions file has an error.

## Actions

The actions file is handled in two places:
- **`ActionScript.ps1` (pure) parses it.** `Read-ActionScript` turns each line into a step hashtable with `Command` and `Line`, plus:
  - `X` and `Y` (raw tokens) and `HasPoint`, for steps with a position
  - `Button` for `click`, `Keys` and `Combo` for `key`, `Direction` and `Count` for `scroll`, `Min` and `Max` for `wait`, `Target` for `focus`

  Coordinates are checked when the file is loaded, but only turned into pixels during a cycle (`Resolve-ActionCoordinate`), so they follow resolution changes. The corner clicks are built with the same parser (`Get-CornerSteps`), so there's only one execution path.
- **`Actions.ps1` runs it.** `Sync-ActionScript` reloads the file when its stamp changes and logs once per change. `Invoke-ActionCycle` runs the steps through `Invoke-ActionStep`.

File format and commands: [actions.md](actions.md).

## One cycle (`Invoke-ActionCycle`)

1. **Record the starting point:** the primary screen size, cursor position and display signature (`$CycleDisplay`). Set `$InAction`, and show overlay markers for every `move`/`click` point if `$ShowOverlay` is set.
2. **Run each step:**
   - `click X Y` moves first and waits 80–250 ms.
   - `focus` remembers the current foreground window the first time.
3. **Return:** if `return_after_move` is on, move back to the start position.
4. **`finally`:** hide the markers, restore the remembered window (`restore_focus`), clear `$CycleDisplay` and `$InAction`, and set `$IgnoreInputBefore = now`.

Every wait goes through `Wait-Action`, which calls `Assert-NotInterrupted`. Each problem throws a short code, which the cycle catches, logs and turns into `$LastCycleResult`:

| Thrown | When | Logged / result |
|---|---|---|
| `Interrupted` | Turned off from the tray, or Exit | not logged; `stopped` |
| `DisplayChanged` | `Get-DisplaySignature` differs from `$CycleDisplay`; checked before the position, because a resolution change moves the cursor | `cancelled: display changed` |
| `UserMoved` | Cursor more than 2 px from `$ExpectedX`/`$ExpectedY` | expected and actual position plus the foreground window; resets the idle timer; `cancelled: you moved the mouse` |
| `CursorBlocked` | `SetCursorPos` failed (in `Set-Cursor`), e.g. UIPI with an elevated window in front of a non-elevated script | Win32 error; the idle timer is left alone; `cancelled: cursor blocked` |
| `FocusFailed` | No window matches, or Windows refused to switch | `cancelled: window not focused` |

`$InterruptDetail` holds the text for these log lines. Any other exception sets `error` and goes up to the main loop's error handler.

**Dry run:** `Move-CursorTo`, `Invoke-MouseClick`, `Invoke-Scroll` and `Invoke-KeyCombo` return early, and `focus` only looks the window up. `$ExpectedX`/`$ExpectedY` stay at the start position, so a real mouse move still cancels the cycle. Click log lines use `$CyclePoint`, where the cursor would be.

## Tray

`Update-Tray State Status [Progress] [Next]` is called every tick.

**Icon:** a dot in the state colour (`$StateColors`):

| State | Colour | Ring progress |
|---|---|---|
| `starting` | silver | — |
| `paused` | gray | — |
| `schedule` (outside every shift) | steel blue | — |
| `user` (waiting for idle) | orange | idle time / `idle_seconds` |
| `idle` (counting down) | green | time since the countdown started |
| `clicking` (cycle running) | sky blue | — |
| `break` | purple | time since the break started |
| `error` (actions file or loop error) | red | — |

With progress, the dot is drawn as a ring that fills clockwise in 12 steps. In a dry run, a white badge sits at the bottom right.

**Tooltip:** three lines: on/off (plus dry run), the status, and today's done/cancelled counts. `NotifyIcon.Text` is capped at 63 characters in .NET Framework, so `Set-TrayText` sets the private `text` field and calls `UpdateIcon` through reflection, allowing up to 127. It falls back to the public property, truncated, if that fails.

**Menu:**
- Disabled info lines: status, next cycle or break end, active shift, actions source, today's counts, last cycle time and result
- Turn ON/OFF
- End break now (only during a break)
- Exit

## Display changes

There are no `SystemEvents` hooks: their handlers run on another thread, which PowerShell can't host. Instead:
- **Every tick:** `Update-Display` compares `Get-DisplaySignature` (primary size, monitor count, desktop bounds) with the last one and logs any change.
- **During a cycle:** `Assert-NotInterrupted` cancels the cycle if the signature changes.
- **Every cycle:** coordinates are resolved again at the start of each cycle, and `Move-CursorTo` clamps targets and path points to the current desktop bounds, so nothing goes stale.

## Idle detection

Windows' `GetLastInputInfo` also reports the script's own synthetic input. A new last-input tick counts as the user's only if it's later than both `$IgnoreInputBefore` (the end of the last cycle) and `$LastUserInput`. `Update-UserActivity` is skipped while `$InAction` is set.

Limitation: keyboard input during a cycle is treated as the script's own (`problems.md` #2).

Tick maths uses `MouseApi.Now/Since/IsAfter`, which handle the 49.7-day `TickCount` wrap. Use these, not plain subtraction.

## Win32 and WinForms notes

- **DPI:** `SetProcessDPIAware()` runs at load time, so all coordinates are physical pixels. The overlay forms rely on this.
- **Coordinates:** relative to the primary monitor (`SM_CXSCREEN`/`SM_CYSCREEN`). Movement is clamped to the virtual desktop (`SM_*VIRTUALSCREEN`).
- **Input:**
  - Mouse buttons and the wheel use the legacy `mouse_event`. Keys use `keybd_event` with the scan code from `MapVirtualKey` and the extended flag where needed. `SendInput` is on the backlog.
  - Wheel deltas are ±120 per notch; up and right are positive.
- **Focus:** `MouseApi.FindWindowByText` enumerates visible titled windows and prefers an exact process-name match over a title match. `MouseApi.FocusWindow` restores minimized windows and calls `SetForegroundWindow`. If Windows refuses, it taps Alt and retries.
- **Thread:** the process must be STA. `run.vbs` passes `-STA`; PowerShell 5.1 consoles are STA by default.
- **Overlay:** `OverlayMarker` is a borderless `Form` with `WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_NOACTIVATE`, so clicks pass through and it never takes focus. Magenta is the transparency key.
- **PowerShell gotchas:**
  - `[Math]::Min(1, $x)` picks the `int` overload and rounds `$x`. Write `1.0` when `$x` is fractional.
  - A function that returns `,$array` and is called through another function ends up nested inside `@()`. Emit the items one by one instead (see `Get-CycleSteps`).

## Adding a module

1. Create `modules/<Name>.ps1` with a `# ===` banner. Put only definitions at the top level, plus side effects that can't wait.
2. Dot-source it in `cursor-utility.ps1`, after everything it needs at load time.
3. If it has pure logic, keep that in functions that take parameters, and add `tests/<Name>.Tests.ps1`.
4. Update the layout in `AGENTS.md` and the tables above.

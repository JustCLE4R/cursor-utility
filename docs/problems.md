# Cursor Utility: Known Problems

Problems found in the code and the log. Ordered by impact.
Last validated 2026-10-18 against commit `d742d49`. Each entry's **Checked** line says how it was confirmed.

## 1. Bottom-left click hits the Start button

- **Where:** the built-in corner steps, `Get-CornerSteps` in `modules/ActionScript.ps1` (line 352)
- **What happens:** on a default Windows 10 taskbar, (0, 1079) is the Start button, so every cycle (in any `click.order`) probably opens the Start menu and leaves it open. The top-left click at (0, 0) can hit a maximized window's system menu or File menu.
- **Fix options:**
  - Click safer points, or move without clicking
  - Check what is under the cursor before clicking (see the safe-click idea in `ideas.md`)
  - Press Esc after clicking
  - Replace clicking with keep-awake via `SetThreadExecutionState`
- **Workaround available now:** use an actions file (`[actions] file=actions.txt`) with safer points or a harmless key such as `key f15`.
- **Checked:** `WindowFromPoint` puts the taskbar (`Shell_TrayWnd`) at (0,1079) and the VS Code window at (0,0) on this PC. The log at 2026-10-18 02:07:48 shows the foreground window was `'Start menu'` right after a bottom-left click.

## 2. Typing during a cycle is ignored

- **Status:** accepted as a known limitation (2026-10-18). It only matters for the 3–5 seconds a cycle runs, and most people move the mouse first when they come back, which cancels the cycle properly. Not planned for now.

- **Where:** `modules/Actions.ps1`, the `finally` block of `Invoke-ActionCycle` (line 227)
- **What happens:** after each cycle, `IgnoreInputBefore` is set to the current time, so any input during the 3–5 second action counts as the script's own. Mouse movement cancels the cycle (`UserMoved`), but keystrokes don't. The script carries on as if you were still idle and clicks again on the next cycle.
- **Fix:** set `IgnoreInputBefore` right after each synthetic move or click instead of at the end of the cycle, and check `GetLastInputInfo` inside `Assert-NotInterrupted` (`modules/Input.ps1` line 326). Or use a low-level keyboard hook.
- **Checked (code):** `Assert-NotInterrupted` only compares the cursor position; nothing in a cycle reads `GetLastInputInfo`; `Update-UserActivity` returns early while `$InAction` is set; and the `finally` block moves `IgnoreInputBefore` past anything typed during the cycle. Key steps from an actions file make the fix harder, because they're keyboard input too.

## 3. Cursor left in a corner when paused or exited mid-cycle

- **Where:** `modules/Actions.ps1`, the `Interrupted` path of `Invoke-ActionCycle` (line 209)
- **What happens:** turning the utility off or exiting during a cycle stops it immediately and skips moving the cursor back. This also applies to `-RunOnce`. It doesn't happen with `-DryRun`, because the cursor never moves. A window switched by `focus` is still switched back.
- **Fix:** on `Interrupted` (not `UserMoved`), move the cursor back to `$original` when `return_after_move=true`.
- **Checked (code):** the `Interrupted` branch only sets `$LastCycleResult = "stopped"`. The return move is the last step inside `try`, so it's skipped.

## 4. Config reading is fragile

- **Where:** `Read-Ini` in `modules/Config.ps1` (line 5), `Convert-ToMinutes` in `modules/Schedule.ps1` (line 12), the first `Import-Settings` call in `cursor-utility.ps1` (line 70)
- **What happens:**
  - The config is read every second. If an editor is saving it at the same moment, `Get-Content` can fail. The log shows this once: `[2026-10-17 20:21:05] ERROR: Stream was not readable.`
  - An invalid time such as `24:00`, `8.30` or an empty value makes `TimeSpan.Parse` throw. Every loop tick then fails and waits 30 seconds. The tests confirm this: `Schedule.Tests.ps1` "throws on an invalid shift time".
  - **At startup** the first `Import-Settings` runs outside any `try`. If it fails there, the hidden process exits with no tray icon, no message box and no log line, because logging isn't set up yet.
- **Fix:**
  - Retry the read, or keep the last good settings when it fails
  - Parse times with `TryParseExact("hh\:mm")`, log a warning once and fall back to the default
  - Wrap the startup read and show a message box when it fails
- **Checked (run):**
  - `Read-Ini` on a file another program holds open throws `IOException: ... being used by another process`, and works again once it's released.
  - `Convert-ToMinutes` throws for `24:00` ("out of range"), `8.30` and an empty value ("not recognized as a valid TimeSpan").
  - `Get-ActiveShift` with `pagi_start=` throws the same, so it would fail every tick.
  - The startup `Import-Settings` (`cursor-utility.ps1` line 70) is outside any `try`.

## 5. Positions are relative to the primary monitor only

- **Where:** `Get-ScreenSize` in `modules/Input.ps1` (`SM_CXSCREEN`/`SM_CYSCREEN`), used by `Resolve-ActionCoordinate`
- **What happens:**
  - Words (`left`, `bottom`, ...) and percentages, including the built-in corners, always refer to the primary monitor.
  - Other monitors can only be reached with raw pixel values, which break when the layout changes.
- **Fix:** a per-step or per-file monitor option, e.g. `monitor 2` (see the monitor selection idea in `ideas.md`).
- **Done:** the single-instance guard that used to be part of this entry (named mutex `Local\CursorUtility`; dry runs and `-RunOnce` may run alongside).
- **Checked (code):** `Get-ScreenSize` reads only `SM_CXSCREEN`/`SM_CYSCREEN`. No effect on this PC, which has one monitor.

## 6. Using the PC during a break doesn't end it

- **Where:** main loop in `cursor-utility.ps1`: the break check (line 327) runs before the idle check (line 343)
- **What happens:** a break ends only by time or from the tray (**End break now**). While you're at the PC, the icon stays purple and says "On a break", although you're really active. Nothing clicks either way, because when the break ends the idle check takes over. So the effect is only a misleading status.
- **Fix (if wanted):** during a break, if the idle time is below `idle_seconds`, clear `$BreakUntil`, log "Break ended: you're back." and fall through to the normal waiting state.
- **Checked (code):** while `$BreakUntil` is in the future, the loop `continue`s before `Get-UserIdleSeconds` is reached.

## 7. `focus` can't find a browser tab that isn't the active one

- **Status:** fix option 2 is implemented as `focus tab NAME` (2026-10-18). It's waiting for a check with real Edge. Use `focus tab whatsapp` instead of `focus whatsapp`.
  - **Tested:** against a standard Windows tab control: finding, selecting, switching back, no match, and the dry run.
  - **Not tested:** this PC has no Edge or Chrome.
  - **Remove this entry** once `focus tab` has worked with WhatsApp Web in Edge on the other PC.
  - **If it fails there:** run the read-only probe in `docs/testing.md` ("Browser tabs"). It shows whether UI Automation can see Edge's tabs on that PC.

- **Where:** `MouseApi.FindWindowByText` in `modules/Input.ps1`, called by `Invoke-FocusStep` in `modules/Actions.ps1`
- **Reported:** 2026-10-18. `focus whatsapp` with WhatsApp Web open in a Microsoft Edge tab works until you switch that Edge window to another tab and go to another app. After that the cycle fails with `Focus failed: no open window matches 'whatsapp'` and is cancelled.
- **Why:**
  - `focus` looks at **windows**, not tabs. Windows itself can't see browser tabs; to Windows, an Edge window is one window whose title is **only the active tab's title**, e.g. `WhatsApp - Microsoft Edge` or `(3) WhatsApp and 4 more pages - Profile 1 - Microsoft Edge`.
  - The lookup tries an exact **process name** first. Edge's process is `msedge`, not `whatsapp`, so that never matches.
  - It then tries the **title**. Once another tab is active, the title no longer contains "WhatsApp", so nothing matches.
  - Even when it does match, `focus` only brings the window to the front. It never changes the tab, so if a different tab were active, the following steps would act on the wrong page.
- **What's fine:** the cycle is cancelled instead of clicking in some other window, so nothing harmful happens. The step just doesn't do its job.
- **Fix options:**
  1. **Workaround with no code change (works now):** give WhatsApp its own window, so its title doesn't depend on which tab is active:
     - In Edge, open WhatsApp Web, then **⋯ → Apps → Install WhatsApp**. It opens in its own window titled `WhatsApp`, and `focus whatsapp` matches it by title every time.
     - Or use the **WhatsApp desktop app**. Its process is named `WhatsApp`, so `focus whatsapp` matches it by process name.
  2. **Tab-aware focus (code change, recommended):** a new form such as `focus tab whatsapp`. It would use Windows **UI Automation** (built into .NET Framework, no install) to list the tabs in every Edge/Chrome window and select the tab whose title contains the text, then bring its window to the front. The user's previously active tab could also be re-selected at the end of the cycle, alongside `restore_focus`.
     - **Pros:** works with an ordinary tab and selects the tab directly, without any key presses.
     - **Cons:**
       - It's slower than the window lookup (roughly 0.1–0.5 s per cycle).
       - It depends on how Edge/Chrome expose their tab strip, which a browser update could change.
       - It needs more code: a new `tab` keyword, parser tests and docs.
       - **Not yet verified on this PC:** Edge wasn't running when this was checked, so it's still unconfirmed whether UI Automation lists its tabs here.
  3. **Remember the window:** once `focus` has found a window, keep its handle and reuse it while that window exists. It's simpler than option 2, but it brings back Edge showing **whatever tab is active**, so later clicks may land on the wrong page. Not recommended on its own.
  4. **Cycle tabs with Ctrl+Tab until the title matches:** no new APIs, but it visibly flips through your tabs, it's slow with many tabs, and it moves your tab position. Not recommended.
- **Related:** "`focus` by title can pick the wrong window" under Minor.

## Minor

- **A failed read of the actions file can stick:** `Sync-ActionScript` only reloads when the file's size or time stamp changes. If a read fails for a moment, e.g. because an editor has the file locked, the error stays until the file is saved again. Fix: don't store the stamp when the error was a read error rather than a parse error.
  - **Checked (run):** with the file locked, the error was "being used by another process". After unlocking, it was still there because the stamp hadn't changed. It cleared only after the time stamp changed.
- **`focus` by title can pick the wrong window:** a title match takes the first visible window whose title contains the text. `focus notepad` would match a VS Code window titled `notepad-notes.md` if Notepad isn't running. An exact process-name match always wins when there is one. Fix: a `focus title:` / `focus process:` prefix to choose explicitly.
  - **Checked (run):** `focus code` matched VS Code by process name. An earlier dry run matched `focus Visual Studio Code` by title. Window titles change all the time (VS Code's follows the open file), which is what makes title matches unpredictable.
- **The focus Alt tap:** if Windows refuses the first `SetForegroundWindow`, the script taps Alt and retries. In some programs, the tap briefly underlines menu letters.
  - **Checked (code only):** it's in `MouseApi.FocusWindow`. The visible effect hasn't been observed, because that needs real window switching.
- **`Get-NaturalRandom` can round outside its range** with non-integer bounds. It clamps to `[Min, Max]` and then rounds, so `Get-NaturalRandom 0 0.6` can return 1 (`modules/Random.ps1` line 25). Only `Move-CursorTo` passes fractional bounds, for its movement duration, so the effect is harmless. Fix: clamp after rounding, to `[ceil(Min), floor(Max)]`.
  - **Checked (run):** over 2000 runs, `0 0.6` returned both 0 and 1, and `200.4 450.7` returned values from 200 to 451, both outside the range.
- **The overlay compiles on first use:** `modules/Overlay.ps1` line 72 runs inside the cycle's `try`. If compiling the C# ever fails, every cycle errors and no clicks happen while the overlay is on.
  - **Checked (code only):** the failure is hypothetical. The compile has worked in every run so far.

## Log observations

- From 2026-09-23 to the refactor on 2026-10-18 there were 15 starts and only 7 completed click cycles, all on 2026-10-17. Six of those ran under an older version of the script, which logged "Active schedule. Waiting N seconds". Only one cycle (20:22) ran under the single-file code.
- Many sessions log "User idle. Running." and then "User active" about 30–50 seconds later with no click in between. The interval had already been picked, so the idle check reset the countdown before the click came. This is either real use or another program sending input.
- Lines tagged `[dry-run]` from 2026-10-18 01:38 onward come from smoke tests, not real clicks.
- **Unexplained exit, 2026-10-18 20:32:09:** in the first watchdog test, a dry-run copy exited with code 1 a few seconds after starting. Its log stops after "Idle before start". The watchdog restarted it, and the restart worked. Six later starts the same way didn't reproduce it, and log rotation and a second writer to the log were ruled out. The watchdog now copies the app's error output into `logs\watchdog.log` on any crash, so if it happens again, the reason is recorded there.
- Up to 2026-10-18 02:09, "User moved the mouse. Cycle cancelled." lines are often false alarms. The curved path to a corner could bulge 1–3 px off-screen, Windows pulled the cursor back onto the screen, and the 2 px check took that for the user. The logs show it, e.g. `expected (-3,15), cursor at (0,15)`. Fixed on 2026-10-18 by keeping every path point on screen (`Move-CursorTo` in `modules/Input.ps1`).

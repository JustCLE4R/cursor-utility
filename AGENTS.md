# AGENTS.md

Entry point for AI coding agents working on Cursor Utility. Read this first, then the doc for your task.

## What this is

A Windows tray app in PowerShell. While the user is idle and the time is inside an active shift, it runs a cycle every 15–60 seconds, with some randomness:
- **By default:** move to the bottom-left corner and click, then the top-left corner, then move back.
- **With an actions file:** the user's own steps instead: `move`, `click`, `key`, `scroll`, `wait`, `focus`.

It also has:
- an automatic exit `stop_extra_minutes` after the shift it was started in ends
- occasional long breaks
- single-instance protection
- display-change handling
- a tray icon that shows its state

Settings live in `config.ini`, and the steps in `actions.txt`. Both are reloaded live.

- **Runtime:** Windows PowerShell **5.1** (not PowerShell 7), started with `-STA` for WinForms
- **Target OS:** Windows 10/11
- **Dependencies:** none outside Windows. Pester **3.4.0** for tests (the version built into Windows)
- **Version control:** git, branch `main`. Commit only when the user asks.

## Commands

```powershell
# Tests (Pester 3.4 syntax: `Should Be`, not `Should -Be`)
Invoke-Pester .\tests
.\test.bat                    # same, with -ExecutionPolicy Bypass; arguments go to Invoke-Pester

# Safe manual check: one cycle, no real mouse movement, red markers on screen
.\cursor-utility.ps1 -RunOnce -DryRun -Overlay

# Normal start, hidden (what the user runs)
.\run.bat                     # arguments are passed on, e.g. .\run.bat -DryRun

# Use a separate config so the user's config.ini stays untouched
.\cursor-utility.ps1 -Config "$env:TEMP\test.ini" -RunOnce -DryRun
```

A missing `-Config` file is created with defaults. Logs always go to `logs\cursor-utility.log`.

## Layout

```
README.md            User guide (setup, tray, settings)
cursor-utility.ps1   Entry point: parameters, loading modules, startup, main loop
watchdog.ps1         Starts cursor-utility.ps1, restarts it after a crash or a missed heartbeat
install-task.ps1     Registers / removes the Task Scheduler logon task
modules/
  Config.ps1         INI parsing, default config text, Import-Settings          (pure)
  Log.ps1            Write-Log with 1 MB rotation
  Random.ps1         $Random, Get-NaturalRandom (bell-curve delays)             (pure)
  Schedule.ps1       Shifts, Get-ActiveShift, Get-ShiftWindow/Get-StopTime      (pure)
                     (exit after the start's shift), Format-Duration
  ActionScript.ps1   Actions-file parser, key table, Get-CornerSteps            (pure)
  Input.ps1          MouseApi (Win32 via Add-Type): idle detection, movement, clicks,
                     wheel, keys, window focus, display signature
  Tray.ps1           State icons, tooltip, info menu, Wait-Responsive
  Overlay.ps1        Debug markers (C# Form compiled on first use)
  Browser.ps1        Browser tabs via UI Automation for "focus tab" (compiled on first use)
  Actions.ps1        Sync-ActionScript, Invoke-ActionCycle: runs one cycle of steps
tests/               Pester tests for the pure modules
config.ini           User settings (live-reloaded; git-ignored)
actions.txt          Example actions file with the command reference (live-reloaded)
test.bat             Runs the Pester tests with -ExecutionPolicy Bypass
run.bat, run.vbs     Hidden launcher (wscript -> powershell watchdog.ps1 -> cursor-utility.ps1)
docs/                Detailed docs (see below)
  actions.md         Actions file format
  ideas.md           Feature backlog; tick items when done
  problems.md        Known bugs with line refs and suggested fixes
logs/                Runtime logs (not source): cursor-utility.log, watchdog.log,
                     heartbeat.txt, app-errors.txt
```

## Docs

| Read this | When you are |
|---|---|
| [docs/architecture.md](docs/architecture.md) | changing behaviour, adding a module, touching shared state |
| [docs/configuration.md](docs/configuration.md) | adding or changing a setting or command-line option |
| [docs/actions.md](docs/actions.md) | changing the actions file format or adding a command |
| [docs/testing.md](docs/testing.md) | writing tests or checking a change |
| [docs/problems.md](docs/problems.md) | fixing bugs |
| [docs/ideas.md](docs/ideas.md) | picking up a feature |

## Rules

1. **Never let real input run while testing.** Use `-DryRun`, which also stops keys, scrolling and window switching. Real clicks hit the Start button and whatever window is in the top-left corner (see `docs/problems.md` #1). Running without `-DryRun` takes over the user's mouse and keyboard, so only do it if they ask.
2. **Don't edit the user's `config.ini` or `actions.txt` to test.** Pass `-Config <temp path>` instead, with its own `[actions] file=`. The user's running copy reloads both files live, so edits take effect right away.
3. **A copy may already be running** (hidden `powershell.exe` with a tray icon, usually under `watchdog.ps1`). It doesn't pick up code changes until it's restarted, so tell the user to restart it. Don't kill it without asking; **killing the app under a watchdog counts as a crash, and it gets restarted**. A normal (non-dry-run) start exits while that copy holds the single-instance mutex; dry runs and `-RunOnce` don't need it, and neither do dry-run or `-RunOnce` watchdogs.
   - **Scheduled task:** don't register or remove the user's real "Cursor Utility" task to test. Use `install-task.ps1 -TaskName "Cursor Utility Test"`, then `-Uninstall` it.
4. **Stay compatible with PowerShell 5.1.** No `??`, `?.`, ternary, `&&`/`||`, `-Parallel`, or `ConvertFrom-Json -AsHashtable`. C# passed to `Add-Type` must compile under the .NET Framework compiler (C# 5): no `$"..."` string interpolation, `=>` members or `out var`.
5. **Modules are dot-sourced, not imported.** Every function and `$script:` variable shares the entry script's scope. Write shared state as `$script:Name = ...` and read it as plain `$Name`. Don't convert them to `.psm1` without redesigning the shared state (see architecture).
6. **Keep the pure modules pure.** `Config.ps1`, `Schedule.ps1`, `Random.ps1` and `ActionScript.ps1` must load without WinForms, Win32 or the tray, so the tests can dot-source them directly. Pass time and config in as parameters (e.g. `Test-ScheduleActive -Ini -Now`) rather than reading globals.
7. **New settings go in three places:** `Import-Settings` (with a default and clamping), `$DefaultConfigText`, and `docs/configuration.md`. Add the key to the user's `config.ini` only if they want it there.
8. **Log only on state change** (`Set-State`) to keep the log small. Errors in the main loop are logged, then the loop waits 30 seconds.
9. **Match the existing style:** `Verb-Noun` function names, `# ===` section banners, `param()` blocks, short comments explaining *why*.
10. **Keep the trackers current:** tick `docs/ideas.md` items you finish and remove fixed entries from `docs/problems.md`.
11. **Start big edits from a clean `git status`**, so the user can review or revert the diff. Don't commit or push unless asked.
12. **New action commands go in four places:** `ConvertFrom-ActionLine` (parse and validate), `Invoke-ActionStep` (run, and skip real input in dry run), the reference comments in `actions.txt`, and `docs/actions.md`, plus tests in `tests/ActionScript.Tests.ps1`.

# AGENTS.md

Entry point for AI coding agents working on Cursor Utility. Read this first, then the doc for your task.

## What this is

A Windows tray app in PowerShell. While the user is idle and the time is inside an active shift, it moves the mouse to the top-left corner and clicks, then to the bottom-left corner and clicks, then moves back. It repeats every 60–120 seconds, with some randomness. Settings live in `config.ini`, which is reloaded every second.

- **Runtime:** Windows PowerShell **5.1** (not PowerShell 7), started with `-STA` for WinForms
- **Target OS:** Windows 10/11
- **Dependencies:** none outside Windows. Pester **3.4.0** for tests (the version built into Windows)
- **Version control:** none yet. The folder is not a git repo.

## Commands

```powershell
# Tests (Pester 3.4 syntax: `Should Be`, not `Should -Be`)
Invoke-Pester .\tests

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
cursor-utility.ps1   Entry point: parameters, loading modules, startup, main loop
modules/
  Config.ps1         INI parsing, default config text, Import-Settings
  Log.ps1            Write-Log with 1 MB rotation
  Random.ps1         $Random, Get-NaturalRandom (bell-curve delays)
  Schedule.ps1       Shift logic (subuh / pagi / malam)
  Input.ps1          MouseApi (Win32 via Add-Type), idle detection, movement, clicks
  Tray.ps1           NotifyIcon, on/off toggle, Wait-Responsive
  Overlay.ps1        Debug markers (C# Form compiled on first use)
  Actions.ps1        Invoke-CornerClicks: one full cycle
tests/               Pester tests for Config, Schedule, Random
config.ini           User settings (live-reloaded)
run.bat, run.vbs     Hidden launcher (wscript -> powershell -WindowStyle Hidden)
docs/                Detailed docs (see below)
  ideas.md           Feature backlog; tick items when done
  problems.md        Known bugs with line refs and suggested fixes
logs/                Runtime log (not source)
```

## Docs

| Read this | When you are |
|---|---|
| [docs/architecture.md](docs/architecture.md) | changing behaviour, adding a module, touching shared state |
| [docs/configuration.md](docs/configuration.md) | adding or changing a setting or command-line option |
| [docs/testing.md](docs/testing.md) | writing tests or checking a change |
| [docs/problems.md](docs/problems.md) | fixing bugs |
| [docs/ideas.md](docs/ideas.md) | picking up a feature |

## Rules

1. **Never let real clicks run while testing.** Use `-DryRun`. Real clicks hit the Start button and whatever window is in the top-left corner (see `docs/problems.md` #1). Running without `-DryRun` takes over the user's mouse, so only do it if they ask.
2. **Don't edit the user's `config.ini` to test.** Pass `-Config <temp path>` instead. The user's running copy reloads `config.ini` every second, so edits take effect right away.
3. **A copy may already be running** (hidden `powershell.exe` with a tray icon). It doesn't pick up code changes until it's restarted, so tell the user to restart it. Don't kill it without asking.
4. **Stay compatible with PowerShell 5.1.** No `??`, `?.`, ternary, `&&`/`||`, `-Parallel`, or `ConvertFrom-Json -AsHashtable`. C# passed to `Add-Type` must compile under the .NET Framework compiler (C# 5): no `$"..."` string interpolation, `=>` members or `out var`.
5. **Modules are dot-sourced, not imported.** Every function and `$script:` variable shares the entry script's scope. Write shared state as `$script:Name = ...` and read it as plain `$Name`. Don't convert them to `.psm1` without redesigning the shared state (see architecture).
6. **Keep the pure modules pure.** `Config.ps1`, `Schedule.ps1` and `Random.ps1` must load without WinForms, Win32 or the tray, so the tests can dot-source them directly. Pass time and config in as parameters (e.g. `Test-ScheduleActive -Ini -Now`) rather than reading globals.
7. **New settings go in three places:** `Import-Settings` (with a default and clamping), `$DefaultConfigText`, and `docs/configuration.md`. Add the key to the user's `config.ini` only if they want it there.
8. **Log only on state change** (`Set-State`) to keep the log small. Errors in the main loop are logged, then the loop waits 30 seconds.
9. **Match the existing style:** `Verb-Noun` function names, `# ===` section banners, `param()` blocks, short comments explaining *why*.
10. **Keep the trackers current:** tick `docs/ideas.md` items you finish and remove fixed entries from `docs/problems.md`.
11. **Back up before big edits** while there's no git repo: copy the touched files somewhere outside the project, or suggest `git init` to the user.

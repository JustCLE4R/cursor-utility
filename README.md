# Cursor Utility

A small Windows tray app that keeps your session looking active while you're away. Once you've been idle for a while, it moves the mouse to the top-left corner of the screen and clicks, then to the bottom-left corner and clicks, then moves the mouse back to where it was. Delays and movement are randomised so the activity looks natural.

It only runs during the shifts you configure. It pauses on its own as soon as you touch the mouse or keyboard, and you can switch it on or off from the tray icon at any time.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1, which comes with Windows. Nothing else to install.

## Quick start

1. Double-click **`run.bat`**.
2. A dot appears in the system tray:
   - 🟢 **green**: on
   - ⚪ **gray**: off
3. Stop using the mouse and keyboard. After `idle_seconds` (2 minutes by default) it starts a cycle every 1–2 minutes.

No console window opens. The tray icon is the only sign that it's running.

## Using the tray icon

| Action | Result |
|---|---|
| Left-click the icon | Turn on / off |
| Right-click → **Turn ON / Turn OFF** | Same as left-click |
| Right-click → **Exit** | Quit |
| Hover over the icon | Status, e.g. `next click in 42s`, `you are active (idle 30s/120s)`, `outside schedule` |

Moving the mouse during a cycle cancels it straight away, and it waits for you to be idle again.

## Settings

Edit **`config.ini`**. Changes apply within a second, with no restart needed.

```ini
[activity]
# Time between cycles
min_interval_seconds=60
max_interval_seconds=120
# How long you must be idle first
idle_seconds=120
# Put the cursor back afterwards
return_after_move=true
# Curved movement instead of jumping
smooth_move=true

[click]
# Pause between the two clicks
corner_delay_min_ms=700
corner_delay_max_ms=2200
# Which corner first: top_first, bottom_first or random
order=top_first

[schedule]
# Shifts: subuh, pagi, malam
pagi_enabled=true
pagi_start=08:00
pagi_end=16:30
```

Comments must be on their own line, starting with `#` or `;`. Text after a value counts as part of the value.

By default the three shifts (subuh, pagi, malam) together cover all 24 hours. Turn shifts off or narrow their times to pause outside working hours. To stop it entirely, set `enabled=false` under `[general]`.

If `config.ini` is missing, a commented default is created on the next start.

**All settings:** [docs/configuration.md](docs/configuration.md)

## Command-line options

```powershell
.\run.bat -DryRun                                         # hidden, but never moves or clicks
.\cursor-utility.ps1 -RunOnce -DryRun -Overlay            # one test cycle, shows where it would click
.\cursor-utility.ps1 -Config D:\profiles\night.ini        # use another config file
```

| Option | Effect |
|---|---|
| `-DryRun` | Log what it would do, without moving the cursor or clicking |
| `-RunOnce` | One cycle right now, ignoring the schedule and idle time, then exit |
| `-Overlay` | Show red markers where each click lands |
| `-Config <path>` | Use a different config file (created if missing) |

## Start with Windows

1. Press **Win + R**, type `shell:startup` and press Enter.
2. Right-click in the folder → **New → Shortcut**, and browse to `run.bat` in this folder.

To stop it starting with Windows, delete the shortcut.

## Logs

Activity is logged to `logs\cursor-utility.log`. When the file reaches 1 MB, it's renamed to `cursor-utility.log.old` and a new one is started. Only state changes are logged, so the file grows slowly. Set `log_enabled=false` to turn logging off.

## Known issues

- **The bottom-left click lands on the Start button** with a default taskbar, so it can open the Start menu. The top-left click goes to whatever window is in that corner.
- **Typing during a cycle doesn't cancel it.** Only mouse movement does.
- **Only the primary monitor is used**, and nothing stops you from starting two copies.

The full list, with fixes, is in [docs/problems.md](docs/problems.md). Planned features are in [docs/ideas.md](docs/ideas.md).

## Project layout

```
run.bat / run.vbs     Hidden launcher
cursor-utility.ps1    Main script: options, startup, main loop
modules/              Config, schedule, input, tray, overlay, actions
tests/                Pester unit tests
config.ini            Your settings
docs/                 Architecture, configuration, testing, problems, ideas
logs/                 Runtime log
```

## Development

```powershell
Invoke-Pester .\tests                               # unit tests (Pester 3.4, built into Windows)
.\cursor-utility.ps1 -RunOnce -DryRun -Overlay      # safe manual check
```

- **How it works:** [docs/architecture.md](docs/architecture.md)
- **Testing:** [docs/testing.md](docs/testing.md)
- **AI coding agents:** start with [AGENTS.md](AGENTS.md)

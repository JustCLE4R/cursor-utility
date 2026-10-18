# Cursor Utility

A small Windows tray app that keeps your session looking active while you're away. Once you've been idle for a while, it moves the mouse to the top-left corner of the screen and clicks, then to the bottom-left corner and clicks, then moves the mouse back to where it was. Delays and movement are randomised so the activity looks natural.

**Your own steps:** instead of the corner clicks, it can run steps from an **actions file**:
- move or click anywhere, with left, right, middle or double clicks
- press keys
- scroll
- bring a window to the front
- wait

It only runs during the shifts you configure. It pauses on its own as soon as you touch the mouse, and now and then it can take a longer break, like a person getting coffee. The tray icon shows what it's doing at a glance, and you can switch it on or off from there at any time.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1, which comes with Windows. Nothing else to install.

## Quick start

1. Double-click **`run.bat`**.
2. A dot appears in the system tray (see the colours below).
3. Stop using the mouse and keyboard. After `idle_seconds` (2 minutes by default) it starts a cycle every 1–2 minutes.

No console window opens. The tray icon is the only sign that it's running.

Only one copy runs at a time. Starting it again shows a short "Already running" notice and does nothing else.

## Using the tray icon

### What the icon means

| Icon | Meaning | The ring fills with… |
|---|---|---|
| 🟠 orange | You're active; waiting for you to be idle | your idle time, up to `idle_seconds` |
| 🟢 green | Counting down to the next cycle | time until the next cycle |
| 🔵 sky blue | Running a cycle right now | — |
| 🟣 purple | On a break | the break passing |
| 🔷 steel blue | Outside your shifts | — |
| ⚪ gray | Turned off | — |
| 🔴 red | Something is wrong, e.g. a mistake in the actions file | — |

A **ring** that fills clockwise shows progress. A **white badge** in the corner means dry-run mode: nothing is really clicked.

### Hover and right-click

**Hovering** shows three lines: on/off, what it's doing (e.g. `Next cycle in 42s`, `On a break, back in 12m 30s`), and today's count of finished and cancelled cycles.

**Right-clicking** shows the details, then the controls:

| Menu line | Example |
|---|---|
| Status | `You are active (idle 30s of 2m 00s)` |
| Next | `Next cycle at 14:05:12` / `Break ends at 14:20` |
| Shift | `Shift: pagi, 08:00-16:30` |
| Actions | `Actions: actions.txt (5 steps)` / `Actions: corners, bottom first` |
| Today | `Today: 42 done, 3 cancelled` |
| Last cycle | `Last cycle: 14:03:40, done` |
| **Turn ON / Turn OFF** | same as left-clicking the icon |
| **End break now** | only shown during a break |
| **Exit** | quit |

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

[actions]
# Your own steps instead of the corner clicks (empty = corners)
file=actions.txt

[break]
# Now and then take a longer break
enabled=true
chance_percent=5
min_minutes=5
max_minutes=20

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

## Your own steps (actions file)

Set `file=actions.txt` under `[actions]`, then edit **`actions.txt`**. Each cycle runs its steps from top to bottom:

```
# Bring Teams to the front (process name or part of the title)
focus teams
# Or select a browser tab, even when another tab is showing in that window
focus tab whatsapp
# Random pause, in milliseconds
wait 500-1200
# Left click in the middle, then a right click near the bottom-right corner
click center center
click right-10 bottom-10 right
# Press a key: f15, shift, scrolllock, ctrl+shift+f15, ...
key f15
scroll down 3
wait 400-900
scroll up 3
```

- **Positions:** pixels (`250`), percentages (`50%`), or words: `left`, `center` and `right` for X, `top`, `center` and `bottom` for Y. Words take an offset, e.g. `right-10`.
- **Click types:** `left`, `right`, `middle` and `double`.
- **Coming back:** the window you had in front comes back after the cycle, and after `focus tab` the browser goes back to the tab you were on.
- **Browser tabs:** `focus tab` searches Edge, Chrome, Brave, Vivaldi, Opera and Firefox. Change the list with `browsers=` under `[actions]`.
- **Saving:** changes apply as soon as you save the file.
- **Mistakes:** a mistake turns the icon red and shows the line number until it's fixed.

The shipped `actions.txt` explains every command in its comments, and its default steps do the same as the corner clicks. Try your steps safely with `.\cursor-utility.ps1 -RunOnce -DryRun -Overlay`.

**Full reference:** [docs/actions.md](docs/actions.md)

## Command-line options

```powershell
.\run.bat -DryRun                                         # hidden, but never moves or clicks
.\cursor-utility.ps1 -RunOnce -DryRun -Overlay            # one test cycle, shows where it would click
.\cursor-utility.ps1 -Config D:\profiles\night.ini        # use another config file
```

| Option | Effect |
|---|---|
| `-DryRun` | Log what it would do, without moving, clicking, typing, scrolling or switching windows. Can run next to a normal copy. |
| `-RunOnce` | One cycle right now, ignoring the schedule, idle time and breaks, then exit |
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
- **Positions are measured from the primary monitor.** Use negative or large pixel values to reach other monitors.

The full list, with fixes, is in [docs/problems.md](docs/problems.md). Planned features are in [docs/ideas.md](docs/ideas.md).

## Project layout

```
run.bat / run.vbs     Hidden launcher
cursor-utility.ps1    Main script: options, startup, main loop
modules/              Config, schedule, action parser, input, tray, overlay, cycle runner
tests/                Pester unit tests
config.ini            Your settings
actions.txt           Your steps (used when [actions] file=actions.txt)
docs/                 Architecture, configuration, actions, testing, problems, ideas
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

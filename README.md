# Cursor Utility

A small Windows tray app that keeps your session looking active while you're away. Once you've been idle for a while, it moves the mouse to the bottom-left corner of the screen and clicks, then to the top-left corner and clicks, then moves the mouse back to where it was. Delays and movement are randomised so the activity looks natural.

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
min_interval_seconds=15
max_interval_seconds=60
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
order=bottom_first

[actions]
# Your own steps instead of the corner clicks (empty = corners)
file=actions.txt

[break]
# Now and then take a longer break
enabled=true
chance_percent=1
min_minutes=5
max_minutes=20

[schedule]
# Shifts: subuh, pagi, malam
pagi_enabled=true
pagi_start=08:00
pagi_end=16:30
```

Comments must be on their own line, starting with `#` or `;`. Text after a value counts as part of the value.

By default the three shifts (subuh, pagi, malam) together cover all 24 hours. Turn shifts off or narrow their times to pause outside working hours. To stop it entirely, set `enabled=false` under `[general]`. It exits by itself 1 hour after the shift you started it in is over (started at 08:15, that's pagi, so it stops at 17:30). Change the extra time with `stop_extra_minutes` under `[general]`, or set `stop_after_shift=false` to keep it running.

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

Register a Task Scheduler task that starts it 30 seconds after you log on:

```powershell
.\install-task.ps1                 # install, or update an existing one
.\install-task.ps1 -Start          # ...and start it now
.\install-task.ps1 -Elevated       # run as administrator (from an admin PowerShell)
.\install-task.ps1 -Uninstall      # remove it
```

**When to use `-Elevated`:** Windows doesn't let a normal program move the cursor or click while an **admin window** is in front, e.g. VS Code started as Administrator. `-Elevated` runs it with the highest privileges so it works there too. Installing that way needs an admin PowerShell.

If you used a Startup-folder shortcut before, the installer tells you so you can delete it.

## Watchdog

`run.bat` (and the scheduled task) start Cursor Utility through **`watchdog.ps1`**, which looks after it:

| Situation | What the watchdog does |
|---|---|
| It crashes | Restarts it after 5 s, waiting longer after each further crash (10 s, 20 s, 40 s, then 60 s) |
| It stops responding for 3 minutes (no heartbeat) | Stops it and restarts it |
| More than 5 restarts within 10 minutes | Gives up, shows a notice and writes the reason to `logs\watchdog.log` |
| You click **Exit** in the tray | Nothing: a normal exit stops the watchdog too |

To stop it for good, use **Exit** in the tray menu. Killing it in Task Manager counts as a crash, so the watchdog starts it again.

The watchdog writes to its own log, `logs\watchdog.log`. If Cursor Utility crashes, its error message is copied in there too. Change the limits, or turn the watchdog off, in the `[watchdog]` section of `config.ini`.

## Logs

Activity is logged to `logs\cursor-utility.log`, and the watchdog's restarts to `logs\watchdog.log`. When the file reaches 1 MB, it's renamed to `cursor-utility.log.old` and a new one is started. Only state changes are logged, so the file grows slowly. Set `log_enabled=false` to turn logging off.

## Known issues

- **The bottom-left click lands on the Start button** with a default taskbar, so it can open the Start menu. The top-left click goes to whatever window is in that corner.
- **Typing during a cycle doesn't cancel it.** Only mouse movement does.
- **Positions are measured from the primary monitor.** Use negative or large pixel values to reach other monitors.

The full list, with fixes, is in [docs/problems.md](docs/problems.md). Planned features are in [docs/ideas.md](docs/ideas.md).

## Project layout

```
run.bat / run.vbs     Hidden launcher (starts the watchdog)
watchdog.ps1          Starts Cursor Utility and restarts it after a crash or hang
install-task.ps1      Start at logon via Task Scheduler
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
.\test.bat                                          # unit tests (Pester 3.4, built into Windows)
.\cursor-utility.ps1 -RunOnce -DryRun -Overlay      # safe manual check
```

- **How it works:** [docs/architecture.md](docs/architecture.md)
- **Testing:** [docs/testing.md](docs/testing.md)
- **AI coding agents:** start with [AGENTS.md](AGENTS.md)

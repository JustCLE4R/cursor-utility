# Configuration

## Command-line options

| Option | Effect |
|---|---|
| `-Config <path>` | Config file to use. Default: `config.ini` next to the script. Relative paths resolve from the current directory. A missing file is created with defaults. |
| `-DryRun` | No cursor movement, clicks, keys, scrolling or window switching. Log lines get `[dry-run]`, the tooltip says "(dry run)" and the icon gets a white badge. Forces `debug.dry_run` on. |
| `-RunOnce` | One cycle immediately, ignoring the schedule, idle time and breaks, then exit. Exit code 1 if the actions file has an error. |
| `-Overlay` | Red markers at every `move`/`click` point during a cycle. Forces `debug.overlay` on. |

`run.bat` and `run.vbs` pass any arguments on to the script.

`watchdog.ps1` also passes two internal options, which you don't normally set yourself: `-HeartbeatFile <path>` (the app writes the time there every 10 s or so) and `-StartedAt yyyy-MM-ddTHH:mm:ss` (the time whose shift sets the stop time, see [Stopping after the shift](#stopping-after-the-shift)).

**Execution policy:** with Windows' default policy, `.\cursor-utility.ps1` fails with "running scripts is disabled". `run.bat` and `test.bat` pass `-ExecutionPolicy Bypass` themselves. For the script, use `powershell -ExecutionPolicy Bypass -File .\cursor-utility.ps1 ...`, or run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` once in that window.

**Single instance:** only one normal copy runs at a time. A second copy logs "Another copy is already running", shows a short tray notice and exits. A dry run or `-RunOnce` may start next to a running copy, so you can test without stopping it.

## `config.ini`

- **Format:** `[section]` headers and `key=value` lines. Lines starting with `#` or `;` are comments. Comments after a value aren't supported: `idle_seconds=120 ; note` reads the whole text as the value, so the number can't be read and the default is used. Spaces around keys and values are trimmed.
- **Values:**
  - True/false values accept `true`, `yes`, `1` or `on`, in any case. Anything else counts as false.
  - A number that can't be read falls back to the default.
- **Reloading:** the file is re-read every second, so changes apply without a restart.

| Key | Default | Validation | Meaning |
|---|---|---|---|
| `general.enabled` | `true` | — | `false` makes the running app exit, and stops it from starting |
| `general.log_enabled` | `true` | — | write `logs\cursor-utility.log` |
| `general.stop_after_shift` | `true` | — | exit when the shift it was started in is over, plus `stop_extra_minutes`; see [Stopping after the shift](#stopping-after-the-shift). `false` = run until stopped. |
| `general.stop_extra_minutes` | `60` | ≥ 0 | how long to keep going after that shift ends |
| `activity.min_interval_seconds` | `15` | ≥ 1 | shortest time between cycles |
| `activity.max_interval_seconds` | `60` | ≥ min | longest time between cycles |
| `activity.idle_seconds` | `120` | ≥ 0 | how long you must be idle before cycles run |
| `activity.return_after_move` | `true` | — | move the cursor back after the clicks |
| `activity.smooth_move` | `true` | — | curved, eased movement instead of jumping |
| `click.corner_delay_min_ms` | `700` | ≥ 50 | shortest pause between the two clicks |
| `click.corner_delay_max_ms` | `2200` | ≥ min | longest pause between the two clicks |
| `click.order` | `bottom_first` | `top_first`, `bottom_first` or `random`, any case; anything else → `bottom_first` | which corner is clicked first; `random` picks again each cycle |
| `actions.file` | empty | path; relative to the config file's folder | run the steps in this file instead of the corner clicks; see [actions.md](actions.md). Empty = corner clicks, which use the `click.*` keys. |
| `actions.restore_focus` | `false` | — | after a cycle with a `focus` step, bring back the window that was in front before (and, after `focus tab`, the tab that was showing) |
| `actions.browsers` | `msedge, chrome, brave, opera, firefox, vivaldi` | process names, separated by commas or spaces, any case, `.exe` optional; empty → default | programs searched by `focus tab NAME` |
| `break.enabled` | `true` | — | take an occasional longer break |
| `break.chance_percent` | `1` | 0–100 | chance of a break after each finished cycle |
| `break.min_minutes` | `5` | ≥ 1 | shortest break |
| `break.max_minutes` | `20` | ≥ min | longest break |
| `watchdog.enabled` | `true` | — | when started through `run.bat`/`run.vbs`/the scheduled task, restart after crashes and hangs. `false` = start it once and don't watch. Read by `watchdog.ps1` before each start. |
| `watchdog.hang_seconds` | `180` | ≥ 30 | restart if the heartbeat is older than this |
| `watchdog.max_restarts` | `5` | ≥ 1 | give up after more restarts than this within 10 minutes |
| `schedule.<shift>_enabled` | `true` | — | shift on/off |
| `schedule.<shift>_start` / `_end` | see below | `TimeSpan.Parse`; invalid values throw | `HH:mm`, both ends included; may cross midnight |
| `debug.dry_run` | `false` | — | same as `-DryRun` |
| `debug.overlay` | `false` | — | same as `-Overlay` |

Values below the minimum are raised to it. If a maximum is below its minimum, it's set to the minimum.

Random values (intervals, delays, break lengths, `wait MIN-MAX`) are drawn from a bell curve centred on the middle of the range, with the range covering ±3σ, and clamped to `[min, max]`.

### Breaks

- **When:** after each cycle that finishes, a break starts with probability `chance_percent`. With the defaults (1%, 15–60 s between cycles), that's roughly one break an hour of idle time.
- **During a break:** no cycles run. The tray turns purple, its ring fills as the break passes, and the tooltip and menu show when it ends.
- **Ending early:** right-click the tray icon → **End break now**.

### Shifts

The shift names are fixed in `$DefaultShifts` (`modules/Schedule.ps1`):

| Shift | Default start | Default end |
|---|---|---|
| `subuh` | 00:00 | 08:30 |
| `pagi` | 08:00 | 16:30 |
| `malam` | 16:00 | 00:30 |

The schedule is active if any enabled shift matches the current minute. The defaults overlap, so together they cover all 24 hours.

### Stopping after the shift

With `stop_after_shift=true`, the app works out at start which shift you're starting in, and exits `stop_extra_minutes` after that shift ends.

- **Overlapping shifts:** the shift that started most recently counts. Started at 08:15 with the defaults, that's pagi (08:00–16:30), not subuh, so it stops at 17:30.
- **Midnight:** started at 16:10, it's malam, which ends at 00:30 the next day, so it stops at 01:30.
- **Outside every shift:** the next shift to start counts.
- **Restarts:** under the watchdog the shift comes from the watchdog's start (passed as `-StartedAt`), so a crash restart keeps the same stop time. The exit is normal, so the watchdog stops too.
- **Changes:** edits to the shift times or these keys apply live. `-RunOnce` ignores them.
- **Tray:** the shift line in the menu shows the stop time.

## Adding a setting

1. Read it in `Import-Settings` (`modules/Config.ps1`) with `Get-IniBool` or `Get-IniInt` and a default. Add clamping under `# Validation` if needed.
2. Add it, with a comment, to `$DefaultConfigText` in the same file.
3. Add a row to the table above.
4. Add a test in `tests/Config.Tests.ps1`. If it belongs in the generated config, also extend the "writes a config that loads with the built-in defaults" test.
5. For a matching command-line switch: add it to `param()` in `cursor-utility.ps1` with a `.PARAMETER` help entry, and combine it in `Import-Settings` the way `$IsDryRun` is.

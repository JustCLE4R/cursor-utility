# Testing

## Unit tests

```powershell
Invoke-Pester .\tests
.\test.bat                          # same, but works with the execution policy set to Restricted
.\test.bat -TestName Get-ShiftWindow  # extra arguments go to Invoke-Pester
```

- **`test.bat`:** starts PowerShell with `-ExecutionPolicy Bypass` for that process only, and exits with the number of failed tests (0 = all passed).
- **Pester version:** 3.4.0 (built into Windows), so use v3 syntax: `$x | Should Be 5`, `{ ... } | Should Throw`. Pester 5 syntax (`Should -Be`, top-level `BeforeAll`) won't run. If Pester 5 is ever installed, the tests must be migrated.
- **Speed:** about 5 seconds. No network access, admin rights or display needed.

| File | Covers |
|---|---|
| `tests/Config.Tests.ps1` | `Read-Ini`, `Get-IniBool`, `Get-IniInt`, `New-DefaultConfig` (the generated file must load with the built-in defaults), `Import-Settings` (defaults, clamping, `[debug]`, switches overriding the config) |
| `tests/Schedule.Tests.ps1` | `Convert-ToMinutes`, `Test-ShiftActive` (normal and cross-midnight, inclusive ends), `Test-ScheduleActive` with a fixed `-Now`, `Get-ShiftWindow` (overlaps, midnight, outside every shift), `Get-StopTime` |
| `tests/Random.Tests.ps1` | `Get-NaturalRandom`: bounds, integer results, centring, bell shape |
| `tests/ActionScript.Tests.ps1` | `Resolve-ActionCoordinate`, `ConvertTo-KeyCombo`, every command and error in `ConvertFrom-ActionLine`, `Read-ActionScript` (comments, line numbers, errors, the shipped `actions.txt`), `Get-CornerSteps` |

`Config.Tests.ps1` also covers `[general]` (the stop settings), `[actions]` (path resolution), `[break]` and `[watchdog]` (clamping). If you change a default, change it in both `Import-Settings` and `$DefaultConfigText`, or the generated-config test fails. `Schedule.Tests.ps1` also covers `Get-ActiveShift` and `Format-Duration`.

### Writing tests

- Dot-source only what you need at the top of the file: `. (Join-Path $here "..\modules\Config.ps1")`. Never dot-source `Input.ps1`, `Tray.ps1`, `Overlay.ps1` or `Actions.ps1`: they compile Win32 code, change the process DPI setting or need WinForms.
- Use `$TestDrive` for temporary files, as the `New-TestIni` helper in `Config.Tests.ps1` does.
- Pass the time in (`-Now`) instead of mocking `Get-Date`.
- `Import-Settings` writes `$script:` variables, which in a test file means the test file's scope. Assert on `$MinInterval` and the others directly after calling it.
- To test logic that is currently tied to Win32 or the tray, first pull it out into a pure function (see `AGENTS.md` rule 6).

## Smoke tests (real app)

These run the real script but never move the mouse. Use a temporary config so the user's `config.ini` isn't touched. Dry runs don't need the single-instance mutex, so they work while the user's copy is running.

```powershell
$cfg = Join-Path $env:TEMP "cu-smoke.ini"
Remove-Item $cfg -ErrorAction SilentlyContinue

# 1. One dry-run cycle: should exit 0 in about 3 s and create $cfg
$p = Start-Process powershell.exe -PassThru -Wait -ArgumentList `
    "-NoProfile","-STA","-ExecutionPolicy","Bypass","-File",".\cursor-utility.ps1",
    "-Config",$cfg,"-RunOnce","-DryRun","-Overlay"
$p.ExitCode
Get-Content .\logs\cursor-utility.log -Tail 6   # expect two "[dry-run] Click:" lines

# 2. Main loop starts and keeps running (stop it afterwards)
$p = Start-Process powershell.exe -PassThru -ArgumentList `
    "-NoProfile","-STA","-ExecutionPolicy","Bypass","-File",".\cursor-utility.ps1",
    "-Config",$cfg,"-DryRun"
Wait-Process -Id $p.Id -Timeout 6 -ErrorAction SilentlyContinue
$p.HasExited                                    # expect False
Stop-Process -Id $p.Id -Force
```

Moving the mouse during smoke test 1 cancels the cycle ("User moved the mouse. Cycle cancelled.").

**Stop after the shift:** start a dry-run main loop with `-StartedAt` set to yesterday 08:15. Its stop time (yesterday 17:30) is already past, so it should log `Stops at <yesterday> 17:30: shift pagi ends 16:30, plus 60 min`, then `Shift over plus 60 min (stop_after_shift). Exiting.`, and exit with code 0 within a few seconds:

```powershell
$started = (Get-Date).Date.AddDays(-1).AddHours(8).AddMinutes(15).ToString("s")
$p = Start-Process powershell.exe -PassThru -Wait -ArgumentList `
    "-NoProfile","-STA","-ExecutionPolicy","Bypass","-File",".\cursor-utility.ps1",
    "-Config",$cfg,"-DryRun","-StartedAt",$started
$p.ExitCode                                     # expect 0
```

**Overlay:** the markers can't be checked automatically. Ask the user to watch the top-left and bottom-left corners during smoke test 1.

**Actions file:** point a temporary config at a temporary actions file that uses every command:

```powershell
$dir = Join-Path $env:TEMP "cu-actions"; New-Item -ItemType Directory -Force $dir | Out-Null
Set-Content "$dir\c.ini" "[actions]`nfile=a.txt"
Set-Content "$dir\a.txt" "move center center`nclick right`nkey ctrl+shift+f15`nscroll down 2`nwait 50-80`nfocus code"
.\cursor-utility.ps1 -Config "$dir\c.ini" -RunOnce -DryRun
```

Expect one log line per click, key, scroll and focus, then `Run once: done`. A broken file should exit with code 1 and log `a.txt line N: ...`.

**Single instance:** keep a dry-run main loop running (smoke test 2), then start a normal copy whose config has every shift disabled, so it can't click even if the check fails. That copy should log "Another copy is already running. Exiting." and quit after about 4 seconds.

**Tray icons:** render `Get-StateIcon` for every state at a few progress values into a scaled-up PNG and look at it. A dot-sourced `Random.ps1`, `Input.ps1` and `Tray.ps1` are enough, so the full app isn't needed.

**Browser tabs (`focus tab`):** without a browser, open a WinForms window with a `TabControl` (e.g. tabs "Inbox", "WhatsApp", "News"). Then check with `browsers=powershell`, since the test window belongs to a `powershell` process:
- `Find-BrowserTab "whatsapp" @("powershell")` finds the tab.
- `[TabFinder]::Select(...)` switches it, and `Get-SelectedTabInWindow` gives back the original tab.
- `-RunOnce -DryRun` with `focus tab whatsapp` logs `would select`.

On a PC with Edge, this read-only probe lists what UI Automation sees, with `*` marking the selected tab. It selects nothing:

```powershell
. .\modules\Browser.ps1
Get-BrowserTabs @("msedge") | ForEach-Object { "{0} '{1}'  in '{2}'" -f $(if ($_.IsSelected) {"*"} else {" "}), $_.Name, $_.WindowTitle }
```

**Watchdog:** start `watchdog.ps1 -Config <temp> -DryRun`, with a temp config that has `idle_seconds=99999` (so nothing clicks) and `hang_seconds=30`. Find the app copy by its `-Config` path in `Win32_Process.CommandLine`. Then:
- **Crash:** `Stop-Process` the app. Expect "exited with code -1. Restarting in 5 s". With `max_restarts=1`, a second kill should make the watchdog give up (exit code 1, balloon).
- **Hang:** freeze the app with `ntdll!NtSuspendProcess`. Expect "stopped responding (no heartbeat for ~35 s)", then a kill and a restart.
- **Normal stop:** add `[general] enabled=false` to the temp config. The app exits 0, and the watchdog logs "exited normally. Watchdog stopping."
- **Read `logs\watchdog.log`** for the sequence. A full run of all three takes about 2 minutes.

**Scheduled task:** `.\install-task.ps1 -TaskName "Cursor Utility Test"`, then check it with `Get-ScheduledTask`: the action is `wscript.exe "<repo>\run.vbs"`, it uses a logon trigger with `PT30S` delay, and the logon type is `Interactive`. Then run it again with `-Elevated` (run level should be `Highest`), and finally `-Uninstall`. Don't `-Start` it: that would launch a real, non-dry-run copy.

**Can't be tested safely by an agent:** real window focusing, real key presses, and display changes. Ask the user to check these.

## Checklist before handing back

- [ ] `Invoke-Pester .\tests` (or `.\test.bat`) passes with 0 failures
- [ ] The smoke tests pass if you touched `cursor-utility.ps1` or a non-pure module
- [ ] No new `ERROR:` lines in `logs\cursor-utility.log` from your runs
- [ ] Docs updated (`AGENTS.md` layout, `docs/*` including `ideas.md` and `problems.md`)
- [ ] The user has been told to restart a copy that's already running

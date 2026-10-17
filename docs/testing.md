# Testing

## Unit tests

```powershell
Invoke-Pester .\tests
```

- **Pester version:** 3.4.0 (built into Windows), so use v3 syntax: `$x | Should Be 5`, `{ ... } | Should Throw`. Pester 5 syntax (`Should -Be`, top-level `BeforeAll`) won't run. If Pester 5 is ever installed, the tests must be migrated.
- **Speed:** about 2 seconds. No network access, admin rights or display needed.

| File | Covers |
|---|---|
| `tests/Config.Tests.ps1` | `Read-Ini`, `Get-IniBool`, `Get-IniInt`, `New-DefaultConfig`, `Import-Settings` (defaults, clamping, `[debug]`, switches overriding the config) |
| `tests/Schedule.Tests.ps1` | `Convert-ToMinutes`, `Test-ShiftActive` (normal and cross-midnight, inclusive ends), `Test-ScheduleActive` with a fixed `-Now` |
| `tests/Random.Tests.ps1` | `Get-NaturalRandom`: bounds, integer results, centring, bell shape |

### Writing tests

- Dot-source only what you need at the top of the file: `. (Join-Path $here "..\modules\Config.ps1")`. Never dot-source `Input.ps1`, `Tray.ps1`, `Overlay.ps1` or `Actions.ps1`: they compile Win32 code, change the process DPI setting or need WinForms.
- Use `$TestDrive` for temporary files, as the `New-TestIni` helper in `Config.Tests.ps1` does.
- Pass the time in (`-Now`) instead of mocking `Get-Date`.
- `Import-Settings` writes `$script:` variables, which in a test file means the test file's scope. Assert on `$MinInterval` and the others directly after calling it.
- To test logic that is currently tied to Win32 or the tray, first pull it out into a pure function (see `AGENTS.md` rule 6).

## Smoke tests (real app)

These run the real script but never move the mouse. Use a temporary config so the user's `config.ini` isn't touched.

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

**Overlay:** the markers can't be checked automatically. Ask the user to watch the top-left and bottom-left corners during smoke test 1.

## Checklist before handing back

- [ ] `Invoke-Pester .\tests` passes with 0 failures
- [ ] The smoke tests pass if you touched `cursor-utility.ps1` or a non-pure module
- [ ] No new `ERROR:` lines in `logs\cursor-utility.log` from your runs
- [ ] Docs updated (`AGENTS.md` layout, `docs/*` including `ideas.md` and `problems.md`)
- [ ] The user has been told to restart a copy that's already running

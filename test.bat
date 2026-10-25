@echo off
rem Runs the Pester tests. Bypass only applies to this one PowerShell process,
rem so the system's execution policy stays as it is.
rem Extra arguments go to Invoke-Pester, e.g.: test.bat -TestName Get-StopTime
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$r = Invoke-Pester .\tests -PassThru %*; exit $r.FailedCount"

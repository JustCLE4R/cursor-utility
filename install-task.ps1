<#
.SYNOPSIS
    Starts Cursor Utility when you log on to Windows, using Task Scheduler.

.DESCRIPTION
    Registers a task for the current user that runs run.vbs at logon (after a short delay,
    so the desktop and tray are ready). run.vbs starts the watchdog, which starts and
    looks after Cursor Utility. Running this again updates the task.

    Replaces a shortcut in the Startup folder; if one is found, you're told so you
    can delete it (two starts are harmless, but pointless).

.PARAMETER Uninstall
    Remove the task.

.PARAMETER Elevated
    Run as administrator ("Run with highest privileges"). Needed for clicks and cursor
    moves to work while an admin window (e.g. an elevated VS Code) is in front.
    Installing this way needs an elevated PowerShell.

.PARAMETER Start
    Also start it now, through the task.

.PARAMETER DelaySeconds
    Wait this long after logon before starting. Default 30.

.PARAMETER TaskName
    Name in Task Scheduler. Default "Cursor Utility".

.EXAMPLE
    .\install-task.ps1
.EXAMPLE
    .\install-task.ps1 -Elevated -Start
.EXAMPLE
    .\install-task.ps1 -Uninstall
#>
param(
    [switch]$Uninstall,
    [switch]$Elevated,
    [switch]$Start,
    [int]$DelaySeconds = 30,
    [string]$TaskName = "Cursor Utility"
)

$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunVbs  = Join-Path $BaseDir "run.vbs"
$User    = "$env:USERDOMAIN\$env:USERNAME"

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($Uninstall) {
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed the '$TaskName' task. Cursor Utility won't start at logon any more."
        Write-Host "A copy that is running now keeps running; use Exit in its tray menu to stop it."
    }
    else {
        Write-Host "There is no '$TaskName' task, so there was nothing to remove."
    }
    return
}

if (-not (Test-Path -LiteralPath $RunVbs)) {
    throw "run.vbs not found next to this script: $RunVbs"
}

$isAdmin = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Elevated -and -not $isAdmin) {
    throw "-Elevated needs an elevated PowerShell (right-click PowerShell > Run as administrator), then run this again."
}

# wscript runs run.vbs without a console window
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$RunVbs`"" -WorkingDirectory $BaseDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
if ($DelaySeconds -gt 0) {
    $trigger.Delay = "PT$($DelaySeconds)S"
}

# Interactive: it needs your desktop for the tray icon and the mouse
$runLevel = if ($Elevated) { "Highest" } else { "Limited" }
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel $runLevel

# wscript returns at once, so no time limit or restart is needed here:
# the watchdog does the looking after
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Description "Starts Cursor Utility (with its watchdog) at logon. Installed by $($MyInvocation.MyCommand.Path)." `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

$verb = if ($existing) { "Updated" } else { "Installed" }
$how = if ($Elevated) { "as administrator" } else { "as $User" }
Write-Host "$verb the '$TaskName' task: starts Cursor Utility $DelaySeconds s after you log on, $how."

# A Startup-folder shortcut would start it a second time
$startup = [Environment]::GetFolderPath("Startup")
$shell = New-Object -ComObject WScript.Shell

foreach ($link in Get-ChildItem -LiteralPath $startup -Filter *.lnk -ErrorAction SilentlyContinue) {
    $target = $shell.CreateShortcut($link.FullName).TargetPath

    if ($target -and $target.StartsWith($BaseDir, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Note: the Startup folder still has '$($link.Name)', which starts it too. You can delete it:"
        Write-Host "      $($link.FullName)"
    }
}

if ($Start) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Started it through the task. Look for the tray icon."
}

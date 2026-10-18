' Starts Cursor Utility with no visible window (only the tray icon).
' It runs under watchdog.ps1, which restarts it if it crashes or stops responding.
' Any arguments are passed on, e.g.: run.vbs -DryRun -Overlay
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
script = dir & "\watchdog.ps1"

args = ""
For Each arg In WScript.Arguments
    args = args & " """ & arg & """"
Next

CreateObject("WScript.Shell").Run _
    "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """" & args, _
    0, False

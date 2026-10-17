' Starts Cursor Utility with no visible window (only the tray icon).
' Any arguments are passed on, e.g.: run.vbs -DryRun -Overlay
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
script = dir & "\cursor-utility.ps1"

args = ""
For Each arg In WScript.Arguments
    args = args & " """ & arg & """"
Next

CreateObject("WScript.Shell").Run _
    "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """" & args, _
    0, False

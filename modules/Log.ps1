# ============================================================
# Logging
# ============================================================

# Expects $LogDir, $LogFile and $LogMaxBytes from the main script,
# and $LogEnabled from Import-Settings.

function Write-Log {
    param(
        [string]$Message
    )

    if (-not $LogEnabled) {
        return
    }

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    # Rotate: keep one previous log file
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {
        Move-Item -Path $LogFile -Destination "$LogFile.old" -Force
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Add-Content `
        -Path $LogFile `
        -Value "[$timestamp] $Message"
}

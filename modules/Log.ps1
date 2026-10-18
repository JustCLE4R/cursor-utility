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

# ============================================================
# Heartbeat (for watchdog.ps1)
# ============================================================

# When started by the watchdog, $HeartbeatFile is set and gets the current time
# every 10 s or so. It's called from every wait loop, so a long "wait" step still
# beats; a call that hangs (e.g. a frozen browser) doesn't, and the watchdog restarts us.
$script:LastHeartbeat = $null
$HeartbeatSeconds = 10

function Update-Heartbeat {

    if (-not $HeartbeatFile) {
        return
    }

    $now = [DateTime]::UtcNow

    if ($LastHeartbeat -and ($now - $LastHeartbeat).TotalSeconds -lt $HeartbeatSeconds) {
        return
    }

    $script:LastHeartbeat = $now

    try {
        [System.IO.File]::WriteAllText($HeartbeatFile, $now.ToString("o"))
    }
    catch {
        # A missed beat is harmless; the next one comes in 10 s
    }
}

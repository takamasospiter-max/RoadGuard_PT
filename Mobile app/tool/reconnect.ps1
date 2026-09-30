<#
.SYNOPSIS
  Reconnect the phone to the RoadGuard backend after its Wi-Fi address changed.

.DESCRIPTION
  For a phone that is already paired for Wireless debugging (for the first
  connection, or a phone plugged in by USB, use connect_wifi.ps1). It:
    1. drops dead ("offline") ADB connections left from the old address,
    2. connects to the phone's new address,
    3. recreates the tunnel: phone 127.0.0.1:8000 -> this PC's backend,
    4. checks the backend answers, from the PC and from the phone.

  Always uses the Android SDK's adb (the one Flutter uses), not another copy
  on PATH such as scrcpy's: two different adb versions restart each other's
  server, which silently drops the tunnel.

  Start the backend first (manage.py runserver); the tunnel only links to it.

.EXAMPLE
  # IP address & port from: Settings > System > Developer options > Wireless debugging
  powershell -ExecutionPolicy Bypass -File tool\reconnect.ps1 192.168.137.192:41251
#>
param(
  # The phone's "IP address & port" shown on the Wireless debugging screen.
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}:\d{1,5}$')]
  [string]$Device,
  # Backend port on this PC (and on the phone, through the tunnel).
  [int]$ApiPort = 8000
)
$ErrorActionPreference = 'Stop'

# The SDK's adb; fall back to adb on PATH only if the SDK isn't installed there.
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'adb' }

# --- 1. Drop dead connections (the phone's old address) ---------------------
& $adb devices | Select-String '\soffline$' | ForEach-Object {
  $old = ($_ -split '\s+')[0]
  Write-Host "Removing dead connection $old"
  & $adb disconnect $old | Out-Null
}

# --- 2. Connect to the new address -------------------------------------------
Write-Host "Connecting to $Device..."
$result = & $adb connect $Device
# Match adb's success line exactly: Windows' failure text also contains "connected".
if ("$result" -notmatch '^(already )?connected to ') {
  throw "Could not connect to ${Device}: $result`n" +
        "Check Wireless debugging is ON and the phone is on the same network as this PC. " +
        "If it asks for pairing: tap 'Pair device with pairing code', run '$adb pair <IP:pairing-port>', then run this again."
}
Start-Sleep -Seconds 2
if (-not (& $adb devices | Select-String ([regex]::Escape($Device) + '\s+device$'))) {
  throw "$Device connected but is not ready (unauthorized/offline). Accept the prompt on the phone, then run this again."
}

# --- 3. Tunnel: phone 127.0.0.1:ApiPort -> PC 127.0.0.1:ApiPort --------------
& $adb -s $Device reverse "tcp:$ApiPort" "tcp:$ApiPort" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not create the tunnel (adb reverse)." }
Write-Host "Tunnel ready: phone 127.0.0.1:$ApiPort -> PC 127.0.0.1:$ApiPort"

# --- 4. Check the backend, from the PC and through the tunnel ----------------
try {
  Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/api/v1/health/" -TimeoutSec 10 | Out-Null
} catch {
  Write-Warning "The phone is connected, but the backend isn't answering on this PC. Start it: .venv\Scripts\python.exe manage.py runserver"
  exit 1
}
# The phone's nc hangs up before the reply unless its input stays open briefly.
# Only single quotes on the phone side: Windows PowerShell 5.1 strips double
# quotes from arguments it passes to adb.exe.
$request = "(printf 'GET /api/v1/health/ HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'; sleep 4) | toybox nc 127.0.0.1 $ApiPort"
$fromPhone = & $adb -s $Device shell $request
if ($fromPhone -match '"status":\s*"ok"') {
  Write-Host 'Done: the phone reaches the backend.' -ForegroundColor Green
} else {
  Write-Warning ("The tunnel exists but the phone got no reply. Run this script again; " +
                 "if it persists, restart adb: & `"$adb`" kill-server")
  exit 1
}

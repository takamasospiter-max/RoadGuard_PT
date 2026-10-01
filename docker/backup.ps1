<#
.SYNOPSIS
  Back up the Docker database to docker\backup\roadguard-docker-<date>.dump.

.DESCRIPTION
  A pg_dump "custom format" file: restore it with pg_restore (see README,
  "Running with Docker"). The containers keep running while it is made.
  docker\backup\ is git-ignored: the file contains all RoadGuard data.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File docker\backup.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$backupDir = Join-Path $PSScriptRoot 'backup'
New-Item -ItemType Directory -Force $backupDir | Out-Null

$settings = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot '.env')) {
  if ($line -match '^\s*([A-Z_]+)\s*=(.*)$') { $settings[$Matches[1]] = $Matches[2].Trim() }
}
$name = "roadguard-docker-$(Get-Date -Format 'yyyy-MM-dd_HHmm').dump"

# Run a docker compose command; the exit code decides success. Docker prints
# progress on stderr, which Windows PowerShell 5.1 would otherwise treat as
# an error.
# No declared parameters on purpose: docker's flags (-T, -U, -d ...) would be
# taken as this function's own. The first argument is the failure message.
function Compose {
  $failure, $dockerArgs = $args
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & docker compose @dockerArgs 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { throw $failure }
  } finally { $ErrorActionPreference = $previous }
}

Push-Location $root
try {
  # Dumped inside the container and copied out with `docker compose cp`:
  # piping binary data through Windows PowerShell would corrupt it.
  Compose 'pg_dump failed. Is the Docker setup running (docker compose ps)?' `
    exec -T db pg_dump -U $settings.POSTGRES_USER -d $settings.POSTGRES_DB -Fc -f /tmp/backup.dump
  Compose 'Copying the backup out of the container failed.' cp db:/tmp/backup.dump (Join-Path $backupDir $name)
  Compose 'Could not remove the temporary file in the container.' exec -T db rm /tmp/backup.dump
} finally { Pop-Location }

Write-Host "Backup written: docker\backup\$name" -ForegroundColor Green

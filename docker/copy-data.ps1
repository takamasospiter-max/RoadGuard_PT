<#
.SYNOPSIS
  Copy the RoadGuard database from the Windows PostgreSQL into Docker (once).

.DESCRIPTION
  1. Exports the Windows database (settings from Web portal/new-backend/.env)
     with pg_dump to docker\backup\<name>-<date>.dump. The Windows database
     is only read, never changed: it stays as a backup.
  2. Refuses to continue if the Docker database already holds RoadGuard data
     (reports, accounts), so reports made in Docker are never overwritten.
     -Force replaces it anyway.
  3. Replaces the (empty) Docker database with the export.
  4. Prints row counts on both sides and whether they match.

  Docker Desktop must be running. The db container is started if needed;
  the backend is stopped during the copy and started again afterwards.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File docker\copy-data.ps1
#>
param([switch]$Force)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$backupDir = Join-Path $PSScriptRoot 'backup'
$backendEnv = Join-Path $root 'Web portal\new-backend\.env'
$dockerEnv = Join-Path $PSScriptRoot '.env'
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'

# Read KEY=value settings from an env file.
function Read-EnvFile([string]$path) {
  $settings = @{}
  foreach ($line in Get-Content $path) {
    if ($line -match '^\s*([A-Z_]+)\s*=(.*)$') { $settings[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'") }
  }
  return $settings
}

# Run a docker compose command from the repository root; stop on failure.
# Docker prints progress on stderr, which Windows PowerShell 5.1 would treat
# as an error under 'Stop': so the exit code alone decides, and the messages
# are shown as plain text.
function Compose {
  Push-Location $root
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & docker compose @args 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "docker compose $args failed" }
  } finally {
    $ErrorActionPreference = $previous
    Pop-Location
  }
}

# One number from a SQL query in the Docker database.
function Docker-Count([string]$sql) {
  Push-Location $root
  try { return (& docker compose exec -T db psql -U $docker.POSTGRES_USER -d $docker.POSTGRES_DB -tAc $sql).Trim() }
  finally { Pop-Location }
}

if (-not (Test-Path $dockerEnv)) { throw 'docker\.env is missing. Run docker\init-env.ps1 first.' }
$windows = Read-EnvFile $backendEnv
$docker = Read-EnvFile $dockerEnv

# --- 1. Export from Windows ------------------------------------------------
New-Item -ItemType Directory -Force $backupDir | Out-Null
$dumpName = "$($windows.DB_NAME)-$(Get-Date -Format 'yyyy-MM-dd_HHmm').dump"
$dumpPath = Join-Path $backupDir $dumpName
Write-Host "Exporting the Windows database '$($windows.DB_NAME)' to docker\backup\$dumpName ..."
$env:PGPASSWORD = $windows.DB_PASSWORD
try {
  $hostName = if ($windows.DB_HOST) { $windows.DB_HOST } else { 'localhost' }
  $port = if ($windows.DB_PORT) { $windows.DB_PORT } else { '5432' }
  & (Join-Path $pgBin 'pg_dump.exe') -h $hostName -p $port -U $windows.DB_USER -d $windows.DB_NAME -Fc -f $dumpPath
  if ($LASTEXITCODE -ne 0) { throw 'pg_dump failed. Is the Windows PostgreSQL service running?' }
} finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }

# The tables compared before and after (row counts must match).
$tables = 'defects', 'report_photos', 'audit_log', 'portal_users', 'travelers', 'traveler_sessions'
$windowsCounts = @{}
$env:PGPASSWORD = $windows.DB_PASSWORD
try {
  foreach ($t in $tables) {
    $windowsCounts[$t] = (& (Join-Path $pgBin 'psql.exe') -h $hostName -p $port -U $windows.DB_USER -d $windows.DB_NAME -tAc "SELECT count(*) FROM $t").Trim()
  }
} finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }

# --- 2. Never overwrite data made in Docker ----------------------------------
Compose up -d --wait db
$hasTables = Docker-Count "SELECT count(*) FROM information_schema.tables WHERE table_name = 'defects'"
if ($hasTables -ne '0') {
  $existing = [int](Docker-Count 'SELECT (SELECT count(*) FROM defects) + (SELECT count(*) FROM portal_users) + (SELECT count(*) FROM travelers)')
  if ($existing -gt 0 -and -not $Force) {
    throw "The Docker database already holds RoadGuard data ($existing reports/accounts). Nothing was changed. " +
          "Use -Force to replace it with the Windows copy (data made in Docker would be LOST)."
  }
}

# --- 3. Replace the Docker database with the export ---------------------------
Write-Host 'Loading it into the Docker database ...'
Compose stop backend web
Compose cp $dumpPath "db:/tmp/restore.dump"
$db = $docker.POSTGRES_DB; $user = $docker.POSTGRES_USER
Compose exec -T db dropdb -U $user --if-exists --force $db
Compose exec -T db createdb -U $user -O $user $db
# --no-owner/--no-privileges: the Windows roles don't exist in Docker; the
# Docker user owns everything.
Compose exec -T db pg_restore -U $user -d $db --no-owner --no-privileges --exit-on-error /tmp/restore.dump
Compose exec -T db rm /tmp/restore.dump
Compose up -d --wait backend web

# --- 4. Compare ---------------------------------------------------------------
Write-Host ''
$allMatch = $true
foreach ($t in $tables) {
  $inDocker = Docker-Count "SELECT count(*) FROM $t"
  $same = $inDocker -eq $windowsCounts[$t]
  if (-not $same) { $allMatch = $false }
  Write-Host ("{0,-18} Windows {1,6}   Docker {2,6}   {3}" -f $t, $windowsCounts[$t], $inDocker, $(if ($same) { 'OK' } else { 'DIFFERENT' }))
}
if ($allMatch) {
  Write-Host "`nDone: the data is in Docker. The Windows database is unchanged (backup: docker\backup\$dumpName)." -ForegroundColor Green
} else {
  Write-Warning 'Some counts differ. The Windows database is unchanged; check the messages above.'
  exit 1
}

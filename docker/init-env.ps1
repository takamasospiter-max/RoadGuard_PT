<#
.SYNOPSIS
  Create docker/.env (the Docker setup's settings) from docker/.env.example.

.DESCRIPTION
  - DJANGO_SECRET_KEY is copied from Web portal/new-backend/.env when it
    exists, so the anonymous phone ids used by crowd sensing stay the same
    (they are keyed hashes of this secret). Otherwise a new random key is made.
  - A new random database password is generated (DB_PASSWORD and
    POSTGRES_PASSWORD, kept identical).
  Refuses to replace an existing docker/.env: the database volume was created
  with the password in it. Use -Force only before the first `docker compose up`,
  or after deleting the volume (`docker compose down -v`, which DELETES the data).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File docker\init-env.ps1
#>
param([switch]$Force)
$ErrorActionPreference = 'Stop'

$dockerDir = $PSScriptRoot
$template = Join-Path $dockerDir '.env.example'
$target = Join-Path $dockerDir '.env'
$backendEnv = Join-Path $dockerDir '..\Web portal\new-backend\.env'

if ((Test-Path $target) -and -not $Force) {
  throw "docker\.env already exists; keeping it. (Its database password is the one the Docker database was created with.)"
}

# A random URL-safe string from the system's cryptographic generator.
function New-Secret([int]$bytes) {
  $buffer = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
  return [Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# The existing secret key, if the non-Docker backend has one.
$secretKey = $null
if (Test-Path $backendEnv) {
  $line = Get-Content $backendEnv | Where-Object { $_ -match '^\s*DJANGO_SECRET_KEY\s*=' } | Select-Object -First 1
  if ($line) {
    $value = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
    if ($value -and $value -ne 'change-me') { $secretKey = $value }
  }
}
if ($secretKey) {
  Write-Host 'DJANGO_SECRET_KEY: copied from Web portal\new-backend\.env (phone ids stay the same).'
} else {
  $secretKey = New-Secret 48
  Write-Host 'DJANGO_SECRET_KEY: new random key.'
}
$dbPassword = New-Secret 24
Write-Host 'Database password: new random password.'

$lines = foreach ($line in Get-Content $template) {
  if ($line -match '^DJANGO_SECRET_KEY=') { "DJANGO_SECRET_KEY=$secretKey" }
  elseif ($line -match '^(DB_PASSWORD|POSTGRES_PASSWORD)=') { "$($Matches[1])=$dbPassword" }
  else { $line }
}
# UTF-8 without a byte-order mark: Docker would read a BOM as part of the
# first setting's name.
[System.IO.File]::WriteAllText($target, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Created $target" -ForegroundColor Green

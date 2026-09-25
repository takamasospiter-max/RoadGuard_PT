$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK is not on PATH. Install/configure Flutter, reopen PowerShell, then run this script again."
}

Write-Host "Using installed Flutter SDK:" -ForegroundColor Cyan
flutter --version
flutter doctor -v

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("roadguard_flutter_shell_" + [guid]::NewGuid().ToString("N"))
$TempApp = Join-Path $TempRoot "roadguard_ai"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

try {
  # Generate Android with THIS machine's Flutter SDK. This avoids carrying an old
  # embedding/Gradle shell from another SDK while preserving Dart/app code.
  flutter create --platforms=android --org com.example --project-name roadguard_ai --no-pub $TempApp

  if (Test-Path "android") { Remove-Item "android" -Recurse -Force }
  Copy-Item (Join-Path $TempApp "android") "android" -Recurse

  # Keep RoadGuard Android requirements on top of the SDK-generated shell.
  $Manifest = "android/app/src/main/AndroidManifest.xml"
  [xml]$Xml = Get-Content $Manifest
  $AndroidNs = "http://schemas.android.com/apk/res/android"

  $permissions = @(
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION"
  )
  foreach ($permission in $permissions) {
    $exists = $false
    foreach ($node in $Xml.manifest.'uses-permission') {
      if ($node.GetAttribute("name", $AndroidNs) -eq $permission) { $exists = $true; break }
    }
    if (-not $exists) {
      $node = $Xml.CreateElement("uses-permission")
      $node.SetAttribute("name", $AndroidNs, $permission)
      [void]$Xml.manifest.PrependChild($node)
    }
  }

  $app = $Xml.manifest.application
  $app.SetAttribute("label", $AndroidNs, "RoadGuard AI")
  $app.SetAttribute("allowBackup", $AndroidNs, "false")
  $app.SetAttribute("usesCleartextTraffic", $AndroidNs, "false")
  $Xml.Save((Join-Path $Root $Manifest))

  $GradleKts = "android/app/build.gradle.kts"
  if (Test-Path $GradleKts) {
    $g = Get-Content $GradleKts -Raw
    $g = $g -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
    Set-Content $GradleKts $g -NoNewline
  }

  flutter clean
  flutter pub get
  flutter analyze
  flutter build apk --debug

  Write-Host "`nAndroid shell repaired from the installed Flutter SDK." -ForegroundColor Green
  Write-Host "APK: build/app/outputs/flutter-apk/app-debug.apk" -ForegroundColor Green
}
finally {
  if (Test-Path $TempRoot) { Remove-Item $TempRoot -Recurse -Force }
}

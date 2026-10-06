param([string]$FlutterRoot, [string]$JavaHome)
$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path $PSScriptRoot -Parent
$previousJavaHome = $env:JAVA_HOME
Push-Location $projectRoot
try {
  if (-not $FlutterRoot) {
    $launcher = (Get-Command flutter -ErrorAction Stop).Source
    $FlutterRoot = Split-Path (Split-Path $launcher -Parent) -Parent
  }
  if ($JavaHome) { $env:JAVA_HOME = $JavaHome }
  $dartRuntime = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
  $flutterTools = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
  $proofDir = Join-Path $projectRoot 'docs/validation'
  New-Item -ItemType Directory -Force $proofDir | Out-Null
  & $dartRuntime $flutterTools pub get 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() } } | Tee-Object (Join-Path $proofDir 'android-dependencies.txt')
  if ($LASTEXITCODE -ne 0) { throw 'Android dependency resolution failed' }
  & $dartRuntime $flutterTools build apk --release --no-pub 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() } } | Tee-Object (Join-Path $proofDir 'android-build.txt')
  if ($LASTEXITCODE -ne 0) { throw 'Android release build failed' }
  Push-Location android
  try {
    & .\gradlew.bat :app:testReleaseUnitTest --console=plain 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() } } | Tee-Object (Join-Path $proofDir 'android-tests.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Android unit tests failed' }
  } finally { Pop-Location }
} finally {
  $env:JAVA_HOME = $previousJavaHome
  Pop-Location
}

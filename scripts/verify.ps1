param([switch]$SkipWeb, [switch]$Quick, [string]$FlutterRoot)
$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
  if (-not $FlutterRoot) {
    $launcher = (Get-Command flutter -ErrorAction Stop).Source
    $FlutterRoot = Split-Path (Split-Path $launcher -Parent) -Parent
  }
  $dartRuntime = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
  $flutterTools = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
  $proofDir = Join-Path $projectRoot 'docs/validation'
  New-Item -ItemType Directory -Force $proofDir | Out-Null
  & $dartRuntime $flutterTools pub get 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object (Join-Path $proofDir 'dependencies.txt')
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
  # Existing style infos are reported; warnings and errors block verification.
  & $dartRuntime $flutterTools analyze --no-pub --no-fatal-infos 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object (Join-Path $proofDir 'analyze.txt')
  if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
  $testArgs = @('test', '--no-pub', '--reporter', 'expanded')
  if ($Quick) { $testArgs += @('test/document_storage_test.dart', 'test/rendering_memory_test.dart', 'test/undo_snapshot_test.dart') }
  & $dartRuntime $flutterTools @testArgs 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object (Join-Path $proofDir 'tests.txt')
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
  if (-not $Quick) {
    & $dartRuntime $flutterTools test --no-pub --reporter expanded --dart-define=OSI_ENABLE_PLUGINS=true --dart-define=OSI_ENABLE_BACKUP=true 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object (Join-Path $proofDir 'tests-experimental.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Experimental profile tests failed' }
  }
  if (-not $SkipWeb -and -not $Quick) {
    & $dartRuntime $flutterTools build web --no-pub 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object (Join-Path $proofDir 'web-build.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
  }
} finally { Pop-Location }


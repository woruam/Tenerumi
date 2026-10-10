param([string]$FlutterRoot = 'C:\src\flutter')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$dart = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$config = Get-Content -LiteralPath (Join-Path $workspace 'tool/plugin_engine_audit/.dart_tool/package_config.json') -Raw | ConvertFrom-Json
$package = $config.packages | Where-Object { $_.name -eq 'fjs' }
if (!$package) { throw 'Eseguire flutter pub get in tool/plugin_engine_audit. Il motore non è una dipendenza dell’app.' }
$packagePath = ([uri]$package.rootUri).LocalPath
$helper = Join-Path $workspace 'build/plugin-test-tool'
$output = Join-Path $workspace 'build/plugin-test-native'
New-Item -ItemType Directory -Force $helper, $output | Out-Null
$dependencyPath = (Join-Path $packagePath 'cargokit/build_tool').Replace('\', '/')
@"
name: osipp_plugin_test_tool
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  build_tool:
    path: '$dependencyPath'
"@ | Set-Content -LiteralPath (Join-Path $helper 'pubspec.yaml') -Encoding utf8
Push-Location $helper
try {
  & $dart pub get
  if ($LASTEXITCODE -ne 0) { throw 'Risoluzione del compilatore non riuscita.' }
} finally { Pop-Location }
$env:CARGOKIT_ROOT_PROJECT_DIR = $workspace
$env:CARGOKIT_TARGET_PLATFORM = 'windows-x64'
$env:CARGOKIT_CONFIGURATION = 'release'
$env:CARGOKIT_MANIFEST_DIR = Join-Path $packagePath 'libfjs'
$env:CARGOKIT_TARGET_TEMP_DIR = $output
$env:CARGOKIT_OUTPUT_DIR = $output
$packages = Join-Path $helper '.dart_tool/package_config.json'
& $dart "--packages=$packages" (Join-Path $packagePath 'cargokit/build_tool/bin/build_tool.dart') build-cmake
if ($LASTEXITCODE -ne 0) { throw 'Download del motore nativo non riuscito.' }
Write-Output 'Motore disponibile soltanto per audit isolato. Non usare questa libreria nell’app.'

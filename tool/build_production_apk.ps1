param(
    [string]$FlutterSdk = 'C:\flutter',
    [string]$Defines = 'output/apk/install-production-defines.json'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
Push-Location $projectDirectory
$previousSigningRequirement = $env:ORG_GRADLE_PROJECT_requireProductionSigning
try {
    if (-not (Test-Path -LiteralPath 'android/key.properties')) {
        throw 'Missing android/key.properties. Supply the production signing configuration before building a production APK.'
    }
    if (-not (Test-Path -LiteralPath $Defines)) {
        throw "Missing production dart defines: $Defines"
    }
    $flutterDart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
    $flutterSnapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
    & $flutterDart $flutterSnapshot test --no-pub --reporter expanded "--dart-define-from-file=$Defines" tool/production_configuration_check_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Production configuration or bundled asset verification failed.' }

    # Gradle must reject its usual local debug-signing fallback for this command.
    $env:ORG_GRADLE_PROJECT_requireProductionSigning = 'true'
    & $flutterDart $flutterSnapshot build apk --release --no-pub "--dart-define-from-file=$Defines"
    if ($LASTEXITCODE -ne 0) { throw 'Production APK build failed.' }

    Write-Output 'APK: build/app/outputs/flutter-apk/app-release.apk'
    Write-Output 'Before distribution, verify the APK signing certificate with Android apksigner and confirm it matches the existing app, if any.'
} finally {
    $env:ORG_GRADLE_PROJECT_requireProductionSigning = $previousSigningRequirement
    Pop-Location
}

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BundledPython = "C:\Users\Windows\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$VenvPython = Join-Path $ProjectDir ".venv\Scripts\python.exe"
$AppName = "AIV0-Batch-Audio-Reviewer-v0.2"

if (-not (Test-Path $VenvPython)) {
    if (-not (Test-Path $BundledPython)) {
        throw "Không tìm thấy Python để tạo môi trường build."
    }
    & $BundledPython -m venv (Join-Path $ProjectDir ".venv")
}

& $VenvPython -m pip install -r (Join-Path $ProjectDir "requirements.txt") -r (Join-Path $ProjectDir "requirements-build.txt")
if ($LASTEXITCODE -ne 0) { throw "Không thể cài dependency build." }
& $VenvPython -m PyInstaller `
    --noconfirm `
    --clean `
    --onefile `
    --windowed `
    --name $AppName `
    --collect-all openpyxl `
    (Join-Path $ProjectDir "app.py")
if ($LASTEXITCODE -ne 0) { throw "PyInstaller build thất bại." }

$ExePath = Join-Path $ProjectDir "dist\$AppName.exe"
if (-not (Test-Path $ExePath)) { throw "Build kết thúc nhưng không tìm thấy EXE." }
Write-Host "EXE: $ExePath"

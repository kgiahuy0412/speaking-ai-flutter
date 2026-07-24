$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $ProjectDir ".venv\Scripts\python.exe"

if (-not (Test-Path $Python)) {
    throw "Chưa có môi trường .venv. Hãy chạy build.ps1 trước."
}

& $Python (Join-Path $ProjectDir "app.py")


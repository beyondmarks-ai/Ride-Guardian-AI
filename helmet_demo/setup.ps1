$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvRoot = Join-Path $demoRoot '.venv'
if (-not (Test-Path (Join-Path $venvRoot 'Scripts\python.exe'))) {
  py -3.11 -m venv $venvRoot
  if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.11 and run setup again.' }
}
& (Join-Path $venvRoot 'Scripts\python.exe') -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'Unable to update pip. Check your internet connection.' }
& (Join-Path $venvRoot 'Scripts\python.exe') -m pip install -r (Join-Path $demoRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
Write-Host 'Webcam demo is ready. Run helmet_demo/run.ps1; Azure CLI is not required.'

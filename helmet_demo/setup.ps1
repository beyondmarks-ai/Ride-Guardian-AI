$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvRoot = 'C:\RideGuardianHelmetEnv'
if (-not (Test-Path (Join-Path $venvRoot 'Scripts\python.exe'))) {
  py -3.11 -m venv $venvRoot
}
& (Join-Path $venvRoot 'Scripts\python.exe') -m pip install --upgrade pip
& (Join-Path $venvRoot 'Scripts\python.exe') -m pip install -r (Join-Path $demoRoot 'requirements.txt')
Write-Host 'Azure Vision-only environment is ready.'

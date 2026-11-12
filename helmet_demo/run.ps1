$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $demoRoot '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) { throw 'Run helmet_demo/setup.ps1 first.' }
& $python (Join-Path $demoRoot 'launch.py')
if ($LASTEXITCODE -ne 0) { throw 'Webcam server stopped with an error. Check the message above.' }

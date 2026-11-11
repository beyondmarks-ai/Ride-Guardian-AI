$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = 'C:\RideGuardianHelmetEnv\Scripts\python.exe'
if (-not (Test-Path $python)) { throw 'Run helmet_demo/setup.ps1 first.' }
Write-Host 'RideGuardian: loading Azure Vision configuration (this may take 10-15 seconds)...'
$env:AZURE_OPENAI_ENDPOINT = 'https://guardian-ai-openai-617db5.openai.azure.com'
$env:AZURE_OPENAI_DEPLOYMENT = 'guardian-vision-accurate'
$env:AZURE_OPENAI_API_VERSION = '2024-10-21'
$env:AZURE_OPENAI_API_KEY = az cognitiveservices account keys list `
  --name 'guardian-ai-openai-617db5' `
  --resource-group 'guardian-ai-rg' `
  --query 'key1' -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not retrieve the RideGuardian vision key.' }
if (-not $env:AZURE_OPENAI_API_KEY) { throw 'Unable to obtain the Azure OpenAI key.' }
Set-Location $demoRoot
Write-Host 'RideGuardian: starting at http://127.0.0.1:8765'
Write-Host 'Keep this window open. Press Ctrl+C to stop the server.'
& $python -m uvicorn app:app --host 127.0.0.1 --port 8765

$ErrorActionPreference = 'Stop'
$project = 'rideguardian-ai-617db5'
$serviceAccount = "rideguardian-push@$project.iam.gserviceaccount.com"
$azureToken = (& az account get-access-token --resource https://management.azure.com --query accessToken -o tsv).Trim()
$settingsUrl = 'https://management.azure.com/subscriptions/617db570-27f6-43a2-8d98-7b067bc2336b/resourceGroups/guardian-ai-rg/providers/Microsoft.Web/sites/rideguardian-api-617db5/config/appsettings'
$azureHeaders = @{Authorization="Bearer $azureToken"}
$settings = Invoke-RestMethod -Method Post -Uri "$settingsUrl/list?api-version=2022-03-01" -Headers $azureHeaders
if (-not $settings.properties.FIREBASE_MESSAGING_CREDENTIALS) {
    $googleToken = (& gcloud auth print-access-token).Trim()
    $key = Invoke-RestMethod -Method Post -Uri "https://iam.googleapis.com/v1/projects/$project/serviceAccounts/$serviceAccount/keys" -Headers @{Authorization="Bearer $googleToken"} -ContentType 'application/json' -Body '{}'
    $credentials = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key.privateKeyData))
    $settings.properties | Add-Member -NotePropertyName FIREBASE_MESSAGING_CREDENTIALS -NotePropertyValue $credentials
    Invoke-RestMethod -Method Put -Uri "$settingsUrl`?api-version=2022-03-01" -Headers $azureHeaders -ContentType 'application/json' -Body ($settings | ConvertTo-Json -Depth 10 -Compress) | Out-Null
    Write-Output 'Push sender credentials stored in Azure Function settings. No credential file created.'
} else {
    Write-Output 'Push credentials already configured; no additional key created.'
}

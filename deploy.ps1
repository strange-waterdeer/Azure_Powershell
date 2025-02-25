# Import module
Import-Module .\AzureModule.psm1 -Force

# Default Param
$params = @{
    ConfigFilePath = ".\AzureInfrastructure-Parameters.json"
    CustomDataBasePath = ".\CustomData"
}

# Deploy
Write-Host "`nInfra Delpoy execute" -ForegroundColor Yellow
Deploy @params

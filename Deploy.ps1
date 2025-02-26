# Import module
Import-Module .\module.psm1 -Force

# Default Param
$params = @{
    ConfigFilePath = ".\param.json"
    CustomDataBasePath = ".\customdata"
}

# Deploy
Write-Host "`nInfra Delpoy execute" -ForegroundColor Yellow
Deploy @params

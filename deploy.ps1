Import-Module .\module.psm1 -Force

$params = @{
    ConfigFilePath = ".\param.json"
    CustomDataBasePath = ".\customdata"
}

Write-Host "`nInfra Delpoy execute" -ForegroundColor Yellow
Deploy @params
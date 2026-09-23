# Debug: fetch GLM quota API and print raw JSON (key read from ../config.ps1)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgFile = Join-Path $dir '..\config.ps1'
if (-not (Test-Path $cfgFile)) { Write-Host 'missing config.ps1 (copy config.example.ps1)'; exit 1 }
. $cfgFile
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$r = Invoke-RestMethod -Uri $Cfg.Url -Headers @{ Authorization = $Cfg.Key } -TimeoutSec 15
$r | ConvertTo-Json -Depth 6

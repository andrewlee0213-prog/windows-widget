# One-time setup: fix UTF-8 BOM on glm-widget.ps1 (zh-CN Windows requirement), create
# Startup shortcut + desktop shortcut + watchdog startup shortcut for the GLM widget.
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

$ps1 = Join-Path $dir 'glm-widget.ps1'
$raw = [IO.File]::ReadAllText($ps1, (New-Object System.Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($ps1, $raw, (New-Object System.Text.UTF8Encoding($true)))
Write-Output 'BOM: ok'

$vbs = Join-Path $dir 'launch.vbs'
$startup = Join-Path ($env:APPDATA + '\Microsoft\Windows\Start Menu\Programs\Startup') 'GLM-widget.lnk'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($startup)
$lnk.TargetPath = 'wscript.exe'
$lnk.Arguments = '"' + $vbs + '"'
$lnk.WorkingDirectory = $dir
$lnk.Save()
Write-Output ('Startup shortcut: ' + $startup)

# Watchdog: keeps the widget alive (auto-relaunch if it dies), also in Startup
$wd = Join-Path $dir 'watchdog.vbs'
$wdStartup = Join-Path ($env:APPDATA + '\Microsoft\Windows\Start Menu\Programs\Startup') 'GLM-watchdog.lnk'
$wlnk = $ws.CreateShortcut($wdStartup)
$wlnk.TargetPath = 'wscript.exe'
$wlnk.Arguments = '"' + $wd + '"'
$wlnk.WorkingDirectory = $dir
$wlnk.Save()
Write-Output ('Watchdog startup: ' + $wdStartup)

# Desktop shortcut for manual relaunch (after exiting the widget)
$desktop = [Environment]::GetFolderPath('Desktop')
$dlnkPath = Join-Path $desktop 'GLM-widget.lnk'
$dlnk = $ws.CreateShortcut($dlnkPath)
$dlnk.TargetPath = 'wscript.exe'
$dlnk.Arguments = '"' + $vbs + '"'
$dlnk.WorkingDirectory = $dir
$dlnk.Save()
Write-Output ('Desktop shortcut: ' + $dlnkPath)

# Dump widget texts with retries
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'GLM Quota Widget')
$w = $null
foreach ($try in 1..3) {
    try { $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond) } catch { $w = $null }
    if ($w) { break }
    Start-Sleep -Seconds 3
}
if (-not $w) { Write-Output 'widget window NOT found'; exit }
Write-Output ('found pid ' + $w.Current.ProcessId + '  rect ' + [int]$w.Current.BoundingRectangle.Width + 'x' + [int]$w.Current.BoundingRectangle.Height)
$textCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
$texts = $null
foreach ($try in 1..3) {
    try { $texts = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond); if ($texts.Count -gt 0) { break } } catch {}
    Start-Sleep -Seconds 3
}
if ($texts) {
    foreach ($t in $texts) { Write-Output ('  | ' + $t.Current.Name) }
} else {
    Write-Output 'no texts after retries'
}

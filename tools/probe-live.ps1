param([switch]$Restart, [switch]$Shot)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Restart) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*glm-widget.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $dir 'launch.vbs') + '"')
    Start-Sleep -Seconds 9
}
Add-Type -ReferencedAssemblies System.Drawing -Name U -Namespace W5 -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern bool EnumWindows(System.IntPtr cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern int GetWindowTextW(System.IntPtr h, System.Text.StringBuilder t, int n);
[DllImport("user32.dll")] public static extern int GetClassNameW(System.IntPtr h, System.Text.StringBuilder t, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out System.Drawing.Rectangle r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(System.IntPtr h, int a, out int v, int c);
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
'@
$script:cpid = (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*glm-widget.ps1*' } | Select-Object -First 1).ProcessId
Write-Host ('widget pid: ' + $script:cpid)
if ($script:cpid) {
    $script:found = New-Object System.Collections.ArrayList
    $cb = {
        param($h, $l)
        $wpid = 0
        [void][W5.U]::GetWindowThreadProcessId($h, [ref]$wpid)
        if ($wpid -eq $script:cpid) {
            $t = New-Object System.Text.StringBuilder 256
            [void][W5.U]::GetWindowTextW($h, $t, 256)
            $c = New-Object System.Text.StringBuilder 256
            [void][W5.U]::GetClassNameW($h, $c, 256)
            $r = New-Object System.Drawing.Rectangle
            [void][W5.U]::GetWindowRect($h, [ref]$r)
            $vis = [W5.U]::IsWindowVisible($h)
            [void]$script:found.Add("hwnd=$h class=$($c.ToString()) title='$($t.ToString())' vis=$vis rect=$r")
        }
        return $true
    }
    [void][W5.U]::EnumWindows([System.Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate([W5.U+EnumProc]$cb), [IntPtr]::Zero)
    if ($script:found.Count) { $script:found | ForEach-Object { Write-Host $_ } } else { Write-Host 'NO WINDOWS for pid' }
    if ($Shot) {
        $vh = $script:found | Where-Object { $_ -match 'vis=True' -and $_ -match 'rect=\{X=\d+,Y=\d+,Width=(\d+),Height=(\d+)\}' } | Select-Object -First 1
        if ($vh -match 'hwnd=(\d+).*rect=\{X=(-?\d+),Y=(-?\d+),Width=(\d+),Height=(\d+)\}') {
            $hx = [int]$Matches[2]; $hy = [int]$Matches[3]; $hw = [int]$Matches[4]; $hh = [int]$Matches[5]
            if ($hw -gt 0 -and $hh -gt 0) {
                Add-Type -AssemblyName System.Drawing
                $b = New-Object System.Drawing.Bitmap($hw, $hh)
                $g = [System.Drawing.Graphics]::FromImage($b)
                $g.CopyFromScreen($hx, $hy, 0, 0, (New-Object System.Drawing.Size($hw, $hh)))
                $out = Join-Path $dir 'widget-shot.png'
                $b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
                $g.Dispose(); $b.Dispose()
                Write-Host ('shot: ' + $out)
            }
        }
    }
    $hwnd = [W5.U]::FindWindow($null, 'GLM Quota Widget')
    Write-Host ('FindWindow by title: ' + $hwnd)
    if ($hwnd -ne [IntPtr]::Zero -and $Shot) {
        $r = New-Object System.Drawing.Rectangle
        [void][W5.U]::GetWindowRect($hwnd, [ref]$r)
        Add-Type -AssemblyName System.Drawing
        $b = New-Object System.Drawing.Bitmap($r.Width, $r.Height)
        $g = [System.Drawing.Graphics]::FromImage($b)
        $g.CopyFromScreen($r.X, $r.Y, 0, 0, (New-Object System.Drawing.Size($r.Width, $r.Height)))
        $out = Join-Path $dir 'widget-shot.png'
        $b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $b.Dispose()
        Write-Host ('shot: ' + $out + ' rect ' + $r)
    }
}
$errlog = Join-Path $dir 'widget-error.log'
Write-Host ('error log: ' + $(if (Test-Path $errlog) { (Get-Content $errlog -Encoding UTF8 | Measure-Object).Count.ToString() + ' lines' } else { 'none' }))

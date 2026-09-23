# GLM Coding Plan 用量桌面挂件 —— WPF 无边框置顶小组件, 零依赖 (Windows PowerShell 5.1 自带)
# 数据源: open.bigmodel.cn 配额接口; 每 5 分钟自动刷新; 拖动移动, 右键菜单
# 注意: 本文件必须保存为 UTF-8 BOM, 否则中文界面会乱码 (跑一次 setup.ps1 即可修复)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

# ---------- 配置 (外置: 复制 config.example.ps1 为 config.ps1 并填入你的 GLM API Key) ----------
$cfgFile = Join-Path $PSScriptRoot 'config.ps1'
if (-not (Test-Path $cfgFile)) {
    Write-Host '缺少 config.ps1 —— 请复制 config.example.ps1 为 config.ps1, 填入 GLM API Key 后再运行'
    exit 1
}
. $cfgFile
# ----------------------------------------------------------------------------------------

# 单实例: 已有挂件在跑就直接退出
$created = $false
$mtx = New-Object System.Threading.Mutex($true, 'Local\GLM-Quota-Widget', [ref]$created)
if (-not $created) { exit }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GLM Quota Widget" Width="650" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False">
  <Border x:Name="Root" CornerRadius="20" Padding="16,14,14,12"
          BorderBrush="#33FFFFFF" BorderThickness="1">
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="0.3,1">
        <GradientStop Color="#F2161E3A" Offset="0"/>
        <GradientStop Color="#E60D1322" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Grid>
      <Rectangle Height="2" VerticalAlignment="Top" Margin="14,1,14,0">
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#55FFFFFF" Offset="0"/>
            <GradientStop Color="#00FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>
    <StackPanel>
      <!-- GLM -->
      <Border CornerRadius="14" BorderThickness="1" BorderBrush="#14FFFFFF" Padding="16,12,14,10" Margin="0,0,0,10">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#12FFFFFF" Offset="0"/>
            <GradientStop Color="#07FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <StackPanel>
          <Grid>
            <StackPanel Orientation="Horizontal">
              <Border Background="#5B9DFF" CornerRadius="2" Width="8" Height="30" VerticalAlignment="Center"/>
              <TextBlock Text="GLM Coding Plan" Foreground="#EAF2FB" FontSize="13" FontWeight="SemiBold"
                         Margin="16,0,0,0" VerticalAlignment="Center"/>
              <Border Background="#265B9DFF" CornerRadius="8" Margin="16,2,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="Level" Text="Pro" Foreground="#8FC2FF" FontSize="10" Padding="12,2"/>
              </Border>
            </StackPanel>
            <TextBlock x:Name="Updated" Text="连接中…" Foreground="#7E93AC" FontSize="10"
                       HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>

          <Grid Margin="0,20,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="84"/>
              <ColumnDefinition Width="340"/>
              <ColumnDefinition Width="80"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="5小时" Foreground="#9FB0C0" FontSize="11" VerticalAlignment="Center"/>
            <Grid Grid.Column="1" VerticalAlignment="Center">
              <Border Background="#1EFFFFFF" CornerRadius="7" Height="14"/>
              <Border x:Name="B1" HorizontalAlignment="Left" Background="#3FB950" CornerRadius="7" Height="14" Width="0"/>
            </Grid>
            <TextBlock x:Name="P1" Grid.Column="2" Text="--" Foreground="#EAF2FB" FontSize="12" FontWeight="SemiBold"
                       TextAlignment="Right" VerticalAlignment="Center"/>
            <TextBlock x:Name="R1" Grid.Column="3" Text="" Foreground="#6E8296" FontSize="10"
                       TextAlignment="Right" VerticalAlignment="Center" Margin="16,0,0,0"/>
          </Grid>

          <Grid Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="84"/>
              <ColumnDefinition Width="340"/>
              <ColumnDefinition Width="80"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="本周" Foreground="#9FB0C0" FontSize="11" VerticalAlignment="Center"/>
            <Grid Grid.Column="1" VerticalAlignment="Center">
              <Border Background="#1EFFFFFF" CornerRadius="7" Height="14"/>
              <Border x:Name="B2" HorizontalAlignment="Left" Background="#3FB950" CornerRadius="7" Height="14" Width="0"/>
            </Grid>
            <TextBlock x:Name="P2" Grid.Column="2" Text="--" Foreground="#EAF2FB" FontSize="12" FontWeight="SemiBold"
                       TextAlignment="Right" VerticalAlignment="Center"/>
            <TextBlock x:Name="R2" Grid.Column="3" Text="" Foreground="#6E8296" FontSize="10"
                       TextAlignment="Right" VerticalAlignment="Center" Margin="16,0,0,0"/>
          </Grid>
          <TextBlock x:Name="GlmCredits" Margin="0,10,0,0" Text="" Foreground="#6C8098" FontSize="9"/>
        </StackPanel>
      </Border>

      <!-- 油价 -->
      <Border CornerRadius="14" BorderThickness="1" BorderBrush="#14FFFFFF" Padding="16,12,14,10" Margin="0,0,0,10">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#12FFFFFF" Offset="0"/>
            <GradientStop Color="#07FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <StackPanel>
          <Grid>
            <StackPanel Orientation="Horizontal">
              <Border Background="#F0A830" CornerRadius="2" Width="8" Height="28" VerticalAlignment="Center"/>
              <TextBlock Text="上海油价" Foreground="#EAF2FB" FontSize="12" FontWeight="SemiBold" Margin="14,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="OilUpdated" Text="" Foreground="#7E93AC" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <Grid Margin="0,12,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="95汽油" Foreground="#9FB0C0" FontSize="11" VerticalAlignment="Center"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <TextBlock x:Name="Oil" Text="--" Foreground="#EAF2FB" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
              <TextBlock Text=" 元/升" Foreground="#6E8296" FontSize="10" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>
          <TextBlock x:Name="OilNote" Margin="0,8,0,0" Text="" Foreground="#6C8098" FontSize="9"/>
          <TextBlock x:Name="OilNext" Margin="0,4,0,0" Text="" Foreground="#6E8296" FontSize="9"/>
        </StackPanel>
      </Border>

      <!-- B站 -->
      <Border CornerRadius="14" BorderThickness="1" BorderBrush="#14FFFFFF" Padding="16,12,14,10" Margin="0,10,0,10">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#12FFFFFF" Offset="0"/>
            <GradientStop Color="#07FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <StackPanel>
          <Grid>
            <StackPanel Orientation="Horizontal">
              <Border Background="#FB7299" CornerRadius="2" Width="8" Height="28" VerticalAlignment="Center"/>
              <TextBlock Text="B站 · 关注更新" Foreground="#EAF2FB" FontSize="12" FontWeight="SemiBold" Margin="14,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="BiliUpdated" Text="" Foreground="#7E93AC" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <StackPanel x:Name="BiliList" Margin="0,8,0,0"/>
        </StackPanel>
      </Border>

      <!-- Anthropic -->
      <Border CornerRadius="14" BorderThickness="1" BorderBrush="#14FFFFFF" Padding="16,12,14,10">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#12FFFFFF" Offset="0"/>
            <GradientStop Color="#07FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <StackPanel>
          <Grid>
            <StackPanel Orientation="Horizontal">
              <Border Background="#D97757" CornerRadius="2" Width="8" Height="28" VerticalAlignment="Center"/>
              <TextBlock Text="Anthropic 研究" Foreground="#EAF2FB" FontSize="12" FontWeight="SemiBold" Margin="14,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="AnthUpdated" Text="" Foreground="#7E93AC" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <StackPanel x:Name="AnthList" Margin="0,8,0,0"/>
        </StackPanel>
      </Border>

      <!-- 手动刷新进度 -->
      <Border x:Name="RpCard" CornerRadius="14" BorderThickness="1" BorderBrush="#14FFFFFF" Padding="16,12,14,12" Margin="0,10,0,10" Visibility="Collapsed">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#12FFFFFF" Offset="0"/>
            <GradientStop Color="#07FFFFFF" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
        <StackPanel>
          <Grid>
            <StackPanel Orientation="Horizontal">
              <Border Background="#5B9DFF" CornerRadius="2" Width="8" Height="28" VerticalAlignment="Center"/>
              <TextBlock Text="刷新进度" Foreground="#EAF2FB" FontSize="12" FontWeight="SemiBold" Margin="14,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="RpCount" Text="0/4" Foreground="#7E93AC" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <Grid Margin="0,10,0,0">
            <Border x:Name="RpTrack" Background="#1EFFFFFF" CornerRadius="3" Height="6"/>
            <Border x:Name="RpBar" HorizontalAlignment="Left" Background="#5B9DFF" CornerRadius="3" Height="6" Width="0"/>
          </Grid>
          <StackPanel Margin="0,10,0,0">
            <TextBlock x:Name="Rp1" Text="" Foreground="#9FB0C0" FontSize="10" Margin="0,0,0,4"/>
            <TextBlock x:Name="Rp2" Text="" Foreground="#9FB0C0" FontSize="10" Margin="0,0,0,4"/>
            <TextBlock x:Name="Rp3" Text="" Foreground="#9FB0C0" FontSize="10" Margin="0,0,0,4"/>
            <TextBlock x:Name="Rp4" Text="" Foreground="#9FB0C0" FontSize="10"/>
          </StackPanel>
        </StackPanel>
      </Border>
      <TextBlock Margin="0,12,0,0" Text="拖动移动 · 右键菜单" Foreground="#6C8098" FontSize="9" HorizontalAlignment="Center"/>
    </StackPanel>
    <Rectangle x:Name="PullTab" HorizontalAlignment="Left" VerticalAlignment="Center" Width="6" Height="64" RadiusX="2" RadiusY="2" Fill="#5B9DFF" Visibility="Collapsed"/>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)

function Set-Row {
    param([string]$Id, $Item, [switch]$Weekly)
    $bar = $win.FindName("B$Id"); $pct = $win.FindName("P$Id"); $rst = $win.FindName("R$Id")
    if ($null -eq $Item -or $null -eq $Item.percentage) {
        $bar.Width = 0; $pct.Text = '--'; $rst.Text = ''; return
    }
    $rem = 100 - [int]$Item.percentage
    if ($Item.usage -and $Item.remaining) { $rem = [int][Math]::Round($Item.remaining / $Item.usage * 100) }
    if ($rem -lt 0) { $rem = 0 }
    if ($rem -gt 100) { $rem = 100 }
    $bar.Width = $Cfg.TrackW * $rem / 100
    $pct.Text = '{0}%' -f $rem
    $hex = if ($rem -le 20) { '#F85149' } elseif ($rem -le 50) { '#D29922' } else { '#3FB950' }
    $bar.Background = (New-Object Windows.Media.BrushConverter).ConvertFromString($hex)
    if ($Item.nextResetTime) {
        $t = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Item.nextResetTime).LocalDateTime
        if ($Weekly) { $rst.Text = '周' + '日一二三四五六'[[int]$t.DayOfWeek] + ' ' + $t.ToString('HH:mm') }
        else { $rst.Text = $t.ToString('HH:mm') + ' 重置' }
    }
}

function Update-Data {
    # 渲染后台线程拉取的GLM数据 (UI线程只读文件, 永不因网络阻塞)
    $f = Join-Path $PSScriptRoot 'glm-data.json'
    if (-not (Test-Path $f)) { return }
    try {
        $r = ConvertFrom-Json ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8))
        if (-not $r.data -or -not $r.data.limits) {
            # 接口错误响应(如服务端500会被后台线程如实落盘): 保留上次的条形图/数值, 只标注状态
            $win.FindName('Updated').Text = (Get-Date).ToString('HH:mm') + ' · 接口错误'
            return
        }
        $lim = @($r.data.limits)
        $five = $lim | Where-Object { $_.unit -eq 3 } | Select-Object -First 1
        $week = $lim | Where-Object { $_.unit -eq 6 } | Select-Object -First 1
        if (-not $five) { $five = $lim[0] }
        if (-not $week) { $week = $lim[1] }
        Set-Row 1 $five
        Set-Row 2 $week -Weekly
        $lv = [string]$r.data.level
        if ($lv.Length -gt 0) { $win.FindName('Level').Text = $lv.Substring(0, 1).ToUpperInvariant() + $lv.Substring(1) }
        $win.FindName('Updated').Text = (Get-Date).ToString('HH:mm') + ' 更新'
        $credits = ''
        if ($five.usage -and $five.remaining) {
            $credits = '5h剩' + $five.remaining + '/' + $five.usage + ' · 本周剩' + $week.remaining + '/' + $week.usage
        }
        $win.FindName('GlmCredits').Text = $credits
        # 后台只在拿到好数据时落盘(错误另写glm-data.json.err), 若错误标记比数据新=接口故障中, 亮旧值
        $errf = Join-Path $PSScriptRoot 'glm-data.json.err'
        if ((Test-Path $errf) -and ((Get-Item $errf).LastWriteTime -gt (Get-Item $f).LastWriteTime)) {
            $win.FindName('Updated').Text = (Get-Date).ToString('HH:mm') + ' · 接口错误(保留旧值)'
        }
    } catch {}
}

function Update-Oil {
    # 上海95号汽油: 金投网油价页, 每24小时拉一次 (调价约每10个工作日一次)
    # 小字行: 调价生效日 + 上期价格(历史调价表第2行) + 下期预估(能源频道首页标题)
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
    $bc = New-Object Windows.Media.BrushConverter
    $qishi = [string][char]0x8D77                                # 起
    $shangqi = -join [char[]](0x4E0A, 0x671F)                    # 上期
    $yuji = -join [char[]](0x9884, 0x8BA1)                       # 预计
    $zhang = [string][char]0x6DA8                                # 涨
    $die = [string][char]0x8DCC                                  # 跌
    try {
        $resp = Invoke-WebRequest -Uri 'https://www.cngold.org/crude/shanghai.html' -UseBasicParsing -TimeoutSec 12 -UserAgent $ua
        $html = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        $i = $html.IndexOf('hq_table1')
        if ($i -lt 0) { throw 'table not found' }
        $seg = $html.Substring($i, [Math]::Min(1000, $html.Length - $i))
        $m = [regex]::Match($seg, '<td>([\d.]+)</td>\s*<td>([\d.]+)</td>\s*<td>([\d.]+)</td>\s*<td>([\d.]+)</td>')
        if (-not $m.Success) { throw 'price not parsed' }
        $cur = [double]$m.Groups[3].Value                        # 列序固定: 89#/92#/95#/0#柴油
        $win.FindName('Oil').Text = $m.Groups[3].Value
        $win.FindName('OilUpdated').Text = (Get-Date).ToString('HH:mm') + ' 更新'
        $note = ''
        $d = [regex]::Match($html, 'class=.data.>\s*(\d{4}-\d{2}-\d{2})')
        if ($d.Success) { $note = $d.Groups[1].Value.Substring(5) + $qishi }
        $rows = [regex]::Matches($html, '<td class=.data.>\s*\d{4}-\d{2}-\d{2}\s*</td>([\s\S]*?)</tr>')
        if ($rows.Count -ge 2) {
            $nums = [regex]::Matches($rows[1].Groups[1].Value, 'class=.nums.>\s*([\d.]+)')
            if ($nums.Count -ge 3) {
                $prev = [double]$nums[2].Groups[1].Value
                $diff = [Math]::Round($cur - $prev, 2)
                $sign = if ($diff -ge 0) { '+' } else { '' }
                $note += ' · ' + $shangqi + $prev + '(' + $sign + $diff + ')'
            }
        }
        $win.FindName('OilNote').Text = $note
        $win.FindName('OilNote').Foreground = $bc.ConvertFromString('#6C8098')
        $oilTimer.Interval = [TimeSpan]::FromHours(24)
        $script:oilOk = $true
    } catch {
        $win.FindName('OilNote').Text = -join [char[]](0x53D6, 0x4EF7, 0x5931, 0x8D25)   # 取价失败
        $win.FindName('OilNote').Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString('#F85149')
        $oilTimer.Interval = [TimeSpan]::FromMinutes(30)   # 失败30分钟后重试, 不等一天
        $script:oilOk = $false
        return
    }
    # 下次调价窗口 + 预估 — 独立降级, 失败时保留上次内容
    try {
        $jin = [string][char]0x4ECA
        $ri = [string][char]0x65E5
        $yue = [string][char]0x6708
        $shi = [string][char]0x65F6
        $sheng = [string][char]0x5347
        $youjia = -join [char[]](0x6CB9, 0x4EF7)                 # 油价
        $tlead = -join [char[]](0x6CB9, 0x4EF7, 0x8C03, 0x6574, 0x6700, 0x65B0, 0x6D88, 0x606F)   # 油价调整最新消息
        $up = -join [char[]](0x4E0A, 0x8C03)                     # 上调
        $dn = -join [char[]](0x4E0B, 0x8C03)                     # 下调
        $gq = -join [char[]](0x6401, 0x6D45)                     # 搁浅
        $szh = -join [char[]](0x4E0A, 0x6DA8)                    # 上涨
        $xdie = -join [char[]](0x4E0B, 0x8DCC)                   # 下跌
        $xiaci = -join [char[]](0x4E0B, 0x6B21)                  # 下次
        $tz2 = -join [char[]](0x8C03, 0x4EF7)                    # 调价
        $yuan = [string][char]0x5143
        $dun = [string][char]0x5428

        $resp2 = Invoke-WebRequest -Uri 'https://energy.cngold.org/' -UseBasicParsing -TimeoutSec 12 -UserAgent $ua
        $h2 = [Text.Encoding]::UTF8.GetString($resp2.RawContentStream.ToArray())

        # 首页标题: 今日(M月D日)油价预计上调/下调/搁浅N元/吨
        $pat = $jin + $ri + '\(\d{1,2}' + $yue + '\d{1,2}' + $ri + '\)' + $youjia + $yuji + '(' + $up + '|' + $dn + '|' + $gq + ')(\d+)?' + $yuan + '/' + $dun
        $mm = [regex]::Match($h2, $pat)

        # 同一条新闻的锚点 -> 文章正文(含调价窗口时间与折合升价区间)
        $win2 = ''
        $rg = $null
        $ma = [regex]::Match($h2, '<a href="([^"]+)"[^>]*title="' + $tlead)
        if ($ma.Success) {
            try {
                $ra = Invoke-WebRequest -Uri $ma.Groups[1].Value -UseBasicParsing -TimeoutSec 12 -UserAgent $ua
                $a = [Text.Encoding]::UTF8.GetString($ra.RawContentStream.ToArray())
                $mw = [regex]::Match($a, '\d{1,2}' + $yue + '\d{1,2}' + $ri + '24' + $shi)
                if ($mw.Success) { $win2 = $mw.Value }           # 例: 9月24日24时
                $md = [regex]::Match($a, '<meta name="description" content="([^"]+)"')
                if ($md.Success) {
                    $rg = [regex]::Match($md.Groups[1].Value, '(' + $szh + '|' + $xdie + ')([\d.]+)' + $yuan + '-([\d.]+)' + $yuan + '/' + $sheng)
                }
            } catch { }
        }

        $ftxt = ''
        if ($mm.Success) {
            $dirn = $mm.Groups[1].Value
            $ftxt = $yuji
            if ($dirn -eq $up) { $ftxt += $zhang } elseif ($dirn -eq $dn) { $ftxt += $die } else { $ftxt += $gq }
            if ($rg -and $rg.Success -and (($dirn -eq $up -and $rg.Groups[1].Value -eq $szh) -or ($dirn -eq $dn -and $rg.Groups[1].Value -eq $xdie))) {
                $ftxt += $rg.Groups[2].Value + '~' + $rg.Groups[3].Value   # 文章自带的折合升价区间
            } elseif ($mm.Groups[2].Value) {
                $ftxt += [Math]::Round([double]$mm.Groups[2].Value / 1350, 2)   # 1吨95#约1350升(兜底)
            }
        }
        $line = ''
        if ($win2) { $line = $xiaci + $tz2 + ' ' + $win2 }
        if ($ftxt) { if ($line) { $line += ' · ' }; $line += $ftxt }
        if ($line) { $win.FindName('OilNext').Text = $line }
    } catch { }
}

function Test-PubToday([string]$pub) {
    # 发布时间文本是否当天 (B站格式: 刚刚/X分钟前/X小时前/X天前/昨天/X月X日)
    if (-not $pub) { return $false }
    $today = (Get-Date).Date
    if ($pub -match '刚刚') { return $true }
    if ($pub -match '\d+分钟前') { return $true }
    if ($pub -match '(\d+)小时前') { return $today -eq ((Get-Date).AddHours(-[double]$Matches[1]).Date) }
    if ($pub -match '(\d{1,2})月(\d{1,2})日') { return ([int]$Matches[1] -eq (Get-Date).Month -and [int]$Matches[2] -eq (Get-Date).Day) }
    return $false
}

function Save-BiliData {
    # 已知的各UP最新视频落盘, 重启后立即回放, 不用等轮询
    try {
        $arr = @()
        foreach ($up in $Cfg.BiliUps) {
            $d = $script:biliData[$up.uid]
            if ($d) { $arr += New-Object psobject -Property @{ uid = $up.uid; name = $d.name; bv = $d.bv; title = $d.title; pub = $d.pub; checked = $d.checked } }
        }
        $json = ConvertTo-Json -InputObject $arr
        [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'bili-data.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}

function Render-Bili {
    $list = $win.FindName('BiliList')
    $list.Children.Clear()
    $ready = 0
    foreach ($up in $Cfg.BiliUps) {
        $d = $script:biliData[$up.uid]
        if (-not $d) { continue }
        $ready++
        $u = 'https://www.bilibili.com/video/' + $d.bv
        $pre = '· ' + $up.name + ' | '
        $budget = 51 - $pre.Length
        if (Test-PubToday $d.pub) { $budget -= 6 }
        $title = $d.title
        if ($title.StartsWith('【' + $up.name + '】')) { $title = $title.Substring($up.name.Length + 2) }   # 去掉自带UP名前缀
        if ($title.Length -gt $budget) { $title = $title.Substring(0, [Math]::Max(4, $budget)) + '…' }
        $bc = New-Object Windows.Media.BrushConverter
        $tb = New-Object Windows.Controls.TextBlock
        $tb.FontSize = 11
        $tb.Cursor = [Windows.Input.Cursors]::Hand
        $tb.Margin = '0,6,0,0'
        $r1 = New-Object System.Windows.Documents.Run -ArgumentList ($pre + $title)
        $r1.Foreground = $bc.ConvertFromString('#C9D6E2')
        $tb.Inlines.Add($r1)
        if (Test-PubToday $d.pub) {
            $r2 = New-Object System.Windows.Documents.Run -ArgumentList ' New'
            $r2.Foreground = $bc.ConvertFromString('#FB7299')
            $r2.FontWeight = [Windows.FontWeights]::Bold
            $tb.Inlines.Add($r2)
        }
        $tb.ToolTip = $up.name + '：' + $d.title + '  (点击打开视频)'
        $tb.Add_MouseLeftButtonDown([scriptblock]::Create('param($s,$e); $e.Handled = $true; Start-Process -FilePath "' + $u + '"'))
        [void]$list.Children.Add($tb)
    }
    if ($ready -gt 0) {
        $win.FindName('BiliUpdated').Text = (Get-Date).ToString('HH:mm') + ' 更新(' + $ready + '/' + $Cfg.BiliUps.Count + ')'
    }
}

# --- B站桥接辅助: 调用超时 + Edge窗口可见性自愈 ---
if (-not ('B7.BRG' -as [type])) {
Add-Type -TypeDefinition '
namespace B7 {
    public struct RCT { public int Left; public int Top; public int Right; public int Bottom; }
    public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
    public class BRG {
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RCT r);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr h, System.IntPtr a, int x, int y, int cx, int cy, uint f);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumWindows(System.IntPtr cb, System.IntPtr l);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool PostMessageW(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
    }
}'}
# --- B站引擎: 全部轮询在后台线程跑(UI永不阻塞), UI侧2秒观察器应用结果 ---
# 通信: $script:biliShared 同步哈希表 — 引擎写 data/progress/status/dirty/done, 观察器消费
$script:biliShared = [hashtable]::Synchronized(@{})
$script:biliShared.data = [hashtable]::Synchronized(@{})
$script:biliShared.kick = 0
$script:biliShared.mode = ''
$script:biliShared.progress = ''
$script:biliShared.status = ''
$script:biliShared.dirty = $false
$script:biliShared.done = $false
$script:biliProbeJs = 'JSON.stringify({u:document.URL,h:!!document.querySelector(''div.bili-video-card'')})'
$script:biliCardJs = 'var c=document.querySelector(''div.bili-video-card'');var o={};o.url=document.URL;if(c){var m=c.innerHTML.match(/BV[0-9A-Za-z]{10}/);var tE=c.querySelector(''.bili-video-card__title'');o.bv=m?m[0]:'''';o.title=tE?(tE.getAttribute(''title'')||tE.textContent.trim()):'''';o.text=(c.innerText||'''').replace(/\s+/g,'' '').substring(0,260)}JSON.stringify(o)'
# 引擎脚本(字符串体内只用双引号, 严禁单引号——外层是跨行单引号字符串)
$biliBg = '
param($Ups, $Dir, $S, $ProbeJs, $NavFmt, $CardJs, $TickMin)
$runner = { param($oa) [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & opencli @oa 2>$null }
function Log([string]$m) {
    try { [IO.File]::AppendAllText(($Dir + "\bili-engine.log"), ((Get-Date).ToString("MM-dd HH:mm:ss ") + $m + [char]13 + [char]10)) } catch {}
}
# WQL字符串值必须单引号包裹(引擎字符串内禁单引号, 用[char]39拼)
$msf = "Name=" + [char]39 + "msedge.exe" + [char]39
function Oc([string[]]$a, [int]$t) {
    $p = [PowerShell]::Create()
    [void]$p.AddScript($runner).AddArgument($a)
    $h = $p.BeginInvoke()
    if ($h.AsyncWaitHandle.WaitOne($t * 1000)) { return ($p.EndInvoke($h) | Out-String) }
    try { $p.Stop() } catch {}
    return $null
}
function BridgeVisible {
    # 桥接Edge窗口离屏/巨宽/最小化都会被Chromium节流(IsWindowVisible对最小化仍true), 每轮前全部归位
    try {
        $script:bpids = @()
        foreach ($pp in (Get-CimInstance Win32_Process -Filter $msf | Where-Object { $_.CommandLine -like "*glm-widget\edge-profile*" -and $_.CommandLine -notlike "*--type=*" })) { $script:bpids += [uint32]$pp.ProcessId }
        if ($script:bpids.Count -eq 0) { return }
        $script:bsw = [W.U32]::GetSystemMetrics(0); $script:bsh = [W.U32]::GetSystemMetrics(1)
        $script:bmove = 0
        $cb = {
            param($h, $l)
            $wp = 0
            [void][B7.BRG]::GetWindowThreadProcessId($h, [ref]$wp)
            if ($script:bpids -contains $wp -and [B7.BRG]::IsWindowVisible($h)) {
                if ([B7.BRG]::IsIconic($h)) { [void][B7.BRG]::ShowWindow($h, 9) }
                $r = New-Object B7.RCT
                [void][B7.BRG]::GetWindowRect($h, [ref]$r)
                if ($r.Right - $r.Left -gt 250 -and $r.Bottom - $r.Top -gt 200) {
                    $off = ($r.Left -lt -50 -or $r.Top -lt -50 -or $r.Right -gt ($script:bsw + 60) -or $r.Bottom -gt ($script:bsh + 60) -or (($r.Right - $r.Left) -gt 700))
                    if ($off) {
                        [void][B7.BRG]::SetWindowPos($h, [IntPtr]::Zero, (8 + $script:bmove * 350), ($script:bsh - 300), 340, 240, 0x14)
                        $script:bmove++
                    }
                }
            }
            return $true
        }
        [void][B7.BRG]::EnumWindows([System.Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate([B7.EnumProc]$cb), [IntPtr]::Zero)
    } catch {}
}
function BridgeStart {
    # 按需拉起桥接Edge(已在则跳过), 等opencli通道就绪(eval探针)
    $pros = @(Get-CimInstance Win32_Process -Filter $msf | Where-Object { $_.CommandLine -like "*glm-widget\edge-profile*" -and $_.CommandLine -notlike "*--type=*" })
    if ($pros.Count -gt 0) { return $true }
    Log("start: launching edge")
    Start-Process -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -ArgumentList @(
        ("--user-data-dir=" + $Dir + "\edge-profile"),
        ("--load-extension=" + $Dir + "\opencli-extension"),
        "--window-size=330,225", "--window-position=8,1050", "--no-first-run", "--disable-gpu", "--hide-crash-restore-bubble"
    ) | Out-Null
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 35) {
        Start-Sleep -Seconds 2
        $pr = Oc @("browser","lc","eval","1+1") 6
        if ($pr -and $pr.Trim() -match "2") { Log("start: ready in " + [int]((Get-Date) - $t0).TotalSeconds + "s"); return $true }
    }
    Log("start: TIMEOUT, opencli通道35秒未就绪")
    return $false
}
function BridgeClose {
    # 优雅关: 每个顶层窗口发WM_CLOSE(让Edge把cookie落盘, 登录态不丢) → 4秒后强杀残留
    try {
        $script:cpids = @()
        foreach ($pp in (Get-CimInstance Win32_Process -Filter $msf | Where-Object { $_.CommandLine -like "*glm-widget\edge-profile*" -and $_.CommandLine -notlike "*--type=*" })) { $script:cpids += [uint32]$pp.ProcessId }
        if ($script:cpids.Count -eq 0) { Log("close: already gone"); return }
        $script:cposts = 0
        $cb = {
            param($h, $l)
            $wp = 0
            [void][B7.BRG]::GetWindowThreadProcessId($h, [ref]$wp)
            if ($script:cpids -contains $wp) { [void][B7.BRG]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero); $script:cposts = $script:cposts + 1 }
            return $true
        }
        [void][B7.BRG]::EnumWindows([System.Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate([B7.EnumProc]$cb), [IntPtr]::Zero)
        Log("close: posted WM_CLOSE x" + $script:cposts)
        Start-Sleep -Seconds 4
        $left = @(Get-CimInstance Win32_Process -Filter $msf | Where-Object { $_.CommandLine -like "*glm-widget\edge-profile*" })
        if ($left.Count -gt 0) {
            Log("close: " + $left.Count + " procs left, force kill")
            $left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } else { Log("close: clean") }
    } catch { Log("close EX: " + $_.Exception.Message) }
}
function PollOne($up, [int]$budget) {
    # 单UP核对: eval导航(秒回) + 就绪轮询 + 提取; 返回 ok/timeout/nolist/empty
    $url = "https://space.bilibili.com/" + $up.uid + "/video"
    $navJs = [string]::Format($NavFmt, $url)
    $why = "timeout"
    $t0 = Get-Date
    $usedOpen = $false
    $empty = 0
    $nolist = 0
    $null = Oc @("browser","lc","eval",$navJs) 8
    while (((Get-Date) - $t0).TotalSeconds -lt $budget) {
        Start-Sleep -Milliseconds 2000
        $pr = Oc @("browser","lc","eval",$ProbeJs) 8
        if (-not $pr) { continue }
        $i2 = $pr.IndexOf("{"); $j2 = $pr.LastIndexOf("}")
        if ($i2 -lt 0 -or $j2 -le $i2) { continue }
        try { $po = ConvertFrom-Json ($pr.Substring($i2, $j2 - $i2 + 1)) } catch { $po = $null }
        if (-not $po) { continue }
        if ($po.u -notlike ("*" + $up.uid + "*")) {
            # 8秒后URL还没切过去 = eval导航没生效, 原生open兜底一次
            if (((Get-Date) - $t0).TotalSeconds -gt 8 -and -not $usedOpen) { $usedOpen = $true; $null = Oc @("browser","lc","open",$url) 20 }
            continue
        }
        if (-not $po.h) {
            # URL对但列表迟迟不出(外壳已渲染): 疑登录失效, 16秒后不再傻等
            $nolist++
            if ($nolist -ge 8) { return "nolist" }
            continue
        }
        $out = Oc @("browser","lc","eval",$CardJs) 8
        if ($out) {
            $i3 = $out.IndexOf("{"); $j3 = $out.LastIndexOf("}")
            if ($i3 -ge 0 -and $j3 -gt $i3) {
                try { $o = ConvertFrom-Json ($out.Substring($i3, $j3 - $i3 + 1)) } catch { $o = $null }
                if ($o -and $o.bv -and ($o.url -like ("*" + $up.uid + "*"))) {
                    $ti = [string]$o.title
                    if ($ti -eq "") { $ti = "（无标题）" }
                    $S.data[$up.uid] = @{ name = $up.name; bv = $o.bv; title = $ti; pub = [string]$o.text; checked = (Get-Date).ToString("MM-dd HH:mm") }
                    return "ok"
                }
            }
        }
        $empty++
        if ($empty -ge 3) { return "empty" }
    }
    return $why
}
$pending = @()
$failRounds = 0
$lastKick = $S.kick
$nextAt = (Get-Date).AddSeconds(20)
while ($true) {
    Start-Sleep -Milliseconds 1500
    $manual = $false
    if ($S.kick -ne $lastKick) { $lastKick = $S.kick; if ($S.mode -eq "manual") { $manual = $true; $nextAt = Get-Date } }
    if ((Get-Date) -lt $nextAt) { continue }
    if ($manual) { $S.progress = "B站 · 正在启动桥接浏览器…" }
    if (-not (BridgeStart)) {
        $S.status = "桥接启动失败 · " + (Get-Date).ToString("HH:mm")
        if ($manual) { $S.progress = "B站 ✗ 桥接浏览器启动失败"; $S.done = $true; $S.mode = "" }
        $nextAt = (Get-Date).AddMinutes(5)
        continue
    }
    BridgeVisible
    $targets = @($Ups)
    if (-not $manual -and $pending.Count -gt 0) { $targets = @($pending) }
    $budget = 45
    if ($manual) { $budget = 25 }
    Log("round: " + $targets.Count + " targets manual=" + $manual + " budget=" + $budget)
    $failNames = @()
    $newPending = @()
    $okAny = $false
    $why = "timeout"
    $k = 0
    foreach ($up in $targets) {
        if ($S.kick -ne $lastKick) { break }   # 手动刷新打断当前轮
        $k++
        if ($manual) { $S.progress = "B站 · " + $k + "/" + $targets.Count + " " + $up.name + " 核对中…" }
        $r = PollOne $up $budget
        if ($r -eq "ok") {
            $okAny = $true
            $S.dirty = $true
            if ($manual) { $S.progress = "B站 · " + $k + "/" + $targets.Count + " " + $up.name + " ✓" }
        } else {
            $why = $r
            $newPending += $up
            $failNames += $up.name
            if ($manual) { $S.progress = "B站 · " + $k + "/" + $targets.Count + " " + $up.name + " ✗" }
        }
    }
    if ($okAny) { $S.dirty = $true }
    if ($failNames.Count -gt 0) {
        if ($why -eq "timeout") { $failRounds = $failRounds + 1 }
        $tag = "加载超时"
        if ($why -eq "empty") { $tag = "拉取为空" }
        if ($why -eq "nolist") { $tag = "列表不加载·请重新登录B站" }
        $S.status = $tag + "(" + ($failNames -join ",") + ") · " + (Get-Date).ToString("HH:mm")
        if ($why -eq "nolist") { $null = Oc @("browser","lc","open","https://passport.bilibili.com/login") 20 }
    } else {
        $failRounds = 0
        $n2 = 0
        foreach ($u2 in $Ups) { if ($S.data.ContainsKey($u2.uid)) { $n2++ } }
        $S.status = (Get-Date).ToString("HH:mm") + " 更新(" + $n2 + "/" + $Ups.Count + ")"
    }
    # 连续3轮timeout类失败 = 桥接僵死, 杀掉重启(登录类失败杀桥接无用)
    if ($failRounds -ge 3) {
        Get-CimInstance Win32_Process -Filter $msf | Where-Object { $_.CommandLine -like "*glm-widget\edge-profile*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
        $failRounds = 0
        $pending = @()
    }
    # 轮后按需关闭浏览器(数据已到手); 登录类失败(nolist)不关——窗口留着亮登录页给用户扫码
    Log("round end: fail=" + $failNames.Count + " why=" + $why)
    if ($why -ne "nolist") { BridgeClose }
    $pending = @($newPending)
    $wait = [TimeSpan]::FromMinutes($TickMin)
    $missing = 0
    foreach ($u3 in $Ups) { if (-not $S.data.ContainsKey($u3.uid)) { $missing++ } }
    if ($pending.Count -gt 0) {
        if ($why -eq "timeout") { $wait = [TimeSpan]::FromMinutes(3) } else { $wait = [TimeSpan]::FromMinutes(60) }
    } elseif ($missing -gt 0) { $wait = [TimeSpan]::FromSeconds(45) }
    $nextAt = (Get-Date).Add($wait)
    if ($manual) {
        if ($failNames.Count -eq 0) { $S.progress = "B站 ✓ " + $targets.Count + "/" + $targets.Count + " 全部核对 " + (Get-Date).ToString("HH:mm:ss") }
        else { $S.progress = "B站 " + ($targets.Count - $failNames.Count) + "/" + $targets.Count + " · " + ($failNames -join ",") + " 失败,稍后自动补试 " + (Get-Date).ToString("HH:mm:ss") }
        $S.done = $true
        $S.mode = ""
    }
}
'
# (Ensure-BridgeVisible/Poll-One/Update-Bili 已并入后台引擎 $biliBg, 旧UI线程版删除)

function Render-Anthropic {
    # 启动时用缓存回放已翻译的标题 (URL 即跳转地址); 当天发布的带 New
    $list = $win.FindName('AnthList')
    $list.Children.Clear()
    $bc = New-Object Windows.Media.BrushConverter
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $n = 0
    foreach ($k in $script:anthItems.Keys) {
        if ($n -ge 3) { break }
        $d = $script:anthItems[$k]
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = '· ' + $d.zh
        $tb.FontSize = 11
        $tb.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString('#C9D6E2')
        $tb.Cursor = [Windows.Input.Cursors]::Hand
        $tb.Margin = '0,6,0,0'
        $tb.ToolTip = '点击打开原文'
        if ($d.cat) {
            $r1 = New-Object System.Windows.Documents.Run -ArgumentList ('  ' + $d.cat)
            $r1.Foreground = $bc.ConvertFromString('#6C8098')
            $r1.FontSize = 9
            $tb.Inlines.Add($r1)
        }
        if ($d.pub -eq $today) {
            $r2 = New-Object System.Windows.Documents.Run -ArgumentList ' New'
            $r2.Foreground = $bc.ConvertFromString('#FB7299')
            $r2.FontWeight = [Windows.FontWeights]::Bold
            $tb.Inlines.Add($r2)
        }
        $tb.Add_MouseLeftButtonDown([scriptblock]::Create('param($s,$e); $e.Handled = $true; Start-Process -FilePath "' + $k + '"'))
        [void]$list.Children.Add($tb)
        $n++
    }
    if ($n -gt 0) { $win.FindName('AnthUpdated').Text = (Get-Date).ToString('HH:mm') + ' (缓存)' }
}

function Update-Anthropic {
    # Anthropic 研究页最新3篇: 抓 research 页, 标题用 GLM glm-4-flash 翻成中文(带缓存)
    $dir = $PSScriptRoot
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
        $resp = Invoke-WebRequest -Uri 'https://www.anthropic.com/research' -UseBasicParsing -TimeoutSec 20 -UserAgent $ua
        $html = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        # 读页内 Publications 表(Date/Category/Title): 比顶部精选卡收录全、更新勤
        $idx = $html.IndexOf('listHeader')
        if ($idx -lt 0) { throw 'publications table not found' }
        $ms = [regex]::Matches($html.Substring($idx), '<li><a href="(/research/[^"]+)"[^>]*>\s*<div[^>]*>\s*<time[^>]*>([^<]+)</time>\s*<span[^>]*>([^<]*)</span>\s*</div>\s*<span[^>]*>([^<]+)</span>')
        if ($ms.Count -eq 0) { throw 'no publications rows' }
        $ci = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
        $arts = @()
        $seenUrl = @{}
        foreach ($m in $ms) {
            $href = 'https://www.anthropic.com' + $m.Groups[1].Value
            if ($seenUrl.ContainsKey($href)) { continue }
            $seenUrl[$href] = $true
            try { $dt = [DateTime]::Parse($m.Groups[2].Value.Trim(), $ci) } catch { continue }
            $ti = [Net.WebUtility]::HtmlDecode(($m.Groups[4].Value -replace '\s+', ' ').Trim())
            $arts += [pscustomobject]@{ href = $href; dt = $dt; title = $ti; cat = $m.Groups[3].Value.Trim() }
        }
        if ($arts.Count -eq 0) { throw 'no articles parsed' }
        $latest = $arts | Sort-Object dt -Descending | Select-Object -First 3
        $need = @($latest | Where-Object { -not $script:anthZh.ContainsKey($_.href) })
        if ($need.Count -gt 0) {
            $lines = @()
            for ($i = 0; $i -lt $need.Count; $i++) { $lines += ('{0}. {1}' -f ($i + 1), $need[$i].title) }
            $prompt = 'Translate these research article titles from English to Chinese. Output only the translations, one per line, keeping the same numbering.'
            $bodyObj = @{ model = 'glm-4-flash'; messages = @(@{ role = 'user'; content = ($prompt + "`n" + ($lines -join "`n")) }) }
            $json = ConvertTo-Json $bodyObj
            $r = Invoke-RestMethod -Uri 'https://open.bigmodel.cn/api/paas/v4/chat/completions' -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' -Headers @{ Authorization = ('Bearer ' + $Cfg.Key) } -TimeoutSec 60
            $content = $r.choices[0].message.content
            foreach ($line in ($content -split "`n")) {
                if ($line -match '^\s*(\d+)[\.、]\s*(.+)$') {
                    $idx = [int]$Matches[1] - 1
                    if ($idx -ge 0 -and $idx -lt $need.Count) { $script:anthZh[$need[$idx].href] = $Matches[2].Trim() }
                }
            }
        }
        # 组装渲染数据: 最新3篇, 当天发布的带New
        $script:anthItems = [ordered]@{}
        foreach ($a in $latest) {
            $zh = $script:anthZh[$a.href]
            $script:anthItems[$a.href] = @{ zh = $(if ($zh) { $zh } else { $a.title }); pub = $a.dt.ToString('yyyy-MM-dd'); cat = $a.cat }
        }
        if ($need.Count -gt 0) {
            $arr = @()
            foreach ($k in $script:anthItems.Keys) { $d = $script:anthItems[$k]; $arr += New-Object psobject -Property @{ url = $k; zh = $d.zh; pub = $d.pub; cat = $d.cat } }
            [IO.File]::WriteAllText((Join-Path $dir 'anthropic-cache.json'), (ConvertTo-Json -InputObject $arr), (New-Object System.Text.UTF8Encoding($false)))
        }
        Render-Anthropic
        $win.FindName('AnthUpdated').Text = (Get-Date).ToString('HH:mm') + ' 更新(' + $script:anthItems.Count + ')'
        # 区块内容改变了高度, 贴边模式下重新吸附+缩回, 否则按锚点回贴
        $win.UpdateLayout()
        if ($script:dockSide) { Dock-Side $script:dockSide; Hide-Dock } else { $win.Top = $script:baseTop - ($win.ActualHeight - $script:baseHeight) }
        $anthTimer.Interval = [TimeSpan]::FromMinutes($Cfg.AnthMin)
        $script:anthOk = $true
    } catch {
        $em = $_.Exception.Message
        if ($em.Length -gt 30) { $em = $em.Substring(0, 30) }
        $win.FindName('AnthUpdated').Text = '抓取失败 · ' + $em
        $anthTimer.Interval = [TimeSpan]::FromMinutes(20)
        $script:anthOk = $false
    }
}

# --- 手动全量刷新: 底部进度面板, 分板块一步一行 ---
# 各步在 Background 优先级执行: "进行中"行先渲染出去, 再进入同步取数(期间窗口静止但进度行可见)
$script:rpDone = 0
$script:rpBusy = $false
$script:rpHideTimer = New-Object Windows.Threading.DispatcherTimer
$script:rpHideTimer.Interval = [TimeSpan]::FromSeconds(8)
$script:rpHideTimer.Add_Tick({
    $script:rpHideTimer.Stop()
    $card = $win.FindName('RpCard')
    if ($card.Visibility -eq 'Visible') {
        $before = $win.ActualHeight
        $card.Visibility = 'Collapsed'
        $win.UpdateLayout()
        if (-not $script:dockSide) { $win.Top = $win.Top + ($before - $win.ActualHeight) }
    }
})
function Set-Rp([int]$idx, [string]$txt, [string]$color) {
    $tb = $win.FindName(('Rp' + $idx))
    $tb.Text = $txt
    $tb.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString($color)
}
function Rp-Advance {
    $script:rpDone++
    $win.FindName('RpCount').Text = "$script:rpDone/4"
    $tw = $win.FindName('RpTrack').ActualWidth
    if ($tw -gt 0) { $win.FindName('RpBar').Width = [Math]::Round($tw * $script:rpDone / 4) }
}
function Rp-Run([scriptblock]$fn) {
    [void]$win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [action]$fn)
}
function Rp-Glm {
    # 触发后台线程立即取数, 等json落盘后渲染 (超时=网络卡, 用缓存值)
    $f = Join-Path $PSScriptRoot 'glm-data.json'
    $trg = Join-Path $PSScriptRoot 'glm-fetch-now'
    $fi = Get-Item $f -ErrorAction SilentlyContinue
    $t0 = if ($fi) { $fi.LastWriteTime } else { [DateTime]::MinValue }
    if ($fi) { Set-Content -Path $trg -Value '1' -Encoding ASCII }
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        $fi2 = Get-Item $f -ErrorAction SilentlyContinue
        if ($fi2 -and $fi2.LastWriteTime -gt $t0) { break }
        Start-Sleep -Milliseconds 400
    }
    Update-Data
    $fi3 = Get-Item $f -ErrorAction SilentlyContinue
    $updTxt = $win.FindName('Updated').Text
    if ($updTxt -match '接口错误') {
        Set-Rp 1 ('GLM · 接口错误(服务端),已保留旧值 ' + (Get-Date).ToString('HH:mm:ss')) '#F0A830'
    } elseif ($fi3 -and $fi3.LastWriteTime -gt $t0) {
        Set-Rp 1 ('GLM 额度 ✓ ' + (Get-Date).ToString('HH:mm:ss')) '#3FB950'
    } else {
        Set-Rp 1 ('GLM 额度 · 响应超时,已用缓存 ' + (Get-Date).ToString('HH:mm:ss')) '#F0A830'
    }
    Rp-Advance
    Set-Rp 2 '上海油价 · 刷新中…' '#EAF2FB'
    Rp-Run ${function:Rp-Oil}
}
function Rp-Oil {
    Update-Oil
    if ($script:oilOk) {
        Set-Rp 2 ('上海油价 ✓ ' + $win.FindName('Oil').Text + '元/升 ' + (Get-Date).ToString('HH:mm:ss')) '#3FB950'
    } else {
        Set-Rp 2 ('上海油价 ✗ 失败,保留旧值 ' + (Get-Date).ToString('HH:mm:ss')) '#F85149'
    }
    Rp-Advance
    Set-Rp 3 ('B站关注 · 全量核对 ' + $Cfg.BiliUps.Count + ' 个UP…') '#EAF2FB'
    Rp-Run ${function:Rp-Bili}
}
function Rp-Bili {
    # 手动路径: 踢后台引擎跑全量核对(25秒/UP预算), 进度行由UI观察器实时刷新, 完成后自动续链Anthropic
    $script:biliShared.mode = 'manual'
    $script:biliShared.kick++
}
function Rp-Anth {
    Update-Anthropic
    if ($script:anthOk) {
        Set-Rp 4 ('Anthropic 研究 ✓ ' + (Get-Date).ToString('HH:mm:ss')) '#3FB950'
    } else {
        Set-Rp 4 ('Anthropic 研究 ✗ 抓取失败 ' + (Get-Date).ToString('HH:mm:ss')) '#F85149'
    }
    Rp-Advance
    $script:rpBusy = $false
    $script:rpHideTimer.Stop(); $script:rpHideTimer.Start()   # 8秒后自动收起面板
}
function Refresh-All {
    if ($script:rpBusy) { return }   # 上一轮还在跑, 忽略重复点击
    $script:rpBusy = $true
    $script:rpHideTimer.Stop()
    $card = $win.FindName('RpCard')
    if ($card.Visibility -ne 'Visible') {
        $before = $win.ActualHeight
        $card.Visibility = 'Visible'
        $win.UpdateLayout()
        if (-not $script:dockSide) { $win.Top = $win.Top - ($win.ActualHeight - $before) }   # 底边不动, 向上生长
    }
    $script:rpDone = 0
    $win.FindName('RpCount').Text = '0/4'
    $win.FindName('RpBar').Width = 0
    Set-Rp 1 'GLM 额度 · 刷新中…' '#EAF2FB'
    Set-Rp 2 '上海油价 · 等待' '#9FB0C0'
    Set-Rp 3 'B站关注 · 等待' '#9FB0C0'
    Set-Rp 4 'Anthropic 研究 · 等待' '#9FB0C0'
    Rp-Run ${function:Rp-Glm}
}

# 拖拽: 系统DragMove(稳定可靠); 松手时靠近屏幕左右缘30DIP内 → 自动吸附该缘并隐藏(留10DIP窄边)
# 拖拽: 原生标题栏拖动通道(WM_NCLBUTTONDOWN), 不会像DragMove那样卡模态循环; 松手后判定吸附
$win.FindName('Root').Add_MouseLeftButtonDown({
    param($s, $e)
    Reset-CardVisual   # 抓取瞬间transform归位, 卡片完整跟随鼠标
    $script:dragStartL = $win.Left
    $script:dragStartT = $win.Top
    $e.Handled = $true
    [W.U32]::ReleaseCapture() | Out-Null
    [void][W.U32]::SendMessage((Get-Hwnd), 0xA1, [System.IntPtr]2, [System.IntPtr]::Zero)   # WM_NCLBUTTONDOWN + HTCAPTION
    $moved = ([Math]::Abs($win.Left - $script:dragStartL) -gt 60 -or [Math]::Abs($win.Top - $script:dragStartT) -gt 60)
    if ($moved) {
        if ($script:dockSide) { Undock }
        if ($mDock.IsChecked) {
            $b = Get-ScreenOf
            if ($win.Top -le ($b.T + 40)) { Dock-Side 'T' }
            elseif ($win.Left -le ($b.L + 40)) { Dock-Side 'L' }
            elseif (($win.Left + $win.ActualWidth) -ge ($b.R - 40)) { Dock-Side 'R' }
            if ($script:dockSide) { Hide-Dock }
        }
        # 拖动后更新高度回贴锚点, 防止后续板块渲染把挂件拽回旧位置
        $script:baseTop = $win.Top
        $script:baseHeight = $win.ActualHeight
    }
})

# --- 贴边隐藏 ---
$script:dockSide = ''
$script:dockHidden = $false
if (-not ('N2.W32' -as [type])) {
Add-Type -TypeDefinition '
namespace N2 {
    public struct RCT { public int Left; public int Top; public int Right; public int Bottom; }
    public struct PT { public int X; public int Y; }
    public struct MONITORINFO { public int cbSize; public RCT rcMonitor; public RCT rcWork; public int dwFlags; }
    public class W32 {
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr MonitorFromWindow(System.IntPtr hwnd, uint dwFlags);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr MonitorFromPoint(PT pt, uint dwFlags);
        [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetMonitorInfo(System.IntPtr hMonitor, ref MONITORINFO lpmi);
    }
}'
}
function Get-Hwnd { return (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle }
function Get-Factor {
    if (-not $script:dpiF) {
        $dpi = [W.U32]::GetDpiForWindow((Get-Hwnd))
        if ($dpi -eq 0) { $dpi = 96 }
        $script:dpiF = $dpi / 96.0
    }
    return $script:dpiF
}
function Get-AllScreensDip {
    # Forms返回物理像素, 除以实测缩放系数换算成窗口DIP坐标 (双屏125%: 主屏物理2880→DIP2304)
    Add-Type -AssemblyName System.Windows.Forms
    $f = Get-Factor
    $r = @()
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $b = $s.Bounds
        $r += [pscustomobject]@{ L = $b.Left / $f; T = $b.Top / $f; R = $b.Right / $f; B = $b.Bottom / $f }
    }
    return $r
}
function Get-PrimaryWork {
    # 主屏工作区(DIP), 与Get-AllScreensDip同口径; 初始摆放/贴边兜底用
    Add-Type -AssemblyName System.Windows.Forms
    $f = Get-Factor
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    return [pscustomobject]@{ L = $wa.Left / $f; T = $wa.Top / $f; R = $wa.Right / $f; B = $wa.Bottom / $f }
}
function Get-ScreenOf {
    # 挂件中心点所在的屏幕 (DIP)
    $cx = $win.Left + $win.ActualWidth / 2
    $cy = $win.Top + $win.ActualHeight / 2
    foreach ($b in (Get-AllScreensDip)) {
        if ($cx -ge $b.L -and $cx -le $b.R -and $cy -ge $b.T -and $cy -le $b.B) { return $b }
    }
    return (Get-AllScreensDip)[0]
}
function Get-NearestSide {
    $b = Get-ScreenOf
    $cands = @(
        [pscustomobject]@{ s = 'L'; d = $win.Left - $b.L }
        [pscustomobject]@{ s = 'R'; d = $b.R - ($win.Left + $win.ActualWidth) }
        [pscustomobject]@{ s = 'T'; d = $win.Top - $b.T }
    )
    return ($cands | Sort-Object d | Select-Object -First 1).s
}
# --- 卡片位移动画: 动Root的RenderTransform, 窗口本体不动 (逐帧挪窗口会闪) ---
$script:tt = New-Object System.Windows.Media.TranslateTransform
$win.FindName('Root').RenderTransform = $script:tt
$script:cardTX = 0.0
$script:cardTY = 0.0
function Animate-CardX([double]$to) {
    $script:cardTX = $to
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList ([double]$script:tt.X, $to, [TimeSpan]::FromMilliseconds(200))
    $a.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
    $a.Add_Completed({ $script:tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null); $script:tt.X = [double]$script:cardTX })
    $script:tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
}
function Animate-CardY([double]$to) {
    $script:cardTY = $to
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList ([double]$script:tt.Y, $to, [TimeSpan]::FromMilliseconds(200))
    $a.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
    $a.Add_Completed({ $script:tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null); $script:tt.Y = [double]$script:cardTY })
    $script:tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a)
}
function Reset-CardVisual {
    # 抓取/拖动/解除前调用: 清动画+transform归零+去裁剪
    $script:tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $script:tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $script:tt.X = 0; $script:tt.Y = 0
    Set-ClipW 0
}
function Dock-Side([string]$s) {
    $b = Get-ScreenOf
    $script:dockSide = $s
    $script:dockRect = $b
    $win.Width = $script:cardW   # 若被Windows半屏吸附改宽, 恢复
    Set-ClipW 0
    # 计算贴边"显示位"(考虑当前transform偏移的视觉位置)
    if ($s -eq 'L') {
        $tl = $b.L
        $tv = [Math]::Max($b.T, [Math]::Min(($win.Top + $script:tt.Y), ($b.B - $win.ActualHeight)))
    }
    elseif ($s -eq 'R') {
        $tl = $b.R - $win.ActualWidth
        $tv = [Math]::Max($b.T, [Math]::Min(($win.Top + $script:tt.Y), ($b.B - $win.ActualHeight)))
    }
    else {   # 顶边: 保持横向位置
        $tv = $b.T
        $tl = [Math]::Max($b.L, [Math]::Min(($win.Left + $script:tt.X), ($b.R - $win.ActualWidth)))
    }
    # 窗口瞬间就位, transform补偿当前视觉位置(无跳变); 紧跟的Hide动画会从补偿值直达隐藏位
    $script:tt.X = ($win.Left + $script:tt.X) - $tl
    $script:tt.Y = ($win.Top + $script:tt.Y) - $tv
    $win.Left = $tl; $win.Top = $tv
    $script:dockLeft = $tl; $script:dockTop = $tv
    $script:dockHidden = $false
    $tab = $win.FindName('PullTab')
    if ($s -eq 'T') { $tab.HorizontalAlignment = 'Center'; $tab.VerticalAlignment = 'Bottom' }
    else { $tab.HorizontalAlignment = 'Left'; $tab.VerticalAlignment = 'Center' }
    if ($mDock) { $mDock.IsChecked = $true }
    Animate-CardX 0; Animate-CardY 0   # 滑到贴边显示位
}
function Set-ClipW([double]$w) {
    # 裁剪Root绘制区域: 右侧贴边隐藏时窗口矩形会伸进副屏上空, 裁掉未绘制部分=视觉隐形+点击穿透
    $root = $win.FindName('Root')
    if ($root.Clip) { $root.Clip.BeginAnimation([System.Windows.Media.RectangleGeometry]::RectProperty, $null) }
    if ($w -le 0) { $root.Clip = $null; return }
    $g = New-Object System.Windows.Media.RectangleGeometry
    $g.Rect = New-Object Windows.Rect -ArgumentList (0.0, 0.0, $w, ($win.ActualHeight + 2))
    $root.Clip = $g
}
function Hide-Dock {
    $b = $script:dockRect
    if (-not $b) { return }
    $win.FindName('PullTab').Visibility = 'Visible'
    $script:dockHidden = $true
    if ($script:dockSide -eq 'L') {
        Animate-CardX (16 - $win.ActualWidth)
    }
    elseif ($script:dockSide -eq 'R') {
        # clip同步收窄 + 卡片右滑出屏
        $g = New-Object System.Windows.Media.RectangleGeometry
        $g.Rect = New-Object Windows.Rect -ArgumentList (0.0, 0.0, ($win.ActualWidth + 2), ($win.ActualHeight + 2))
        $win.FindName('Root').Clip = $g
        $ra = New-Object System.Windows.Media.Animation.RectAnimation
        $ra.From = $g.Rect
        $ra.To = New-Object Windows.Rect -ArgumentList (0.0, 0.0, 16.0, ($win.ActualHeight + 2))
        $ra.Duration = [TimeSpan]::FromMilliseconds(200)
        $ra.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
        $g.BeginAnimation([System.Windows.Media.RectangleGeometry]::RectProperty, $ra)
        Animate-CardX ($win.ActualWidth - 16)
    }
    else {
        Animate-CardY (16 - $win.ActualHeight)
    }
}
function Show-Dock {
    if (-not $script:dockSide) { return }
    if (-not $script:dockHidden) { $hideTimer.Stop(); return }   # 已展开/展开中: 只取消隐藏计时, 不重启动画(否则闪)
    $b = $script:dockRect
    if (-not $b) { return }
    $win.FindName('PullTab').Visibility = 'Collapsed'
    $script:dockHidden = $false
    if ($script:dockSide -eq 'R') {
        # clip从窄条展开 + 卡片左滑回位
        $g = New-Object System.Windows.Media.RectangleGeometry
        $g.Rect = New-Object Windows.Rect -ArgumentList (0.0, 0.0, 16.0, ($win.ActualHeight + 2))
        $win.FindName('Root').Clip = $g
        $ra = New-Object System.Windows.Media.Animation.RectAnimation
        $ra.From = $g.Rect
        $ra.To = New-Object Windows.Rect -ArgumentList (0.0, 0.0, ($win.ActualWidth + 2), ($win.ActualHeight + 2))
        $ra.Duration = [TimeSpan]::FromMilliseconds(220)
        $ra.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
        $ra.Add_Completed({
            $root2 = $win.FindName('Root')
            if ($root2.Clip) { $root2.Clip.BeginAnimation([System.Windows.Media.RectangleGeometry]::RectProperty, $null) }
            $gFull = New-Object System.Windows.Media.RectangleGeometry
            $gFull.Rect = New-Object Windows.Rect -ArgumentList (0.0, 0.0, ($win.ActualWidth + 2), ($win.ActualHeight + 2))
            $root2.Clip = $gFull   # 全幅geometry(不能赋Rect, 类型不符会抛异常引发闪塌循环)
        })
        $g.BeginAnimation([System.Windows.Media.RectangleGeometry]::RectProperty, $ra)
        Animate-CardX 0
    }
    elseif ($script:dockSide -eq 'L') { Animate-CardX 0 }
    else { Animate-CardY 0 }
}
function Undock {
    $script:dockSide = ''
    $script:dockHidden = $false
    $script:dockRect = $null
    Reset-CardVisual
    $win.FindName('PullTab').Visibility = 'Collapsed'
    if ($mDock) { $mDock.IsChecked = $false }
}

$menu = New-Object Windows.Controls.ContextMenu
$mRefresh = New-Object Windows.Controls.MenuItem
$mRefresh.Header = '立即刷新'
$mRefresh.Add_Click({ Refresh-All })
[void]$menu.Items.Add($mRefresh)
$mTop = New-Object Windows.Controls.MenuItem
$mTop.Header = '窗口置顶'
$mTop.IsCheckable = $true
$mTop.IsChecked = $true
$mTop.Add_Click({ $win.Topmost = $mTop.IsChecked })
[void]$menu.Items.Add($mTop)
$mDock = New-Object Windows.Controls.MenuItem
$mDock.Header = '贴边隐藏'
$mDock.IsCheckable = $true
$mDock.Add_Click({ if ($mDock.IsChecked) { Dock-Side (Get-NearestSide); Hide-Dock } else { Undock } })
[void]$menu.Items.Add($mDock)
$mExit = New-Object Windows.Controls.MenuItem
$mExit.Header = '退出'
$mExit.Add_Click({ $win.Close() })
[void]$menu.Items.Add($mExit)
$win.FindName('Root').ContextMenu = $menu

# 出现在主屏右下角
$win.Add_ContentRendered({
    $wa = Get-PrimaryWork
    $win.Left = $wa.R - $win.ActualWidth - 20
    $win.Top = $wa.B - $win.ActualHeight - 20
    $script:baseTop = $win.Top
    $script:baseHeight = $win.ActualHeight
    $script:waRect = $wa
    $script:cardW = $win.Width
    # 注: DWM亚克力方案在这台机器的WPF/.NET组合上渲染为纯黑窗(已实测), 故不启用;
    # 注: 毛玻璃(ACCENT blur)与DWM亚克力在这台机器的Win11 24H2上都会让窗口变透明幽灵/纯黑(已实测),
    # 两者均已禁用; 玻璃质感用高不透明午夜蓝渐变+高光+描边模拟, 渲染100%可靠
})

# GLM数据渲染: 每10秒读后台线程写的json (UI线程无网络操作)
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(10)
$timer.Add_Tick({ Update-Data })
Update-Data
$timer.Start()

# GLM数据后台拉取: 独立线程每60秒 (网络卡死只影响后台线程, UI永不冻结)
$glmFetch = '
param($Url, $Key, $Out)
while ($true) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri $Url -Headers @{ Authorization = $Key } -TimeoutSec 12
        if ($r.data) { $r | ConvertTo-Json -Depth 6 | Set-Content -Path $Out -Encoding UTF8 }
        else { (Get-Date).ToString("o") | Set-Content -Path ($Out + ".err") -Encoding ASCII }
    } catch { }
    # 手动刷新可打断60秒等待: 触发文件出现即立刻再取一轮 (此字符串用跨行单引号包住, 内部禁用单引号)
    $trg = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Out), "glm-fetch-now")
    for ($i = 0; $i -lt 120; $i++) {
        if (Test-Path $trg) { Remove-Item $trg -Force -ErrorAction SilentlyContinue; break }
        Start-Sleep -Milliseconds 500
    }
}
'
try {
    $glmPs = [PowerShell]::Create()
    [void]$glmPs.AddScript($glmFetch).AddArgument($Cfg.Url).AddArgument($Cfg.Key).AddArgument((Join-Path $PSScriptRoot 'glm-data.json'))
    [void]$glmPs.BeginInvoke()
} catch {}

$oilTimer = New-Object Windows.Threading.DispatcherTimer
$oilTimer.Interval = [TimeSpan]::FromHours(24)
$oilTimer.Add_Tick({ Update-Oil })
Update-Oil
$oilTimer.Start()

$script:biliData = @{}
# 回放上次已知的各UP最新视频 (重启不清空, 轮询只做"有没有更新"的增量核对)
$bj = Join-Path $PSScriptRoot 'bili-data.json'
if (Test-Path $bj) {
    try {
        foreach ($s in (ConvertFrom-Json ([IO.File]::ReadAllText($bj, [Text.Encoding]::UTF8)))) {
            if ($s.uid) { $script:biliData[$s.uid] = @{ name = $s.name; bv = $s.bv; title = $s.title; pub = $s.pub; checked = $s.checked } }
        }
    } catch {}
}
Render-Bili
# 回放数据灌进引擎共享表(引擎据此判断谁缺数据)
foreach ($rk in @($script:biliData.Keys)) { $script:biliShared.data[$rk] = $script:biliData[$rk] }
# 观察器: 每2秒应用引擎结果(数据落盘渲染/状态文本/进度行/手动完成续链)
$biliTimer = New-Object Windows.Threading.DispatcherTimer
$biliTimer.Interval = [TimeSpan]::FromSeconds(2)
$biliTimer.Add_Tick({
    $S = $script:biliShared
    if ($S.dirty) {
        $S.dirty = $false
        foreach ($uid2 in @($S.data.Keys)) { $script:biliData[$uid2] = $S.data[$uid2] }
        Save-BiliData
        Render-Bili
        # 高度变化后回贴; 贴边模式下重新吸附+缩回
        $win.UpdateLayout()
        if ($script:dockSide) { Dock-Side $script:dockSide; Hide-Dock } else { $win.Top = $script:baseTop - ($win.ActualHeight - $script:baseHeight) }
    }
    if ($S.status) { $win.FindName('BiliUpdated').Text = $S.status; $S.status = '' }
    if ($S.progress) {
        $col = '#EAF2FB'
        if ($S.progress -match '✓') { $col = '#3FB950' }
        elseif ($S.progress -match '✗') { $col = '#F85149' }
        elseif ($S.progress -match '补试') { $col = '#F0A830' }
        Set-Rp 3 $S.progress $col
        $S.progress = ''
    }
    if ($S.done) {
        $S.done = $false
        Rp-Advance
        Set-Rp 4 'Anthropic 研究 · 刷新中…' '#EAF2FB'
        Rp-Run ${function:Rp-Anth}
    }
})
$biliTimer.Start()
# 启动后台引擎(20秒后首轮全量, 之后自调度; W.U32/B7类型此刻已加载)
try {
    $biliPs = [PowerShell]::Create()
    [void]$biliPs.AddScript($biliBg).AddArgument($Cfg.BiliUps).AddArgument($PSScriptRoot).AddArgument($script:biliShared).AddArgument($script:biliProbeJs).AddArgument("location.href='{0}'").AddArgument($script:biliCardJs).AddArgument([int]$Cfg.BiliTickMin)
    [void]$biliPs.BeginInvoke()
} catch {}

# Anthropic 研究板块: 启动缓存回放 + 2小时刷新
$script:anthZh = @{}
$script:anthItems = [ordered]@{}
$acf = Join-Path $PSScriptRoot 'anthropic-cache.json'
if (Test-Path $acf) {
    try {
        foreach ($p in (ConvertFrom-Json ([IO.File]::ReadAllText($acf, [Text.Encoding]::UTF8)))) {
            if ($p.url) {
                $script:anthZh[$p.url] = $p.zh
                $script:anthItems[$p.url] = @{ zh = $p.zh; pub = $p.pub; cat = $p.cat }
            }
        }
    } catch {}
}
if ($script:anthItems.Count -gt 0) { Render-Anthropic }
$anthTimer = New-Object Windows.Threading.DispatcherTimer
$anthTimer.Interval = [TimeSpan]::FromSeconds(60)
$anthTimer.Add_Tick({ Update-Anthropic })
$anthTimer.Start()

# 贴边隐藏: 鼠标移开0.7秒后缩进, 移上去滑出
$script:dockSide = ''
$script:dockHidden = $false
Add-Type -Name U32 -Namespace W -MemberDefinition '[DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
[DllImport("user32.dll")] public static extern uint GetDpiForWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ReleaseCapture();
[DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);'
$hideTimer = New-Object Windows.Threading.DispatcherTimer
$hideTimer.Interval = [TimeSpan]::FromMilliseconds(700)
$hideTimer.Add_Tick({
    # 收起前确认鼠标真的不在挂件上 (防边缘1px进出抖动)
    if ($script:dockSide -and (-not $win.FindName('Root').IsMouseOver)) { Hide-Dock }
    $hideTimer.Stop()
})
$win.FindName('Root').Add_MouseEnter({ if ($script:dockSide) { Show-Dock }; $hideTimer.Stop() })
$win.FindName('Root').Add_MouseLeave({
    if ($script:dockSide) { $hideTimer.Stop(); $hideTimer.Start() }
})

$app = New-Object Windows.Application
$app.ShutdownMode = [Windows.ShutdownMode]::OnMainWindowClose
$app.Add_DispatcherUnhandledException({
    param($s, $e)
    $e.Handled = $true
    try { [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'widget-error.log'), (Get-Date).ToString('MM-dd HH:mm:ss ') + $e.Exception.Message + "`r`n") } catch {}
})   # 任何处理器异常不再崩溃整个挂件, 记日志便于诊断
[void]$app.Run($win)

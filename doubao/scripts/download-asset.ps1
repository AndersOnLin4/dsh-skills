# Doubao asset download (generic): open chat asset -> preview -> find Save/Download button -> invoke -> handle dialog -> collect file.
# Also supports watch mode: waits for hover-revealed buttons (user hovers; we click).
# Never moves the physical cursor. Use -Action extract in doubao.ps1 as the preferred lossless route.
param(
    [string]$TargetName = 'image',   # chat element name: 'image' (generated picture) | 'Asset cover' (doc card) | custom
    [string]$SaveDir = '.',
    [string]$SaveFile = 'asset',
    [int]$WatchSec = 0,              # >0: first watch for hover-revealed buttons (user must hover), then open preview
    [int]$TimeoutSec = 240
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not ('W32DA' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W32DA {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
}
'@
}
if (-not [W32DA]::SetProcessDpiAwarenessContext([IntPtr](-4))) { [W32DA]::SetProcessDPIAware() | Out-Null }

if (-not (Test-Path $SaveDir)) { New-Item -ItemType Directory -Force -Path $SaveDir | Out-Null }
$SaveDir = (Resolve-Path $SaveDir).Path

# Doubao download dir from Preferences (default_directory), fallback system Downloads
function Get-DoubaoDownloadDir {
    $prefs = Join-Path $env:LOCALAPPDATA 'Doubao\User Data\Default\Preferences'
    try {
        $t = [IO.File]::ReadAllText($prefs)
        $m = [regex]::Match($t, '"download":\s*\{[^}]*"default_directory"\s*:\s*"((?:[^"\\]|\\.)*)"')
        if ($m.Success) {
            $d = ($m.Groups[1].Value -replace '\\u002F', '/' -replace '\\(["\\])', '$1')
            $d = $d -replace '\\\\', '\'
            if ($d -and (Test-Path $d)) { return $d }
        }
    } catch {}
    $dl = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path $dl) { return $dl }
    return $env:TEMP
}

# window-chrome / app-level button names that must never be clicked in watch mode
$chromeNames = @(
    '最小化','最大化','关闭','恢复','取消','确定','技能','AI 创作','云盘','图像生成','PPT 生成','帮我写作','视频生成','深入研究','录音转写','音乐生成','更多','快速','专家',
    '工作任务 Auto','工作任务 Turbo','工作任务 Pro','开启自动播报','朗读','是风儿啊~ 学生免费版','搜索','帮助(&H)','视图滑块','组织','新建文件夹','筛选器下拉列表','折叠组',
    '上一行','下一行','向上翻页','向下翻页','上移行','下移行','Drop Down Button','立即查看','无法撤消','无法重复','置顶','分享','重命名','举报','删除','收藏','反馈与举报',
    '选择云盘文件','截图提问','共享屏幕和应用','上传文件或图片','设置','收藏夹','豆包官网','API 服务','检查更新','帮助与反馈','升级到专业版','切换账号','退出登录'
)

function Get-DoubaoProc {
    Get-Process -Name Doubao -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

function Refresh($hwnd) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty, [int]$hwnd)
    $win = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $win) { throw 'Doubao window UIA element not found' }
    # tree builds async: always re-wake and wait >=2s before FindAll
    [W32DA]::SendMessage([IntPtr]$hwnd, 0x003D, [IntPtr]::Zero, [IntPtr]0xFFFFFFFC) | Out-Null
    Start-Sleep -Milliseconds 2000
    return $win
}

# handle classic (#32770 ctrlid 1148/1) or modern (UIA Edit ValuePattern) save dialog
function Handle-SaveDialog([int]$pidDoubao, [string]$target) {
    $dlg = $null
    foreach ($k in [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($k.Current.ClassName -eq '#32770' -and $k.Current.ProcessId -eq $pidDoubao) { $dlg = $k; break }
    }
    if (-not $dlg) { return $false }
    Write-Output 'save dialog detected; filling path'
    $edit = $null
    foreach ($e in ($dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Edit') {
            $pats = ($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
            if ($pats -contains 'ValuePatternIdentifiers.Pattern') { $edit = $e; break }
        }
    }
    if ($edit) {
        $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($target)
        Start-Sleep -Milliseconds 800
    } else {
        $dlgH = [IntPtr]$dlg.Current.NativeWindowHandle
        $script:clsEdit = [IntPtr]::Zero; $script:clsBtn = [IntPtr]::Zero
        $cb = [W32DA+EnumProc]{
            param($h, $l)
            $sb = New-Object System.Text.StringBuilder 128
            [W32DA]::GetClassName($h, $sb, 128) | Out-Null
            $id = [W32DA]::GetDlgCtrlID($h)
            if ($sb.ToString() -eq 'Edit' -and $id -eq 1148) { $script:clsEdit = $h }
            if ($sb.ToString() -eq 'Button' -and $id -eq 1) { $script:clsBtn = $h }
            return $true
        }
        [W32DA]::EnumChildWindows($dlgH, $cb, [IntPtr]::Zero) | Out-Null
        if ($script:clsEdit -ne [IntPtr]::Zero) {
            [W32DA]::SendMessage($script:clsEdit, 0x000C, [IntPtr]::Zero, ('"{0}"' -f $target)) | Out-Null
            Start-Sleep -Milliseconds 400
        }
        if ($script:clsBtn -ne [IntPtr]::Zero) {
            [W32DA]::SendMessage($script:clsBtn, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
    }
    foreach ($e in ($dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $e.Current.Name -match '^(保存|Save|&Save|是|确定)') {
            $pats = ($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
            if ($pats -contains 'InvokePatternIdentifiers.Pattern') { $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-Output 'dialog confirm invoked'; break }
        }
    }
    Start-Sleep -Seconds 3
    return $true
}

# collect newest file in Doubao download dir that appeared after $since
function Collect-NewDownload([string]$ddir, [datetime]$since, [string]$extFilter) {
    $f = Get-ChildItem $ddir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $since -and ($extFilter -eq '*' -or $_.Extension -in $extFilter) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $f
}

$ddir = Get-DoubaoDownloadDir
Write-Output ("Doubao download dir: {0}" -f $ddir)
$mark = (Get-Date).AddSeconds(-5)
$knownDl = @{}
Get-ChildItem $ddir -File -ErrorAction SilentlyContinue | ForEach-Object { $knownDl[$_.FullName] = $true }
$knownDlPaths = @($knownDl.Keys)

# find window (watch mode waits for it)
$proc = Get-DoubaoProc
if (-not $proc -and $WatchSec -gt 0) {
    $deadline = (Get-Date).AddSeconds($WatchSec)
    while (-not $proc -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5; $proc = Get-DoubaoProc }
}
if (-not $proc) { throw 'Doubao is not running or has no main window' }
$hwnd = $proc.MainWindowHandle

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$openedOnce = $false
$seen = @{}

while ((Get-Date) -lt $deadline) {
    $win = Refresh $hwnd
    $wr = $win.Current.BoundingRectangle
    $winX = [double]$wr.X; $winY = [double]$wr.Y; $winW = [double]$wr.Width; $winH = [double]$wr.Height
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)

    # 1) named download-ish button anywhere (preview Save, dialog-less download)
    $btn = $null
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $e.Current.Name -and $e.Current.Name -match '下载|另存|导出|保存|Download|Save') {
            $pats = ($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
            if ($pats -contains 'InvokePatternIdentifiers.Pattern') { $btn = $e; break }
        }
    }

    # 2) watch mode: new hover-revealed buttons (relative-coord de-dup, chrome blacklist)
    $newCandidates = @()
    if (-not $btn) {
        foreach ($e in $all) {
            if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
            $b = $e.Current.BoundingRectangle
            if ([double]::IsNaN([double]$b.X) -or [double]::IsInfinity([double]$b.X)) { continue }
            $rx = [double]$b.X - $winX; $ry = [double]$b.Y - $winY
            $name = $e.Current.Name
            if ($name -and $chromeNames -contains $name) { continue }
            if ($name -and $name -match '下载|另存|导出|保存|Download|Save') { $newCandidates += ,[pscustomobject]@{El=$e;Rx=$rx;Ry=$ry;Name=$name;Named=$true}; continue }
            if (-not $name) {
                if ($ry -lt 60 -or $ry -gt ($winH * 0.88)) { continue }
                if ($rx -lt ($winW * 0.12) -and $ry -lt ($winH * 0.75)) { continue }
                $pats = ($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
                if ($pats -notcontains 'InvokePatternIdentifiers.Pattern') { continue }
                $key = "{0}|{1}|{2}" -f $name, [int]($rx / 8), [int]($ry / 8)
                if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $newCandidates += ,[pscustomobject]@{El=$e;Rx=$rx;Ry=$ry;Name=$name;Named=$false} }
            }
        }
    }

    if ($btn -or $newCandidates.Count -gt 0) {
        $clickList = @()
        if ($btn) { $clickList += ,[pscustomobject]@{El=$btn;Rx=0;Ry=0;Name=$btn.Current.Name;Named=$true} }
        $clickList += @($newCandidates | Sort-Object Named -Descending | Sort-Object Ry, Rx)
        foreach ($c in $clickList) {
            Write-Output ("click: '{0}'" -f $c.Name)
            try { $c.El.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { continue }
            Start-Sleep -Seconds 3
            if (Handle-SaveDialog $proc.Id (Join-Path $SaveDir ($SaveFile + '.docx'))) { Start-Sleep -Seconds 2 }
            $got = Collect-NewDownload $ddir $mark @('*')
            if ($got) {
                $dest = Join-Path $SaveDir ($SaveFile + $got.Extension)
                Copy-Item -LiteralPath $got.FullName -Destination $dest -Force
                Write-Output ("SAVED: {0} ({1:N0} bytes)" -f $dest, $got.Length)
                exit 0
            }
            $gotDlg = Collect-NewDownload $SaveDir $mark @('.docx','.doc','.png','.jpg','.jpeg','.webp','.zip','.pdf')
            if ($gotDlg) { Write-Output ("SAVED (dialog dir): {0}" -f $gotDlg.FullName); exit 0 }
        }
    }

    # 3) open preview (once) if target element present
    if (-not $openedOnce) {
        $t = $null
        foreach ($e in $all) { if ($e.Current.Name -eq $TargetName) { $t = $e; break } }
        if ($t) {
            $ir = $t.Current.BoundingRectangle
            $container = $null
            foreach ($e in $all) {
                if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Group') {
                    $b = $e.Current.BoundingRectangle
                    if ([double]::IsNaN([double]$b.X) -or [double]::IsInfinity([double]$b.X)) { continue }
                    if ([Math]::Abs([double]$b.X - [double]$ir.X) -lt 6 -and [Math]::Abs([double]$b.Y - [double]$ir.Y) -lt 6) {
                        $pats = ($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
                        if ($pats -contains 'InvokePatternIdentifiers.Pattern') { $container = $e; break }
                    }
                }
            }
            if ($container) {
                Write-Output 'opening preview via container invoke'
                $container.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                $openedOnce = $true
                Start-Sleep -Seconds 3
                continue
            }
        }
    }

    Start-Sleep -Seconds 2
}

Write-Output "timeout: no download triggered. Suggestions: 1) ask the user to hover the cursor over the asset and retry (hover reveals the download button); 2) use doubao.ps1 -Action extract to pull the original from disk cache instead."
exit 1

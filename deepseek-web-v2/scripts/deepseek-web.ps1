# DeepSeek 网页版（chat.deepseek.com）驱动脚本 v2——纯 UIA，零鼠标不抢焦点
# 用法见同目录 SKILL.md
#
# v2 相比 v1 的增强（见 CHANGELOG.md，与 doubao-v2 同一套修复思路）：
#   1) 所有动作自动前置 ensure：浏览器窗口最小化/在主屏外/副屏时自动移回主屏并最大化
#   2) 新增探测动作 probe-windows / probe-buttons / probe-menu：教 agent 按"锚点→候选→验证→降级"方法链自己找控件
#   3) 修复发送后读回复前不重新唤醒无障碍树导致"找不到输入框"的问题

param(
    [ValidateSet('status','open','newchat','send','read','wait','ensure','probe-windows','probe-buttons','probe-menu')]
    [string]$Action = 'status',
    [string]$Text = '',
    [int]$WaitSec = 0,
    [int]$MaxLines = 20,
    [ValidateSet('auto','edge','chrome')]
    [string]$Browser = 'auto',
    [switch]$NewWindow,
    [string]$ButtonAt = ''
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('W32DW' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W32DW {
    public delegate bool EnumWinProc(IntPtr h, IntPtr l);
    public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, ref RECT rect, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

    [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWinProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int cx, int cy, bool repaint);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO mi);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
}
'@
}

# ---------- 窗口就位保障（v2 新增，与 doubao-v2 同思路） ----------

function Get-PrimaryWorkArea {
    $script:primaryWork = $null
    $cb = [W32DW+MonitorEnumProc]{
        param($hMon, $hdc, [ref]$rc, $l)
        $mi = New-Object W32DW+MONITORINFO
        $mi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mi)
        if ([W32DW]::GetMonitorInfo($hMon, [ref]$mi)) {
            if ($mi.dwFlags -band 1) { $script:primaryWork = $mi.rcWork }  # MONITORINFOF_PRIMARY
        }
        return $true
    }
    [W32DW]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero, $cb, [IntPtr]::Zero) | Out-Null
    if (-not $script:primaryWork) { return [pscustomobject]@{ L = 0; T = 0; R = 1920; B = 1080 } }
    return $script:primaryWork
}

function Ensure-WebWindow($win) {
    # 修复实测类问题：浏览器窗口可能被最小化/移到屏幕外/留在副屏，导致 UIA 坐标异常或拿不到输入框
    $h = [IntPtr]$win.Current.NativeWindowHandle
    if ([W32DW]::IsIconic($h)) { [W32DW]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 800 }  # SW_RESTORE
    $wa = Get-PrimaryWorkArea
    $r = New-Object W32DW+RECT
    [W32DW]::GetWindowRect($h, [ref]$r) | Out-Null
    $cx = ($r.L + $r.R) / 2.0; $cy = ($r.T + $r.B) / 2.0
    $onPrimary = ($cx -ge $wa.L -and $cx -lt $wa.R -and $cy -ge $wa.T -and $cy -lt $wa.B)
    if (-not $onPrimary) {
        $w = [Math]::Min(($wa.R - $wa.L), 1600); $hh = [Math]::Min(($wa.B - $wa.T), 1000)
        [W32DW]::MoveWindow($h, $wa.L + 40, $wa.T + 20, $w, $hh, $true) | Out-Null
        Start-Sleep -Milliseconds 600
        Write-Output ("窗口不在主屏，已移回主屏工作区: {0},{1} {2}x{3}" -f ($wa.L + 40), ($wa.T + 20), $w, $hh)
    }
    [W32DW]::ShowWindow($h, 3) | Out-Null  # SW_MAXIMIZE
    Start-Sleep -Milliseconds 800
}

function Get-WindowPhysRect($win) {
    $r = New-Object W32DW+RECT
    [W32DW]::GetWindowRect([IntPtr]$win.Current.NativeWindowHandle, [ref]$r) | Out-Null
    return $r
}

# ---------- 浏览器/窗口定位 ----------

function Find-BrowserExe {
    $names = @()
    if ($Browser -eq 'auto') { $names = @('msedge.exe','chrome.exe') }
    elseif ($Browser -eq 'edge') { $names = @('msedge.exe') }
    else { $names = @('chrome.exe') }
    $dirs = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application')
    )
    foreach ($n in $names) {
        foreach ($d in $dirs) {
            $f = Join-Path $d $n
            if (Test-Path -LiteralPath $f) { return $f }
        }
        $procName = $n -replace '\.exe$',''
        $p = Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path) } | Select-Object -First 1
        if ($p) { return $p.Path }
    }
    throw '未找到 Edge/Chrome 浏览器（可 -Browser edge|chrome 指定，或安装其一）'
}

function Get-ChromeWindows {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    return @($all | Where-Object { $_.Current.ClassName -eq 'Chrome_WidgetWin_1' })
}

function Test-DeepSeekWindow($win) {
    # 标题粗筛：'DeepSeek*'（加载期）或 '* - DeepSeek*'（会话命名后）；排除多标签混合窗口（标题含 '个页面'）
    $t = $win.Current.Name
    if ($t -notlike 'DeepSeek*' -and $t -notlike '* - DeepSeek*') { return $false }
    if ($t -like '*个页面*') { return $false }
    return $true
}

function Get-ChatInputOf($win) {
    # 精筛：唤醒后窗口树里能拿到聊天输入框才算真正的聊天窗口（排除空白标签页）
    try {
        [W32DW]::SendMessage([IntPtr]$win.Current.NativeWindowHandle, 0x003D, [IntPtr]::Zero, [IntPtr]0xFFFFFFFC) | Out-Null
        Start-Sleep -Milliseconds 1000
        return Find-InputEditQuiet (Get-All $win)
    } catch { return $null }
}

function Get-DeepSeekWindow {
    # 默认：复用含聊天输入框的 DeepSeek 专用窗口；-NewWindow 强制新开隔离窗口
    if (-not $NewWindow) {
        foreach ($w in (Get-ChromeWindows)) {
            if (-not (Test-DeepSeekWindow $w)) { continue }
            if (Get-ChatInputOf $w) { return $w }
        }
    }
    $before = @(Get-ChromeWindows | ForEach-Object { $_.Current.NativeWindowHandle })
    $exe = Find-BrowserExe
    Start-Process -FilePath $exe -ArgumentList '--new-window','https://chat.deepseek.com'
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        foreach ($w in (Get-ChromeWindows)) {
            if ($before -notcontains $w.Current.NativeWindowHandle -and (Test-DeepSeekWindow $w) -and (Get-ChatInputOf $w)) { return $w }
        }
    }
    throw '新窗口未就绪（页面加载失败或浏览器未启动）'
}

function Wake-Tree($win) {
    [W32DW]::SendMessage([IntPtr]$win.Current.NativeWindowHandle, 0x003D, [IntPtr]::Zero, [IntPtr]0xFFFFFFFC) | Out-Null
    Start-Sleep -Milliseconds 1200
}

function Get-All($win) {
    return $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
}

# 菜单弹层是独立顶层窗口，挂在 RootElement 下、属于浏览器进程。
# 只在浏览器进程的顶层窗口子树内搜 MenuItem（遍历整个桌面树会被无响应的 provider 卡死——doubao-v2 实测教训）
function Get-PopupMenuItems($win) {
    $pid2 = 0
    [W32DW]::GetWindowThreadProcessId([IntPtr]$win.Current.NativeWindowHandle, [ref]$pid2) | Out-Null
    $pcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$pid2)
    $mic = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)
    $items = @()
    foreach ($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $pcond)) {
        try { foreach ($m in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $mic)) { $items += $m } } catch {}
    }
    return ,$items
}

function Find-InputEditQuiet($all) {
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Edit') { continue }
        if ($e.Current.Name -like '给 DeepSeek 发送消息*' -or $e.Current.Name -like '*发送消息*') {
            try { $null = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); return $e } catch {}
        }
    }
    return $null
}

function Invoke-SendButton($all, $edit) {
    $er = $edit.Current.BoundingRectangle
    $cands = @()
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        $r = $e.Current.BoundingRectangle
        if ($r.X -gt ($er.X + $er.Width * 0.4) -and $r.Y -gt ($er.Y + $er.Height - 80) -and $r.Y -lt ($er.Y + $er.Height + 130)) {
            if (($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -contains 'InvokePatternIdentifiers.Pattern') { $cands += $e }
        }
    }
    if (-not $cands) {
        foreach ($e in $all) {
            if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $e.Current.Name -match '发送|Send') {
                if (($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -contains 'InvokePatternIdentifiers.Pattern') { $cands += $e }
            }
        }
    }
    if (-not $cands) { return $false }
    $send = $cands | Sort-Object { $_.Current.BoundingRectangle.X } -Descending | Select-Object -First 1
    $send.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    return $true
}

function New-Chat($win) {
    $label = $null
    foreach ($e in (Get-All $win)) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and $e.Current.Name -in @('开启新对话','新对话','New chat')) { $label = $e; break }
    }
    if (-not $label) { throw '找不到「开启新对话」按钮' }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $p = $walker.GetParent($label)
    $depth = 0
    while ($p -and $depth -lt 4) {
        if (($p.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -contains 'InvokePatternIdentifiers.Pattern') {
            $p.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Start-Sleep -Seconds 2
            return
        }
        $p = $walker.GetParent($p); $depth++
    }
    throw '「开启新对话」按钮不可调用'
}

function Send-Text($win, $edit, [string]$text) {
    $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($text)
    Start-Sleep -Milliseconds 1500
    if (-not (Invoke-SendButton (Get-All $win) $edit)) { throw '找不到发送按钮（文字可能已写入但未发送）' }
}

function Get-Messages($all, $edit, $maxLines) {
    $doc = $null
    foreach ($e in $all) { if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Document') { $doc = $e; break } }
    $left = -1e9
    $top = -1e9
    $docW = 0
    if ($doc) { $left = $doc.Current.BoundingRectangle.X + 300; $top = $doc.Current.BoundingRectangle.Y + 40; $docW = $doc.Current.BoundingRectangle.Width }
    $er = $edit.Current.BoundingRectangle
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $items = @()
    foreach ($e in $all) {
        $ct = $e.Current.ControlType.ProgrammaticName
        if ($ct -notin @('ControlType.Text','ControlType.ListItem','ControlType.Hyperlink')) { continue }
        $nm = $e.Current.Name
        if (-not $nm) { continue }
        $r = $e.Current.BoundingRectangle
        if ($r.X -lt $left -or $r.Y -lt $top -or $r.Y -gt ($er.Y - 40)) { continue }
        # 排除页面级弹层/浮层元素：其直接 Group 父级铺满整页宽度
        $p = $walker.GetParent($e)
        if ($p -and $p.Current.ControlType.ProgrammaticName -eq 'ControlType.Group' -and $docW -gt 0 -and $p.Current.BoundingRectangle.Width -ge ($docW - 50)) { continue }
        $items += ,[pscustomobject]@{ Y = $r.Y; X = $r.X; Text = $nm }
    }
    # 相邻同文本去重（页面常把思考块在相邻位置暴露两份）
    $out = @()
    $prevText = $null
    foreach ($it in ($items | Sort-Object Y, X)) {
        if ($it.Text -eq $prevText) { continue }
        $prevText = $it.Text
        $out += $it
    }
    return @($out | Select-Object -Last $maxLines)
}

function Wait-ReplyStable($win, $edit, $timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $prev = ''
    $stable = 0
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $msgs = Get-Messages (Get-All $win) $edit 200
        $sig = ($msgs | ForEach-Object { $_.Text }) -join '|'
        if ($sig -and $sig -eq $prev) { $stable++; if ($stable -ge 2) { return $true } } else { $stable = 0 }
        $prev = $sig
    }
    return $false
}

# ---------- 探测动作（v2 新增：方法链的"寻找工具"） ----------

function Show-ProbeWindows {
    $wa = Get-PrimaryWorkArea
    Write-Output ("主屏工作区: {0},{1} - {2},{3}" -f $wa.L, $wa.T, $wa.R, $wa.B)
    Write-Output '浏览器顶层窗口（hwnd | title | rect | visible | iconic | DeepSeek?）:'
    $script:probeLines = New-Object System.Collections.Generic.List[string]
    $cb = [W32DW+EnumWinProc]{
        param($h, $l)
        $cls = New-Object System.Text.StringBuilder 128
        [W32DW]::GetClassName($h, $cls, 128) | Out-Null
        if ($cls.ToString() -ne 'Chrome_WidgetWin_1') { return $true }
        $txt = New-Object System.Text.StringBuilder 256
        [W32DW]::GetWindowText($h, $txt, 256) | Out-Null
        $r = New-Object W32DW+RECT
        [W32DW]::GetWindowRect($h, [ref]$r) | Out-Null
        $isDS = ($txt.ToString() -like 'DeepSeek*' -or $txt.ToString() -like '* - DeepSeek*')
        $script:probeLines.Add(("  h=$h title='$($txt.ToString())' rect=$($r.L),$($r.T),$($r.R),$($r.B) visible=$([W32DW]::IsWindowVisible($h)) iconic=$([W32DW]::IsIconic($h)) ds=$isDS"))
        return $true
    }
    [W32DW]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    if ($script:probeLines.Count -eq 0) { Write-Output '  （无 Chrome_WidgetWin_1 窗口：浏览器未运行，先 -Action open 拉起）' } else { $script:probeLines | ForEach-Object { Write-Output $_ } }
}

function Show-ProbeButtons($win) {
    Wake-Tree $win
    $all = Get-All $win
    $edit = Find-InputEditQuiet $all
    if ($edit) {
        $r = $edit.Current.BoundingRectangle
        Write-Output ("输入框(锚点): {0},{1},{2},{3}" -f $r.X, $r.Y, $r.Width, $r.Height)
    } else {
        Write-Output '输入框: 未找到（树可能未唤醒，重跑一次）'
    }
    Write-Output '按钮清单（Name | x,y,w,h | 模式）:'
    $n = 0
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        $n++
        $r = $e.Current.BoundingRectangle
        $pats = (($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName -replace 'PatternIdentifiers\.Pattern','' }) -join '+')
        Write-Output ("  [{0}] '{1}' | {2},{3},{4},{5} | {6}" -f $n, $e.Current.Name, $r.X, $r.Y, $r.Width, $r.Height, $pats)
    }
    Write-Output "共 $n 个按钮。选择候选时优先看「与锚点的相对位置 + 模式」，点击前用 probe-menu 验证。"
}

function Show-ProbeMenu($win, [string]$buttonAt) {
    $xy = $buttonAt -split ','
    if ($xy.Count -lt 2) { throw '需要 -ButtonAt x,y（取自 probe-buttons 输出的按钮矩形内任一点）' }
    $x = [int]$xy[0]; $y = [int]$xy[1]
    Wake-Tree $win
    $btn = $null
    foreach ($e in (Get-All $win)) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        $r = $e.Current.BoundingRectangle
        if ($x -ge $r.X -and $x -lt ($r.X + $r.Width) -and $y -ge $r.Y -and $y -lt ($r.Y + $r.Height)) { $btn = $e; break }
    }
    if (-not $btn) { throw '该坐标处没有按钮（界面可能变了，先重跑 probe-buttons 取最新坐标）' }
    try { $ecp = $btn.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern) } catch { throw '该按钮不支持 ExpandCollapse，无法展开（换一个候选）' }
    Write-Output ("展开按钮: '{0}' ({1},{2},{3},{4})" -f $btn.Current.Name, $btn.Current.BoundingRectangle.X, $btn.Current.BoundingRectangle.Y, $btn.Current.BoundingRectangle.Width, $btn.Current.BoundingRectangle.Height)
    if ($ecp.Current.ExpandCollapseState -eq [System.Windows.Automation.ExpandCollapseState]::Expanded) { $ecp.Collapse(); Start-Sleep -Milliseconds 500 }
    try { $ecp.Expand() } catch {}
    Start-Sleep -Milliseconds 1200
    $wr = Get-WindowPhysRect $win
    $shown = 0
    foreach ($m in (Get-PopupMenuItems $win)) {
        $r = $m.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0 -or -not $m.Current.Name) { continue }
        $mcx = $r.X + $r.Width / 2.0; $mcy = $r.Y + $r.Height / 2.0
        if ($mcx -ge ($wr.L - 300) -and $mcx -le ($wr.R + 300) -and $mcy -ge ($wr.T - 300) -and $mcy -le ($wr.B + 300)) {
            $shown++
            Write-Output ("  菜单项 '{0}' | {1},{2},{3},{4}" -f $m.Current.Name, $r.X, $r.Y, $r.Width, $r.Height)
        }
    }
    if ($shown -eq 0) { Write-Output '（未发现可见菜单项：可能展开失败或菜单挂载较慢，重跑一次）' }
    try { $ecp.Collapse() } catch {}  # 探测完毕收起菜单，不留垃圾状态
}

try {
    # probe-windows 是纯诊断动作：不强制拉起/归位窗口（窗口都拿不到时也能诊断）
    if ($Action -eq 'probe-windows') {
        Show-ProbeWindows
        exit 0
    }

    $win = Get-DeepSeekWindow
    Ensure-WebWindow $win  # v2 新增：还原最小化 + 移回主屏 + 最大化

    # 等页面就绪：轮询输入框（最多约30s）；若出现登录按钮说明未登录
    $edit = $null
    $login = $null
    for ($i = 0; $i -lt 12; $i++) {
        Wake-Tree $win
        $all = Get-All $win
        $edit = Find-InputEditQuiet $all
        if ($edit) { break }
        $login = $all | Where-Object { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $_.Current.Name -match '登录|Sign in' } | Select-Object -First 1
        if ($login) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $edit) {
        if ($Action -eq 'open') { Write-Output '窗口已打开（尚未登录：请手动登录 chat.deepseek.com）'; exit 0 }
        if ($login) { throw '网页未登录：请让用户手动登录 chat.deepseek.com 后重试' }
        throw '页面未就绪：找不到输入框（网络慢？重试一次）'
    }

    switch ($Action) {
        'status' {
            $doc = ($all | Where-Object { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Document' } | Select-Object -First 1).Current.Name
            $val = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
            Write-Output "页面: $doc"
            Write-Output "输入框: $(if ($val) { $val } else { '(空)' })"
            $msgs = Get-Messages $all $edit 3
            Write-Output "最近消息: $($msgs.Count) 条"
            $msgs | ForEach-Object { Write-Output ("  " + $_.Text) }
        }
        'ensure' {
            $r = Get-WindowPhysRect $win
            Write-Output ("窗口已就位: title='$($win.Current.Name)' rect=$($r.L),$($r.T),$($r.R),$($r.B)")
        }
        'open' { Write-Output '窗口已就绪（已登录）' }
        'newchat' { New-Chat $win; Write-Output '已开新会话' }
        'send' {
            if ($Text) {
                Send-Text $win $edit $Text
                Write-Output "已发送: $Text"
            }
            if ($WaitSec -gt 0) {
                Wake-Tree $win  # v2 修复：发送后界面重渲染，先重新唤醒树再定位（v1 直接 Get-All 会拿到过期树）
                $edit2 = Find-InputEditQuiet (Get-All $win)
                if (-not $edit2) { $edit2 = $edit }
                $done = Wait-ReplyStable $win $edit2 $WaitSec
                Write-Output ($(if ($done) { '回复生成完毕' } else { '等待超时（可能仍在生成）' }) + ':')
                Get-Messages (Get-All $win) $edit2 $MaxLines | ForEach-Object { Write-Output ("  " + $_.Text) }
            }
        }
        'read' {
            Wake-Tree $win
            $edit = Find-InputEditQuiet (Get-All $win)
            if (-not $edit) { throw '找不到输入框（树未唤醒，重试一次）' }
            Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output $_.Text }
        }
        'wait' {
            if ($WaitSec -le 0) { $WaitSec = 60 }
            Wake-Tree $win
            $edit = Find-InputEditQuiet (Get-All $win)
            if (-not $edit) { throw '找不到输入框（树未唤醒，重试一次）' }
            $done = Wait-ReplyStable $win $edit $WaitSec
            Write-Output ($(if ($done) { '回复生成完毕' } else { '等待超时' }))
            Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output $_.Text }
        }
        'probe-buttons' {
            Show-ProbeButtons $win
        }
        'probe-menu' {
            Show-ProbeMenu $win $ButtonAt
        }
    }
} catch {
    Write-Output "DEEPSEEK_WEB_ERROR: $($_.Exception.Message)"
    exit 1
}

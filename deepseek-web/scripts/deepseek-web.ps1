# DeepSeek 网页版（chat.deepseek.com）驱动脚本——纯 UIA，零鼠标不抢焦点
# 用法见同目录 SKILL.md

param(
    [ValidateSet('status','open','newchat','send','read','wait')]
    [string]$Action = 'status',
    [string]$Text = '',
    [int]$WaitSec = 0,
    [int]$MaxLines = 20,
    [ValidateSet('auto','edge','chrome')]
    [string]$Browser = 'auto',
    [switch]$NewWindow
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('W32DW' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class W32DW {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@
}

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

try {
    $win = Get-DeepSeekWindow
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
        'open' { Write-Output '窗口已就绪（已登录）' }
        'newchat' { New-Chat $win; Write-Output '已开新会话' }
        'send' {
            if ($Text) {
                Send-Text $win $edit $Text
                Write-Output "已发送: $Text"
            }
            if ($WaitSec -gt 0) {
                $done = Wait-ReplyStable $win $edit $WaitSec
                Write-Output ($(if ($done) { '回复生成完毕' } else { '等待超时（可能仍在生成）' }) + ':')
                Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output ("  " + $_.Text) }
            }
        }
        'read' { Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output $_.Text } }
        'wait' {
            if ($WaitSec -le 0) { $WaitSec = 60 }
            $done = Wait-ReplyStable $win $edit $WaitSec
            Write-Output ($(if ($done) { '回复生成完毕' } else { '等待超时' }))
            Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output $_.Text }
        }
    }
} catch {
    Write-Output "DEEPSEEK_WEB_ERROR: $($_.Exception.Message)"
    exit 1
}

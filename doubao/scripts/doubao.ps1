# 豆包桌面版（进程名 Doubao.exe，自动定位，与安装路径无关）驱动脚本
# 全程 UIA + Win32 消息注入，不移动鼠标、不抢焦点，不影响用户办公。
#
# 用法（在 pwsh 中执行，脚本路径按实际 skill 目录拼接）:
#   & '<skill目录>\scripts\doubao.ps1' -Action status
#   & '<skill目录>\scripts\doubao.ps1' -Action newchat
#   & '<skill目录>\scripts\doubao.ps1' -Action mode -Mode 快速  # 快速 | 专家 | 工作任务 Auto | 工作任务 Turbo | 工作任务 Pro
#   & '<skill目录>\scripts\doubao.ps1' -Action send -Text '你好' -WaitSec 20 -MaxLines 8
#   & '<skill目录>\scripts\doubao.ps1' -Action send -Text '看图说话' -Files 'C:\a.png','C:\b.txt'
#   & '<skill目录>\scripts\doubao.ps1' -Action read -MaxLines 10
#   & '<skill目录>\scripts\doubao.ps1' -Action wait -WaitSec 60  # 等待回复生成完毕

param(
    [ValidateSet('status','newchat','mode','send','attach','read','wait')]
    [string]$Action = 'status',
    [string]$Text = '',
    [string[]]$Files = @(),
    [string]$Mode = '',
    [int]$WaitSec = 0,
    [int]$MaxLines = 20,
    [switch]$NewChat
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('W32Doubao' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W32Doubao {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
}
'@
}

function Get-MainWindow {
    $p = Get-Process -Name Doubao -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $p) { throw '豆包未运行或没有主窗口（请先启动并登录豆包桌面版）' }
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty, [int]$p.MainWindowHandle)
    $win = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $win) { throw '找不到豆包主窗口的 UIA 元素' }
    return $win
}

function Wake-Tree($win) {
    # 向窗口发 WM_GETOBJECT 唤醒 Chromium 无障碍树（否则树里只有窗口按钮）
    [W32Doubao]::SendMessage([IntPtr]$win.Current.NativeWindowHandle, 0x003D, [IntPtr]::Zero, [IntPtr]0xFFFFFFFC) | Out-Null
    Start-Sleep -Milliseconds 1500
}

function Get-All($win) {
    return $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
}

function Find-InputEdit($all) {
    # 聊天输入框：支持 ValuePattern 的 Edit 中，底部最宽的那个（不依赖占位符文本，工作任务模式下占位符不同）
    $best = $null
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Edit') { continue }
        try { $null = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern) } catch { continue }
        $r = $e.Current.BoundingRectangle
        if ($r.Width -gt 300 -and $r.Height -gt 20) {
            if (-not $best -or $r.Width -gt $best.Current.BoundingRectangle.Width) { $best = $e }
        }
    }
    if (-not $best) { throw '找不到消息输入框（无障碍树可能未唤醒，重试或先跑 -Action status）' }
    return $best
}

function Invoke-SendButton($all, $edit) {
    # 发送按钮 = 输入框右下方的无名 Button；同坐标常有 Invoke/ExpandCollapse 两个变体，必须选支持 Invoke 的
    $r = $edit.Current.BoundingRectangle
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        $br = $e.Current.BoundingRectangle
        if ($br.X -gt ($r.X + $r.Width - 160) -and $br.Y -gt ($r.Y + 20) -and $br.Y -lt ($r.Y + 140)) {
            if (($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -contains 'InvokePatternIdentifiers.Pattern') {
                $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                return $true
            }
        }
    }
    return $false
}

function Get-ModeChip($all, [string]$mode) {
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        if ($e.Current.Name -eq $mode) { return $e }
    }
    return $null
}

function Set-Mode($win, [string]$mode) {
    Wake-Tree $win
    $all = Get-All $win
    if (Get-ModeChip $all $mode) { Write-Output "模式已是 $mode"; return }
    # 找到当前模式芯片（Button 且名字是任一模式名）并展开
    $chip = $null
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        if ($e.Current.Name -in @('快速','专家','工作任务 Auto','工作任务 Turbo','工作任务 Pro')) { $chip = $e; break }
    }
    if (-not $chip) { throw '找不到模式切换芯片' }
    try { $chip.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch {}
    Start-Sleep -Milliseconds 700
    $item = $null
    foreach ($e in (Get-All $win)) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.MenuItem' -and $e.Current.Name -like "$mode*") { $item = $e; break }
    }
    if (-not $item) { throw "模式菜单里找不到 '$mode'（下拉可能没展开，重试一次）" }
    $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    # 菜单项生效有 3-5 秒延迟
    Start-Sleep -Seconds 4
    Write-Output ("模式切换完成: " + $(if (Get-ModeChip (Get-All $win) $mode) { $mode } else { "$mode (未确认到芯片变化，多半已生效)" }))
}

function New-Chat($win) {
    Wake-Tree $win
    $label = $null
    foreach ($e in (Get-All $win)) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and $e.Current.Name -eq '新对话') { $label = $e; break }
    }
    if (-not $label) { throw '找不到侧栏「新对话」按钮' }
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
    throw '「新对话」按钮不可调用'
}

function Send-Text($win, [string]$text) {
    Wake-Tree $win
    $edit = Find-InputEdit (Get-All $win)
    $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($text)
    Start-Sleep -Milliseconds 1200
    if (-not (Invoke-SendButton (Get-All $win) $edit)) { throw '找不到可调用的发送按钮（文字可能已写入但未发送）' }
}

function Add-Attachments($win, [string[]]$files) {
    Wake-Tree $win
    $all = Get-All $win
    $edit = Find-InputEdit $all
    $er = $edit.Current.BoundingRectangle
    # 附件(+)按钮：输入框左下方、支持 ExpandCollapse 的无名 Button
    $plus = $null
    foreach ($e in $all) {
        if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
        $br = $e.Current.BoundingRectangle
        if ($br.X -gt ($er.X - 80) -and $br.X -lt $er.X -and $br.Y -gt ($er.Y + 30) -and $br.Y -lt ($er.Y + 130)) {
            if (($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -contains 'ExpandCollapsePatternIdentifiers.Pattern') { $plus = $e; break }
        }
    }
    if (-not $plus) { throw '找不到附件(+)按钮' }
    $plus.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Start-Sleep -Milliseconds 900
    $up = $null
    foreach ($e in (Get-All $win)) {
        if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.MenuItem' -and $e.Current.Name -eq '上传文件或图片') { $up = $e; break }
    }
    if (-not $up) { throw '找不到「上传文件或图片」菜单项' }
    $up.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 2
    # 弹出的系统文件对话框是豆包主窗口的 #32770 子窗口
    $dlg = $null
    foreach ($k in $win.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($k.Current.ClassName -eq '#32770') { $dlg = $k; break }
    }
    if (-not $dlg) {
        # 备选：在根元素下找豆包进程的 #32770
        foreach ($k in [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
            if ($k.Current.ClassName -eq '#32770' -and $k.Current.ProcessId -eq (Get-Process -Name Doubao -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).Id) { $dlg = $k; break }
        }
    }
    if (-not $dlg) { throw '文件对话框未出现' }
    $dlgH = [IntPtr]$dlg.Current.NativeWindowHandle
    $script:dlgEdit = [IntPtr]::Zero
    $script:dlgBtn = [IntPtr]::Zero
    $cb = [W32Doubao+EnumProc]{
        param($h, $l)
        $cls = New-Object System.Text.StringBuilder 128
        [W32Doubao]::GetClassName($h, $cls, 128) | Out-Null
        $id = [W32Doubao]::GetDlgCtrlID($h)
        if ($cls.ToString() -eq 'Edit' -and $id -eq 1148) { $script:dlgEdit = $h }
        if ($cls.ToString() -eq 'Button' -and $id -eq 1) { $script:dlgBtn = $h }
        return $true
    }
    [W32Doubao]::EnumChildWindows($dlgH, $cb, [IntPtr]::Zero) | Out-Null
    if ($script:dlgEdit -eq [IntPtr]::Zero -or $script:dlgBtn -eq [IntPtr]::Zero) { throw '文件对话框控件未找到（需要 ctrlid=1148 的文件名框和 ctrlid=1 的打开按钮）' }
    # 多文件：'"路径1" "路径2"'（必须带引号）；WM_SETTEXT + BM_CLICK 纯消息注入，不动鼠标
    $quoted = ($files | ForEach-Object { '"' + $_.Trim('"') + '"' }) -join ' '
    [W32Doubao]::SendMessage($script:dlgEdit, 0x000C, [IntPtr]::Zero, $quoted) | Out-Null
    Start-Sleep -Milliseconds 500
    [W32Doubao]::SendMessage($script:dlgBtn, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Seconds 1
}

function Get-Messages($all, $edit, $maxLines) {
    $er = $edit.Current.BoundingRectangle
    $left = $er.X - 50
    $items = @()
    foreach ($e in $all) {
        $ct = $e.Current.ControlType.ProgrammaticName
        if ($ct -notin @('ControlType.Text','ControlType.ListItem','ControlType.Hyperlink')) { continue }
        $nm = $e.Current.Name
        if (-not $nm) { continue }
        $r = $e.Current.BoundingRectangle
        if ($r.X -lt $left -or $r.Y -lt 80 -or $r.Y -gt ($er.Y - 10)) { continue }
        $items += ,[pscustomobject]@{ Y = $r.Y; X = $r.X; Text = $nm }
    }
    return @($items | Sort-Object Y, X | Select-Object -Last $maxLines)
}

function Wait-ReplyStable($win, $edit, $timeoutSec) {
    # 轮询消息区文本签名，连续两轮不变即认为生成结束
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
    $win = Get-MainWindow
    Wake-Tree $win
    $all = Get-All $win
    $edit = $null
    try { $edit = Find-InputEdit $all } catch {}

    switch ($Action) {
        'status' {
            $doc = ($all | Where-Object { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Document' } | Select-Object -First 1).Current.Name
            $chip = ($all | Where-Object { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $_.Current.Name -in @('快速','专家','工作任务 Auto','工作任务 Turbo','工作任务 Pro') } | Select-Object -First 1).Current.Name
            $val = ''
            if ($edit) { $val = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
            Write-Output "窗口: $doc"
            Write-Output "模式: $(if ($chip) { $chip } else { '未知' })"
            Write-Output "输入框内容: $val"
        }
        'newchat' {
            New-Chat $win
            Write-Output '已开新会话'
        }
        'mode' {
            if (-not $Mode) { throw '需要 -Mode（快速|专家|工作任务 Auto|工作任务 Turbo|工作任务 Pro）' }
            Set-Mode $win $Mode
        }
        'send' {
            if ($NewChat) { New-Chat $win; $all = Get-All $win; $edit = Find-InputEdit $all }
            if ($Files) { Add-Attachments $win $Files }
            if ($Text) {
                Send-Text $win $Text
                Write-Output "已发送: $Text"
            } else { Write-Output '已添加附件（未发文字，可继续 -Action send -Text ...）' }
            if ($WaitSec -gt 0) {
                $all = Get-All $win; $edit2 = Find-InputEdit $all
                $done = Wait-ReplyStable $win $edit2 $WaitSec
                Write-Output ($(if ($done) { '回复生成完毕' } else { '等待超时（可能仍在生成）' }) + ':')
                Get-Messages (Get-All $win) $edit2 $MaxLines | ForEach-Object { Write-Output ("  " + $_.Text) }
            }
        }
        'attach' {
            if (-not $Files) { throw '需要 -Files' }
            Add-Attachments $win $Files
            Write-Output '附件已加入输入框'
        }
        'read' {
            if (-not $edit) { throw '找不到输入框，无法定位消息区' }
            Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output $_.Text }
        }
        'wait' {
            if ($WaitSec -le 0) { $WaitSec = 60 }
            $done = Wait-ReplyStable $win $edit $WaitSec
            Write-Output ($(if ($done) { '回复生成完毕' } else { '等待超时' }))
            Get-Messages (Get-All $win) $edit $MaxLines | ForEach-Object { Write-Output $_.Text }
        }
    }
} catch {
    Write-Output "DOUBAO_ERROR: $($_.Exception.Message)"
    exit 1
}

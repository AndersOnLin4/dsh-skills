---
name: doubao
description: 驱动本机的豆包桌面客户端（Doubao.exe）——开新会话、切换快速/专家/工作任务模式、发消息、上传附件（文件/图片）、读取回复。纯 UIA + Win32 消息注入，零鼠标不抢焦点。统一入口是随附的 scripts/doubao.ps1。
whenToUse: 用户要求调用豆包/给豆包发消息/问豆包、切换豆包模式（快速/专家/工作任务）、向豆包上传文件或图片、读取豆包回复时使用。前提：豆包桌面客户端已运行且已登录。
---

# 豆包桌面版自动化

统一入口脚本 `scripts/doubao.ps1`（与本 SKILL.md 同目录），全程零鼠标、不抢焦点。先跑脚本；报错再查排障参考。

**脚本路径**：本 skill 加载时注入的资源根目录即 `<skill目录>`，脚本在 `<skill目录>\scripts\doubao.ps1`。找不到时按以下顺序定位：`Join-Path $env:DSH_HOME 'skills\doubao\scripts\doubao.ps1'`，或 `Get-ChildItem $env:DSH_HOME -Recurse -Filter doubao.ps1 | Select-Object -First 1`。

## 用法（pwsh 工具；每个新进程先执行第一句）

```powershell
$s = Join-Path $env:DSH_HOME 'skills\doubao\scripts\doubao.ps1'   # 或替换为上面说明的资源根目录拼接
Set-ExecutionPolicy -Scope Process Bypass -Force

& $s -Action status                                        # 窗口/当前模式/输入框内容
& $s -Action newchat                                       # 开新会话
& $s -Action mode -Mode 快速                                # 快速|专家|工作任务 Auto|工作任务 Turbo|工作任务 Pro
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10     # 发消息，等回复稳定后打印最后10行
& $s -Action send -Text '描述这张图' -Files 'C:\a.png','C:\b.txt' -WaitSec 40   # 带附件发送（可多文件）
& $s -Action send -Text '...' -NewChat                     # 开新会话再发
& $s -Action attach -Files 'C:\x.pdf'                      # 只加附件不发送
& $s -Action read -MaxLines 15                             # 只读会话最后15行
& $s -Action wait -WaitSec 60                              # 等生成结束再打印
```

- 失败输出以 `DOUBAO_ERROR:` 开头：常规错误重试一次；深入排障读 `references/troubleshooting.md`（机制细节与常见问题）。
- `-WaitSec` 判定 = 消息区文本连续两轮(3s)不变；长回复给 60s+，或分次 `-Action read`。
- 改过 doubao.ps1 后若报乱码解析错误：脚本必须带 UTF-8 BOM。补 BOM：`$p=$s; $c=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($p,$c,[Text.UTF8Encoding]::new($true))`

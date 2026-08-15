---
name: deepseek-web
description: 通过 UI 自动化驱动 DeepSeek 网页版聊天（chat.deepseek.com）：自动检测/启动浏览器、新建会话、发送消息、读取回复。纯 UIA，零鼠标不抢焦点。统一入口 scripts/deepseek-web.ps1。
whenToUse: 用户要求用 DeepSeek 网页版聊天、在 chat.deepseek.com 新建会话发消息、读取网页版回复或测试网页版接入时使用。前提：浏览器已登录 chat.deepseek.com（脚本自动检测并提示）。
---

# DeepSeek 网页版驱动

入口脚本 `scripts/deepseek-web.ps1`（与本 SKILL.md 同目录），纯 UIA 零鼠标。

## 用法（pwsh 工具；每个新进程先执行第一句）

```powershell
$s = Join-Path $env:DSH_HOME 'skills\deepseek-web\scripts\deepseek-web.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force

& $s -Action status
& $s -Action open                                       # 没有窗口时新开（默认自动复用已有 DeepSeek 窗口）
& $s -Action send -Text '...' -NewWindow                # 强制新开隔离窗口，不碰已有标签页
& $s -Action newchat                                    # 新建会话
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10  # 发消息，等回复稳定后打印最后10行
& $s -Action read -MaxLines 15                          # 只读最后15行
& $s -Action wait -WaitSec 60                           # 等生成结束再打印
```

- 浏览器自动检测：Edge/Chrome 常见安装路径 + 运行中进程兜底；`-Browser edge|chrome` 可显式指定。
- 失败输出以 `DEEPSEEK_WEB_ERROR:` 开头。含「未登录」的错误：让用户手动登录 chat.deepseek.com 后重跑；其余排障读 `references/troubleshooting.md`。
- 改过脚本后若报乱码解析错误：脚本必须带 UTF-8 BOM，补 BOM 命令与 doubao skill 相同。
- ⚠️ 灰色通道：网页端协议禁止自动化访问，仅适合个人低频自用/测试；规模化或程序化调用请走 DeepSeek 开放平台 API（本 harness 即是）。

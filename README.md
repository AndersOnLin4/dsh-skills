# DSH Skills Collection · DSH 技能合集

A collection of practical skills for [DeepSeek Harness (DSH)](https://github.com/deepseek-ai) — Windows automation, GitHub publishing, and token-saving subagent delegation.

面向 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai) 的实用技能合集：Windows 自动化、GitHub 发布、省 token 的子代理委派。

## Included Skills · 包含的技能

| Skill 技能 | 说明（中文） | Description (English) |
| --- | --- | --- |
| `doubao` | 驱动本机豆包桌面客户端：开新会话、切模式（快速/专家/工作任务）、发消息、上传文件/图片、读回复。纯 UIA + 消息注入，零鼠标不抢焦点 | Drive the local Doubao desktop client: new chats, mode switching, messaging, file/image uploads, reading replies. Pure UIA + message injection — zero mouse, no focus stealing |
| `deepseek-web` | 驱动 DeepSeek 网页版聊天（chat.deepseek.com）：自动检测/启动浏览器、新建会话、发消息、读回复。纯 UIA，零鼠标不抢焦点 | Drive the DeepSeek web chat (chat.deepseek.com): auto-detect/launch the browser, new chats, messaging, reading replies. Pure UIA — zero mouse, no focus stealing |
| `github-push` | GitHub 推送三分支：有 git 走 git push；无 git 走 REST API 直传；无凭证自动设备码授权（浏览器输验证码）| Push to GitHub with three branches: git push when git exists; REST API upload otherwise; automatic device-code auth (enter a code in the browser) when no credentials |
| `agent-delegation-slim` | 子任务委派 + 12 套强制精简返回 Schema，主上下文只留结构化 JSON | Subagent delegation with 12 enforced slim-return schemas — the main context keeps only structured JSON |

## Install · 安装

Copy the skill folders you need into a DSH skills root:

把需要的技能目录复制到 DSH 的 skills 根目录：

- User-level (all projects) 用户级（所有项目）: `<dshHome>\skills\` — e.g. `G:\harness\dsh-home\skills\` (typical) or `~/.dsh/skills`
- Project-level 项目级: `<project>\.dsh\skills\` or `<project>\.agents\skills\`

Example 示例:

```powershell
Copy-Item .\doubao, .\deepseek-web, .\github-push, .\agent-delegation-slim -Destination "$env:DSH_HOME\skills" -Recurse
```

Skills are discovered automatically 技能会被自动发现（多数情况下无需重启）.

## Quick Start · 快速开始

### doubao

```powershell
$s = Join-Path $env:DSH_HOME 'skills\doubao\scripts\doubao.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10          # send & wait 发消息并等回复
& $s -Action mode -Mode 专家                                     # switch mode 切换模式（快速/专家/工作任务 Auto/Turbo/Pro）
& $s -Action send -Text '描述这张图' -Files 'C:\a.png','C:\b.txt' -WaitSec 40   # with attachments 带附件
```

Requires the Doubao desktop client running and logged in 需要豆包桌面客户端已运行并登录.

### deepseek-web

```powershell
$s = Join-Path $env:DSH_HOME 'skills\deepseek-web\scripts\deepseek-web.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action status                                            # window / input state 窗口与输入框状态
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10         # send & wait 发消息并等回复
& $s -Action send -Text '...' -NewWindow                       # isolated new window 强制新开隔离窗口
```

Requires a browser (Edge/Chrome, auto-detected) logged in at chat.deepseek.com. ⚠️ Web-UI automation is a gray channel: personal low-frequency use only; use the official API for anything programmatic. 需要浏览器（Edge/Chrome 自动检测）已登录 chat.deepseek.com。⚠️ 网页端自动化属灰色通道：仅个人低频自用，程序化请走官方 API。

### github-push

```powershell
$s = Join-Path $env:DSH_HOME 'skills\github-push\scripts\push-github.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action check                                               # detect environment 检测环境
& $s -Action push -Path 'G:\my-project' -Repo 'my-repo' -Visibility public   # push a folder 推目录
& $s -Action release -Path 'G:\my-project' -Repo 'my-repo' -Tag 'v1.0.0' -Body 'changelog 变更说明'  # zip + Release 打包发布
```

- If no token is found, the script starts GitHub **device-code auth**: it prints a code like `ABCD-1234` and the URL `https://github.com/login/device` — open the URL, enter the code, done. The token is saved to `%USERPROFILE%\.github-token.txt` for reuse. 未发现凭证时脚本自动发起设备码授权：打印形如 `ABCD-1234` 的验证码和网址，浏览器输入即完成；token 自动保存复用。
- Token lookup order 查找顺序: `-TokenFile` → `$env:GH_PAT` → workspace `.github-token.txt` → `%USERPROFILE%\.github-token.txt`.

## Releases · 版本下载

Versioned archives are attached to [GitHub Releases](https://github.com/AndersOnLin4/dsh-skills/releases): download `dsh-skills-vX.Y.Z.zip`, unzip it, and copy the skill folders into your skills root.

版本压缩包发布在 [GitHub Releases](https://github.com/AndersOnLin4/dsh-skills/releases)：下载 `dsh-skills-vX.Y.Z.zip`，解压后把技能目录复制到 skills 根目录即可。

## Requirements · 环境要求

- Windows with PowerShell 5.1+ or PowerShell 7  Windows + PowerShell 5.1+ 或 PowerShell 7
- `doubao` / `deepseek-web` / `github-push` were tested on a 200%-scaled display; they work without git and without any API key. 三个技能均在 200% 缩放显示器上实测；无需 git、无需 API Key。

## License · 许可证

MIT — see [LICENSE](LICENSE) 详见 [LICENSE](LICENSE)。

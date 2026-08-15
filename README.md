# DSH Skills Collection · DSH 技能合集

实用技能合集，面向 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai)：Windows 自动化、GitHub 发布、省 token 的子代理委派。

**中文说明在上，English below.**

---

## 包含的技能（中文）

| 技能 | 说明 |
| --- | --- |
| `doubao` | 驱动本机豆包桌面客户端：开新会话、切模式（快速/专家/工作任务）、发消息、上传文件/图片、读回复。纯 UIA + 消息注入，零鼠标不抢焦点（v1，回退用） |
| `doubao-v2` | 豆包驱动 v2：自动启动豆包、窗口自动移回主屏并最大化（副屏/离屏自愈）、probe 探测三件套 + UI 发现方法链、修复附件上传实测 bug。**独立项目仓库：[doubao-v2](https://github.com/AndersOnLin4/doubao-v2)** |
| `deepseek-web` | 驱动 DeepSeek 网页版聊天（chat.deepseek.com）：自动检测/启动浏览器、新建会话、发消息、读回复。纯 UIA，零鼠标不抢焦点（v1，回退用） |
| `deepseek-web-v2` | DeepSeek 网页版 v2：窗口自动移回主屏并最大化、probe 探测三件套 + UI 发现方法链、修复发送后读回复拿旧树的问题 |
| `github-push` | GitHub 推送三分支：有 git 走 git push；无 git 走 REST API 直传；无凭证自动设备码授权（浏览器输验证码） |
| `agent-delegation-slim` | 子任务委派 + 12 套强制精简返回 Schema，主上下文只留结构化 JSON（v1，回退用） |
| `agent-delegation-slim-v2` | 委派规范 v2：路由表优先指向 `doubao-v2`/`deepseek-web-v2`（回退 v1）、新增 UI 通道「锚点→候选→验证→降级」方法链指引 |

## 版本策略

- `-v2` 目录是当前推荐版：自带**窗口就位保障**（自动启动/移回主屏/最大化）与**探测工具 + 发现方法链**，对副屏、离屏、客户端改版更抗造；同名无后缀目录是 v1 原版，保留作回退。
- `doubao-v2` 为独立项目，仓库在 [AndersOnLin4/doubao-v2](https://github.com/AndersOnLin4/doubao-v2)，本仓库不重复收录。

## 安装

把需要的技能目录复制到 DSH 的 skills 根目录：

- 用户级（所有项目）：`<dshHome>\skills\` — 例如 `G:\harness\dsh-home\skills\`（典型）或 `~/.dsh/skills`
- 项目级：`<project>\.dsh\skills\` 或 `<project>\.agents\skills\`

示例：

```powershell
Copy-Item .\doubao-v2, .\deepseek-web-v2, .\github-push, .\agent-delegation-slim-v2 -Destination "$env:DSH_HOME\skills" -Recurse
# doubao-v2 独立仓库安装（从 AndersOnLin4/doubao-v2 下载后）：
Copy-Item .\doubao-v2 -Destination "$env:DSH_HOME\skills" -Recurse
```

技能会被自动发现（多数情况下无需重启）。

## 快速开始

### doubao / doubao-v2

```powershell
$s = Join-Path $env:DSH_HOME 'skills\doubao-v2\scripts\doubao.ps1'   # v2 推荐；v1 用 'skills\doubao\...'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10          # 发消息并等回复（自动启动豆包并归位窗口）
& $s -Action mode -Mode 专家                                     # 切换模式（快速/专家/工作任务 Auto/Turbo/Pro）
& $s -Action send -Text '描述这张图' -Files 'C:\a.png','C:\b.txt' -WaitSec 40   # 带附件
& $s -Action probe-windows                                       # 诊断：窗口/主屏信息
```

v2 无需预先启动豆包：自动拉起、还原并最大化窗口；完整用法见 [doubao-v2 仓库](https://github.com/AndersOnLin4/doubao-v2)。

### deepseek-web / deepseek-web-v2

```powershell
$s = Join-Path $env:DSH_HOME 'skills\deepseek-web-v2\scripts\deepseek-web.ps1'   # v2 推荐；v1 用 'skills\deepseek-web\...'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action status                                            # 窗口与输入框状态（自动归位主屏）
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10         # 发消息并等回复
& $s -Action send -Text '...' -NewWindow                       # 强制新开隔离窗口
& $s -Action probe-buttons                                     # 诊断：输入框锚点 + 全部按钮
```

需要浏览器（Edge/Chrome 自动检测）已登录 chat.deepseek.com。⚠️ 网页端自动化属灰色通道：仅个人低频自用，程序化请走官方 API。

### github-push

```powershell
$s = Join-Path $env:DSH_HOME 'skills\github-push\scripts\push-github.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action check                                               # 检测环境
& $s -Action push -Path 'G:\my-project' -Repo 'my-repo' -Visibility public   # 推目录
& $s -Action release -Path 'G:\my-project' -Repo 'my-repo' -Tag 'v1.0.0' -Body 'changelog 变更说明'  # zip + Release 打包发布
```

- 未发现凭证时脚本自动发起设备码授权：打印形如 `ABCD-1234` 的验证码和网址，浏览器输入即完成；token 自动保存复用。
- 凭证查找顺序：`-TokenFile` → `$env:GH_PAT` → 工作区 `.github-token.txt` → `%USERPROFILE%\.github-token.txt`。

## Releases · 版本下载

版本压缩包发布在 [GitHub Releases](https://github.com/AndersOnLin4/dsh-skills/releases)：下载 `dsh-skills-vX.Y.Z.zip`，解压后把技能目录复制到 skills 根目录即可。

## 环境要求

- Windows + PowerShell 5.1+ 或 PowerShell 7
- `doubao` / `deepseek-web` / `github-push` 均在 200% 缩放显示器上实测；无需 git、无需 API Key

## 许可证

MIT — 详见 [LICENSE](LICENSE)。

---

## English

A collection of practical skills for [DeepSeek Harness (DSH)](https://github.com/deepseek-ai): Windows automation, GitHub publishing, and token-saving subagent delegation.

### Included Skills

| Skill | Description |
| --- | --- |
| `doubao` | Drive the local Doubao desktop client: new chats, mode switching, messaging, file/image uploads, reading replies. Pure UIA + message injection — zero mouse, no focus stealing (v1, fallback) |
| `doubao-v2` | Doubao driver v2: auto-launch, auto move-to-primary-screen & maximize (secondary/off-screen self-healing), probe tools + UI discovery chain, attachment-upload bug fixes. **Separate project repo: [doubao-v2](https://github.com/AndersOnLin4/doubao-v2)** |
| `deepseek-web` | Drive the DeepSeek web chat (chat.deepseek.com): auto-detect/launch the browser, new chats, messaging, reading replies. Pure UIA — zero mouse, no focus stealing (v1, fallback) |
| `deepseek-web-v2` | DeepSeek web v2: window auto-normalization (primary screen + maximize), probe tools + UI discovery chain, stale-tree fix when reading replies |
| `github-push` | Push to GitHub with three branches: git push when git exists; REST API upload otherwise; automatic device-code auth (enter a code in the browser) when no credentials |
| `agent-delegation-slim` | Subagent delegation with 12 enforced slim-return schemas — the main context keeps only structured JSON (v1, fallback) |
| `agent-delegation-slim-v2` | Delegation spec v2: routing prefers the v2 channels (fallback v1), adds the UI discovery-chain guidance |

### Versioning

- The `-v2` folders are the recommended versions: they ship auto window normalization (launch / move-to-primary / maximize) plus probe tools and the UI discovery chain, which make them resilient to secondary monitors, off-screen windows, and client UI redesigns. The un-suffixed folders are the original v1 kept as fallback.
- `doubao-v2` lives in its own repo: [AndersOnLin4/doubao-v2](https://github.com/AndersOnLin4/doubao-v2) — not duplicated here.

### Install

Copy the skill folders you need into a DSH skills root:

- User-level (all projects): `<dshHome>\skills\` — e.g. `G:\harness\dsh-home\skills\` (typical) or `~/.dsh/skills`
- Project-level: `<project>\.dsh\skills\` or `<project>\.agents\skills\`

Example:

```powershell
Copy-Item .\doubao-v2, .\deepseek-web-v2, .\github-push, .\agent-delegation-slim-v2 -Destination "$env:DSH_HOME\skills" -Recurse
# For the standalone doubao-v2 repo (after downloading from AndersOnLin4/doubao-v2):
Copy-Item .\doubao-v2 -Destination "$env:DSH_HOME\skills" -Recurse
```

Skills are discovered automatically (no restart needed in most setups).

### Quick Start

#### doubao / doubao-v2

```powershell
$s = Join-Path $env:DSH_HOME 'skills\doubao-v2\scripts\doubao.ps1'   # v2 recommended; v1: 'skills\doubao\...'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10          # send & wait (auto-launches Doubao and normalizes the window)
& $s -Action mode -Mode 专家                                     # switch mode (快速/专家/工作任务 Auto/Turbo/Pro)
& $s -Action send -Text '描述这张图' -Files 'C:\a.png','C:\b.txt' -WaitSec 40   # with attachments
& $s -Action probe-windows                                       # diagnostics: window / primary-screen info
```

v2 no longer requires the Doubao client to be pre-launched — it auto-launches, restores, and maximizes the window. Full usage: [doubao-v2 repo](https://github.com/AndersOnLin4/doubao-v2).

#### deepseek-web / deepseek-web-v2

```powershell
$s = Join-Path $env:DSH_HOME 'skills\deepseek-web-v2\scripts\deepseek-web.ps1'   # v2 recommended; v1: 'skills\deepseek-web\...'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action status                                            # window / input state (auto-normalizes to primary screen)
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10         # send & wait
& $s -Action send -Text '...' -NewWindow                       # isolated new window
& $s -Action probe-buttons                                     # diagnostics: input anchor + all buttons
```

Requires a browser (Edge/Chrome, auto-detected) logged in at chat.deepseek.com. ⚠️ Web-UI automation is a gray channel: personal low-frequency use only; use the official API for anything programmatic.

#### github-push

```powershell
$s = Join-Path $env:DSH_HOME 'skills\github-push\scripts\push-github.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force
& $s -Action check                                               # detect environment
& $s -Action push -Path 'G:\my-project' -Repo 'my-repo' -Visibility public   # push a folder
& $s -Action release -Path 'G:\my-project' -Repo 'my-repo' -Tag 'v1.0.0' -Body 'changelog'  # zip + Release
```

- If no token is found, the script starts GitHub device-code auth: it prints a code like `ABCD-1234` and the URL `https://github.com/login/device` — open the URL, enter the code, done. The token is saved for reuse.
- Token lookup order: `-TokenFile` → `$env:GH_PAT` → workspace `.github-token.txt` → `%USERPROFILE%\.github-token.txt`.

### Releases

Versioned archives are attached to [GitHub Releases](https://github.com/AndersOnLin4/dsh-skills/releases): download `dsh-skills-vX.Y.Z.zip`, unzip it, and copy the skill folders into your skills root.

### Requirements

- Windows with PowerShell 5.1+ or PowerShell 7
- `doubao` / `deepseek-web` / `github-push` were tested on a 200%-scaled display; they work without git and without any API key.

### License

MIT — see [LICENSE](LICENSE).

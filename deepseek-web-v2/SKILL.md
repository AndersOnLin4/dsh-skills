---
name: deepseek-web-v2
description: 通过 UI 自动化驱动 DeepSeek 网页版聊天（chat.deepseek.com）v2——自动检测/启动浏览器、窗口自动移回主屏并最大化（副屏/离屏/最小化自愈）、新建会话、发送消息、读取回复；新增 probe-windows/probe-buttons/probe-menu 探测工具 + 「锚点→候选→验证→降级」UI 发现方法链。纯 UIA，零鼠标不抢焦点。统一入口 scripts/deepseek-web.ps1。变更详情见 CHANGELOG.md；v1 原版保留在同级 deepseek-web 目录。
whenToUse: 用户要求用 DeepSeek 网页版聊天、在 chat.deepseek.com 新建会话发消息、读取网页版回复或测试网页版接入时使用。浏览器未运行会自动拉起，无需人工启动；窗口在主屏外/副屏/最小化也会自动归位最大化。前提：浏览器已登录 chat.deepseek.com（脚本自动检测并提示）。
---

# DeepSeek 网页版驱动 v2

入口脚本 `scripts/deepseek-web.ps1`（与本 SKILL.md 同目录），纯 UIA 零鼠标。

> 本目录是 **v2 版本**，v1 原版保留在 `G:\harness\dsh-home\skills\deepseek-web\` 未改动。v1→v2 全部变更见 `CHANGELOG.md`。

## 铁律：先确保窗口就位，再操作（v2 新增）

每个需要窗口的动作都会**自动前置 ensure**：选中的 DeepSeek 窗口若最小化则还原；窗口中心不在主屏工作区（副屏、被拖出屏幕）则自动 `MoveWindow` 回主屏；最后 `SW_MAXIMIZE` 放大化。主 Agent 不需要关心浏览器窗口"在哪块屏、是否最小化"——直接发动作指令即可。仅 `probe-windows` 例外（纯诊断，保证 ensure 本身出问题时也能排障）。

## 铁律：UI 发现方法链——锚点 → 候选 → 验证 → 降级（v2 新增）

**不写死坐标、不盲目信任控件名。** 网页改版/换分辨率/换屏后控件名、位置都可能变。当标准动作报错（`DEEPSEEK_WEB_ERROR:` 开头）时，按下面方法链逐步探测：

1. **锚点**：先定位最稳定的元素——聊天输入框（`probe-buttons` 第一行，Name 含「发送消息」且支持 ValuePattern 的 Edit）
2. **候选**：在锚点的相对区域内按「角色 + 模式」收候选（发送按钮 = 输入框右下、支持 Invoke 的 Button；新对话 = 侧栏含「新对话」文字的 Text 的上级可 Invoke 元素）；`probe-buttons` 列出全部按钮的 Name | x,y,w,h | 模式
3. **验证**：动手前 `probe-menu -ButtonAt 'x,y'` 展开候选、看菜单/弹层内容确认身份，确认了再操作
4. **降级**：窗口元素坐标全负/异常 → `probe-windows` 看窗口 rect 是否在屏内，不在就跑一次 `ensure`；菜单项找不到 → 弹层挂在 RootElement 下（v2 已按浏览器进程顶层窗口子树搜索，不会卡死）；全部失败 → 把 probe 输出带给用户，说明"网页改版超出 skill 已知范围"，不要硬点

标准排障顺序：`probe-windows`（窗口层）→ `probe-buttons`（控件层）→ `probe-menu`（菜单层）→ 定位目标 → Invoke/SetValue 操作。

## 用法（pwsh 工具；每个新进程先执行第一句）

```powershell
$s = Join-Path $env:DSH_HOME 'skills\deepseek-web-v2\scripts\deepseek-web.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force

& $s -Action status
& $s -Action ensure                                      # 手动确保：窗口移回主屏并最大化
& $s -Action open                                        # 没有窗口时新开（默认自动复用已有 DeepSeek 窗口）
& $s -Action send -Text '...' -NewWindow                 # 强制新开隔离窗口，不碰已有标签页
& $s -Action newchat                                     # 新建会话
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10   # 发消息，等回复稳定后打印最后10行
& $s -Action read -MaxLines 15                           # 只读最后15行
& $s -Action wait -WaitSec 60                            # 等生成结束再打印

# 探测三件套（排障/方法链专用）
& $s -Action probe-windows           # 主屏工作区 + 全部浏览器顶层窗口(hwnd/title/rect/visible/iconic/是否DeepSeek)
& $s -Action probe-buttons           # 输入框锚点 + 全部按钮(名称/矩形/模式)
& $s -Action probe-menu -ButtonAt '800,900'   # 展开该坐标处按钮，列出可见菜单项（探测完自动收起）
```

- 浏览器自动检测：Edge/Chrome 常见安装路径 + 运行中进程兜底；`-Browser edge|chrome` 可显式指定。
- 失败输出以 `DEEPSEEK_WEB_ERROR:` 开头。含「未登录」的错误：让用户手动登录 chat.deepseek.com 后重跑；其余排障先走上面的方法链，再读 `references/troubleshooting.md`。
- 改过脚本后若报乱码解析错误：脚本必须带 UTF-8 BOM。补 BOM：`$p=$s; $c=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($p,$c,[Text.UTF8Encoding]::new($true))`
- ⚠️ 灰色通道：网页端协议禁止自动化访问，仅适合个人低频自用/测试；规模化或程序化调用请走 DeepSeek 开放平台 API（本 harness 即是）。

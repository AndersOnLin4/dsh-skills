---
name: doubao
description: 驱动本机的豆包桌面客户端（Doubao.exe）——开新会话、切换快速/专家/工作任务模式、发消息、上传附件（文件/图片）、读取回复、下载/提取豆包生成的图片与文档原文件。纯 UIA + Win32 消息注入，零鼠标不抢焦点。统一入口是随附的 scripts/doubao.ps1。
whenToUse: 用户要求调用豆包/给豆包发消息/问豆包、切换豆包模式（快速/专家/工作任务）、向豆包上传文件或图片、读取豆包回复、**让豆包创作（生成图片/视频/文档/文案等）并取回成品文件**时使用。前提：豆包桌面客户端已运行且已登录。
---

# 豆包桌面版自动化（子 AI 通道）

豆包是创作类任务的主力**子 AI**：图片生成、视频生成、文档生成、写作、多模态。主 Agent 需要这些能力时，加载本 skill 驱动豆包——**本 skill 就是"打开豆包"的遥控器**。

## 铁律：转述，不要设计

主 Agent 不擅长设计/创作，**禁止替用户设计参数**（不要自己编配色、构图、风格、文案结构——既费 token 又平庸）。

- ✅ 正确：把用户的原始意图**直接转述**给豆包（如"给这个模型生成个图标"→ 发给豆包"帮我给 Qwen3.6-35B-A3B 模型生成一个应用图标"），让豆包发挥创作能力。
- ❌ 错误：主 Agent 自己写"紫色渐变 #A78BFA→#7C3AED、白色粗圆环、3 个青色节点、扁平矢量风……"再让豆包执行。
- 主 Agent 的职责：理解意图 → 转述 → 等待生成 → 用下面的方式取回成品 → 交付。

## 铁律：直连模式，任务 + 硬性返回格式写进同一条消息

豆包本身是 AI，会遵守格式要求。主 Agent **直接**通过本 skill 给豆包发消息时，把任务和硬性返回格式（JSON 骨架 + 约束）写在**同一条消息**里，豆包直接按格式返回。

- ✅ 正确：`-Action send -Text '请把结果严格按以下 JSON 返回，不要任何额外文字：{"status":"success","summary":"...","data":{}}。任务：……'`
- ❌ 错误：为"转述 + 把豆包回答改写成 JSON"再包一层子 Agent 当传话筒——中转多烧一层上下文，纯属浪费 token（详见 `agent-delegation-slim` 的「委派的两种形态」）
- 识别类同理：`-Files 图片/音频/视频` 上传 + 消息里附 JSON 格式指令，豆包直接返回结构化文本（主 Agent 的"伪多模态化"首选通道）

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
& $s -Action extract -OutDir 'C:\out' -MinutesBack 10 -MinKB 100   # 从缓存提取最近生成的原文件（无损，首选）
& '<skill目录>\scripts\download-asset.ps1' -TargetName 'image' -SaveDir 'C:\out' -SaveFile 'icon'          # UI 下载生成图片
& '<skill目录>\scripts\download-asset.ps1' -TargetName 'Asset cover' -SaveDir 'C:\out' -SaveFile 'doc' -WatchSec 300   # UI 下载文档
```

- 失败输出以 `DOUBAO_ERROR:` 开头：常规错误重试一次；深入排障读 `references/troubleshooting.md`（机制细节与常见问题）。
- `-WaitSec` 判定 = 消息区文本连续两轮(3s)不变；长回复给 60s+，或分次 `-Action read`。
- 改过 .ps1 后若报乱码解析错误：脚本必须带 UTF-8 BOM。补 BOM：`$p=$s; $c=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($p,$c,[Text.UTF8Encoding]::new($true))`
- **DPI/缩放自适应**：脚本启动时用 `GetDpiForWindow` 探测豆包窗口实际 DPI，所有像素阈值按 `dpi/96` 自动缩放——多显示器、混 DPI、任意系统缩放均无需改代码；UIA 坐标是物理像素，所有定位相对输入框矩形推算，窗口移动/换屏不影响。
- **取回生成的原文件（图片/文档）**：完整流程（extract 缓存提取 → download-asset UI 下载 → 对话框处理 → 豆包下载目录 `G:\下载`）见 `references/download-extract.md`。不要截图（多显示器/混 DPI 下易错位、PrintWindow 可能黑屏、且损失精度）。

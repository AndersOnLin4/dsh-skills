# 生成物下载与提取（图片/文档）通用流程

豆包聊天里生成的图片/文档要落到本地，按以下优先级选路。**两条路都全程不移动光标、与显示器/DPI 无关。**

## 首选：磁盘缓存提取（无损、最快、最稳）

豆包显示任何图片/文档都要先从网络拉取，原始数据落在 Chromium 磁盘缓存里。

```powershell
# 在生成完成后立刻执行（把 MinutesBack 覆盖到生成完成的时间点）
& $s -Action extract -OutDir 'C:\out' -MinutesBack 10 -MinKB 100
```

- 按文件签名识别：PNG `89 50 4E 47`、JPEG `FF D8 FF`、WebP `RIFF`+`WEBP`、docx `50 4B 03 04`、doc `D0 CF 11 E0`、PDF `25 50 44 46`。
- `-MinKB` 用于过滤 UI 小图标（豆包会反复缓存 50~90KB 的图标素材）；真实生成图通常 >100KB（例：2048×2048 PNG ≈ 2.4MB）。
- 不需要豆包窗口、不需要登录态、不受多显示器/DPI 影响。
- 局限：**文档预览拉取的是内部二进制格式（无 docx 签名）**，只有真正触发"下载"才会产生标准 docx/doc——此时走第二条路，或用 extract 观察下载后新出现的 docx/doc 缓存条目。

## 次选：UI 下载流（download-asset.ps1）

当缓存里没有标准格式文件时（如云盘 docx），用随附脚本走 UI：

```powershell
# 下载聊天里的生成图片（点开预览 → 找「保存」→ 处理对话框 → 收集文件）
& '<skill目录>\scripts\download-asset.ps1' -TargetName 'image' -SaveDir 'C:\out' -SaveFile 'icon'

# 下载文档卡片（点开预览 → 找下载按钮 → 处理对话框 → 收集文件）
& '<skill目录>\scripts\download-asset.ps1' -TargetName 'Asset cover' -SaveDir 'C:\out' -SaveFile 'doc' -WatchSec 300
```

### 机制要点（踩坑沉淀）

1. **下载目录不是系统 Downloads**：豆包有自己的 `download.default_directory`（本机为 `G:\下载`）。脚本从 `%LOCALAPPDATA%\Doubao\User Data\Default\Preferences` 自动读取；`prompt_for_download:true` 意味着会弹保存对话框（#32770，兼容经典 ctrlid 1148/1 与现代 UIA Edit 两种写法）。
2. **下载按钮是 hover 才出现的**（消息行/预览工具栏/图片预览的「保存」）。注入 `WM_MOUSEMOVE`/`PostMessage` 对 Chromium 无效（客户端只认真实光标）。对策：`-WatchSec` 守望模式——让用户把光标悬停在目标上，脚本检测到新出现的按钮立即点击（相对坐标去重 + 窗口控件黑名单，窗口移动安全）。
3. **无障碍树异步构建**：每次 `WM_GETOBJECT` 后等 ≥2s 再 `FindAll`；轮询时每轮都重新唤醒，否则拿到半棵树（表现为"保存"按钮时有时无）。
4. **图片容器点击是开关**：预览关闭时点图片容器=打开预览；预览已开时再点=点到遮罩关掉预览。脚本用 open-once 语义避免误关。
5. 具名按钮（保存/下载）优先于点未名按钮；未名按钮只在消息区/预览区（相对坐标过滤标题栏、侧栏、输入区）且被黑名单排除后才点。

## 真实案例（2026-08-15）

- **图标**：`image` 生成 2048×2048 PNG → extract 从缓存直取，2.5MB 无损。
- **哪吒文档**：docx 在豆包云盘（file_id 在 `Default\WebStorage\6\IndexedDB\indexeddb.leveldb\*.log` 可查到），UI 下载流点「保存」后落在 `G:\下载\少年封神，风骨长存——致敬永不落幕的少年英雄哪吒.docx`。
- **失败教训**：不要用截图取内容（PrintWindow 黑屏、多显示器坐标错位、画质损失）；第一版守望脚本窗口移动后误点最小化按钮——守望必须用相对坐标+控件黑名单。

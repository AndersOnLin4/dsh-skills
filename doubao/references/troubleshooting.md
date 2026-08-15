# 豆包自动化 — 机制与排障参考（按需阅读，不常驻上下文）

## 工作机制（脚本内部实现，排查问题时对照）

1. **唤醒无障碍树**：向主窗口发 `WM_GETOBJECT`（Msg 0x003D，lParam 0xFFFFFFFC）后等 1.5s，否则 UIA 树里只有窗口按钮。
2. **主窗口定位**：`Get-Process Doubao | Where MainWindowHandle -ne 0`，再用 UIA RootElement 按 NativeWindowHandle 找顶层元素。主窗口类名 `Chrome_WidgetWin_1`，标题形如「<会话名> - 豆包」。
3. **输入框**：支持 ValuePattern 的 Edit 中底部最宽的那个。普通聊天占位符「发消息或按住空格说话...」，工作任务模式占位符「输入问题或任务，/ 选择技能」（name 为空，不要依赖占位符）。
4. **发送按钮**：输入框右下方的**无名 Button**。Chromium 在同坐标暴露两个变体（一个只有 ExpandCollapse、一个只有 Invoke）——必须选**支持 InvokePattern** 的那个，否则静默失败。
5. **模式切换**：输入行左侧模式芯片（Button，名称「快速/专家/工作任务 Auto/Turbo/Pro」之一）只有 ExpandCollapsePattern，Expand 弹菜单；菜单项是 MenuItem（如「快速 适用于大部分情况」「专家 研究级专业问答 - 2.1 Turbo」「工作任务 Auto 执行 agent 任务 - Auto」），对目标项 InvokePattern.Invoke()。**生效有 3-5 秒延迟**，之后芯片名变为新模式名。
6. **附件上传**：输入框左下无名 Button（ExpandCollapse 变体）Expand → 菜单项「上传文件或图片」Invoke → 弹出系统文件对话框（豆包主窗口的 `#32770` 子窗口）。枚举其子窗口：文件名框 = class Edit + ctrlid 1148；打开按钮 = class Button + ctrlid 1。`WM_SETTEXT`（Msg 0x000C，Unicode）写入 `"路径1" "路径2"`（多文件必须带引号），`BM_CLICK`（Msg 0x00F5）提交。附件成功后输入框上方出现附件条。
7. **读回复**：消息区（输入框左缘-50 为左边界，y 80~输入框上方）内 ControlType 为 Text/ListItem/Hyperlink 的元素的 Name，按 y 排序即会话内容。工作任务模式执行过程先出现「执行…任务」「已读取 xxx」等中间行，最终结果在最后。生成中/结束无显式状态按钮，靠文本稳定性轮询（`-Action wait`）。
8. 所有坐标相对输入框矩形推算，窗口缩放/移动不影响。**不要用 SetCursorPos/mouse_event**：会占用用户鼠标，且高 DPI 缩放（如 200%）下 UIA 是物理像素、光标 API 是逻辑像素，坐标易错位；纯 UIA + 消息注入已覆盖全部场景。

## 常见问题

- `找不到主窗口`：豆包没开或最小化到托盘，请用户打开窗口并确认已登录。
- 模式菜单没展开：Expand 后 sleep 700ms 再找 MenuItem；仍无则整条命令重试一次。
- 消息没发出去（输入框仍有文字）：命中了无 InvokePattern 的按钮变体（见机制第 4 条）；重跑 send 即可。
- 文件对话框控件没找到：确认弹出的是经典「打开」对话框（ctrlid 1148/1）；若豆包换了对话框样式，用 `EnumChildWindows` 枚举结果找 Edit+Button 对，改脚本。
- 上传后附件条重复：多次 attach 会重复添加同名文件，属正常行为，直接发送即可。
- 执行策略报错（cannot be loaded because running scripts is disabled）：每个新 pwsh 进程先 `Set-ExecutionPolicy -Scope Process Bypass -Force`。
- 脚本解析乱码（Unexpected token 乱码）：文件被编辑工具重写后丢了 UTF-8 BOM，用 SKILL.md 里的补 BOM 命令恢复。
- 豆包版本更新后按钮/菜单名变了：先跑 `-Action status`，再手工扫描 UIA 树定位新名称，更新脚本。
- 控件时有时无（屏幕上明明有却找不到）：无障碍树是异步构建的，`WM_GETOBJECT` 后要等 ≥2s 再 `FindAll`；轮询查找时**每次都要重新唤醒**，否则拿到旧树/半棵树（表现为个别控件永远"找不到"）。
- hover 才出现的控件（消息工具栏、图片/文档预览的保存/下载按钮）：注入的 `WM_MOUSEMOVE`/`PostMessage` **无法触发** Chromium 的 hover（客户端只认真实光标），且这些控件随光标离开自动隐藏。对策：让用户把光标悬停在目标上，脚本轮询到控件出现后立刻 Invoke；或直接走下面的缓存提取，绕开 UI。
- 多显示器/混 DPI（如 4K+1080p）：不要用截图取内容（PrintWindow 可能黑屏、UIA 物理坐标与光标逻辑坐标错位、且损失精度）。脚本已按窗口实际 DPI 自动缩放全部像素阈值（`GetDpiForWindow` → `dpi/96`），换显示器/换机器无需改代码。

## 备注

- 该通道走桌面端 UI，等同于用户手动操作，不消耗 API Key 额度；用户豆包账户自身配额照常消耗（档位以用户账户为准）。
- 模式下拉里「工作任务 Pro」带“升级”标记，可能触发付费/升级提示，慎用。

## 拿生成的原文件（图片/文档）——优先缓存提取，不要截图

豆包生成的图片/文档经网络拉取后会落到 Chromium 磁盘缓存：`%LOCALAPPDATA%\Doubao\User Data\Default\Cache\Cache_Data\f_*`。

1. 记下生成完成的大致时间，列出该时间点前后几分钟内修改的 `f_*` 文件（按 `LastWriteTime` 排序）。
2. 按文件签名识别：PNG `89 50 4E 47`、JPEG `FF D8 FF`、WebP `RIFF`+`WEBP`、docx/ZIP `50 4B 03 04`、doc/OLE2 `D0 CF 11 E0`、PDF `25 50 44 46`。
3. 读取时用 `FileShare.ReadWrite -bor FileShare.Delete` 共享读（缓存文件被进程锁着），整段拷出即为**原始无损文件**——与显示器数量、DPI、缩放完全无关。
4. 聊天消息本体在 `Default\IndexedDB\chrome_doubao-chat_*.indexeddb.leveldb\*.log`（UTF-8 文本，可搜消息内容和附件元数据）；文档类附件的元数据（file_id/file_type 等）可能在 `Default\WebStorage\6\IndexedDB\indexeddb.leveldb\*.log`。

若缓存里没有目标文件（尚未被预览/下载过），先在 UI 里打开一次预览让资源入缓存，再重复 1-3。注意：豆包文档预览拉取的是内部二进制格式（无 docx 签名），只有真正触发“下载”才会产生标准 docx/doc 文件。

# DeepSeek 网页版 skill v2 — 机制与排障参考（按需阅读，不常驻上下文）

## 工作机制（脚本内部实现）

1. **浏览器定位**：`-Browser auto` 依次查 Edge/Chrome 的常见安装路径（Program Files(x86)/Microsoft/Edge、Program Files/Google/Chrome、LOCALAPPDATA/Google/Chrome），再用运行中进程的 Path 兜底。找不到抛错，`-Browser edge|chrome` 强制指定。
2. **窗口定位**：默认复用标题以 `DeepSeek` 开头的现有窗口（不会命中标题是别的会话名的混合窗口），没有才 `Start-Process <exe> --new-window https://chat.deepseek.com` 新开；`-NewWindow` 强制新开（快照现有 `Chrome_WidgetWin_1` 句柄后轮询新出现的，要求标题以 `DeepSeek` 开头）。
3. **窗口就位（v2 新增）**：定位到窗口后自动 `Ensure-WebWindow`——`IsIconic` 则 `SW_RESTORE`；`EnumDisplayMonitors` 取主屏工作区，窗口中心不在主屏就 `MoveWindow` 回主屏；最后 `SW_MAXIMIZE`。修复窗口最小化/离屏/副屏时 UIA 坐标异常、拿不到输入框的问题。
4. **唤醒**：`WM_GETOBJECT` 后等 ≥1.2s；**每次 FindAll 前都要重新唤醒**（发送消息后界面重渲染，旧树会报"找不到输入框"——v2 已在 send/read/wait 的读取路径重新唤醒+重新定位）。
5. **登录判定**：能找到 Edit（占位符「给 DeepSeek 发送消息 」）即已登录；找不到时若树里有「登录/Sign in」按钮则报未登录，否则报页面结构变化。
6. **新会话**：Text「开启新对话」（兜底「新对话」/「New chat」）→ 向上找支持 InvokePattern 的父级 → Invoke。
7. **发送按钮**：输入框右下方的无名 Button，筛选条件 X > 输入框左缘+40% 宽、Y 在输入框下缘±130px 内，取**最右侧**且支持 InvokePattern 的那个（左侧的「深度思考」等工具按钮被 X 条件排除）；兜底找名称含「发送/Send」的按钮。
8. **读回复**：消息区 = Document 左缘 +300px（排除侧栏会话列表）到输入框上缘 -40px，取 Text/ListItem/Hyperlink 的 Name 按 y 排序；排除“直接 Group 父级铺满整页宽度”的弹层/浮层元素，并对同位置同文本去重（页面常把思考块暴露两份）。侧栏的「开启新对话」「今天/昨天」分组标签靠 X 阈值排除。
9. **菜单弹层（v2 新增）**：挂在 RootElement 下、属于浏览器进程的独立顶层窗口。`Get-PopupMenuItems` 只在浏览器进程的顶层窗口子树内搜 MenuItem——直接遍历整个桌面树会被无响应的 provider 卡死（doubao-v2 实测教训）。
10. 所有判定相对输入框/Document 矩形，窗口大小、多显示器（含负坐标显示器）不受影响；窗口被移回主屏后 DPI 变化由脚本按窗口实际状态自适应。

## 常见问题

- `未找到 Edge/Chrome 浏览器`：装一个或 `-Browser` 指定；浏览器装在非标准路径时把路径加进脚本 $dirs。
- `新窗口未就绪`：页面加载慢（代理/网络），重跑；或浏览器弹「设为默认」之类拦截页，手动关掉重试。
- `未登录`：网页端现在必须登录才能聊天；让用户手动登录（扫码/手机号），登录状态会保持，之后脚本直接复用。
- **窗口坐标全负/控件 rect 异常（v1 实测坑）**：窗口被移到屏幕外或副屏布局变化。`probe-windows` 确认 rect/iconic，跑一次 `-Action ensure` 或任意动作（自动归位主屏最大化）。
- 消息没发出（输入框仍有文字）：发送按钮筛选没命中（页面更新导致按钮位置变化）。**走方法链**：`probe-buttons` 看按钮清单与锚点，按机制第 7 条调整阈值或改走名称兜底。
- 发送后读回复报"找不到输入框"：v2 已在读取路径重新唤醒树；仍报则整条命令重跑一次。
- 侧栏会话混进读结果：X 阈值（+300px）不够时改大（窗口缩放不同会变）。
- 脚本解析乱码：文件被编辑工具重写后丢 BOM，用 SKILL.md 提到的命令补回。

## 备注

- 网页端是灰色通道（协议禁止自动化访问），仅供个人低频自用/测试；正规开发走开放平台 API。
- 目前不支持附件上传（网页端 + 按钮未适配）；需要时按 doubao-v2 的文件对话框套路扩展。
- v2 的 ensure 每次动作前会把 DeepSeek 窗口移回主屏并最大化，属设计行为。

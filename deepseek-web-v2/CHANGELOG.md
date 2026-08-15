# deepseek-web skill v1 → v2 变更记录

v2 目录：`G:\harness\dsh-home\skills\deepseek-web-v2\`（本目录）
v1 原版：`G:\harness\dsh-home\skills\deepseek-web\`（未改动，保留）

## 变更动因

与 doubao-v2 同一轮反馈的问题（详见 doubao-v2 的 CHANGELOG 与 `G:\文档\网络学习笔记\图片识别测试.md` 实测记录）：

1. v1 没有窗口就位保障——浏览器窗口被最小化/移到屏幕外/留在副屏时，UIA 坐标异常、拿不到输入框，全部动作失败
2. 没有副屏/多显示器兜底
3. 控件名/位置写死后，网页改版就失效；没有"怎么找控件"的方法论和探测工具
4. 实测类 bug：发送后界面重渲染，v1 直接 `Get-All` 读旧树会报"找不到输入框"

## 具体变更

### A. 窗口就位保障（对应问题 1、2）

| 项 | v1 | v2 |
|---|---|---|
| 窗口最小化 | 无处理 | 自动 SW_RESTORE |
| 窗口在主屏外/副屏 | 无处理 | EnumDisplayMonitors 取主屏工作区，中心不在主屏就 MoveWindow 回主屏 |
| 放大化 | 无 | 每次动作前 SW_MAXIMIZE，保证全可见 |
| 执行时机 | — | 所有窗口相关动作自动前置 ensure；仅 probe-windows 例外（诊断用） |

浏览器自动检测/启动（v1 已有）保留：Edge/Chrome 安装路径 + 运行中进程兜底，新开窗口轮询就绪。

### B. UI 发现方法链 + 探测工具（对应问题 3）

SKILL.md 新增「锚点→候选→验证→降级」铁律；新增三个探测动作：

- `-Action probe-windows`：主屏工作区 + 全部浏览器顶层窗口（hwnd/title/rect/visible/iconic/是否 DeepSeek）
- `-Action probe-buttons`：输入框锚点 + 全部按钮（Name | x,y,w,h | 支持模式）
- `-Action probe-menu -ButtonAt 'x,y'`：展开指定坐标按钮并 dump 可见菜单项（探测完自动收起）

菜单弹层搜索改为"浏览器进程的顶层窗口子树内搜 MenuItem"——直接遍历整个桌面树会被无响应的 provider 卡死（doubao-v2 实测教训，同步预防）。

### C. 读回复路径修复（对应问题 4）

| 项 | v1 | v2 |
|---|---|---|
| send 后等回复 | 直接 Get-All 读旧树 → 报"找不到输入框" | Wake-Tree 重新唤醒 + 重新定位输入框 |
| read / wait | 用启动时的输入框引用 | 每次读取前重新唤醒 + 重新定位 |

### D. 其他

- W32DW 扩展：新增 EnumWindows/GetWindowRect/MoveWindow/ShowWindow/IsIconic/IsWindowVisible/EnumDisplayMonitors/GetMonitorInfo/GetDpiForWindow 等窗口管理 API（v1 只有 SendMessage）
- SendMessage 显式 `EntryPoint="SendMessageW"`（v1 无 EntryPoint 也能工作，此处与 doubao-v2 统一写法）
- SKILL.md 版本标注 + 方法链指引；v1 版本号不变

## 升级指引

- 本会话技能目录已注册新 skill 名 `deepseek-web-v2`；`agent-delegation-slim` 路由表中 DeepSeek 通道在 v2 中改为优先 `deepseek-web-v2`。
- 脚本为 UTF-8 BOM 编码；编辑后若报乱码，按 SKILL.md 的补 BOM 命令恢复。
- v2 的 ensure 每次动作前会把 DeepSeek 窗口移回主屏并最大化，属设计行为。
- ⚠️ 灰色通道提醒不变：网页端自动化仅适合个人低频自用/测试，规模化请走 DeepSeek 开放平台 API。

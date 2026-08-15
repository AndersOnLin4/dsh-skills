# agent-delegation-slim v1 → v2 变更记录

v2 目录：`G:\harness\dsh-home\skills\agent-delegation-slim-v2\`（本目录）
v1 原版：`G:\harness\dsh-home\skills\agent-delegation-slim\`（未改动，保留）

## 变更动因

doubao-v2 / deepseek-web-v2 两个 UI 自动化通道发布后，本 skill 作为"中枢路由表 + 外包规范"，需要同步两件事：

1. 路由表仍指向 v1 通道（`doubao` / `deepseek-web`），agent 会加载到没有窗口保障、没有探测工具的旧版
2. 主 Agent 需要知道：UI 通道报错时的标准处置流程（发现方法链），而不是自己瞎试

本 skill 本身是纯文本规范，不涉及 UI 自动化问题（自动启动/副屏/坐标那类问题在通道 skill 里解决），v2 只做路由升级与方法链衔接。

## 具体变更

1. **frontmatter**：`name: agent-delegation-slim-v2`，`version: 2.0.0`，description 注明 v2 差异与 v1 保留位置
2. **子 AI 通道表**：豆包 → `doubao-v2`（优先，回退 `doubao`）；DeepSeek 网页版 → `deepseek-web-v2`（优先，回退 `deepseek-web`）
3. **AI 能力路由表**：全部 `doubao` 通道项改为「`doubao-v2`，回退 `doubao`」；`deepseek-web` 项改为「`deepseek-web-v2`，回退 `deepseek-web`」
4. **环境自适应**段落：更新为 v2 优先 + v1 回退的检查顺序；本机现状说明更新
5. **skill 命名约定**：新增「版本化惯例」——通道 skill 出新版用 `-v2` 后缀建新目录，v1 保留作回退，路由表写"优先 v2，回退 v1"
6. **新增「UI 通道方法链」小节**（第 6 节，原 4/5 节顺延为 7/8 节）：主 Agent 只需记住两条——①窗口就位是自动的，直接发指令；②报错走「锚点→候选→验证→降级」四步探测（probe-windows → probe-buttons → probe-menu），走完方法链前禁止硬点/盲改坐标，全部失败把 probe 输出带给用户
7. **多模态强制外包规则 / 伪多模态化机制 / 快速使用流程 / 模板定位**：`doubao` → `doubao-v2`（含示例命令）

## 模板与工具定义

`templates/`（12 套返回 Schema）与 `delegate_tool_schema.json` 内容未变，原样保留。它们约束的是子 Agent 返回格式，与通道版本无关。

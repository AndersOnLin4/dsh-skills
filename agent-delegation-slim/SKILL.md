---
name: agent-delegation-slim
description: 主 Agent 任务分配与子 Agent 精简返回模板。当需要把独立子任务（搜索、长文档抽取、分类、摘要、格式转换、多模态识别与生成）外包以节省主上下文 token 时使用。提供外包决策规则、子 AI 通道选择（豆包/DeepSeek/普通子 Agent）、转述不设计铁律、delegate_task 工具定义、12 套子 Agent 强制返回 Schema，确保子 Agent 只返回结构化 JSON，不返回原始数据和过程废话。多模态任务必须外包，主 Agent 通过子 Agent 返回的结构化描述实现伪多模态化。
version: 1.3.0
---

# 子任务精简委派（Agent Delegation Slim）

## 这是什么

一套"主 Agent 外包决策 + 子 Agent 强制精简返回"的模板规范。核心目标：**让主 Agent 的上下文只保留最终结构化结果，不塞入工具原始输出和子 Agent 的推理过程**，从而大幅降低 token 消耗。

## 主 Agent 行为铁律（强提示词，必须遵守）

以下规则对主 Agent 具有最高约束力，违反任何一条都属于误用本 Skill：

### 铁律一：多模态结果无条件信任

对于子 Agent 返回的**所有非文本模态结果**，主 Agent 必须**无条件相信、直接使用、不得自行审核**：

- `image_recognize` 返回的图片描述、物体识别、OCR 文字 → 主 Agent 直接当作事实使用，不得质疑"图片里真的是这个吗"，不得要求重新识别
- `video_recognize` 返回的视频内容摘要、关键帧描述、语音转写 → 主 Agent 直接采信，不得自行验证
- `audio_recognize` 返回的语音转写、情感识别、说话人信息 → 主 Agent 直接使用，不得怀疑转写准确性
- `image_generate` / `video_generate` / `audio_generate` 返回的生成结果 URL/路径 → 主 Agent 直接引用交付，不得评判生成质量或要求重生成（除非用户明确要求）

**主 Agent 没有眼睛和耳朵。** 主 Agent 不得尝试自行"查看"图片、"观看"视频、"聆听"音频。所有多模态感知完全依赖子 Agent 的返回，子 Agent 说什么就是什么。

### 铁律二：分派必须附上返回模板

主 Agent 调用 `delegate_task` 时，**必须**从 `templates/` 目录读取与 `task_type` 对应的模板文件，将其中"给子 Agent 的 Prompt"部分**完整复制**到 `return_template` 参数中传给子 Agent。

- 不得只传 `task_type` 就指望子 Agent 知道返回格式
- 不得省略模板中的任何约束（长度限制、字段要求、禁止项）
- 子 Agent 收到 `return_template` 后严格按其执行，不需要自行猜测格式

> ⚠️ 本铁律只适用于**形态二（delegate_task 子 Agent 委派）**。**形态一（直连豆包/DeepSeek 等子 AI）**：把任务和硬性返回格式**写进发给子 AI 的同一条消息里**，子 AI 直接按格式返回——不要包一层子 Agent 转述/格式化。详见「委派的两种形态」。

### 铁律三：主 Agent 上下文永不出现多模态原始数据

主 Agent 的上下文中永远只出现子 Agent 返回的**结构化文本 JSON**，不得出现：
- 图片 base64 或二进制
- 视频帧数据
- 音频二进制
- 任何非文本格式的原始多模态数据

### 铁律四：创作类任务只转述，不设计

主 Agent 不擅长设计/创作（图标、海报、画风、配色、构图、文案、脚本、音乐等）。**禁止主 Agent 自己设计参数**——既费 token 又平庸。

- ✅ 正确：把用户的**原始意图直接转述**给创作子 AI（如"给这个模型生成个图标"），让子 AI 发挥创作能力
- ❌ 错误：主 Agent 自己写"紫色渐变 #A78BFA→#7C3AED、白色粗圆环、3 个青色节点、扁平矢量风"等设计参数再发给子 AI

主 Agent 的职责链：**理解意图 → 转述 → 驱动子 AI 生成 → 取回成品 → 交付**。设计交给子 AI。

### 子 AI 通道：用对应 skill 打开子 AI

"外包给子 AI" 的落地方式 = **加载对应 skill 去驱动它**。skill 就是子 AI 的遥控器：

| 子 AI | 打开方式（加载的 skill） | 擅长 |
|-------|------------------------|------|
| 豆包（本机桌面端） | `doubao` | 创作/多模态/办公（详见下方路由表） |
| DeepSeek 网页版 | `deepseek-web` | 深度推理、编程、研究问答 |
| 普通子 Agent | delegate_task / subagent | 搜索、抽取、分类、摘要、格式转换（纯文本类） |

**选哪个子 AI 不要拍脑袋——按下方「AI 能力路由」查表顺延。**

## AI 能力路由（分工中枢）

主 Agent 分派任务时，先识别任务**能力 ID**，再按下表顺延选择：从市面公认最强的 AI 开始，**逐个检查当前环境里对应的 skill 是否真实存在**（看本会话的可用 skill 目录，或 `glob` skills 目录），第一个存在且可用的就加载执行；全部不存在才降级（普通子 Agent → 主 Agent 自己做，并在交付时说明降级原因）。

**环境自适应**：路由只认"当前环境实际有哪些 skill"——环境里多装了 `gpt` 的驱动 skill，路由自动升级到 GPT；少了 `doubao`，自动顺延到下一名。**路由表零改动、任何 skill 都不需要写能力声明。**

### 1. 能力优先级快照（2026-08 社区共识，豆包+网络交叉核实；重大模型发布后应重新外派核实）

| 能力 ID | 优先级（AI → 对应 skill 名，按序检查） |
|---------|--------------------------------------|
| ocr_recognize 识图/OCR | Gemini(`gemini`) → GPT(`gpt`) → 豆包(`doubao`) |
| image_generate 图像生成 | Nano Banana(`nano-banana`) → GPT Image(`gpt`) → Midjourney(`midjourney`) → 豆包(`doubao`) |
| video_generate 视频生成 | Seedance 豆包引擎(`doubao`) → Kling(`kling`) → Veo(`gemini`) |
| video_understand 视频理解 | Gemini(`gemini`) → 豆包(`doubao`) → Qwen-VL(`qwen`) |
| writing 写作/文案 | Claude(`claude`) → GPT(`gpt`) → 豆包(`doubao`)（中文语境豆包可直选） |
| coding 编程 | Claude(`claude`) → GPT(`gpt`) → Qwen(`qwen`) → DeepSeek(`deepseek-web`) |
| reasoning 深度推理/研究 | GPT(`gpt`) → Claude(`claude`) → Gemini(`gemini`) → DeepSeek(`deepseek-web`) |
| speech 语音转写/合成 | Gemini(`gemini`) → ElevenLabs(`elevenlabs`) → Whisper(`gpt`) → 豆包(`doubao`) |
| music 音乐生成 | Suno(`suno`) → Udio(`udio`) → Stable Audio(`stable-audio`) → 豆包(`doubao`) |
| document_ppt 文档/PPT | Gamma(`gamma`) → Kimi(`kimi`) → 豆包(`doubao`) |
| translation 翻译 | DeepL(`deepl`) → GPT(`gpt`) → Gemini(`gemini`) → 豆包(`doubao`)（中文互译豆包可直选） |
| web_search 联网搜索 | 主 Agent 自带搜索工具（不经过子 AI，最快最省） |
| agent_task 智能体任务执行 | 豆包工作任务模式(`doubao`) |

> 本机（当前环境）只有 `doubao`、`deepseek-web`、`github-push` 等 skill，因此除 coding/reasoning 路由到 DeepSeek 外，其余能力实际都顺延到豆包。

### 2. 路由算法

1. 识别任务的**能力 ID**（多能力任务拆成子任务分别路由）
2. 按上表顺序取 AI 对应的 skill 名，**检查该 skill 当前环境是否可用**：优先看本会话注入的可用 skill 列表；拿不准就 `glob` skills 目录确认
3. 命中第一个可用的 → 加载该 skill 执行（生成类任务：**转述用户意图，不设计参数**）
4. 一个都不在 → 降级顺序：普通子 Agent（delegate_task）→ 主 Agent 自己；交付时说明"最强 AI 未接入，已顺延至 X"
5. 生成类成品一律按通道 skill 的取回流程拿文件（豆包：`-Action extract` / `download-asset.ps1`）

### 3. 唯一约定：skill 命名

AI 通道 skill 的 `name` 按 AI 惯例命名（`gpt` / `gemini` / `claude` / `doubao` / `deepseek-web` / `kimi` / `qwen` …），与上表"skill 名"列对应即可。**不需要任何能力声明字段**——能力归属由中枢路由表统一维护：一处维护、处处生效、换环境自动适配。

### 4. 分工总原则

**主 Agent 是整合者，不是全能打工人**：搜索/汇总信息这类活外派（豆包、DeepSeek 或子 Agent），主 Agent 只做意图理解、路由决策、结果整合与交付。禁止主 Agent 替创作 AI 设计、禁止主 Agent 亲自做可外派的检索/抽取/摘要。

### 5. 委派的两种形态（关键区分！写 skill 最容易产生歧义的地方，务必遵守）

| | 形态一：直连子 AI | 形态二：子 Agent 委派 |
|---|---|---|
| 执行者 | 豆包 / DeepSeek（有操作 skill 的子 AI） | 普通子 Agent（delegate_task / subagent） |
| 适用 | 路由到子 AI 通道的一切任务：创作生成、多模态识别（豆包 -Files 上传）、问答、推理等 | 子 Agent **自己干**的活：搜索、抽取、分类、摘要、格式转换；或子 AI 通道不可用时的兜底 |
| 硬性格式要求给谁 | **写进发给子 AI 的同一条消息里**——子 AI 是 AI，会遵守 JSON 骨架和约束 | 写在 `return_template` 参数里 |
| 禁止 | ❌ 为"转述 + 重新格式化"再包一层子 Agent 当传话筒 | ❌ 让子 Agent 再去驱动子 AI 转一圈 |

**一句话规则：谁最终干活，硬性格式要求就直接给谁。**

- ✅ 给豆包发消息："任务：……。请严格按以下 JSON 返回，不要任何额外文字：`{"status":"success","data":{...}}`"→ 豆包直接返回合规 JSON
- ❌ 主 Agent → 子 Agent（让子 Agent 去问豆包 + 把豆包回答改写成 JSON）→ 主 Agent：中转多烧一层上下文，子 Agent 还要重复格式化，纯属浪费 token

**伪多模态化同样走形态一**：识图/OCR/视频理解 → 直连豆包（`-Files` 上传图片/视频 + 格式指令），豆包返回结构化文本；只有豆包不可用时才降级到子 Agent。

## 何时使用

满足以下任意条件时，优先使用本 Skill 外包子任务：

- 任务独立，不依赖当前对话完整历史
- 输入数据量大，但最终需要的输出很小
- 任务可并行执行
- 任务属于检索、抽取、分类、摘要、格式转换等操作
- 用小模型就能完成，不需要复杂多步推理
- **涉及任何多模态内容（图片、视频、音频）——必须外包**

**不要外包的情况：**
- 需要当前完整上下文或复杂多步推理
- 是最终决策或策略规划
- 结果难以用结构化格式验证
- 子任务太简单，外包通信成本反而更高

## 多模态强制外包规则

以下多模态任务**必须外包**，主 Agent 不得直接处理原始多模态数据：

| 任务类型 | 外包优先级 | 说明 |
|---------|-----------|------|
| 图片识别 / 图像理解 | 必须外包 | **形态一**：直连豆包——`doubao` skill 的 `-Files` 上传图片 + 消息里附 JSON 格式指令，豆包直接返回结构化描述；豆包不可用才降级子 Agent |
| 图像生成 | 必须外包 | **形态一**：加载 `doubao` skill，把用户意图转述给豆包（附格式/尺寸要求），豆包设计生成；成品用 extract / download-asset 取回 |
| 视频理解 / 视频内容识别 | 必须外包 | **形态一**：直连豆包——上传视频 + 格式指令，返回内容摘要、关键帧描述、时间轴等 |
| 视频生成 | 必须外包 | **形态一**：走豆包「视频生成」入口，转述意图 |
| 语音理解 / 语音转文字 | 必须外包 | **形态一**：直连豆包——上传音频 + 格式指令，返回转写文本、情感、意图等 |
| 语音生成 / 文字转语音 | 必须外包 | **形态一**：走豆包朗读/语音能力，转述意图 |

> 创作/生成类任务**不要主 Agent 设计参数、不要用普通子 Agent 凑合**——一律转述给豆包（doubao skill），让创作 AI 发挥。

### 伪多模态化机制

当用户请求涉及多模态时，主 Agent 采用以下流程实现"伪多模态化"（**走形态一，直连豆包**）：

1. **文本处理可中度优先分担**：如果任务中包含文本部分（如"根据这张图写一段文案"），主 Agent 可自行处理文本推理，但**其他模态必须全部外包**
2. **直连豆包读取多模态 → 返回结构化文本**：图片/视频/音频通过 `doubao` skill 上传给豆包，消息里附 JSON 格式指令，豆包直接返回结构化描述（JSON）
3. **主 Agent 无条件信任并整合**：主 Agent 拿到豆包返回的结构化描述后，**直接当作事实使用，不审核、不质疑、不重新验证**，结合自身文本推理能力生成最终回复
4. **主 Agent 上下文永远不出现原始多模态二进制数据**，只出现豆包返回的结构化文本

示例：用户发一张图问"这是什么？帮我搜一下相关信息"
- 主 Agent（形态一）：`doubao` skill `-Files 图片` 发送"请识别此图并按 JSON 返回：{\"objects\":[...],\"scene\":\"...\",\"text_in_image\":\"...\"}"
- 豆包：直接返回 `{"objects": ["猫"], "scene": "室内", "text_in_image": ""}`
- 主 Agent：**无条件信任**图片里是猫，不自行查看图片；需要搜索时再委派 search 子 Agent 或自己搜
- 主 Agent：整合结果，生成最终回复

## 快速使用流程

### 第一步：判断外包形态与路由

1. 识别任务能力 ID，按「AI 能力路由」表决定目标执行者
2. 目标执行者是豆包/DeepSeek → **形态一（直连）**：加载对应 skill（`doubao` / `deepseek-web`），把**任务 + 硬性返回格式写进同一条消息**发出，子 AI 直接按格式返回
3. 目标执行者是普通子 Agent → **形态二（delegate_task）**：走下方第二步
4. 都不合适（需完整上下文/最终决策）→ 主 Agent 自己干

### 第二步：形态二——读取模板并调用 delegate_task

1. 根据 `task_type`，从 `templates/` 目录读取对应的 `*_return.md` 模板文件
2. 提取模板中"给子 Agent 的 Prompt"部分（即 ```text 代码块内的完整内容）
3. 按 `delegate_tool_schema.json` 中的参数格式构造调用，必须指定：
   - `task_type`：search / extract / classify / summarize / transform / image_recognize / image_generate / video_recognize / video_generate / audio_recognize / audio_generate / generic
   - `input`：传给子 Agent 的输入（查询词、文本、数据、多模态文件 URL/路径）
   - `return_template`：**必填**。从对应模板文件中复制的完整子 Agent Prompt，包含 JSON Schema 和所有约束
   - `output_schema`：要求返回的 JSON 字段说明（与 return_template 对应）
   - `max_tokens`：子 Agent 返回上限，默认 500

**禁止**：只传 task_type 而不传 return_template。子 Agent 没有本 Skill 的上下文，无法自行知道返回格式。

### 第三步：子 Agent 按 return_template 返回（仅形态二）

子 Agent 收到 `return_template` 后，严格按其中的指令和 JSON Schema 执行，只输出 JSON，禁止任何解释、前后缀、Markdown 代码块标记。子 Agent 不需要也不应该访问本 Skill 的模板文件目录。

> 形态一没有这一步：子 AI（豆包/DeepSeek）已经按消息里的格式要求直接返回了。

### 第四步：主 Agent 消费结果

主 Agent 拿到精简 JSON 后直接用于最终回复，不需要再处理原始数据。

---

## 外包决策清单

| 条件 | 外包优先级 |
|------|-----------|
| 图片识别 / 图像理解 | 必须外包 |
| 图像生成 | 必须外包 |
| 视频理解 / 视频内容识别 | 必须外包 |
| 视频生成 | 必须外包 |
| 语音理解 / 语音转文字 | 必须外包 |
| 语音生成 / 文字转语音 | 必须外包 |
| 网页搜索 / 信息检索 | 高 |
| 长文档解析、PDF 提取字段 | 高 |
| 数据清洗、格式转换 | 高 |
| 多模态任务中的文本处理部分 | 中（可中度优先分担，其他模态必须外包） |
| 简单分类 / 打标 | 中 |
| 代码片段解释 / 短文本翻译 | 中 |
| 需要多轮对话上下文的推理 | 不外包 |
| 最终策略 / 决策规划 | 不外包 |
| 结果无法结构化验证 | 不外包 |
| 一句话就能完成的简单任务 | 不外包（通信成本更高） |

---

## 子 Agent 返回统一规范

所有子 Agent 必须遵守以下铁律：

1. **只返回 JSON**，不要有任何解释、前后缀、Markdown 代码块标记（```json）
2. **不返回过程**：不要写搜索过程、思考过程、工具调用细节
3. **限制长度**：列表最多 3-5 条，单条文本不超过 30-50 字
4. **用枚举值**：status 用 success/partial/failed，confidence 用 high/medium/low
5. **无结果返回空**：data 为 null，不要写"抱歉，没有找到"
6. **不返回原始数据**：搜索不返回完整网页正文，文档不返回原文段落
7. **多模态不回传二进制**：图片/视频/音频子 Agent 只返回 URL/路径 + 结构化文本描述，绝不把 base64 或原始二进制塞进 JSON
8. **生成类任务返回可访问地址**：图像/视频/语音生成后，返回 URL 或本地路径，主 Agent 通过地址引用，不直接持有数据
9. **识别类任务返回文本化描述**：图片/视频/音频识别结果全部转成结构化文本字段，主 Agent 基于文本做伪多模态推理

### 通用返回骨架

```json
{
  "status": "success | partial | failed",
  "summary": "不超过 100 字的结果摘要",
  "data": {},
  "error": null,
  "needs_human": false
}
```

---

## 模板文件索引

### 文本类

| task_type | 模板文件 | 适用场景 |
|-----------|---------|---------|
| search | `templates/search_return.md` | 网页搜索、信息检索 |
| extract | `templates/extract_return.md` | 长文档/PDF 字段抽取 |
| classify | `templates/classify_return.md` | 文本分类、打标 |
| summarize | `templates/summarize_return.md` | 长文本摘要 |
| transform | `templates/transform_return.md` | 格式转换、数据清洗 |
| generic | `templates/generic_return.md` | 其他通用子任务 |

### 多模态类（必须外包）

| task_type | 模板文件 | 适用场景 |
|-----------|---------|---------|
| image_recognize | `templates/image_recognize_return.md` | 图片识别、图像理解、OCR |
| image_generate | `templates/image_generate_return.md` | 图像生成、图片设计 |
| video_recognize | `templates/video_recognize_return.md` | 视频理解、内容识别、关键帧提取 |
| video_generate | `templates/video_generate_return.md` | 视频生成、文生视频、图生视频 |
| audio_recognize | `templates/audio_recognize_return.md` | 语音转文字、语音理解、情感识别 |
| audio_generate | `templates/audio_generate_return.md` | 文字转语音、语音生成、配音 |

每个模板文件包含：给子 Agent 的 prompt 指令 + 返回 JSON Schema + 主 Agent 看到的结果示例。

> 生成类模板（image_generate / video_generate / audio_generate）的定位：**规范"给豆包的转述内容 + 成品回传格式"**（image_url/路径 + 简要描述）。执行通道是 `doubao` skill（转述给豆包生成 → extract / download-asset 取回成品），不是让普通子 Agent 去"生成"。

---

## 节省 Token 的额外技巧

1. **并行外包**：多个独立子任务同时委派，主 Agent 只等一次结果汇总
2. **分层摘要**：超长文档先让子 Agent 分段摘要，再汇总二次摘要
3. **缓存复用**：相同查询的子任务结果可缓存，避免重复委派
4. **增量返回**：子 Agent 处理大数据时分批返回，主 Agent 按需取用
5. **丢弃中间态**：子 Agent 的工具调用原始结果在子上下文内消化，绝不回传主 Agent

---

## 工具定义

完整的 `delegate_task` 工具 JSON Schema 见同目录 `delegate_tool_schema.json`，可直接粘贴到 function calling 配置中使用。

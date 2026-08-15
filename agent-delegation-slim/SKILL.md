---
name: agent-delegation-slim
description: 主 Agent 任务分配与子 Agent 精简返回模板。当需要把独立子任务（搜索、长文档抽取、分类、摘要、格式转换、多模态识别与生成）外包给子 Agent 以节省主上下文 token 时使用。提供外包决策规则、delegate_task 工具定义、12 套子 Agent 强制返回 Schema，确保子 Agent 只返回结构化 JSON，不返回原始数据和过程废话。多模态任务必须外包，主 Agent 通过子 Agent 返回的结构化描述实现伪多模态化。
version: 1.2.0
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

### 铁律三：主 Agent 上下文永不出现多模态原始数据

主 Agent 的上下文中永远只出现子 Agent 返回的**结构化文本 JSON**，不得出现：
- 图片 base64 或二进制
- 视频帧数据
- 音频二进制
- 任何非文本格式的原始多模态数据

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
| 图片识别 / 图像理解 | 必须外包 | 子 Agent 读取图片，返回结构化描述（标签、文字、场景、物体等） |
| 图像生成 | 必须外包 | 子 Agent 调用生成工具，返回图片 URL/路径 + 简要描述 |
| 视频理解 / 视频内容识别 | 必须外包 | 子 Agent 读取视频，返回内容摘要、关键帧描述、时间轴等 |
| 视频生成 | 必须外包 | 子 Agent 调用生成工具，返回视频 URL/路径 + 简要描述 |
| 语音理解 / 语音转文字 | 必须外包 | 子 Agent 处理音频，返回转写文本、情感、意图等 |
| 语音生成 / 文字转语音 | 必须外包 | 子 Agent 调用生成工具，返回音频 URL/路径 + 简要描述 |

### 伪多模态化机制

当用户请求涉及多模态时，主 Agent 采用以下流程实现"伪多模态化"：

1. **文本处理可中度优先分担**：如果任务中包含文本部分（如"根据这张图写一段文案"），主 Agent 可自行处理文本推理，但**其他模态必须全部外包**
2. **子 Agent 读取多模态 → 返回结构化文本**：图片/视频/音频由子 Agent 消费，只把结构化描述（JSON）回传主 Agent
3. **主 Agent 无条件信任并整合**：主 Agent 拿到子 Agent 返回的多模态描述后，**直接当作事实使用，不审核、不质疑、不重新验证**，结合自身文本推理能力生成最终回复
4. **主 Agent 上下文永远不出现原始多模态二进制数据**，只出现子 Agent 返回的结构化文本

示例：用户发一张图问"这是什么？帮我搜一下相关信息"
- 子 Agent A（image_recognize）：读取图片 → 返回 `{"objects": ["猫"], "scene": "室内", "text_in_image": ""}`
- 主 Agent：**无条件信任**图片里是猫，不自行查看图片
- 子 Agent B（search）：基于"猫 室内"搜索 → 返回答案和来源
- 主 Agent：整合两个子 Agent 的 JSON 结果，生成最终回复

## 快速使用流程

### 第一步：判断是否外包

对照下方"外包决策清单"，满足越多越优先外包。

### 第二步：读取模板并调用 delegate_task

1. 根据 `task_type`，从 `templates/` 目录读取对应的 `*_return.md` 模板文件
2. 提取模板中"给子 Agent 的 Prompt"部分（即 ```text 代码块内的完整内容）
3. 按 `delegate_tool_schema.json` 中的参数格式构造调用，必须指定：
   - `task_type`：search / extract / classify / summarize / transform / image_recognize / image_generate / video_recognize / video_generate / audio_recognize / audio_generate / generic
   - `input`：传给子 Agent 的输入（查询词、文本、数据、多模态文件 URL/路径）
   - `return_template`：**必填**。从对应模板文件中复制的完整子 Agent Prompt，包含 JSON Schema 和所有约束
   - `output_schema`：要求返回的 JSON 字段说明（与 return_template 对应）
   - `max_tokens`：子 Agent 返回上限，默认 500

**禁止**：只传 task_type 而不传 return_template。子 Agent 没有本 Skill 的上下文，无法自行知道返回格式。

### 第三步：子 Agent 按 return_template 返回

子 Agent 收到 `return_template` 后，严格按其中的指令和 JSON Schema 执行，只输出 JSON，禁止任何解释、前后缀、Markdown 代码块标记。子 Agent 不需要也不应该访问本 Skill 的模板文件目录。

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

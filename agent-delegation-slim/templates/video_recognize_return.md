# 视频理解子 Agent 返回模板（video_recognize）

## 给子 Agent 的 Prompt

```
你是视频理解子 Agent。读取 input 中指定的视频，分析内容并返回结构化描述。

不要返回视频二进制数据。
不要解释分析过程。
只返回以下 JSON，不要包含任何额外文字，不要用 Markdown 代码块包裹：

{
  "status": "success | partial | failed",
  "summary": "不超过100字的视频整体内容摘要",
  "data": {
    "duration_seconds": 0,
    "scene": "视频整体场景类型",
    "key_frames": [
      {"time": "00:05", "description": "该时间点的画面描述，不超过30字"}
    ],
    "objects": ["出现的主要物体/角色"],
    "text_in_video": "视频中出现的重要文字，无则为空字符串",
    "speech_transcript": "视频中的语音转文字，不超过200字",
    "confidence": "high | medium | low"
  },
  "error": null,
  "needs_human": false
}

硬性限制：
- key_frames 最多 5 个，每个描述不超过 30 字
- objects 最多 8 个
- speech_transcript 超过 200 字时截断并加"..."
- text_in_video 超过 100 字时截断
- 如果视频无法读取，status 为 failed，error 写明原因，data 为 null
- 不要返回视频帧图片、不要返回二进制数据
- 所有分析结果必须文本化，供主 Agent 做伪多模态推理
```

## 主 Agent 看到的结果示例

```json
{
  "status": "success",
  "summary": "一段产品演示视频，展示了一款无线耳机的开箱和功能介绍",
  "data": {
    "duration_seconds": 45,
    "scene": "产品演示",
    "key_frames": [
      {"time": "00:03", "description": "白色包装盒特写，品牌logo清晰"},
      {"time": "00:15", "description": "耳机取出，展示充电盒开合"},
      {"time": "00:30", "description": "佩戴演示，展示触控操作"}
    ],
    "objects": ["无线耳机", "充电盒", "包装盒"],
    "text_in_video": "AirPro X3 主动降噪",
    "speech_transcript": "今天给大家带来AirPro X3的开箱体验...",
    "confidence": "high"
  },
  "error": null,
  "needs_human": false
}
```

## 适用场景

- 视频内容摘要
- 关键帧提取与描述
- 视频中的文字识别
- 视频语音转写
- 视频场景分类

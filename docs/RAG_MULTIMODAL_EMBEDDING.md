# 多模态 RAG 与 Embedding 构建

更新时间：2026-10-30

## 能力边界

智谱 `embedding-3` 的输入模态是文本，支持 256、512、1024、2048 维向量，单条请求最多 64 段文本。直接将图片对象放入 `/embeddings` 的 `input` 会返回参数错误（错误码 1210）。因此本项目采用可审计的“多模态转文字后向量化”方案：

- 文本资料按 800 字符、120 字符重叠分段，再调用 Embedding API。
- 图片使用人工描述、OCR 结果或视觉模型生成的图片理解文本参与向量化，同时保留原始图片路径和 MIME 类型。
- 表格序列化为包含表头、行列关系和单元格值的文本。
- 音频、视频先使用转写文本和时间区间，引用仍可回到原始媒体。

这种方式可以用文本向量模型完成跨模态语义检索，但不是原生的图片、音频或视频向量。需要直接以图片查询图片时，应使用智谱 GLM 全模态知识库或 `Embedding-Multimodel`；当前公开的 `/paas/v4/embeddings` 文档只定义了文本输入。

## 数据结构

`KnowledgeChunk` 保留原有 `content/vector/vectorModel`，并增加可选字段：

- `modality`：`text`、`image`、`table`、`audio` 或 `video`。
- `mediaPath`：原始媒体在本机的沙箱路径。
- `mediaMimeType`：原始媒体 MIME 类型。

`RagIndexBuilder` 负责分段、批量向量化和生成稳定片段 ID。`OpenAiCompatibleEmbeddingService` 负责调用 `/embeddings`；模型的 `vectorModel` 使用 `模型名@维度`，避免同模型不同维度被错误比较。

## 构建测试

确定性测试不访问网络：

```powershell
$node = 'D:\DevEco Studio\tools\node\node.exe'
$ts = 'D:\DevEco Studio\tools\ohpm\node_modules\typescript\lib\typescript.js'
& $node tests/rag-construction.test.cjs $ts
```

覆盖内容：

- 固定长度和重叠分段。
- 图片、表格元数据保留。
- 批量 Embedding 返回顺序与输入对应。
- 模型不匹配时降级为关键词检索。
- 关键词与向量余弦混合排序。
- OpenAI 兼容 Embeddings 请求体和维度校验。

真实 API 测试从环境变量读取密钥，不写入源码或配置文件：

```powershell
$env:EMBEDDING_API_KEY = 'your-key'
$env:EMBEDDING_DIMENSIONS = '512'
& $node tests/rag-embedding-live.test.cjs $ts
```

测试语料包含图片描述、软件工程文本、课程表和音频转写。三个问题分别验证“找安静且可充电的学习地点”“根据输入输出来设计测试用例”“查询星期三课程”，并要求正确来源进入前三名。

本次使用 `embedding-3@512` 完成真实调用，三组语义检索全部命中。移动端不应内置长期 API Key；公开产品应通过自有后端代理 Embedding 请求，并执行鉴权、配额和日志脱敏。

## 当前检索策略

默认资料库仍使用 `local-hash-64`，保证离线可用。在线向量通过 `Embedding-3` 构建后，查询向量与文档向量必须使用相同 `vectorModel` 和维度才能参与余弦计算；不匹配时继续使用 BM25 中文二元组关键词检索，不会把不兼容向量硬算成相似度。

图片没有描述时仍可加入对话，但不会参与检索。资料库中的“添加图片描述”会保存描述、启用检索，并保留原始图片作为可预览附件。

## 资料库工作台

资料库保持原有整体导航和黑白灰视觉，只增加内部工作区：

- **资料**：左侧资料列表、右侧正文或图片详情；保留导入、图片描述、检索开关和加入上下文。
- **知识库**：管理多个知识库及其资料范围。在线知识库选择 Embedding API 后构建索引；重排序可选择不重排、本地重排或在线 Rerank。
- **数据可视化**：以关系图、节点或表格展示来源和片段。关系图节点可点击，检索命中来源会高亮，片段可直接加入当前对话。
- **模型与 API**：分别管理 Embedding 和 Rerank 服务地址、模型、密钥及向量维度。密钥只保存在设备沙箱。
- **本地算法**：调整关键词/向量权重、BM25 K1/B、Top K、最低分数、单来源上限、上下文预算、本地重排权重及切块参数。

知识库、API配置、索引和算法保存在应用沙箱 `rag_workspace.json`。公开部署时长期API密钥应由后端代理保存，不应随客户端HAP分发。

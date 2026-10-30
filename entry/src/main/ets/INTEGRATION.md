# 前端与 Agent 模块联调约定

此入口模块提供知识检索、来源引用、外部模型流式对话、本地会话存储、附件及系统语音能力，以及表单、学习、魔方的接口边界。生产索引、业务服务、设备联动和本地加密存储仍需各自负责人接入；未接入的业务适配器会明确返回“服务尚未接入”，不会伪造请求成功。统一注册位置为 `services/IntegrationService.ets`。

## M7 检索数据侧

由数据侧注入 `KnowledgeRepository` 和可选的 `QueryEmbedder`。`snapshot()` 一次返回同一索引版本：

- `revision` 是每次索引更新的稳定版本标识。
- 每段 `KnowledgeChunk` 有稳定唯一的 `id`、文档级 `sourceId`、原始资料标题、章节或页码 `location`、课程 `course` 和用于引用的 `content`。
- `vector` 与 `vectorModel` 成对提供。`QueryEmbedder.modelId` 必须与文档向量所用模型一致；维数和模型不匹配的片段只参与关键词搜索。
- 可选 `modality`、`mediaPath`、`mediaMimeType` 记录文本、图片、表格、音频或视频来源；图片、音视频应先把描述或转写作为 `content`，原始媒体仍通过路径回溯。
- 每一处内容与位置应能回溯到原始文档；文档解析、切块、向量生成、索引存储和联网兜底由 M7 数据侧承担。

`RagService.search(query, options)` 会按选择的课程过滤片段，执行中文字符二元组与英文词的 BM25 关键词检索；有匹配模型向量时，将关键词得分与余弦相似度合并。默认最多返回 4 个片段、每份资料最多 2 段，截取的资料文本预算为 2400 个字符。低于相关度阈值的片段不入选。每条结果包含稳定编号、来源、章节、原文片段和分数；检索不到时返回空引用和明确提示，不自动把猜测内容当成资料。

请将一份索引版本的全部片段一次传给 repository，避免生成过程读到正在更新的索引。空文档、空片段和重复 ID 会被检索过滤。演示索引中的课程资料仅供离线演示，并不代表学校官方资料。

## 系统日程工具与持久备忘录

全局页面由 `Index.appSection` 切换，`GlobalRail` 始终显示；`TaskCenterPage` 承载日历、提醒、备忘录与 `AgentTaskPage`，`LibraryPage` 统一管理资料。普通会话保持独立状态，不用特殊工作区模拟这些页面。

`LibraryService` 包装原有 `KnowledgeRepository`，组合已启用的外部片段和持久化本地资料，实现 `snapshot()`；`IntegrationService.knowledge` 指向该组合仓库。文件迁移/导入复制到 `library_files`，发送附件再次复制到 `chat_attachments`，两者生命周期独立。文本按800字符、120重叠分段；JSON索引校验后保留向量、模型及模态标识，命名空间前缀隔离片段ID。图片没有描述时只可预览和加入对话；保存图片描述后会以描述文本参与检索，并保留图片路径与 MIME 类型。`library.json` 保存开关、正文、元数据和删除标记，禁止旧会话重新导入已删除源。

默认 base 为炫神（许昊龙）公开知识库（14 段，`local-hash-64` 向量）。本地文本与导入文本在分段时同样补 `local-hash-64` 向量；`IntegrationService.embedder` 默认使用 `StudentQueryEmbedder`，因此资料库与对话检索可离线执行关键词 + 余弦混合检索。RAG JSON 中已有向量的片段保留原向量与 `vectorModel`，模型不匹配时只参与关键词检索。

`OpenAiCompatibleEmbeddingService` 提供在线 `/embeddings` 批量调用；`RagIndexBuilder` 负责分段、模态文本拼接、最多64条批处理和稳定片段ID。智谱 `embedding-3` 只接受文本输入，图片检索需先保存图片描述、OCR 或视觉模型描述；原生跨模态检索应接入 GLM 全模态知识库或 `Embedding-Multimodel`。详见 [多模态 RAG 与 Embedding 构建](../../../../docs/RAG_MULTIMODAL_EMBEDDING.md)。

`RagWorkspaceService` 在应用沙箱 `rag_workspace.json` 持久保存知识库、API配置、已构建索引和本地算法。每个知识库可选择内置/本地资料范围、在线或本地 Embedding、在线或本地重排序。在线索引通过 `RagIndexBuilder` 构建；资料或知识库设置改变后旧索引会失效并显示为待重建。`OpenAiCompatibleRerankService` 兼容 `/rerank` 的 `results/data + index + relevance_score/score` 响应。

资料库前端保持原有黑白灰框架，在内部提供“资料、知识库、数据可视化、模型与 API、本地算法”五个工作区。资料页为列表/详情分栏；可视化支持可点击关系图、节点和表格，并可直接执行当前知识库检索、高亮命中来源和把片段加入对话上下文。

`AgentTaskService/Store` 管理周期、状态及最近5次结果；`LocalJsonStore` 使用原子替换、同步备份和短时目录锁。`AgentTaskRuntime` 前台轮询到期任务，并注册一个2小时周期的系统延迟任务；`AgentTaskAbility` 在后台回调时认领到期任务。实际唤醒受系统活跃分组等策略控制，不能作为准时闹钟。跨进程认领先落盘 `runId/runningSince`，周期推进后才调用模型，重复到期合并一次，过期执行记录为中断，旧回调不能覆盖新结果或复活已删除任务。

自动执行最多85秒；工具白名单只有读时间、日历、提醒和本地备忘录的list/read，服务端分派也校验，不能靠模型遵循提示词来保护写操作。后台只检查现有日历授权，不弹窗。普通对话额外提供 `manage_agent_task` 管理任务，执行前展示时间/周期核对；API配置存设备私有首选项供后台读取，清空后不自动复活打包配置。

`ScheduleService` 提供独立于平台的参数校验和9个工具契约；`HarmonyScheduleAdapter` 实现 `SchedulePlatform`，在聊天页初始化并与原有4个工作区工具一起提供给模型。系统工具对所有现有工作区可用，`Index.executeWorkspaceTool` 优先分派这些调用，实际结果作为 `role: tool` 返回给模型。

- `get_system_time`：设备当前时间、IANA时区、UTC偏移。请求初始上下文也包含设备时间。
- `query_calendar_events`：查询授权日历中的事件实例，单次最多31天、返回100项；部分日历失败或截断标记 `partial`，不把部分读取当作无冲突。
- `create_calendar_event`、`update_calendar_event`、`delete_calendar_event`：真实日历写操作，使用 `calendarId/eventId` 定位；更新保留未修改字段，同标题同起止时间不重复创建。重复日程不直接修改整个系列。
- `create_system_reminder`：`alarm/calendar/timer` 三种系统代理提醒；`list_system_reminders`、`cancel_system_reminder` 仅管理本应用发布的提醒。系统时钟应用的闹钟不在可访问范围内。
- `manage_memo`：`list/read/save/delete/share`，本地跨会话保存。列表返回400字预览，修改前按ID读取全文，避免把预览覆盖成完整正文。`MemoStore` 原子替换与备份恢复；备份同步删除状态。分享使用官方 `Share Kit`，返回 `status=share_opened` 仅说明入口已打开，不能声称目标应用已经保存。

所有日期工具参数要求带时区的 ISO8601；星期为周一1到周日7，闹钟时刻按设备本地时间，日期提醒精确到未来整分钟。日历读写按需请求权限，代理提醒检查通知授权。写操作展示实际对象与内容核对；用户取消、停止生成、会话切换或权限请求后调用失效时不继续写。已经执行的系统操作不能通过取消网络请求撤销，需再次查询系统列表。

`SystemSchedulePanel` 是独立的设置窗口入口，不依赖模型即可查询/管理日程、提醒和备忘录。系统能力、权限与代理提醒权益失败都返回 `ok=false`，不会静默改用其他类型的提醒。只申请读写日历及发布代理提醒权限，不申请读取全部私有日历的受限权限。官方能力说明：[Calendar Kit](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-calendarmanager)、[代理提醒限制](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)。

## Agent 消息流

输入框内麦克风右侧的模型名称可切换已保存配置；菜单“管理模型 API…”打开配置窗口，支持最多20组独立的名称、服务地址、模型和可选API Key。填写服务根地址（例如 `https://api.example.com/v1`）；可选 Key 适用于本地或无鉴权服务。应用会在请求时拼接 `/chat/completions`，发送系统指令、当前功能 ID、最近 12 条历史（每条最多 4000 字符）、当前问题及合并后的检索资料。`ohos.permission.INTERNET` 已在 entry 模块声明。

也可直接编辑 `entry/src/main/resources/rawfile/local_api.json`，首次初始化多配置存档时会读取。原有运行时单配置优先迁移；一旦已有多配置存档，配置文件不再覆盖应用内选择，清空配置也不自动复活文件中的密钥。该文件已加入 `.gitignore`，不会被常规 `git add` 和提交上传；`local_api.example.json` 提供无密钥模板。配置示例：

```json
{
  "baseUrl": "https://api.example.com/v1",
  "model": "your-model-name",
  "apiKey": "your-key"
}
```

rawfile 会被打入 HAP，因此 Git 忽略只保护密钥不进入仓库，不能保护已构建或分发的安装包。公开部署应由自有后端保管密钥并代理模型调用。

外部模型适配器为 `OpenAiCompatibleGateway`，实现 `AgentGateway.generate(request, sink)`。适配器对 `request.retrieval.context` 必须按**不可信资料**处理；只给有资料支持的句子加 `[编号]`，缺少证据时明确说明。默认配置为空，未填写服务地址和模型前不会假装生成成功。

当前兼容适配器通过 `requestInStream` 接收 OpenAI SSE 流，并在每个 `dataReceive` 事件中解析 `choices[0].delta.content`，通过 `sink.onDelta` 立即更新聊天气泡；部分不支持流式的兼容服务会自动回退读取完整 JSON 回答。用户取消、切换页面或等待模型超过 93 秒时，UI 会调用 `AgentGateway.cancel()` 销毁进行中的 HTTP 请求。等待系统工具、授权或核对窗口期间暂停模型超时计时，系统操作返回后重新计时。复杂问题会被提示以简短的“思路摘要”说明任务拆解和关键依据，不展示逐字内部推演。

## 回答排版与思路摘要

Agent 气泡使用 `MarkdownContent` 原生渲染标题、粗体/斜体、列表/任务项、分隔线、引用、行内代码、代码块和横向滚动表格。渲染器不执行 HTML、不自动请求远程图片。旧历史消息的 Markdown 无需改写即可重新排版。消息重绘标识包含会话 ID 与内容版本，避免流式更新或切换历史时显示旧节点。

`AgentAnswer` 提供可折叠的思路摘要区：请求期间显示实际的检索/连接/分析/生成阶段、加载图标及用时；完成后显示摘要入口。外部模型通过正文 `<summary>...</summary>` 提供简短用户可见摘要，旧版本 `## 思路摘要` 也兼容。API 的 `reasoning_content` 只触发“正在思考”阶段，不展示、不保存内部推演原文。摘要是用户可见的任务拆解/方法说明，不声称等同于模型完整内部推理。展开状态跨当轮流式刷新保留；摘要正文与完成用时随消息一起本地保存。

展开区还通过 `ExecutionTimeline` 显示实际执行记录。`Index` 在 `executeTool` 前后记录请求与真实回执；`ExecutionTraceService` 只保留白名单参数摘要、状态、时间和有回执支持的文件/资料/产物信息，最多24条。工具请求中的正文、密钥和所谓命令不直接写入日志；当前工具未提供终端执行，不将工具名、计划或模型文字当作已运行的命令。会话产物保存在 `chat_sessions.json`，与导出的独立文件区别展示；只将实际新增、变更或移除的产物记为相应操作，入口打开当前版本。

`AgentMessage.executionId/executions/thinkingLastActiveAt` 与消息一同保存。结束、报错和停止时固定 `thinkingDurationMs`，重开历史不重新计算；旧消息没有结束用时则标为未记录。中断时运行中的工具标为结果未确认；迟到的真实回执按原会话和原回复ID补入，不切换当前会话、不复活已删除记录，也不重置固定用时。记录文本过滤当前API密钥/服务地址和常见凭据格式，不保存 `reasoning_content`。

## 工作区 Agent 与任务面板

`WorkspaceConfig.ets` 为九个工作区集中定义角色提示词、开场白、快捷提问与初始任务模板。`ChatService.request` 会加入当前工作区预设、设备时间和当前会话面板快照，包括目标、任务、摘要及产物。人工修改的完成状态也进入下一轮请求。

`AgentRequest` 可选提供 `tools` 和 `executeTool`。外部网关接收增量 `tool_calls`，按调用 ID 与索引组装参数，执行后把 `role: tool` 的实际结果回传模型，继续流式生成回答；兼容非流式 JSON 工具结果。单轮最多四轮工具请求、十二次工具操作，随后要求输出最终回答。停止生成或切换会话会令旧调用失效，不更新新会话。

- `read_workspace`：读取当前会话的工作区与面板。
- `update_task_panel`：更新目标、摘要、任务、Markdown 产物，校验字段类型、长度、唯一 ID 及任务状态。未提供的字段保留，提供的任务/产物数组为完整替换。
- `switch_workspace`：在同一会话中切换角色，保留消息、目标、摘要和产物，更换任务模板；返回新角色要求供后续生成使用。
- `run_workspace_action`：仅执行当前工作区允许的表单、学习或魔方业务操作，使用注册适配器的真实结果。服务未接入时返回失败，不假装成功。

工具没有读写 API 配置、任意文件或其他会话的能力。右侧支持手动完成/重开任务、将任务交给 Agent 继续处理、查看与复制产物；“推进下一步”发送真实对话请求，已移除定时增加进度的演示逻辑。业务页面中的任务统计与产物也读取同一会话状态。

面板存入 `ChatSession.workspace`，包含 `goal/summary/tasks/artifacts/updatedAt`。旧会话缺少该字段时使用对应工作区的待处理模板，不把旧演示进度当作已完成。保存面板不会改变会话的最近消息时间；生成或发送消息仍按原规则更新。需要模型服务支持标准 Chat Completions `tools/tool_calls`。

## 动态工作区与自动归类

`SessionArchive.workspaces` 保存当前真实分区注册表。旧档案没有此字段时迁移默认九组；`home`、`trash` 始终补齐且不可删，删除的默认分区不会重新自动出现。用户点击工作区分组标题，再从选中行的“⋯ → 新建工作区”打开独立弹窗，填写名称、说明、可选角色提示词；最多 30 个分区，名称唯一。删除工作区为一次归档事务，全部所属会话移入回收站，落盘失败同时恢复注册表与会话归属。

`WorkspaceConfig.profile(id, features)` 为内置分区提供预设，自定义分区使用用户填写的提示词。`WorkspaceService.tools(features)` 和 `snapshot(..., features)` 只向模型提供当前存在的可对话分区，排除回收站。智能助理按主要话题主动 `switch_workspace`，无明确匹配则归入或保留 `home`；不提供创建/删除工作区的模型工具。不能切换到已删除 ID，也不能在回收站更新面板。该自动归类依赖所选模型支持并实际调用标准工具。

可点击区域共用悬停/按压样式，输入框聚焦显示柔和边框与阴影，分组及面板折叠使用短动画；流式回答气泡不会逐片段重复播放入场效果。

## 首页与工作区欢迎页

左上角品牌入口（收起侧栏时为品牌 C 图标）调用 `openHome`，进入 `home` 欢迎页。点击工作区名称也进入对应欢迎页；`trash` 仍进入回收站。`isWelcomePage` 区分欢迎与历史会话，欢迎页只显示时段问候、对应分区说明与角色快捷提问，暂时隐藏任务面板，避免显示上一会话的状态。

进入欢迎页前停止生成并保存当前会话，清理未发送附件、草稿和上下文。浏览欢迎页及菜单“新建对话”均不生成空白历史；发送首条有效消息时才调用 `SessionService.create`，保留当前待发送附件与资料，随后按正常流式流程保存消息和面板。历史入口直接调用 `restoreSession`，恢复已保存的内容与所属工作区。每次创建应用主页面时都显示首页欢迎页，不自动打开上次实际会话；历史记录及其最近消息时间不受影响。

## 本地历史对话

`SessionService` 在 Ability 启动时从应用沙箱 `context.filesDir/chat_sessions.json` 恢复历史。每个会话使用独立 UUID，首条问题自动作为标题；记录创建时间与最后消息更新时间，侧栏显示日期时间并按最后消息时间倒序排列，同一时间使用创建时间和 UUID 稳定排序。保存未变化的消息、查看或切换会话、修改上下文不会刷新最后消息时间，因此不会因切换而跳动。切换会话同时恢复所属工作区、消息全文、来源引用、主动加入的资料及任务进度，重启后进入首页，点击侧栏会话可恢复原有内容。不再按 100 条截断历史；发送给模型的上下文仍受最近 12 条及单条 4000 字符限制。

侧栏会话选中后才显示“⋯”；“⋯ → 移入回收站”先确认，然后只修改所属分区并记录 `deletedAt/originFeatureId/originFeatureName`，保留原消息时间、正文、引用、任务和附件。回收站会话只读，不参与最近对话和模型工具调用；恢复时回到仍存在的原分区，否则回到 `home`。只有回收站的“永久删除”会清理底层记录及不再被其他会话引用的沙箱附件副本。写入失败回滚内存；备份同步删除状态，防止旧备份复活。

左栏采用中性深色、紧凑文件夹树、固定顶部入口与统一滚动区。`SidebarService.view` 根据 `SessionSummary.featureId` 将会话归到对应工作区；同一 ID 同时进入跨工作区的最近对话列表，不复制消息记录。每个工作区可独立折叠，默认显示最近 3 条，会话多时可展开；最近对话默认 8 条，可显示全部。顶部搜索按会话标题和工作区名称同时筛选两处列表。

工作区行、会话行、顶部对话入口和工作区分组标题的菜单只在点击选中后显示。`sidebarSelection` 区分工作区、分组及工作区/最近对话两个会话入口，同一会话不会在两处同时出现菜单。工作区“⋯ → 新建对话”创建该工作区的会话，顶部“对话 → ⋯ → 新建对话”沿用当前工作区；分组标题“⋯”可新建工作区。所有侧栏新建入口统一放进菜单。选择只保留在本次运行中，普通会话切换不强制打开已折叠的文件夹。Agent 切换工作区后，保存的 `featureId` 会让两处列表同步更新归属；移入回收站仍只修改一次底层记录。会话操作使用独立 SVG 三点图标和零内边距按钮，避免文字按钮被挤掉。

`SessionArchive.sidebar` 保存分组开关、独立工作区展开列表、较早会话展开列表、最近对话展开范围、左右侧栏可见状态与宽度（默认256/274vp，基础最小220/244vp，随大字号提高，最大400/420vp）。边界手柄使用水平 PanGesture，限制宽度以保留正文空间；双击复位，拖动结束落盘。滚动内容右侧保留 12vp 空隙，滚动条宽度 3vp，避免覆盖会话操作。旧档案没有这些设置时使用默认值；非法字段回退到默认配置。侧栏收纳操作不改会话消息时间，删除会话与恢复备份均保留侧栏偏好。搜索词只保留在本次运行中。

欢迎页和聊天标题栏的“＋上下文”入口使用独立的居中弹窗（窄屏适配系统面板），资料检索区域独立滚动，不插入聊天消息流。点击“完成”或遮罩关闭，资料选择继续绑定当前会话并保存到本地。

用户发送后立即保存；生成中最多每 700ms 写入一次已收到的片段，完成、停止、切换和进入后台时立即落盘。写入通过临时文件、fsync 和重命名替换，同时保留 `.bak` 上一份有效快照；主文件损坏时读取备份。进程意外终止后，未完成消息显示“上次生成已中断”，可继续对话。读写失败会显示提示。文件仅位于设备应用沙箱，不写入项目目录或 Git；当前为沙箱内 JSON，未额外加密，M8 可在此存储边界接入加密。

## 附件与麦克风

输入框“＋”调用系统文件/相册选择器。每条消息最多 4 个附件、单个原文件上限 12 MB；图片转为最长边 1440px 的 JPEG 并保存在应用沙箱，文档支持 UTF-8/UTF-16LE 的 TXT/MD/CSV/JSON/LOG、文本型 PDF 和 DOCX。DOCX 只在内存读取 `word/document.xml`，不解压任意 ZIP 路径；PDF 扫描件没有文字层时明确提示改用图片。每份文档最多提供 12000 字符，截断会提示；单次模型请求合计提供最多 24000 字符附件文本、4 张图片，优先当前附件及最近历史。原始文件、提取文字和消息附件关联一起保留在设备本地。

文件文字以不可信参考数据拼入用户消息；图片按 OpenAI `image_url` data URL 发送，需模型支持视觉。API Key 不会写入附件内容。发送前可以移除附件，不删除系统中选中的原文件；取消选择、导入失败、导入中切换会话会丢弃本次未发送附件，不影响已发送附件。

麦克风使用 `HarmonyVoiceAdapter`（Core Speech Kit）中文离线识别，点击时申请 `ohos.permission.MICROPHONE`，再次点击结束。中间/最终结果填入输入框，始终由用户核对后主动发送；设备缺失语音引擎、权限拒绝、启动超时会显示具体提示。切换会话、退出页面或进入后台会取消录音；等待权限期间取消也不会在稍后偷偷启动麦克风。语音原始音频不落盘。原有“朗读回答”同时接到系统中文 TTS，朗读前移除 Markdown 标记和思路摘要。

## 其他页面接口

在 `IntegrationService` 注册各自的 `ModuleAdapter`：`forms` 执行模板、草稿、导出和辅助填充；`study` 执行课表、提醒、计划、打卡和复习手册；`hardware` 执行连接、姿态查询和专注控制。按 `ModuleResult.ok` 判断操作成功，只将成功响应中的 items 展示为实际结果。

`IntegrationService.voice` 默认注册系统 `HarmonyVoiceAdapter`，也可替换为其他 `VoiceAdapter`。`start(observer)` 开始识别，`stop()` 结束并返回待用户核对的文字，`cancel()` 立即停止采集。`speak(text)` 播报回答，`stopSpeaking()` 中断播报。UI 不会在用户确认前自动发送识别内容。

资料检索入口位于欢迎页及聊天标题栏的“＋上下文”，使用独立弹窗；输入框旁的“＋”用于导入文件或图片。用户可预览资料原文并逐条加入或移除引用；发送消息时把这些资料与当轮检索合并，再把统一编号后的引用交给 Agent 和消息列表。左栏的工作区会话树与最近对话统一滚动，引用文字可复制。


## 独立 API 配置面板

欢迎页与会话页共用输入区`ModelSelector`，自定义弹层和管理窗口复用`ApiProfileList`的搜索、限高滚动、当前项标记与字号缩放；0配置直接打开配置窗口。`apiSettingsVisible`通过主内容容器独立`bindSheet`打开`ApiProfilesSheet`，与上下文弹窗使用不同锚点。窗口支持新建、编辑、另存、仅保存、保存并使用及删除；API Key使用密码输入，全部输入提示显式跟随全局字号。关闭或遮罩退出不保存草稿，保存并使用成功后关闭，校验或存储失败留在窗口提示。

`LocalAgentConfigService`在`agent_runtime`私有首选项的`profiles_v1`中统一保存配置列表和activeId，一次flush提交，失败回滚缓存；迁移后移除旧settings副本。UI列表只取得id/name/model摘要，不展示服务地址和密钥；模型菜单切换成功后才更换网关，生成过程中禁用切换。后台每次执行先刷新进程内首选项缓存，再通过同一服务读取activeId所选配置，已创建的网关保留自身设置快照。损坏存档保留且不静默回退到另一服务，删除最后一组后持久保留空存档。


## 黑白界面主题

`UiTheme.ets` 统一页面底色、卡片、主按钮、文本、边框及聚焦样式，侧栏保持深灰。应用显式使用浅色系统控件以匹配页面的黑白灰布局；输入框光标、选区、Markdown 和思路摘要也使用中性色。`UiTheme.userBubble` 单独保留用户气泡的淡绿色，与白色 Agent 气泡区分。启动入口不再调用当前会话恢复，仅加载侧栏和历史列表并进入智能助理首页；会话仍通过历史入口恢复。


## 清单与回执交互

`InteractiveContent` 在正常 Agent 正文、产物详情及记忆摘要中复用 `MarkdownContent`：明确任务清单呈现小型圆角方形勾选框，普通解释列表保持文字排版，“填写 / 补充”切换表格单元格编辑并展示补充说明；代码块和引用不生成交互控件。统一提供确认内容、需要调整、撤回确认及重置反馈。

`InteractionService.layout` 按标题路径、项目文字、行标识和列名生成稳定控件 ID，同名重复项分别计数，避免只用显示位置导致错配。每份内容使用独立来源 ID（`message-序号`、`artifact-产物ID`、`memory-summary`），反馈存入 `WorkspaceState.interactions`，不改写模型原始正文或消息时间。输入回调附带会话和内容标识，切换后的旧回调、生成中及回收站操作均拒绝写入。

每个字段最多1000字符，每份内容最多160个控件；会话交互记录限制为120份、480个已操作字段、48000字符，超限时拒绝新改动并保留旧值。输入采用700ms合并写入，勾选、确认和重置立即落盘；切换、继续对话或应用进入后台会刷新待写入数据。重置保留 `resetAt` 记录，撤回确认使用 `decision=none`，明确清空的字段保留空字符串。

`ChatService` 将全部有效交互反馈作为有来源的独立数据附加到下一轮请求，即使其原消息已不在最近12条内。工作区快照和工具读取也包含反馈；首次请求避免重复附加同一份记录。模型可读用户反馈，不能通过 `update_task_panel` 直接重写 `interactions`。切换工作区和恢复旧面板均保留经过校验的交互数据，任务面板字段损坏时仍尽量恢复有效反馈。反馈仅代表本地用户标记/填写，不能声称已执行未接入的外部业务。

交互记录还保存 `contentSignature`。内容改版后，整份旧确认不自动授权新版；界面保留输入并提示核对，请求上下文以 `versionStatus` 区分版本，并将已移除控件标记为 `active=false`。表格中的“待填写”等初始文本在编辑时作为占位提示，不拼接到用户输入中；产物预览同步显示已勾选和已填写值。

### 原位表单与字号

`InteractionService.formTokens` 在 Markdown 行内格式解析前识别 `___`、全角下划线与 Unicode 方框，代码、转义、加粗及标识符保持文字。`InlineFormContent` 在段落、列表和表格中直接呈现横线输入与选项；单位、示例留在字段外，单选组写入时同时取消同组其他选项，多选独立保存。字段继承来源隔离、版本校验、持久化和下一轮反馈机制。

`SidebarPreferences.fontScale` 保存0.8–1.3的缩放系数，默认0.9；各文本组件通过 `@StorageLink('campusFontScale')` 同步更新。左侧栏固定底部设置入口在收起状态仍可访问。

输入控件需分别设置 `fontSize` 与 `placeholderFont`，避免提示文字沿用系统默认字号。聊天输入区使用紧凑单层容器；原位输入宽96、高28的基础尺寸及表格列宽184均乘以 `fontScale`，搜索、勾选、间距与补充输入区同步缩放，百分比布局保持适应可用宽度。

### 侧栏最小宽度与折叠手势

`SidebarService.panelMinimum` 以左220、右244vp为基础，大字号乘以缩放系数提高可读下限；`resize` 将宽度限制在可用范围，在拖动意图宽度小于或等于本次手势开始宽度的1/3时标记待折叠；将拖动点移回1/3以上可取消待折叠。拖动过程中保持最小可读宽度，结束时以最终位移重新判定，满足1/3比例条件才收起并保留手势开始宽度，取消手势不收起；展开按钮恢复保留宽度。`SidebarPreferences.taskPanelVisible` 保存右栏开关，缺失字段按展开兼容旧存档。收起后的左侧图标栏也适应大字号。

气泡操作按钮和朗读按钮使用同一紧凑尺寸与圆角；右侧任务、进度卡片及内边距跟随 `fontScale`。记忆摘要通过 `InteractiveContent.compact` 使用13vp正文基准，保留相同的反馈数据与行为。

## 自律模式与健康使用设备

自律魔方页面提供番茄钟与 Screen Time Guard Kit 设备专注锁。番茄钟默认 25 分钟专注、5 分钟休息，可调整专注时长，支持开始、暂停、重置、进度环和累计番茄数。暂停番茄钟时同步解除设备锁；继续时按剩余分钟重新创建总时长策略，避免系统墙钟计时与暂停状态不一致。

设备锁流程：

1. `guardService.getUserAuthStatus()` / `requestUserAuth()` 获取用户明确授权。
2. `appPicker.startAppPicker()` 拉起系统应用选择器，返回去标识化 token 作为 APP 白名单。
3. `addGuardStrategy()` + `startGuardStrategy()` 创建并启动 `TOTAL_DURATION_TYPE` 策略，`totalDuration` 单位为分钟；`TRUSTLIST_TYPE` 表示白名单内应用可用、名单外应用在时长内受限。
4. `stopGuardStrategy()` + `removeGuardStrategy()` 解除并清理策略。

Agent 在自律魔方工作区可通过 `focus_lock` 工具设置 `action`（start / stop / status）、`durationMinutes`（1-1440）和 `useWhitelist`。只有工具返回 `ok:true` 后才能向用户声称设备锁已生效；权限被拒、设备不支持或用户取消时明确提示，并保留本地番茄钟。

`ohos.permission.MANAGE_SCREEN_TIME_GUARD` 是受限 ACL 权限：调试需在自动签名中启用对应 ACL，发布前需按华为开发者联盟流程申请 ACL 权限。

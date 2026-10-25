# CampusPilot · 杭电校园助手

基于 HarmonyOS、ArkTS 和 ArkUI 的校园助手项目，面向手机和平板，提供对话式入口、课程资料检索和多个校园生活功能页面。当前开发重点为张睿祥负责的前端交互、Agent 对话及模块联调。

本说明对应截至 **2026 年 10 月 25 日** 的工作区代码。按日期记录的开发内容见 [开发日志](CHANGELOG.md)，模块接口及数据约定见 [联调说明](entry/src/main/ets/INTEGRATION.md)。

## 功能与当前状态

| 功能 | 当前状态 |
| --- | --- |
| Agent 对话 | 可配置 OpenAI Chat Completions 兼容 API，支持流式回答、停止生成、错误与超时提示 |
| 回答排版 | 原生显示 Markdown 标题、强调、列表、引用、代码块和表格 |
| 思路摘要 | 显示连接、分析、生成等阶段及用时，支持展开简短摘要；不展示模型内部推演原文 |
| 课程资料 | 支持关键词检索、课程筛选、来源引用和主动加入上下文；匹配模型的向量可参与混合检索 |
| 上下文选择 | 独立弹窗，资料选择与当前会话绑定 |
| 本地历史 | 保存消息、引用、附件关联及任务进度；按最近消息时间倒序，切换时顺序不变；支持删除与备份恢复 |
| 文件与图片 | 输入框“＋”打开系统文件或图片选择器，支持文档提取及图片随消息发送 |
| 语音 | 接入系统中文语音识别与朗读，识别结果填入输入框后由用户发送 |
| 功能页面 | 包含智能助理、求职实验室、智能日程、消费洞察、表单填报、自律魔方、健康计划、天气穿搭、学习助手 |

功能页面与任务面板中仍有演示内容。表单、学习课程、自律魔方的业务适配器默认返回“服务尚未接入”；课表同步、表单导出、蓝牙设备联动等需由对应模块继续实现。生产课程资料的解析、切块、向量生成及索引服务也需接入，内置资料仅用于离线演示。

## 开发环境

- DevEco Studio：当前已验证版本为 **6.0.2.670**。
- HarmonyOS SDK：项目目标与兼容版本均为 **6.0.2（API 22）**，以 `build-profile.json5` 为准。
- 构建工具：项目自带 Hvigor，依赖由 OHPM 管理。
- 运行设备：HarmonyOS 手机或平板；当前已在 **MatePad Pro 11 模拟器**构建、安装并验证主要交互。
- 命令行：本项目开发使用 `devecocli`。未加入 PATH 时可使用本机安装位置的绝对路径。

## 获取与运行

```powershell
git clone https://github.com/ZRX-1001/huawei_project.git
cd huawei_project
```

使用 DevEco Studio 打开项目根目录，完成 SDK、依赖同步，并在 Device Manager 中启动设备。连接真机时按本机环境配置调试与签名；当前仓库未提供个人签名材料。

在项目根目录运行：

```powershell
devecocli device list
devecocli build
devecocli run --module entry
```

连接多个设备时指定设备名称或序列号：

```powershell
devecocli run --module entry --device "MatePad Pro 11"
```

本机命令不在 PATH 时的调用示例：

```powershell
& "$env:APPDATA\npm\devecocli.cmd" build
& "$env:APPDATA\npm\devecocli.cmd" run --module entry --device "MatePad Pro 11"
```

当前 DevEco Studio 6.0.2 环境可使用 CLI 构建、部署及 UI 检查；CLI 的 `emulator list/start` 命令要求 Studio 6.1.0 及以上，因此本环境通过 Studio 启动模拟器，再使用 `device list` 检查连接。

## 配置模型 API

### 方式一：应用内填写

点击聊天输入框下方的“配置外部模型 API”或“管理 API”，填写：

- **服务地址**：服务商提供的 Chat Completions 兼容根地址，例如 `https://api.example.com/v1`。
- **模型名称**：该服务实际支持的模型 ID。
- **API Key**：对应密钥；无鉴权的本地服务可以留空。

应用会拼接 `/chat/completions`，请勿将示例地址当作可用服务。当前应用内配置保存在运行时内存中；需启动时自动载入配置时使用下方本地文件方式。

### 方式二：本地文件自动载入

在项目根目录执行：

```powershell
Copy-Item entry/src/main/resources/rawfile/local_api.example.json entry/src/main/resources/rawfile/local_api.json
```

如果已经存在 `local_api.json`，直接编辑原文件，避免覆盖已有配置。内容示例：

```json
{
  "baseUrl": "https://api.example.com/v1",
  "model": "your-model-name",
  "apiKey": "your-api-key"
}
```

修改后重新构建部署，应用启动时读取该文件。`local_api.json` 已被 `.gitignore` 忽略；提交前可检查：

```powershell
git check-ignore entry/src/main/resources/rawfile/local_api.json
```

示例文件只放占位值。**rawfile 配置会进入构建的 HAP 安装包**，Git 忽略并不能隐藏安装包中的密钥；公开分发应由后端保管密钥并代理请求。

模型请求需要设备或模拟器能够访问服务地址。电脑能访问服务不代表模拟器网络已连通；图片分析还需要所选服务和模型支持视觉输入。

## 使用说明

1. 配置 API 后，新建对话并发送消息，回答会逐段显示。
2. 点击“＋上下文”，在独立弹窗中检索资料、加入当前会话，点击“完成”返回对话。
3. 输入框“＋”用于导入文件或选择图片；麦克风按钮用于识别语音，再次点击结束识别。
4. 最近对话显示日期时间，按最近消息倒序；打开已有会话不会刷新其时间。右侧三点按钮可打开删除菜单，删除前需确认。
5. 点击“最近对话”标题可向上收起列表，标题不再随收起下移。工作区和会话列表分别滚动。

支持文本型 TXT、MD、CSV、JSON、LOG、PDF、DOCX 文件；扫描 PDF 暂无 OCR，可改为图片输入。每条消息最多 4 个附件，单个原文件上限 12 MB；更详细的文本、图片预算见 [联调说明](entry/src/main/ets/INTEGRATION.md)。

历史记录位于设备应用沙箱的 `filesDir/chat_sessions.json`，附件副本位于 `filesDir/chat_attachments/`，不会写到项目目录。应用重启后恢复历史；卸载或清除应用数据会清除这些记录。当前采用本地 JSON 与备份文件，尚未额外加密，也未实现跨设备同步。

## 代码结构

```text
AppScope/                         应用标识与全局资源
entry/src/main/
├── ets/
│   ├── pages/Index.ets           主界面、侧栏、对话及功能入口
│   ├── components/              Markdown 回答与思路摘要组件
│   ├── config/                  API 请求限制、功能目录、检索参数
│   ├── models/                  消息、检索、附件及适配器类型
│   ├── services/                对话网关、检索、存储、附件和语音服务
│   ├── entryability/            应用生命周期入口
│   └── INTEGRATION.md           模块联调约定
├── resources/rawfile/
│   └── local_api.example.json   无真实密钥的 API 配置模板
└── module.json5                模块、设备类型与权限声明
tests/                          本地回归测试脚本
hvigor/                         Hvigor 构建配置
README.md                       项目介绍与运行说明
CHANGELOG.md                    按日期整理的开发日志
```

接入业务能力时在 `IntegrationService.ets` 注册适配器：`agent` 负责模型，`knowledge/embedder` 负责检索数据，`forms/study/hardware` 负责各业务模块，`voice` 负责语音。

## 验证与测试

`devecocli build` 用于验证 ArkTS 编译和 HAP 打包。`tests/` 下的 Node 脚本加载真实服务源码，并模拟 HarmonyOS 原生接口边界；这些测试不替代设备上的权限、拾取器及语音识别验证。

以下是当前开发机的 PowerShell 示例，其他环境需修改 DevEco Studio 安装路径：

```powershell
$devEcoRoot = 'F:\DevEco Studio'
$nodeExe = Join-Path $devEcoRoot 'tools\node\node.exe'
$typescriptModule = Join-Path $devEcoRoot 'tools\ohpm\node_modules\typescript\lib\typescript.js'

& $nodeExe tests/gateway-stream.test.cjs $typescriptModule
& $nodeExe tests/markdown-presentation.test.cjs $typescriptModule
& $nodeExe tests/session-persistence.test.cjs $typescriptModule
& $nodeExe tests/attachments-voice.test.cjs $typescriptModule
```

| 脚本 | 覆盖范围 |
| --- | --- |
| `gateway-stream.test.cjs` | SSE 分片、回答解析、错误、取消及 JSON 回答兼容 |
| `markdown-presentation.test.cjs` | Markdown 解析、正文排版数据与思路摘要处理 |
| `session-persistence.test.cjs` | 历史保存、稳定排序、删除回滚、附件清理及备份恢复 |
| `attachments-voice.test.cjs` | 附件导入与提取、请求内容组织及语音适配器行为 |

模拟器已验证流式回答、Markdown 显示、上下文弹窗、历史切换、删除及重启保留，以及三点菜单和侧栏折叠。文件/图片选择器与麦克风授权入口已验证；实际语音转写质量及不同真机适配仍需设备测试。

## 开发记录

详见 [CHANGELOG.md](CHANGELOG.md)。日志使用北京时间（UTC+8），区分 Git 提交与本地开发验证记录；日志日期不代表该日改动已推送到远端。

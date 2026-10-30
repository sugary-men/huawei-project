# 2026-10-30 分支合并与硬件恢复

合并 main（2f5d854）与 codex/knowledge-base-library（1f5a274）。初次合并以知识库分支为基准，后续审查发现 BLE/NFC 是可用能力而非可删除冲突，现已通过协调适配器恢复。隐私档案独立初始化，继续可用。

string.json 是严格 JSON，不能写注释，旧权限文案记录在此。其余源代码的冲突旧片段在原位置以注释保留。文档的双方记录均保留。

## README.md

### main 原片段（停用或整合）

```
| 统一资料库 | 统一管理对话附件、导入文件/图片、粘贴文本、已选上下文及RAG资料；本地持久保存、分段检索、JSON向量索引导入、检索启停、预览和加入对话 |
| 自律魔方 | BLE 扫描/GATT 姿态通知、NFC 碰一碰、专注计时、姿态中断与应用内锁机兜底 |
| 隐私与档案 | Preferences + HUKS AES-GCM 加密学生档案，敏感字段脱敏，支持上传前授权状态 |
| 功能页面 | 包含智能助理、求职实验室、智能日程、消费洞察、表单填报、自律魔方、隐私与档案、健康计划、天气穿搭、学习助手 |

任务面板及日程、消费页面的任务和产物使用当前会话的真实本地状态。自律魔方已接入 BLE GATT 通知协议、NFC 标签和专注状态机；系统级锁机仍需 Screen Time Guard ACL 与真机授权。表单、学习课程等适配器未接入时会明确返回失败。参考硬件、固件和联调步骤见 [硬件、语音与隐私说明](docs/HARDWARE_VOICE_SECURITY.md)、[验收指南](docs/VERIFY_FOCUS_PRIVACY.md) 与 [ESP32-C3 参考硬件](hardware/esp32_focus_cube/README.md)。
```

### 知识库分支片段（采用）

```
| 统一资料库 | 以资料库为知识库前端，统一管理对话附件、导入文件/图片、粘贴文本、已选上下文及 RAG 资料；内置炫神知识库，本地持久保存、分段向量化、JSON 向量索引导入、检索启停、预览和加入对话 |
| 功能页面 | 包含智能助理、求职实验室、智能日程、消费洞察、表单填报、自律魔方、健康计划、天气穿搭、学习助手 |

任务面板及日程、消费页面的任务和产物使用当前会话的真实本地状态。表单、学习课程业务适配器默认返回“服务尚未接入”；课表同步、表单导出等需由对应模块继续实现。自律魔方已接入 Screen Time Guard，设备锁需要 ACL 权限与用户授权，失败时会明确提示。本地资料可提取正文并分段检索，也可导入已有向量的 JSON 索引；内置炫神资料与本地哈希向量用于离线演示，正式在线向量和联网兜底仍由数据侧接入。
```

## CHANGELOG.md

### main 原片段（停用或整合）

```
### 自律魔方、语音、隐私与工程增强

- 新增自律魔方专注状态机，覆盖 BLE 稳定姿态自动开始、陀螺仪姿态中断、NFC 触发、计时完成和应用内锁机兜底。
- 使用 Connectivity Kit 接入 BLE 扫描、GATT 连接和特征值通知，定义 `CampusCube` 的 Service/Notify UUID 与 CSV 姿态协议，并补充 ESP32-C3 + MPU6050 参考固件。
- 使用 NFC 标签拉起 Ability，通过 EventHub 自动切换到自律魔方并开始专注；无 NFC/蓝牙时保留明确降级。
- 明确 Screen Time Guard Kit 的 ACL 限制：未授权时不伪造系统锁机，保留应用内专注提示。
- 复用 Core Speech Kit 的中文 ASR/TTS，保留麦克风授权、停止、取消、超时和错误归一化。
- 新增“隐私与档案”工作区，使用 ArkData Preferences 保存密文、HUKS 托管 AES-256-GCM 密钥加密学生档案，学号和手机号默认脱敏。
- 增加上传前预览授权状态、撤销授权和本机档案清除入口，明确授权不等于自动上传敏感数据。
- 新增姿态协议与专注状态机回归测试、参考硬件 BOM/接线/烧录说明及 HarmonyOS/Android/iOS 打包前置条件文档。
- DevEco CLI 构建通过；姿态协议与专注状态机回归通过。BLE/NFC、系统锁机和 HUKS 仍需鸿蒙真机最终联调。
```

### 知识库分支片段（采用）

```
### 资料库前端基准迁移与知识库重写

- 基于远端新仓库 `LibraryPage` / `LibraryService` / `LibraryModels` 重写知识库前端：资料库统一管理本地文件、图片、粘贴文本、RAG JSON 与内置炫神知识库。
- `IntegrationService.initializeLibrary` 默认注入炫神（许昊龙）14 段资料；本地文本分段补 `local-hash-64` 向量，默认 `StudentQueryEmbedder` 参与关键词 + 余弦混合检索。
- 移除旧 `KnowledgeAdminPanel` 作为知识库前端，保留 `ONNX_INTEGRATION.md` 与 MiniLM 词表作为后续端侧模型接入资料。
- 迁移自律魔方番茄钟与 Screen Time Guard 设备专注锁：分钟时长、APP 白名单、暂停解除、继续按剩余时长重开，以及 Agent `focus_lock` 工具。
- DevEco 构建通过；新仓库 11 组回归（资料库、Agent、日程、交互、会话、侧栏、网关、附件、API、执行记录、消息时间）通过。
```

## entry/src/main/ets/pages/Index.ets

### main 原片段（停用或整合）

```
    IntegrationService.initializeDeviceServices(this.getUIContext().getHostContext() as common.UIAbilityContext)
    host.eventHub.on('focusNfcTap', this.nfcEvent)
    const pendingNfc = NfcFocusBridge.peek()
    if (pendingNfc.length > 0) this.nfcEvent(pendingNfc)
```

### 知识库分支片段（采用）

```
    IntegrationService.initializeFocus(host)
```

## entry/src/main/ets/pages/Index.ets

### main 原片段（停用或整合）

```
            else if (this.activeFeature === 'forms' || this.activeFeature === 'focus' || this.activeFeature === 'study' || this.activeFeature === 'privacy') { this.ModuleContent() }
```

### 知识库分支片段（采用）

```
            else if (this.activeFeature === 'focus') { this.FocusContent() }
            else if (this.activeFeature === 'forms' || this.activeFeature === 'study') { this.ModuleContent() }
```

## entry/src/main/ets/services/IntegrationService.ets

### main 原片段（停用或整合）

```
  static initializeDeviceServices(context: common.UIAbilityContext): void {
    if (IntegrationService.hardware instanceof UnavailableModule) IntegrationService.hardware = new HarmonyFocusModuleAdapter(context)
    if (IntegrationService.privacy instanceof UnavailableModule) IntegrationService.privacy = new PrivacyModuleAdapter(context)
  }
  static disposeDeviceServices(): void {
    if (IntegrationService.hardware instanceof HarmonyFocusModuleAdapter) IntegrationService.hardware.dispose()
```

### 知识库分支片段（采用）

```
  static initializeFocus(context: common.UIAbilityContext): void {
    IntegrationService.hardware = new FocusModuleAdapter(context)
```

## entry/src/main/module.json5

### main 原片段（停用或整合）

```
        "name": "ohos.permission.ACCESS_BLUETOOTH",
        "reason": "$string:bluetooth_reason",
        "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
      },
      {
        "name": "ohos.permission.NFC_TAG",
        "reason": "$string:nfc_reason",
```

### 知识库分支片段（采用）

```
        "name": "ohos.permission.MANAGE_SCREEN_TIME_GUARD",
        "reason": "$string:screen_time_guard_reason",
```

## entry/src/main/resources/base/element/string.json

### main 原片段（停用或整合）

```
      "name": "bluetooth_reason",
      "value": "用于发现并连接你的自律魔方"
    },
    {
      "name": "nfc_reason",
      "value": "用于读取自律魔方 NFC 标签并开始专注"
```

### 知识库分支片段（采用）

```
      "name": "screen_time_guard_reason",
      "value": "用于按你设置的时长和应用白名单开启设备专注锁"
```

## 硬件恢复结果

- 新增 `FocusIntegrationAdapter`，把 Screen Time Guard 与 `HarmonyFocusModuleAdapter` 组合到同一业务接口。
- 恢复 `ACCESS_BLUETOOTH`、`NFC_TAG` 权限及权限文案，恢复 `focusNfcTap` 订阅、冷启动待处理标签消费和页面销毁清理。
- 自律魔方页面重新提供扫描连接、NFC 碰一碰、硬件状态和姿态中断入口；Screen Time Guard 继续负责设备锁、白名单及授权状态。
- `focus_lock status` 改为独立的 `status` 动作，避免查询锁机状态时误触发蓝牙扫描。

## 验证

DevEco CLI 构建成功，CodeLinter 为 0 错误，15 个 Node 回归测试全部通过。构建未签名，本次未部署；系统专注锁、真实 BLE/NFC 硬件和隐私加密仍需相应真机验证。

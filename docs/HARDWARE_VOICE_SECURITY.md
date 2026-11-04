# 硬件、语音、隐私与工程交付说明

本文对应当前 `feature/focus-hardware-privacy` 分支，覆盖 M4、M6、M8/M9、M11/M12。原则是先复用 HarmonyOS 自带 Kit，不伪造未授权或未验证的系统能力。

## 1. 能力映射

| 模块 | 当前实现 | 使用的系统能力 |
| --- | --- | --- |
| M4 自律魔方 | BLE 扫描、GATT 连接与姿态通知、NFC 拉起、专注状态机、应用内锁机兜底 | Connectivity Kit `ble` / `tag` |
| M6 语音 | 中文 ASR、TTS、停止与取消、权限失败提示 | Core Speech Kit `speechRecognizer` / `textToSpeech` |
| M8 本地存储 | 会话 JSON 持久化、原子写入、备份恢复；学生档案加密持久化 | Core File Kit、ArkData Preferences |
| M9 隐私安全 | HUKS 托管 AES-256-GCM 密钥、密文存储、脱敏展示、上传授权状态 | Universal Keystore Kit HUKS、Crypto Architecture Kit |
| M11 工程增强 | 专注状态机单测、hilog 脱敏日志、错误降级 | hilog、Node 回归脚本 |
| M12 打包交付 | HarmonyOS HAP 构建/部署说明；跨端现状与前置条件 | DevEco Studio / devecocli |

## 2. M4 自律魔方

运行链路：

1. 进入“自律魔方”，点击“扫描 / 查询魔方”。
2. 应用请求 `ohos.permission.ACCESS_BLUETOOTH`，检查蓝牙开关。
3. 按 Service UUID `0000ffe0-...` 扫描并连接 `CampusCube`，订阅特征值 `0000ffe1-...`。
4. 固件以 10 Hz 发送 `pitch,roll,yaw`；稳定姿态自动开始 25 分钟专注，超过 28° 自动中断。
5. 输入框填写数字可改为 1～180 分钟，也可手动开始和结束。
6. NFC 标签通过 `ohos.nfc.tag.action.TAG_FOUND` 拉起应用；标签事件由 `NfcFocusBridge` 传递并由 `EventHub` 自动切到魔方页开始专注。
7. 无 BLE/NFC 硬件、模拟器或未授权时，专注计时仍可使用，界面明确显示降级状态。

需要的声明：

- `ohos.permission.ACCESS_BLUETOOTH`：用户授权。
- `ohos.permission.NFC_TAG`：NFC 标签读取。
- Ability 注册 `ohos.nfc.tag.action.TAG_FOUND` 与 `tag-tech/Ndef`。

参考硬件与固件：`hardware/esp32_focus_cube/`。ESP32-C3 负责 BLE 与 MPU6050 姿态计算，NFC 使用 NTAG215。

尚未完成的部分：

- 真实硬件烧录、BLE 回连稳定性和姿态阈值标定仍需真机验证。
- 系统级锁机应使用 Huawei Screen Time Guard Kit。该能力需要 `ohos.permission.MANAGE_SCREEN_TIME_GUARD` 受限 ACL、签名配置和用户授权。仓库不伪造系统锁机成功；未授权时使用应用内专注兜底。

## 3. M6 语音

`HarmonyVoiceAdapter` 已使用 Core Speech Kit：

- `speechRecognizer.createEngine()`：中文短语音识别。
- `textToSpeech.createEngine()`：回答朗读。
- 支持麦克风权限、开始/结束/取消、启动超时、识别超时、停止播报和错误归一化。
- 识别文字先写入输入框，由用户核对后发送，不自动提交。

真机验证要点：麦克风授权、中文识别质量、蓝牙耳机路由、来电/后台中断、TTS 音色可用性。

## 4. M8/M9 本地存储与隐私

### 会话存储

`SessionService` 将继续使用应用沙箱 JSON 和 `.bak` 恢复文件：

- `filesDir/chat_sessions.json`
- `filesDir/chat_sessions.json.bak`
- `filesDir/chat_attachments/`

该存储保证完整历史和删除回滚，但当前仍是普通沙箱文件，不等同于加密数据库。

### 学生档案

`SecureProfileService` 使用两层能力：

1. ArkData Preferences 保存密文信封和非敏感授权状态。
2. HUKS 生成不可导出的 AES-256 密钥，使用 AES-GCM 加密档案 JSON。
3. 密文信封包含版本、12 字节随机 nonce 和 ciphertext。
4. 界面读取后默认脱敏显示学号、手机号。

“隐私与档案”页面支持：

- 加密保存档案：输入 `姓名,学号,手机号`。
- 解密并查看档案。
- 允许/撤销上传前预览授权。
- 查看授权状态。
- 清除本机加密档案。

上传原则：授权不等于自动上传；任何敏感字段发送给外部模型前仍需展示范围并由用户确认。API Key、学号和联系方式不得提交到仓库。

## 5. M11 测试、日志与性能

已完成：

- `tests/focus-mode.test.cjs` 覆盖 CSV/JSON 姿态解析、稳定自动开始、NFC 触发、陀螺仪中断、计时完成和锁机状态。
- 新服务使用 hilog，仅记录阶段和错误消息，不记录档案正文、API Key 或原始标签 UID。
- BLE 扫描限制为 8 秒，成功或超时都立即调用 `stopBLEScan()`；断开时释放 GATT client。
- 档案只在打开页面时解密读取，不放入全局 AppStorage。

后续建议：

- 为真实 GATT 回连增加真机压力测试。
- 为 HUKS 档案往返增加设备测试；单测环境不模拟系统密钥库。
- 长会话继续使用分页/懒加载，避免一次渲染全部消息。

## 6. M12 构建与打包

HarmonyOS：

```powershell
devecocli build
devecocli device list
devecocli run --module entry
```

正式签名需要在 DevEco Studio 的 Project Structure > Signing Configs 配置证书，或使用：

```powershell
devecocli auth login
devecocli signature generate --product default
devecocli build
```

Android/iOS 现状：

- 当前仓库是原生 HarmonyOS ArkTS/ArkUI 工程，不是 ArkUI-X 跨端工程。
- 不能从当前 `entry` 直接产出 Android APK 或 iOS IPA。
- 若命题要求三端，需要另建 ArkUI-X 工程或将共享逻辑迁入 ArkUI-X，然后分别配置 Android Gradle 与 Xcode/Podfile。
- Android/iOS 的 BLE、NFC、语音和加密必须由对应平台适配器实现；当前接口边界可复用，系统 Kit 不可直接复用。

## 7. 验收清单

- [x] HarmonyOS 构建通过。
- [x] 专注状态机可回归测试。
- [x] NFC Ability 与权限已声明。
- [x] BLE 扫描有超时、权限和关闭降级。
- [x] 学生档案使用 HUKS AES-GCM 加密。
- [x] 敏感字段默认脱敏。
- [x] 上传授权有显式允许/撤销入口。
- [x] ESP32 参考固件与 GATT 通知协议已提供。
- [ ] 真实魔方硬件联调与阈值标定。
- [ ] Screen Time Guard ACL 签名与真机授权。
- [ ] Android APK / iOS IPA 跨端工程。

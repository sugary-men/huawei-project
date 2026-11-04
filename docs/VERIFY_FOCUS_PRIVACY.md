# 自律魔方与隐私模块验收指南

适用分支：`feature/focus-hardware-privacy`

## 1. 当前已验证结果

截至 2026-10-28：

- DevEco CLI `devecocli build`：通过。
- 全仓库回归：13 个测试文件全部通过。
- `Pura 90 Pro` 模拟器：安装、启动成功，无崩溃日志。
- “隐私与档案”：保存演示档案成功，重新解密读取成功。
- “自律魔方”：协议解析、稳定自动开始、姿态中断、NFC 触发和计时状态机单测通过。

尚未验证：

- 真实 BLE 魔方连接与回连。
- 真实 NFC 标签触发。
- Screen Time Guard ACL 系统锁机。
- 真实设备上的 ASR/TTS 质量。

## 2. 代码与构建验证

在 `D:\Huawei` 执行：

```powershell
git branch --show-current
git status --short
devecocli build
```

通过标准：

- 当前分支为 `feature/focus-hardware-privacy`。
- 输出包含 `BUILD SUCCESSFUL`。
- HAP 生成于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。

## 3. 自动化测试

```powershell
$node = 'D:\DevEco Studio\tools\node\node.exe'
$ts = 'D:\DevEco Studio\tools\ohpm\node_modules\typescript\lib\typescript.js'
Get-ChildItem tests -Filter '*.test.cjs' | ForEach-Object {
  & $node $_.FullName $ts
  if ($LASTEXITCODE -ne 0) { throw "失败：$($_.Name)" }
}
```

重点观察：

- `focus-mode.test.cjs` 输出 `PASS: BLE sample parsing...`。
- 最后应显示 13 个测试文件全部通过。

## 4. 模拟器验证

```powershell
devecocli emulator start "Pura 90 Pro"
devecocli device list
devecocli run --module entry --device "Pura 90 Pro"
```

通过标准：

- 输出包含 `App installed successfully`。
- 输出包含 `start ability successfully`。
- 应用界面可打开。

### 隐私与档案

1. 打开“隐私与档案”工作区。
2. 点击“保存演示档案”。
3. 预期显示“档案已使用 HUKS 密钥加密并保存到本机。”
4. 点击“解密并查看档案”。
5. 预期显示“已从本机解密并读取档案。”
6. 检查学号和手机号是否脱敏。
7. 点击“允许上传前预览”和“查看授权状态”，确认状态变为已允许。
8. 重启应用后再次读取档案，确认数据仍能解密。

### 自律魔方降级流程

1. 进入任意已创建的自律魔方会话，确保出现业务操作按钮。
2. 点击“开始专注”。
3. 预期显示“专注已开始，共 25 分钟...”。
4. 点击“模拟姿态中断”。
5. 预期显示“已模拟陀螺仪姿态变化，专注按预期中断。”
6. 点击“锁机联动状态”，确认系统锁机显示需要 Screen Time Guard ACL，而不是伪造成功。

## 5. 真机硬件验证

烧录 `hardware/esp32_focus_cube/esp32_focus_cube.ino`。

### BLE

1. 串口出现 `CampusCube advertising`。
2. 鸿蒙真机打开自律魔方，点击“扫描 / 查询魔方”。
3. 允许蓝牙权限。
4. 预期显示“已连接 CampusCube。摆正魔方后会自动开始专注。”
5. 保持 pitch/roll 小于 8°，预期自动进入专注。
6. 将魔方倾斜超过 28°，预期专注中断。

### NFC

1. 准备 NTAG213/215/216 标签。
2. 将标签靠近手机 NFC 区域。
3. 预期拉起 CampusPilot 并进入自律魔方，自动开始专注。
4. 冷启动和已运行状态都应验证。

## 6. 语音验证

1. 在鸿蒙真机点击输入框麦克风。
2. 允许麦克风权限。
3. 说一句中文，再点击结束。
4. 预期识别文本先进入输入框，不自动发送。
5. 对 Agent 回答点击朗读，预期使用系统 TTS 播放并可停止。

## 7. 日志验证

```powershell
devecocli log --device "Pura 90 Pro" --crash --bundle-name com.example.myapplication
devecocli log --device "Pura 90 Pro" --bundle-name com.example.myapplication --level E --from 5m --tail 100
```

通过标准：

- 无崩溃记录。
- 不应出现 `save encrypted profile failed`。
- 不应出现 `enable notifications failed`。

## 8. 系统锁机说明

系统级锁机必须在真机完成以下条件后才算验收通过：

1. 申请并获批 `ohos.permission.MANAGE_SCREEN_TIME_GUARD` 受限 ACL。
2. 使用包含 ACL 的正式签名。
3. 用户完成 Screen Time Guard 授权。
4. 创建并启动管控策略。

未满足这些条件时，应用只声明“应用内专注兜底”，不把系统锁机标记为成功。

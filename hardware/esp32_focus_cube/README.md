# ESP32-C3 自律魔方参考硬件

## BOM

- ESP32-C3 SuperMini 1 块
- MPU6050 六轴模块 1 个
- 3.7V 锂聚合物电池 1 块
- TP4056 充电板 1 块
- 电源开关 1 个
- NFC NTAG215 标签 1 枚
- 普通三阶魔方外壳或 3D 打印外壳
- USB-C 数据线和杜邦线

## 接线

| MPU6050 | ESP32-C3 |
| --- | --- |
| VCC | 3V3 |
| GND | GND |
| SDA | GPIO8 |
| SCL | GPIO9 |

不同开发板 I2C 默认引脚不同，必要时修改固件顶部的 `FOCUS_SDA` 和 `FOCUS_SCL`。

## BLE 协议

- 设备名：`CampusCube`
- Service UUID：`0000ffe0-0000-1000-8000-00805f9b34fb`
- Notify UUID：`0000ffe1-0000-1000-8000-00805f9b34fb`
- Notify 数据：`pitch,roll,yaw\n`，单位为度，建议 10 Hz
- 可选写命令：`PING`，设备返回 `PONG\n`

HarmonyOS 端在收到稳定姿态（pitch/roll 绝对值不超过 8°）后自动开始专注；超过 28° 时中断。阈值位于 `FocusModeManager.ets`，可在后续设置页开放调节。

## NFC

使用支持 NDEF 的 NTAG213/215/216 标签，写入任意文本或 URL 即可。HarmonyOS 应用已声明 `ohos.nfc.tag.action.TAG_FOUND` 和 `tag-tech/Ndef`，触碰标签后会拉起 CampusPilot 并触发专注。

## 烧录

1. Arduino IDE 安装 ESP32 Board Support。
2. 安装 `Adafruit MPU6050` 和 `Adafruit Unified Sensor`。
3. 选择 ESP32-C3 开发板并上传固件。
4. 串口确认出现 `CampusCube advertising`。
5. 在 HarmonyOS 真机打开“自律魔方”，点击“扫描 / 查询魔方”并授权蓝牙。

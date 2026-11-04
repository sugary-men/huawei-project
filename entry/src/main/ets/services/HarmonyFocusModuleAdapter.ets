import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { access, ble, constant } from '@kit.ConnectivityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'
import { ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'
import { FocusDevice, FocusSessionSnapshot } from '../models/FocusModels'
import { FocusModeManager } from './FocusModeManager'
import { FocusOrientationSample, FocusProtocol } from './FocusProtocol'
import { NfcFocusBridge } from './NfcFocusBridge'

export class HarmonyFocusModuleAdapter implements ModuleAdapter {
  private static readonly LOG_DOMAIN: number = 0xD004
  private static readonly LOG_TAG: string = 'FocusMode'
  private context: common.UIAbilityContext
  private manager: FocusModeManager = new FocusModeManager()
  private scanning: boolean = false
  private scanListenerReady: boolean = false
  private foundDeviceName: string = ''
  private foundDeviceId: string = ''
  private connected: boolean = false
  private client: ble.GattClientDevice | undefined = undefined
  private scanResolve: ((ok: boolean) => void) | undefined = undefined
  private lastSample: FocusOrientationSample | undefined = undefined

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  async execute(action: string, input: string): Promise<ModuleResult> {
    if (action === 'connect') return this.discover()
    if (action === 'start') return this.start(input)
    if (action === 'stop') return this.stop()
    if (action === 'nfc') return this.nfc()
    if (action === 'lock') return this.screenLockStatus()
    if (action === 'interrupt') return this.interrupt()
    return this.status()
  }

  snapshot(): FocusSessionSnapshot {
    return this.manager.refresh()
  }

  ingestGyroscope(pitch: number, roll: number): FocusSessionSnapshot {
    return this.manager.ingestOrientation(pitch, roll)
  }

  dispose(): void {
    if (this.client !== undefined) {
      try { this.client.disconnect(); this.client.close() } catch (_error) {}
      this.client = undefined
    }
    this.connected = false
  }

  private async discover(): Promise<ModuleResult> {
    if (this.scanning) return this.result(true, '正在搜索自律魔方，请靠近设备。', this.items())
    const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
      this.context, ['ohos.permission.ACCESS_BLUETOOTH'])
    if (permission.authResults[0] !== 0) {
      return this.result(false, '蓝牙权限未开启。请在系统设置中允许 CampusPilot 使用蓝牙。', [])
    }
    try {
      if (access.getState() !== access.BluetoothState.STATE_ON) {
        return this.result(false, '蓝牙未开启。请先在系统控制中心打开蓝牙，再重新搜索魔方。', [])
      }
    } catch (error) {
      this.logError('read bluetooth state failed', error)
      return this.result(false, '当前设备无法读取蓝牙状态。', [])
    }
    this.foundDeviceName = ''
    this.foundDeviceId = ''
    this.connected = false
    this.scanning = true
    this.subscribeScan()
    const discovery = new Promise<boolean>((resolve: (ok: boolean) => void): void => { this.scanResolve = resolve })
    try {
      const scanFilter: ble.ScanFilter = { serviceUuid: FocusProtocol.SERVICE_UUID }
      const options: ble.ScanOptions = {
        interval: 500,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_POWER,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      }
      ble.startBLEScan([scanFilter], options)
    } catch (error) {
      this.scanning = false
      this.scanResolve = undefined
      this.logError('start BLE scan failed', error)
      return this.result(false, 'BLE 扫描启动失败，请确认设备支持蓝牙并已开启权限。', [])
    }
    const timer = setTimeout((): void => {
      const resolve = this.scanResolve
      this.scanResolve = undefined
      if (resolve !== undefined) resolve(false)
    }, 8000)
    const found = await discovery
    clearTimeout(timer)
    try { ble.stopBLEScan() } catch (_error) {}
    this.scanning = false
    this.scanResolve = undefined
    if (!found || !this.connected) {
      return this.result(false,
        '未发现可连接的 CampusCube，或 GATT 连接未建立。可先使用应用内专注，并检查参考固件与 UUID。',
        [{ id: 'focus-fallback', title: '应用内专注可用', detail: '当前未连接硬件；NFC、手动计时和应用内锁机兜底仍可使用。' }])
    }
    const device: FocusDevice = { id: this.foundDeviceId, name: this.foundDeviceName, rssi: 0, source: 'ble' }
    this.manager.connect(device)
    return this.result(true, `已连接 ${this.foundDeviceName}。摆正魔方后会自动开始专注。`, this.items())
  }

  private async start(input: string): Promise<ModuleResult> {
    const nfcTag = NfcFocusBridge.consume()
    if (nfcTag.length > 0) return this.startByNfc(nfcTag)
    const minutes = this.parseMinutes(input)
    this.manager.start(minutes, 'manual')
    return this.result(true, `专注已开始，共 ${minutes} 分钟。应用保持专注页面；系统级锁机需完成 Screen Time Guard 授权。`,
      this.items())
  }

  private startByNfc(tagId: string): ModuleResult {
    this.manager.nfcTap(tagId)
    return this.result(true, 'NFC 碰一碰已触发，专注已开始。', this.items())
  }

  private stop(): ModuleResult {
    const snapshot = this.manager.stop('用户结束专注')
    return this.result(true, `本次专注已结束：${this.formatDuration(snapshot.startedAt)}。`, this.items())
  }

  private nfc(): ModuleResult {
    const tagId = NfcFocusBridge.consume()
    if (tagId.length === 0) {
      return this.result(false, '请将手机 NFC 区域触碰已写入专注标签的卡片。标签将拉起应用并自动开始专注。',
        [{ id: 'nfc-waiting', title: '等待 NFC 标签', detail: '需要亮屏、解锁并开启系统 NFC；模拟器不支持 NFC。' }])
    }
    return this.startByNfc(tagId)
  }

  private screenLockStatus(): ModuleResult {
    const snapshot = this.manager.refresh()
    const items: ModuleItem[] = [
      { id: 'lock-app', title: snapshot.screenLockLinked ? '应用内专注已启用' : '应用内专注未启用', detail: '专注期间保持当前页面并提供专注提示。' },
      { id: 'lock-system', title: '系统锁机联动', detail: '项目已按 Screen Time Guard Kit 设计；正式启用前需申请 MANAGE_SCREEN_TIME_GUARD ACL 并由用户授权。' }
    ]
    return this.result(true, snapshot.phase === 'focusing'
      ? '专注进行中，系统锁机使用应用内全屏兜底。'
      : '系统锁机不会伪造成功；请先开始专注并完成受限权限授权。', items)
  }

  private interrupt(): ModuleResult {
    const before = this.manager.refresh()
    if (before.phase !== 'focusing') return this.result(false, '当前没有进行中的专注。', [])
    this.manager.ingestOrientation(45, 20, 28, false)
    return this.result(true, '已模拟陀螺仪姿态变化，专注按预期中断。', this.items())
  }

  private status(): ModuleResult {
    return this.result(true, '已刷新自律魔方状态。', this.items())
  }

  private items(): ModuleItem[] {
    const snapshot = this.manager.refresh()
    const phaseLabel = snapshot.phase === 'focusing' ? '专注中'
      : snapshot.phase === 'ready' ? '设备就绪'
        : snapshot.phase === 'completed' ? '已完成'
          : snapshot.phase === 'interrupted' ? '已中断' : '待开始'
    const sampleText = this.lastSample === undefined ? '尚未收到姿态数据'
      : `pitch ${this.lastSample.pitch.toFixed(1)}° · roll ${this.lastSample.roll.toFixed(1)}°`
    const items: ModuleItem[] = [
      { id: 'focus-state', title: `状态：${phaseLabel}`, detail: snapshot.deviceName.length > 0
        ? `设备：${snapshot.deviceName}${this.connected ? ' · GATT 已连接' : ''}`
        : '设备：未连接（可使用应用内专注）' },
      { id: 'focus-time', title: `计划：${snapshot.durationMinutes} 分钟`, detail: snapshot.startedAt > 0
        ? `已进行：${this.formatDuration(snapshot.startedAt)}${snapshot.interruptionReason.length > 0 ? ` · ${snapshot.interruptionReason}` : ''}`
        : '摆正魔方或点击开始后计时。' },
      { id: 'focus-sample', title: '姿态数据', detail: sampleText },
      { id: 'focus-lock', title: snapshot.screenLockLinked ? '锁机联动：应用内专注' : '锁机联动：未启用',
        detail: '系统级应用限制使用 Huawei Screen Time Guard Kit，并遵守用户授权与 ACL 审核。' }
    ]
    return items
  }

  private subscribeScan(): void {
    if (this.scanListenerReady) return
    this.scanListenerReady = true
    try {
      ble.on('BLEDeviceFind', (results: Array<ble.ScanResult>): void => {
        for (const result of results) {
          const name = result.deviceName || FocusProtocol.DEVICE_NAME
          this.foundDeviceName = name
          this.foundDeviceId = result.deviceId
          try { ble.stopBLEScan() } catch (_error) {}
          const resolve = this.scanResolve
          this.scanResolve = undefined
          if (resolve !== undefined) {
            this.connectGatt(result.deviceId, name).then((ok: boolean): void => resolve(ok))
              .catch((_error: Error): void => resolve(false))
          }
          break
        }
      })
    } catch (error) {
      this.logError('subscribe BLE scan failed', error)
    }
  }

  private async connectGatt(deviceId: string, deviceName: string): Promise<boolean> {
    this.dispose()
    try {
      this.foundDeviceId = deviceId
      this.foundDeviceName = deviceName
      const client = ble.createGattClientDevice(deviceId)
      this.client = client
      const connected = new Promise<boolean>((resolve: (ok: boolean) => void): void => {
        let settled = false
        const finish = (ok: boolean): void => { if (!settled) { settled = true; resolve(ok) } }
        client.on('BLEConnectionStateChange', (state: ble.BLEConnectionChangeState): void => {
          if (state.state === constant.ProfileConnectionState.STATE_CONNECTED) {
            this.connected = true
            finish(true)
            this.enableNotifications(client).catch((error: Error): void => this.logError('enable notifications failed', error))
          } else if (state.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
            this.connected = false
            finish(false)
          }
        })
        client.on('BLECharacteristicChange', (value: ble.BLECharacteristic): void => {
          if (value.characteristicUuid.toLowerCase() !== FocusProtocol.NOTIFY_UUID) return
          const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(value.characteristicValue))
          const sample = FocusProtocol.parse(text)
          if (sample === undefined) return
          this.lastSample = sample
          this.manager.ingestOrientation(sample.pitch, sample.roll)
        })
        client.connect()
        setTimeout((): void => finish(false), 10000)
      })
      return await connected
    } catch (error) {
      this.logError('connect GATT failed', error)
      return false
    }
  }

  private async enableNotifications(client: ble.GattClientDevice): Promise<void> {
    const services = await client.getServices()
    for (const service of services) {
      if (service.serviceUuid.toLowerCase() !== FocusProtocol.SERVICE_UUID) continue
      for (const characteristic of service.characteristics) {
        if (characteristic.characteristicUuid.toLowerCase() !== FocusProtocol.NOTIFY_UUID) continue
        await client.setCharacteristicChangeNotification(characteristic, true)
        hilog.info(HarmonyFocusModuleAdapter.LOG_DOMAIN, HarmonyFocusModuleAdapter.LOG_TAG, 'focus notifications enabled')
        return
      }
    }
    throw new Error('CampusCube notify characteristic not found')
  }

  private parseMinutes(input: string): number {
    const matched = input.match(/\d{1,3}/)
    if (matched === null) return 25
    return Math.max(1, Math.min(180, Number(matched[0])))
  }

  private formatDuration(startedAt: number): string {
    if (startedAt <= 0) return '0 分 0 秒'
    const totalSeconds = Math.max(0, Math.floor((Date.now() - startedAt) / 1000))
    return `${Math.floor(totalSeconds / 60)} 分 ${totalSeconds % 60} 秒`
  }

  private result(ok: boolean, message: string, items: ModuleItem[]): ModuleResult {
    return { ok: ok, message: message, items: items }
  }

  private logError(message: string, error: BusinessError | Error): void {
    const business = error as BusinessError
    const detail = business.code === undefined ? error.message : `${business.code}: ${error.message}`
    hilog.error(HarmonyFocusModuleAdapter.LOG_DOMAIN, HarmonyFocusModuleAdapter.LOG_TAG, `${message}: ${detail}`)
  }
}


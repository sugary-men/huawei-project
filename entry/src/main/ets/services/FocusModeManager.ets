import { FocusDevice, FocusModeListener, FocusPhase, FocusSessionSnapshot } from '../models/FocusModels'

export class FocusModeManager {
  private static readonly DEFAULT_DURATION_MINUTES: number = 25
  private static readonly DEFAULT_TILT_THRESHOLD: number = 28
  private phase: FocusPhase = 'idle'
  private device: FocusDevice | undefined = undefined
  private startedAt: number = 0
  private expectedEndAt: number = 0
  private durationMinutes: number = FocusModeManager.DEFAULT_DURATION_MINUTES
  private interruptionReason: string = ''
  private lastTrigger: string = ''
  private screenLockLinked: boolean = false
  private tiltDegrees: number = 0
  private listener: FocusModeListener | undefined = undefined

  setListener(listener: FocusModeListener): void {
    this.listener = listener
    this.notify()
  }

  connect(device: FocusDevice): FocusSessionSnapshot {
    this.device = device
    if (this.phase !== 'focusing') this.phase = 'ready'
    this.notify()
    return this.snapshot()
  }

  disconnect(): FocusSessionSnapshot {
    if (this.phase === 'focusing') this.stop('设备连接已断开')
    this.device = undefined
    if (this.phase !== 'interrupted') this.phase = 'idle'
    this.notify()
    return this.snapshot()
  }

  start(durationMinutes: number = FocusModeManager.DEFAULT_DURATION_MINUTES, trigger: string = 'manual'): FocusSessionSnapshot {
    const minutes = Math.max(1, Math.min(180, Math.floor(durationMinutes)))
    this.phase = 'focusing'
    this.startedAt = Date.now()
    this.expectedEndAt = this.startedAt + minutes * 60 * 1000
    this.durationMinutes = minutes
    this.interruptionReason = ''
    this.lastTrigger = trigger
    this.screenLockLinked = true
    this.tiltDegrees = 0
    this.notify()
    return this.snapshot()
  }

  stop(reason: string = '用户结束专注'): FocusSessionSnapshot {
    if (this.phase === 'focusing') {
      this.phase = reason === '专注完成' ? 'completed' : 'interrupted'
      this.interruptionReason = reason
      this.screenLockLinked = false
    }
    this.notify()
    return this.snapshot()
  }

  ingestOrientation(pitch: number, roll: number, thresholdDegrees: number = FocusModeManager.DEFAULT_TILT_THRESHOLD, autoStart: boolean = true): FocusSessionSnapshot {
    this.tiltDegrees = Math.max(Math.abs(pitch), Math.abs(roll))
    if (autoStart && this.phase === 'ready' && this.tiltDegrees <= 8) {
      return this.start(this.durationMinutes, 'ble-steady')
    }
    if (this.phase === 'focusing' && this.tiltDegrees >= thresholdDegrees) {
      this.phase = 'interrupted'
      this.interruptionReason = '检测到魔方姿态变化，专注已中断'
      this.screenLockLinked = false
      this.notify()
    }
    return this.snapshot()
  }

  nfcTap(tagId: string): FocusSessionSnapshot {
    const device: FocusDevice = { id: tagId || 'nfc-focus-tag', name: 'NFC 专注标签', rssi: 0, source: 'nfc' }
    this.connect(device)
    return this.start(this.durationMinutes, 'nfc')
  }

  refresh(): FocusSessionSnapshot {
    if (this.phase === 'focusing' && Date.now() >= this.expectedEndAt) {
      this.phase = 'completed'
      this.interruptionReason = '专注完成'
      this.screenLockLinked = false
      this.notify()
    }
    return this.snapshot()
  }

  snapshot(): FocusSessionSnapshot {
    return {
      phase: this.phase,
      deviceName: this.device?.name || '',
      deviceId: this.device?.id || '',
      startedAt: this.startedAt,
      expectedEndAt: this.expectedEndAt,
      durationMinutes: this.durationMinutes,
      interruptionReason: this.interruptionReason,
      lastTrigger: this.lastTrigger,
      screenLockLinked: this.screenLockLinked,
      tiltDegrees: this.tiltDegrees
    }
  }

  private notify(): void {
    this.listener?.onChanged(this.snapshot())
  }
}


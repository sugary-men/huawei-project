export type FocusPhase = 'idle' | 'ready' | 'focusing' | 'completed' | 'interrupted'

export interface FocusDevice {
  id: string
  name: string
  rssi: number
  source: string
}

export interface FocusSessionSnapshot {
  phase: FocusPhase
  deviceName: string
  deviceId: string
  startedAt: number
  expectedEndAt: number
  durationMinutes: number
  interruptionReason: string
  lastTrigger: string
  screenLockLinked: boolean
  tiltDegrees: number
}

export interface FocusModeListener {
  onChanged(snapshot: FocusSessionSnapshot): void
}

export interface FocusModuleItem {
  id: string
  title: string
  detail: string
}

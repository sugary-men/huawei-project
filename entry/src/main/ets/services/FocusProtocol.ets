export interface FocusOrientationSample {
  pitch: number
  roll: number
  yaw: number
  receivedAt: number
}

export class FocusProtocol {
  static readonly SERVICE_UUID: string = '0000ffe0-0000-1000-8000-00805f9b34fb'
  static readonly NOTIFY_UUID: string = '0000ffe1-0000-1000-8000-00805f9b34fb'
  static readonly DEVICE_NAME: string = 'CampusCube'
  static readonly STABLE_TILT_DEGREES: number = 8

  static parse(text: string): FocusOrientationSample | undefined {
    const value = text.trim()
    if (value.length === 0) return undefined
    try {
      if (value.startsWith('{')) {
        const payload = JSON.parse(value) as Record<string, number>
        return FocusProtocol.make(Number(payload.pitch), Number(payload.roll), Number(payload.yaw || 0))
      }
      const parts = value.split(',')
      if (parts.length < 2) return undefined
      return FocusProtocol.make(Number(parts[0]), Number(parts[1]), parts.length > 2 ? Number(parts[2]) : 0)
    } catch (_error) {
      return undefined
    }
  }

  static isStable(sample: FocusOrientationSample): boolean {
    return Math.max(Math.abs(sample.pitch), Math.abs(sample.roll)) <= FocusProtocol.STABLE_TILT_DEGREES
  }

  private static make(pitch: number, roll: number, yaw: number): FocusOrientationSample | undefined {
    if (!Number.isFinite(pitch) || !Number.isFinite(roll) || !Number.isFinite(yaw)) return undefined
    return { pitch: pitch, roll: roll, yaw: yaw, receivedAt: Date.now() }
  }
}

import { tag } from '@kit.ConnectivityKit'
import { Want } from '@kit.AbilityKit'

export class NfcFocusBridge {
  private static pendingAt: number = 0
  private static pendingTagId: string = ''

  static handleWant(want: Want): string {
    try {
      const info = tag.getTagInfo(want)
      if (info === undefined || info.uid === undefined || info.uid.length === 0) return ''
      NfcFocusBridge.pendingTagId = Array.from(info.uid)
        .map((value: number): string => value.toString(16).padStart(2, '0')).join(':')
      NfcFocusBridge.pendingAt = Date.now()
      return NfcFocusBridge.pendingTagId
    } catch (_error) {
      return ''
    }
  }

  static consume(maxAgeMs: number = 120000): string {
    if (NfcFocusBridge.pendingAt === 0 || Date.now() - NfcFocusBridge.pendingAt > maxAgeMs) return ''
    const id = NfcFocusBridge.pendingTagId
    NfcFocusBridge.pendingAt = 0
    NfcFocusBridge.pendingTagId = ''
    return id
  }

  static peek(): string {
    return NfcFocusBridge.pendingAt === 0 ? '' : NfcFocusBridge.pendingTagId
  }
}

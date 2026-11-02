import { common } from '@kit.AbilityKit'
import { ModuleItem } from '../models/IntegrationModels'
import { IntegrationService } from './IntegrationService'
import { FocusGuardService } from './FocusGuardService'

interface FocusTimerInput {
  durationMinutes?: number
}

export class FocusWorkspaceController {
  static readonly workMinutesKey: string = 'focusWorkMinutes'
  static readonly breakMinutesKey: string = 'focusBreakMinutes'
  static readonly remainingSecondsKey: string = 'focusRemainingSeconds'
  static readonly runningKey: string = 'focusRunning'
  static readonly phaseKey: string = 'focusPhase'
  static readonly completedKey: string = 'focusCompleted'
  static readonly whitelistKey: string = 'focusWhitelistTokens'
  static readonly guardNoticeKey: string = 'focusGuardNotice'
  static readonly guardActiveKey: string = 'focusGuardActive'
  static readonly guardEnabledKey: string = 'focusGuardEnabled'
  static readonly guardBusyKey: string = 'focusGuardBusy'
  static readonly hardwareBusyKey: string = 'focusHardwareBusy'
  static readonly moduleNoticeKey: string = 'focusModuleNotice'
  static readonly moduleItemsKey: string = 'focusModuleItems'
  private static initialized: boolean = false
  private static timerId: number = -1
  private static endAt: number = 0

  static initialize(): void {
    if (FocusWorkspaceController.initialized) return
    FocusWorkspaceController.initialized = true
    if (AppStorage.get<number>(FocusWorkspaceController.workMinutesKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.workMinutesKey, 25)
    }
    if (AppStorage.get<number>(FocusWorkspaceController.breakMinutesKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.breakMinutesKey, 5)
    }
    if (AppStorage.get<number>(FocusWorkspaceController.remainingSecondsKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.remainingSecondsKey, 25 * 60)
    }
    if (AppStorage.get<boolean>(FocusWorkspaceController.runningKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.runningKey, false)
    }
    if (AppStorage.get<string>(FocusWorkspaceController.phaseKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.phaseKey, 'focus')
    }
    if (AppStorage.get<number>(FocusWorkspaceController.completedKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.completedKey, 0)
    }
    if (AppStorage.get<string[]>(FocusWorkspaceController.whitelistKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.whitelistKey, [] as string[])
    }
    if (AppStorage.get<string>(FocusWorkspaceController.guardNoticeKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.guardNoticeKey, '')
    }
    if (AppStorage.get<boolean>(FocusWorkspaceController.guardActiveKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.guardActiveKey, false)
    }
    if (AppStorage.get<boolean>(FocusWorkspaceController.guardEnabledKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.guardEnabledKey, true)
    }
    if (AppStorage.get<boolean>(FocusWorkspaceController.guardBusyKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.guardBusyKey, false)
    }
    if (AppStorage.get<boolean>(FocusWorkspaceController.hardwareBusyKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.hardwareBusyKey, false)
    }
    if (AppStorage.get<string>(FocusWorkspaceController.moduleNoticeKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.moduleNoticeKey, '')
    }
    if (AppStorage.get<ModuleItem[]>(FocusWorkspaceController.moduleItemsKey) === undefined) {
      AppStorage.setOrCreate(FocusWorkspaceController.moduleItemsKey, [] as ModuleItem[])
    }
  }

  private static workMinutes(): number {
    return AppStorage.get<number>(FocusWorkspaceController.workMinutesKey) || 25
  }
  private static breakMinutes(): number {
    return AppStorage.get<number>(FocusWorkspaceController.breakMinutesKey) || 5
  }
  private static remainingSeconds(): number {
    return AppStorage.get<number>(FocusWorkspaceController.remainingSecondsKey) || 0
  }
  private static running(): boolean {
    return AppStorage.get<boolean>(FocusWorkspaceController.runningKey) === true
  }
  private static phase(): string {
    return AppStorage.get<string>(FocusWorkspaceController.phaseKey) || 'focus'
  }
  private static guardActive(): boolean {
    return AppStorage.get<boolean>(FocusWorkspaceController.guardActiveKey) === true
  }
  private static guardEnabled(): boolean {
    return AppStorage.get<boolean>(FocusWorkspaceController.guardEnabledKey) !== false
  }

  private static set(key: string, value: number | string | boolean | string[] | ModuleItem[]): void {
    AppStorage.setOrCreate(key, value)
  }

  static progress(): number {
    const total = (FocusWorkspaceController.phase() === 'focus'
      ? FocusWorkspaceController.workMinutes() : FocusWorkspaceController.breakMinutes()) * 60
    if (total <= 0) return 0
    return Math.max(0, Math.min(100,
      ((total - FocusWorkspaceController.remainingSeconds()) / total) * 100))
  }

  static formatTime(seconds: number): string {
    const safe = Math.max(0, Math.floor(seconds))
    const minutes = Math.floor(safe / 60)
    const rest = safe % 60
    return `${minutes < 10 ? `0${minutes}` : `${minutes}`}:${rest < 10 ? `0${rest}` : `${rest}`}`
  }

  static adjustWorkMinutes(delta: number): void {
    if (FocusWorkspaceController.running()) return
    const minutes = Math.max(5, Math.min(120, FocusWorkspaceController.workMinutes() + delta))
    FocusWorkspaceController.set(FocusWorkspaceController.workMinutesKey, minutes)
    if (FocusWorkspaceController.phase() === 'focus') {
      FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey, minutes * 60)
    }
  }

  static setGuardEnabled(enabled: boolean): void {
    FocusWorkspaceController.set(FocusWorkspaceController.guardEnabledKey, enabled)
  }

  static setNotice(message: string): void {
    FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey, message)
  }

  private static startTimer(): void {
    if (FocusWorkspaceController.running()) return
    let remaining = FocusWorkspaceController.remainingSeconds()
    if (remaining <= 0) {
      remaining = (FocusWorkspaceController.phase() === 'focus'
        ? FocusWorkspaceController.workMinutes() : FocusWorkspaceController.breakMinutes()) * 60
      FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey, remaining)
    }
    FocusWorkspaceController.set(FocusWorkspaceController.runningKey, true)
    FocusWorkspaceController.endAt = Date.now() + remaining * 1000
    FocusWorkspaceController.timerId = setInterval((): void => FocusWorkspaceController.tick(), 1000)
  }

  private static tick(): void {
    const remaining = Math.max(0, Math.ceil((FocusWorkspaceController.endAt - Date.now()) / 1000))
    FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey, remaining)
    if (remaining > 0) return
    FocusWorkspaceController.stopTimer()
    FocusWorkspaceController.finishPhase()
  }

  private static stopTimer(): void {
    if (FocusWorkspaceController.timerId >= 0) {
      clearInterval(FocusWorkspaceController.timerId)
      FocusWorkspaceController.timerId = -1
    }
    FocusWorkspaceController.set(FocusWorkspaceController.runningKey, false)
  }

  private static pauseTimer(): void {
    if (!FocusWorkspaceController.running()) return
    FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey,
      Math.max(0, Math.ceil((FocusWorkspaceController.endAt - Date.now()) / 1000)))
    FocusWorkspaceController.stopTimer()
  }

  static reset(): void {
    FocusWorkspaceController.stopTimer()
    FocusWorkspaceController.set(FocusWorkspaceController.phaseKey, 'focus')
    FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey,
      FocusWorkspaceController.workMinutes() * 60)
  }

  private static finishPhase(): void {
    if (FocusWorkspaceController.phase() === 'focus') {
      const completed = (AppStorage.get<number>(FocusWorkspaceController.completedKey) || 0) + 1
      FocusWorkspaceController.set(FocusWorkspaceController.completedKey, completed)
      FocusWorkspaceController.set(FocusWorkspaceController.phaseKey, 'break')
      FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey,
        FocusWorkspaceController.breakMinutes() * 60)
      FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, false)
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        '专注完成，设备锁已到期；休息一下吧。')
      FocusGuardService.stopLock().catch(() => {})
    } else {
      FocusWorkspaceController.set(FocusWorkspaceController.phaseKey, 'focus')
      FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey,
        FocusWorkspaceController.workMinutes() * 60)
    }
  }

  static async toggleSession(context: common.UIAbilityContext): Promise<void> {
    if (FocusWorkspaceController.running()) {
      await FocusWorkspaceController.pauseSession()
      return
    }
    if (FocusWorkspaceController.phase() !== 'focus') {
      FocusWorkspaceController.set(FocusWorkspaceController.phaseKey, 'focus')
      FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey,
        FocusWorkspaceController.workMinutes() * 60)
    }
    FocusWorkspaceController.startTimer()
    if (!FocusWorkspaceController.guardEnabled() || FocusWorkspaceController.guardActive()) return
    FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, true)
    try {
      const remainingMinutes = Math.max(1,
        Math.ceil(FocusWorkspaceController.remainingSeconds() / 60))
      const message = await FocusGuardService.startLock(context, remainingMinutes, true)
      FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, true)
      FocusWorkspaceController.set(FocusWorkspaceController.whitelistKey,
        FocusGuardService.whitelistTokens())
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey, message)
    } catch (error) {
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        `番茄钟已开始，设备锁未开启：${FocusGuardService.friendlyError(error as Error)}`)
    } finally {
      FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, false)
    }
  }

  private static async pauseSession(): Promise<void> {
    FocusWorkspaceController.pauseTimer()
    if (!FocusWorkspaceController.guardActive()) return
    try { await FocusGuardService.stopLock() } catch (_error) {}
    FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, false)
    FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
      '番茄钟已暂停，设备锁已解除；继续时会按剩余时长重新开启。')
  }

  static async enableGuard(context: common.UIAbilityContext): Promise<void> {
    FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, true)
    try {
      const remainingMinutes = Math.max(1,
        Math.ceil(FocusWorkspaceController.remainingSeconds() / 60))
      const message = await FocusGuardService.startLock(context, remainingMinutes, true)
      FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, true)
      FocusWorkspaceController.set(FocusWorkspaceController.whitelistKey,
        FocusGuardService.whitelistTokens())
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey, message)
    } catch (error) {
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        FocusGuardService.friendlyError(error as Error))
    } finally {
      FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, false)
    }
  }

  static async disableGuard(): Promise<void> {
    FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, true)
    try {
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        await FocusGuardService.stopLock())
      FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, false)
    } catch (error) {
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        FocusGuardService.friendlyError(error as Error))
    } finally {
      FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, false)
    }
  }

  static async pickWhitelist(context: common.UIAbilityContext): Promise<void> {
    FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, true)
    try {
      const tokens = await FocusGuardService.pickWhitelist(context)
      FocusWorkspaceController.set(FocusWorkspaceController.whitelistKey, tokens)
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        `已选择 ${tokens.length} 个白名单应用。`)
    } catch (error) {
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        FocusGuardService.friendlyError(error as Error))
    } finally {
      FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, false)
    }
  }

  static async queryGuard(): Promise<void> {
    FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, true)
    try {
      const state = await FocusGuardService.snapshot()
      FocusWorkspaceController.set(FocusWorkspaceController.whitelistKey,
        FocusGuardService.whitelistTokens())
      FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey,
        state.activeStrategy.length > 0)
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        `授权：${state.authorized ? '已授权' : '未授权'}；策略：${state.strategies.length} 个；白名单：${state.whitelistCount} 个应用。`)
    } catch (error) {
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey,
        FocusGuardService.friendlyError(error as Error))
    } finally {
      FocusWorkspaceController.set(FocusWorkspaceController.guardBusyKey, false)
    }
  }

  static async hardwareAction(action: string, context: common.UIAbilityContext): Promise<void> {
    if (AppStorage.get<boolean>(FocusWorkspaceController.hardwareBusyKey) === true) return
    FocusWorkspaceController.set(FocusWorkspaceController.hardwareBusyKey, true)
    FocusWorkspaceController.set(FocusWorkspaceController.moduleNoticeKey, '正在处理…')
    try {
      const result = await IntegrationService.hardware.execute(action, '')
      FocusWorkspaceController.set(FocusWorkspaceController.moduleNoticeKey, result.message)
      FocusWorkspaceController.set(FocusWorkspaceController.moduleItemsKey,
        result.ok ? result.items : [] as ModuleItem[])
      if (result.ok && action === 'nfc') {
        FocusWorkspaceController.startToolSession('25')
        FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, true)
      } else if (result.ok && action === 'interrupt') {
        FocusWorkspaceController.stopTimer()
        FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, false)
      }
      FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey, result.message)
    } catch (error) {
      FocusWorkspaceController.set(FocusWorkspaceController.moduleNoticeKey,
        (error as Error).message || '硬件操作失败。')
      FocusWorkspaceController.set(FocusWorkspaceController.moduleItemsKey, [] as ModuleItem[])
    } finally {
      FocusWorkspaceController.set(FocusWorkspaceController.hardwareBusyKey, false)
    }
  }

  static startToolSession(input: string): void {
    let minutes = FocusWorkspaceController.workMinutes()
    try {
      const parsed = JSON.parse(input || '{}') as FocusTimerInput
      if (typeof parsed.durationMinutes === 'number' && Number.isFinite(parsed.durationMinutes)) {
        minutes = Math.max(1, Math.min(1440, Math.round(parsed.durationMinutes)))
      }
    } catch (_error) {}
    FocusWorkspaceController.stopTimer()
    FocusWorkspaceController.set(FocusWorkspaceController.workMinutesKey, minutes)
    FocusWorkspaceController.set(FocusWorkspaceController.phaseKey, 'focus')
    FocusWorkspaceController.set(FocusWorkspaceController.remainingSecondsKey, minutes * 60)
    FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, true)
    FocusWorkspaceController.set(FocusWorkspaceController.whitelistKey,
      FocusGuardService.whitelistTokens())
    FocusWorkspaceController.startTimer()
  }

  static stopToolSession(message: string): void {
    FocusWorkspaceController.stopTimer()
    FocusWorkspaceController.set(FocusWorkspaceController.guardActiveKey, false)
    FocusWorkspaceController.set(FocusWorkspaceController.guardNoticeKey, message)
  }

  static dispose(): void {
    FocusWorkspaceController.stopTimer()
  }
}

import { appPicker, guardService } from '@kit.ScreenTimeGuardKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'

export interface FocusGuardSnapshot {
  authorized: boolean
  strategies: string[]
  whitelistCount: number
  activeStrategy: string
}

interface FocusActionInput {
  durationMinutes?: number
  useWhitelist?: boolean
}

// 基于 Screen Time Guard Kit 的设备专注锁：对接系统“健康使用设备”的管控能力。
// 时长策略从 startGuardStrategy 成功后开始计时；TRUSTLIST 表示白名单内应用可用，
// 名单外应用在时长内被限制访问。
export class FocusGuardService {
  private static selectedTokens: string[] = []
  private static activeStrategy: string = ''

  static whitelistTokens(): string[] {
    return FocusGuardService.selectedTokens.slice()
  }

  static active(): string {
    return FocusGuardService.activeStrategy
  }

  static async authorized(): Promise<boolean> {
    try {
      return await guardService.getUserAuthStatus() === guardService.AuthStatus.AUTH_GRANTED
    } catch (_error) {
      return false
    }
  }

  static async ensureAuthorized(context: common.UIAbilityContext): Promise<void> {
    const status = await guardService.getUserAuthStatus()
    if (status === guardService.AuthStatus.AUTH_GRANTED) return
    await guardService.requestUserAuth(context)
    const next = await guardService.getUserAuthStatus()
    if (next !== guardService.AuthStatus.AUTH_GRANTED) throw new Error('用户未授权设备专注锁。')
  }

  static async pickWhitelist(context: common.UIAbilityContext): Promise<string[]> {
    // 系统应用选择器返回去标识化 token，不把应用包名暴露给业务层。
    const tokens = await appPicker.startAppPicker(context, { appTokens: FocusGuardService.selectedTokens })
    FocusGuardService.selectedTokens = tokens.slice()
    return FocusGuardService.whitelistTokens()
  }

  static async startLock(context: common.UIAbilityContext, durationMinutes: number, useWhitelist: boolean = true): Promise<string> {
    await FocusGuardService.ensureAuthorized(context)
    let tokens = FocusGuardService.selectedTokens
    if (useWhitelist && tokens.length === 0) tokens = await FocusGuardService.pickWhitelist(context)
    if (FocusGuardService.activeStrategy.length > 0) await FocusGuardService.stopLock()

    const minutes = Math.max(1, Math.min(1440, Math.round(durationMinutes)))
    const strategyName = `focus_${Date.now()}`
    const time: guardService.TimeStrategy = {
      type: guardService.TimeStrategyType.TOTAL_DURATION_TYPE,
      totalDuration: minutes
    }
    const info: guardService.AppInfo = { appTokens: tokens }
    const strategy: guardService.GuardStrategy = {
      name: strategyName,
      timeStrategy: time,
      appInfo: info,
      appRestrictionType: guardService.RestrictionType.TRUSTLIST_TYPE
    }
    await guardService.addGuardStrategy(strategy)
    await guardService.startGuardStrategy(strategyName)
    FocusGuardService.activeStrategy = strategyName
    return `已开启 ${minutes} 分钟设备专注锁，白名单 ${tokens.length} 个应用。`
  }

  static async stopLock(): Promise<string> {
    let names: string[] = []
    if (FocusGuardService.activeStrategy.length > 0) {
      names = [FocusGuardService.activeStrategy]
    } else {
      try {
        const list = await guardService.queryGuardStrategies()
        names = list.map((item: guardService.GuardStrategy): string => item.name)
          .filter((name: string): boolean => name.startsWith('focus_'))
      } catch (_error) {}
    }
    if (names.length === 0) return '当前没有由本应用启动的设备专注锁。'
    for (let i = 0; i < names.length; i++) {
      try {
        await guardService.stopGuardStrategy(names[i])
      } catch (_error) {}
      try {
        await guardService.removeGuardStrategy(names[i])
      } catch (_error) {}
    }
    FocusGuardService.activeStrategy = ''
    return `已解除 ${names.length} 个设备专注锁。`
  }

  static async snapshot(): Promise<FocusGuardSnapshot> {
    let authorized = false
    let strategies: string[] = []
    try {
      authorized = await guardService.getUserAuthStatus() === guardService.AuthStatus.AUTH_GRANTED
      const list = await guardService.queryGuardStrategies()
      strategies = list.map((item: guardService.GuardStrategy): string => item.name)
    } catch (_error) {}
    return { authorized: authorized, strategies: strategies,
      whitelistCount: FocusGuardService.selectedTokens.length, activeStrategy: FocusGuardService.activeStrategy }
  }

  static friendlyError(error: Error): string {
    const business = error as BusinessError
    if (business.code === 201) return '缺少屏幕时间守护权限，请在签名配置中申请 ACL 权限。'
    if (business.code === 801) return '当前设备或系统版本不支持屏幕时间守护。'
    if (business.code === 1019000002) return '尚未获得用户授权，请先在弹窗中允许设备专注锁。'
    if (business.code === 1019000003) return '用户取消了设备专注锁授权。'
    if (business.code === 1019000007) return '该专注锁已在运行。'
    if (business.code === 1019000008) return '该专注锁尚未启动。'
    if (business.code === 1019000009) return '专注锁参数无效，请检查时长和白名单。'
    return business.message || '设备专注锁操作失败。'
  }
}

// 让 Agent 的 run_workspace_action / focus_lock 与自律魔方页面共用同一套设备能力。
export class FocusModuleAdapter implements ModuleAdapter {
  private context: common.UIAbilityContext

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  async execute(action: string, input: string): Promise<ModuleResult> {
    try {
      if (action === 'connect') {
        const state = await FocusGuardService.snapshot()
        const items: ModuleItem[] = [
          { id: 'focus-auth', title: '用户授权', detail: state.authorized ? '已授权设备专注锁' : '未授权，开始专注时会拉起授权页面' },
          { id: 'focus-strategies', title: '已有策略', detail: state.strategies.length === 0 ? '暂无' : state.strategies.join('、') },
          { id: 'focus-whitelist', title: '白名单', detail: `${state.whitelistCount} 个应用` }
        ]
        return { ok: true, message: '设备专注锁状态已查询。', items: items }
      }
      if (action === 'start') {
        const parsed = FocusModuleAdapter.parseInput(input)
        const minutes = parsed.durationMinutes === undefined ? 25 : parsed.durationMinutes
        const message = await FocusGuardService.startLock(this.context, minutes, parsed.useWhitelist !== false)
        return { ok: true, message: message, items: [{ id: 'focus-lock', title: '设备专注锁', detail: message }] }
      }
      if (action === 'stop') {
        const message = await FocusGuardService.stopLock()
        return { ok: true, message: message, items: [] }
      }
      return { ok: false, message: '自律魔方不支持该操作。', items: [] }
    } catch (error) {
      return { ok: false, message: FocusGuardService.friendlyError(error as Error), items: [] }
    }
  }

  private static parseInput(input: string): FocusActionInput {
    const result: FocusActionInput = { durationMinutes: 25, useWhitelist: true }
    const text = input.trim()
    if (text.length === 0) return result
    try {
      const parsed = JSON.parse(text) as FocusActionInput
      if (typeof parsed.durationMinutes === 'number' && Number.isFinite(parsed.durationMinutes)) {
        result.durationMinutes = Math.max(1, Math.min(1440, Math.round(parsed.durationMinutes)))
      }
      if (typeof parsed.useWhitelist === 'boolean') result.useWhitelist = parsed.useWhitelist
      return result
    } catch (_error) {}
    const match = text.match(/\d+/)
    if (match !== null) result.durationMinutes = Math.max(1, Math.min(1440, parseInt(match[0])))
    return result
  }
}

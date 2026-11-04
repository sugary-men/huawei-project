import { common } from '@kit.AbilityKit'
import { ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'
import { FocusModuleAdapter } from './FocusGuardService'
import { HarmonyFocusModuleAdapter } from './HarmonyFocusModuleAdapter'

// 保留主分支的设备专注锁，同时恢复 BLE/NFC 魔方链路。
export class FocusIntegrationAdapter implements ModuleAdapter {
  private guard: FocusModuleAdapter
  private hardware: HarmonyFocusModuleAdapter

  constructor(context: common.UIAbilityContext) {
    this.guard = new FocusModuleAdapter(context)
    this.hardware = new HarmonyFocusModuleAdapter(context)
  }

  async execute(action: string, input: string): Promise<ModuleResult> {
    if (action === 'start') return this.guard.execute('start', input)
    if (action === 'stop') {
      const guard = await this.guard.execute('stop', input)
      const hardware = await this.hardware.execute('stop', input)
      return FocusIntegrationAdapter.combine(guard, hardware, guard.ok || hardware.ok)
    }
    if (action === 'status' || action === 'lock') return this.guard.execute('connect', input)
    if (action === 'connect' || action === 'nfc' || action === 'interrupt' || action === 'hardware-status') {
      try {
        return await this.hardware.execute(action === 'hardware-status' ? 'status' : action, input)
      } catch (error) {
        return {
          ok: false,
          message: `自律魔方硬件操作失败：${(error as Error).message || '未知错误'}`,
          items: []
        }
      }
    }
    return { ok: false, message: '自律魔方不支持该操作。', items: [] }
  }

  dispose(): void {
    this.hardware.dispose()
  }

  private static combine(first: ModuleResult, second: ModuleResult, ok: boolean): ModuleResult {
    return {
      ok: ok,
      message: `${first.message}\n${second.message}`,
      items: FocusIntegrationAdapter.prefixItems('guard', first.items)
        .concat(FocusIntegrationAdapter.prefixItems('hardware', second.items))
    }
  }

  private static prefixItems(prefix: string, items: ModuleItem[]): ModuleItem[] {
    return items.map((item: ModuleItem, index: number): ModuleItem => {
      return { id: `${prefix}-${item.id || index}`, title: item.title, detail: item.detail }
    })
  }
}

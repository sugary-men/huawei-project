import { ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'

// M2 表单工具的接入契约：动作集合、结果形状与自检。
// 张耀之实现 ModuleAdapter 后调用 IntegrationService.initializeForms 注入即可，编排器、工具层与页面不需要改动。
export class FormModuleContract {
  static readonly actions: string[] = ['templates', 'draft', 'export', 'fill']

  // 工具层与页面共用的动作说明，避免两处各写一份。
  static readonly summary: string = '表单工作区支持 templates（模板清单）、draft（生成草稿）、fill（按字段回填）、export（导出或复制草稿）'

  static accepts(action: string): boolean {
    return FormModuleContract.actions.includes(action)
  }

  static describeRequiredInput(action: string): string {
    if (action === 'fill') return '需要 input 提供字段名与新值，无法识别的字段由适配器返回失败说明。'
    if (action === 'export') return 'input 可指定目标格式；为空时导出当前草稿。'
    return 'input 可为空。'
  }

  // 适配器自检：只核对契约要求的形状，不判断业务内容，也不写入任何用户数据。
  static async verify(adapter: ModuleAdapter): Promise<string[]> {
    const problems: string[] = []
    if (adapter === undefined || adapter === null || typeof adapter.execute !== 'function') {
      return ['适配器必须实现 execute(action, input): Promise<ModuleResult>。']
    }
    for (const action of FormModuleContract.actions) {
      let result: ModuleResult
      try {
        result = await adapter.execute(action, '')
      } catch (error) {
        problems.push(`${action}：执行抛出异常「${(error as Error).message}」。`)
        continue
      }
      if (result === undefined || result === null) {
        problems.push(`${action}：没有返回结果。`)
        continue
      }
      if (typeof result.ok !== 'boolean') problems.push(`${action}：ok 必须是布尔值。`)
      if (typeof result.message !== 'string' || result.message.length === 0) problems.push(`${action}：message 不能为空。`)
      if (!Array.isArray(result.items)) {
        problems.push(`${action}：items 必须是数组，空结果也要返回空数组。`)
        continue
      }
      result.items.forEach((item: ModuleItem, index: number) => {
        if (item === undefined || item === null || typeof item.id !== 'string' || typeof item.title !== 'string' ||
          typeof item.detail !== 'string') problems.push(`${action}：items[${index}] 需要 id/title/detail 三个字符串字段。`)
      })
    }
    return problems
  }
}
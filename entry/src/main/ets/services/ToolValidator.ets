import { AgentToolProperty } from '../models/WorkspaceModels'
import { ToolDescriptor } from '../models/ToolModels'

// 统一的参数校验：按工具自己声明的 JSON Schema 检查类型、必填、枚举与未知字段。
// 语义校验（如产物总量、时间范围）仍由各工具服务负责，这里只保证进入业务逻辑前的结构一致。
export class ToolValidator {
  static validate(descriptor: ToolDescriptor, raw: string): Record<string, Object> {
    if (typeof raw !== 'string') throw new Error('工具参数必须是 JSON 文本。')
    if (raw.length > descriptor.argumentLimit) throw new Error('工具参数过长。')
    let parsed: Object
    try {
      parsed = JSON.parse(raw.length === 0 ? '{}' : raw) as Object
    } catch (_error) {
      throw new Error('工具参数不是有效的 JSON。')
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('工具参数必须是对象。')
    const args = parsed as Record<string, Object>
    ToolValidator.shape(args, descriptor.definition.function.parameters, '参数')
    return args
  }

  private static shape(value: Record<string, Object>, schema: AgentToolProperty, path: string): void {
    const properties = schema.properties
    Object.keys(value).forEach((key: string) => {
      const property = properties === undefined ? undefined : properties[key]
      if (property === undefined) throw new Error(path === '参数' ? `不支持的字段：${key}` : `${path}不支持字段：${key}`)
      ToolValidator.check(value[key], property, path === '参数' ? key : `${path}.${key}`)
    })
    if (schema.required !== undefined) {
      schema.required.forEach((key: string) => { if (value[key] === undefined) throw new Error(`缺少字段：${key}`) })
    }
  }

  private static check(value: Object, property: AgentToolProperty, path: string): void {
    if (property.type === 'array') {
      if (!Array.isArray(value)) throw new Error(`${path}必须为数组。`)
      const items = property.items
      if (items === undefined) return
      (value as Object[]).forEach((item: Object, index: number) => {
        if (items.type === 'object') {
          if (item === null || typeof item !== 'object' || Array.isArray(item)) throw new Error(`${path}[${index}]必须为对象。`)
          ToolValidator.shape(item as Record<string, Object>, items, `${path}[${index}]`)
        } else {
          ToolValidator.check(item, items, `${path}[${index}]`)
        }
      })
      return
    }
    if (property.type === 'object') {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${path}必须为对象。`)
      ToolValidator.shape(value as Record<string, Object>, property, path)
      return
    }
    if (typeof value !== property.type) throw new Error(`${path}类型不正确。`)
    if (property.type === 'number' && !Number.isFinite(value as number)) throw new Error(`${path}必须是有效数字。`)
    if (property.enum !== undefined && !property.enum.includes(value as string)) throw new Error(`${path}取值不正确。`)
  }
}
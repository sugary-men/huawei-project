import { FeatureDefinition } from '../models/AppModels'
import { FEATURE_CATALOG } from '../config/FeatureCatalog'
import { AgentToolDefinition } from '../models/WorkspaceModels'
import { ToolDescriptor, ToolMeta } from '../models/ToolModels'
import { WorkspaceService } from './WorkspaceService'
import { ScheduleService } from './ScheduleService'
import { AgentTaskService } from './AgentTaskService'
import { StudyToolService } from './StudyToolService'

// 工具接入的单一登记处：新增工具只需在所属服务补齐定义，再在此登记展示名、分类与限制。
// 缺少登记会直接报错，避免执行记录显示成“工具请求”或后台任务越权调用写操作。
export class ToolRegistry {
  private static readonly META: string = `[
    {"name":"read_workspace","label":"读取任务面板","category":"workspace","confirmation":false,"blocksTimeout":false,"background":false,"limit":40000},
    {"name":"update_task_panel","label":"更新任务面板与产物","category":"workspace","confirmation":false,"blocksTimeout":false,"background":false,"limit":40000},
    {"name":"switch_workspace","label":"切换工作区","category":"workspace","confirmation":false,"blocksTimeout":false,"background":false,"limit":40000},
    {"name":"run_workspace_action","label":"调用工作区服务","category":"workspace","confirmation":false,"blocksTimeout":false,"background":false,"limit":40000},
    {"name":"focus_lock","label":"设备专注锁","category":"workspace","confirmation":false,"blocksTimeout":true,"background":false,"limit":12000},
    {"name":"get_system_time","label":"读取设备时间","category":"schedule","confirmation":false,"blocksTimeout":true,"background":true,"limit":20000},
    {"name":"query_calendar_events","label":"查询系统日历","category":"schedule","confirmation":false,"blocksTimeout":true,"background":true,"limit":20000},
    {"name":"create_calendar_event","label":"创建日程","category":"schedule","confirmation":true,"blocksTimeout":true,"background":false,"limit":20000},
    {"name":"update_calendar_event","label":"修改日程","category":"schedule","confirmation":true,"blocksTimeout":true,"background":false,"limit":20000},
    {"name":"delete_calendar_event","label":"删除日程","category":"schedule","confirmation":true,"blocksTimeout":true,"background":false,"limit":20000},
    {"name":"create_system_reminder","label":"设置系统代理提醒","category":"schedule","confirmation":true,"blocksTimeout":true,"background":false,"limit":20000},
    {"name":"list_system_reminders","label":"查询系统代理提醒","category":"schedule","confirmation":false,"blocksTimeout":true,"background":true,"limit":20000},
    {"name":"cancel_system_reminder","label":"取消系统代理提醒","category":"schedule","confirmation":true,"blocksTimeout":true,"background":false,"limit":20000},
    {"name":"manage_memo","label":"管理备忘录","category":"schedule","confirmation":true,"blocksTimeout":true,"background":true,"limit":20000},
    {"name":"manage_agent_task","label":"管理Agent定时任务","category":"agentTask","confirmation":true,"blocksTimeout":true,"background":false,"limit":12000},
    {"name":"manage_study","label":"管理学习课程","category":"study","confirmation":true,"blocksTimeout":true,"background":true,"limit":20000}
  ]`

  static meta(): ToolMeta[] { return JSON.parse(ToolRegistry.META) as ToolMeta[] }

  static descriptors(features: FeatureDefinition[] = FEATURE_CATALOG): ToolDescriptor[] {
    const meta = ToolRegistry.meta()
    const definitions = WorkspaceService.tools(features).concat(ScheduleService.tools(), AgentTaskService.tools(), StudyToolService.tools())
    const names = new Set<string>()
    return definitions.map((definition: AgentToolDefinition): ToolDescriptor => {
      const name = definition.function.name
      if (names.has(name)) throw new Error(`工具名称重复：${name}`)
      names.add(name)
      const entry = meta.find((item: ToolMeta) => item.name === name)
      if (entry === undefined) throw new Error(`工具缺少注册信息：${name}`)
      return { name: name, label: entry.label, category: entry.category, needsConfirmation: entry.confirmation,
        blocksTimeout: entry.blocksTimeout, background: entry.background, argumentLimit: entry.limit, definition: definition }
    })
  }

  static definitions(features: FeatureDefinition[] = FEATURE_CATALOG): AgentToolDefinition[] {
    return ToolRegistry.descriptors(features).map((item: ToolDescriptor): AgentToolDefinition => item.definition)
  }

  // 后台定时任务只能读取授权数据；读取清单与写操作边界由登记表决定，不在运行时代码里另写一份。
  static backgroundTools(): AgentToolDefinition[] {
    return ToolRegistry.definitions().filter((tool: AgentToolDefinition) => {
      const entry = ToolRegistry.meta().find((item: ToolMeta) => item.name === tool.function.name)
      return entry !== undefined && entry.background
    })
  }

  static descriptor(name: string, features: FeatureDefinition[] = FEATURE_CATALOG): ToolDescriptor | undefined {
    return ToolRegistry.descriptors(features).find((item: ToolDescriptor) => item.name === name)
  }

  static handles(name: string): boolean {
    return ToolRegistry.meta().some((item: ToolMeta) => item.name === name)
  }

  static label(name: string): string {
    const entry = ToolRegistry.meta().find((item: ToolMeta) => item.name === name)
    return entry === undefined ? '工具请求' : entry.label
  }

  static blocksTimeout(name: string): boolean {
    const entry = ToolRegistry.meta().find((item: ToolMeta) => item.name === name)
    return entry !== undefined && entry.blocksTimeout
  }

  static category(name: string): string {
    const entry = ToolRegistry.meta().find((item: ToolMeta) => item.name === name)
    return entry === undefined ? '' : entry.category
  }
}
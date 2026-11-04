import { AgentToolCall, AgentToolDefinition, WorkspaceState, WorkspaceToolResult } from './WorkspaceModels'
import { FeatureDefinition } from './AppModels'
import { ModuleItem, ModuleResult } from './IntegrationModels'

// 工具接入的公共契约：注册信息、统一回执与分发上下文都在这里定义，避免各服务各写一套。
export interface ToolMeta {
  name: string
  label: string
  category: string
  confirmation: boolean
  blocksTimeout: boolean
  background: boolean
  limit: number
}

export interface ToolDescriptor {
  name: string
  label: string
  category: string
  needsConfirmation: boolean
  blocksTimeout: boolean
  background: boolean
  argumentLimit: number
  definition: AgentToolDefinition
}

export interface ToolReceiptEntry {
  id?: string
  title?: string
  calendarId?: number
  eventId?: number
  reminderId?: number
}

// 回传模型的统一回执；entries/tasks 沿用系统工具与定时任务的既有字段名。
export interface ToolReceipt {
  ok: boolean
  status?: string
  message: string
  workspace?: string
  entries?: ToolReceiptEntry[]
  tasks?: ToolReceiptEntry[]
}

// 分发结果保留面板变更与业务回执，供页面落盘和提示，工具层本身不直接操作 UI。
export interface ToolExecution {
  output: string
  ok: boolean
  cancelled: boolean
  message: string
  workspace?: WorkspaceToolResult
  moduleNotice?: string
  moduleItems?: ModuleItem[]
}

// 系统能力由页面注入真实实现；工具层只做校验与分发，便于脱离设备单测。
export interface ToolContext {
  featureId: string
  workspace: WorkspaceState
  features: FeatureDefinition[]
  isActive: () => boolean
  confirm: (title: string, detail: string) => Promise<boolean>
  schedule?: (call: AgentToolCall, isActive: () => boolean, confirm: (title: string, detail: string) => Promise<boolean>) => Promise<string>
  agentTask?: (call: AgentToolCall, isActive: () => boolean, confirm: (title: string, detail: string) => Promise<boolean>) => Promise<string>
  module?: (featureId: string, action: string, input: string) => Promise<ModuleResult>
  study?: (call: AgentToolCall, isActive: () => boolean, confirm: (title: string, detail: string) => Promise<boolean>) => Promise<string>
}
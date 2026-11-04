import { AgentMessage, FeatureDefinition } from './AppModels'
import { AgentToolCall, WorkspaceState } from './WorkspaceModels'
import { ChatAttachment } from './AttachmentModels'
import { RetrievalOptions, RetrievalResult, SourceCitation } from './RagModels'

// 一个回合的显式状态。页面与后台任务共用，状态迁移只发生在编排器内部。
export class AgentTurnState {
  static readonly idle: string = 'idle'
  static readonly retrieving: string = 'retrieving'
  static readonly connecting: string = 'connecting'
  static readonly analyzing: string = 'analyzing'
  static readonly tool: string = 'tool'
  static readonly answering: string = 'answering'
  static readonly complete: string = 'complete'
  static readonly failed: string = 'failed'
  static readonly cancelled: string = 'cancelled'
}

// 编排器只上报进行中阶段；终态随 run() 的返回值给出，避免页面与状态机各写一套结束逻辑。
export interface AgentTurnObserver {
  onPhase(phase: string, detail: string): void
  onDelta(content: string): void
  onRetrieved(result: RetrievalResult): void
  // 与正文无关的过程提示，例如已切换到备用模型配置。
  onNotice?(text: string): void
}

export interface AgentTurnInput {
  prompt: string
  featureId: string
  history: AgentMessage[]
  retrievalOptions: RetrievalOptions
  attachments: ChatAttachment[]
  attachedSources: SourceCitation[]
  workspace: WorkspaceState
  features: FeatureDefinition[]
  reviewContext: string
}

export interface AgentTurnResult {
  state: string
  content: string
  sources: SourceCitation[]
  calls: number
  reason: string
  startedAt: number
  finishedAt: number
  // 模型正常返回但没有任何正文，页面按“未返回内容”提示，而不是伪装成生成失败原因。
  empty: boolean
  // 传输层或截止时刻判定的超时：页面按“响应超时”提示，不把英文底层错误直接给用户。
  timeout: boolean
  // 超时或停止已经通过 onPhase 上报过，页面不必再渲染一次终态。
  notified: boolean
}

export interface AgentOrchestratorOptions {
  timeoutMs?: number
  intervalMs?: number
  graceMs?: number
  blocksTimeout?: (name: string) => boolean
}
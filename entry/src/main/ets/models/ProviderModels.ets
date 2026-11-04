import { AgentToolCall, AgentToolDefinition } from './WorkspaceModels'
import { ModelContentPart } from './AttachmentModels'

// 服务商标识：空字符串表示按服务地址自动判断，避免旧配置被迫改字段。
export class ProviderKind {
  static readonly auto: string = ''
  static readonly openAi: string = 'openai'
  static readonly anthropic: string = 'anthropic'
}

// 与具体服务商无关的消息表示；由各适配器翻译成自己的线格式。
export interface ProviderMessage {
  role: string
  content: string | ModelContentPart[]
  toolCalls?: AgentToolCall[]
  toolCallId?: string
}

export interface ProviderDeltaSink {
  isCancelled(): boolean
  onDelta(text: string): void
  onAnalyzing(): void
}

export interface ProviderTurn {
  content: string
  calls: AgentToolCall[]
}

// 一次模型补全。回合循环、重试与降级在 LlmClient，适配器只负责一家服务的线格式。
export interface ProviderAdapter {
  kind: string
  label: string
  complete(system: string, messages: ProviderMessage[], tools: AgentToolDefinition[], sink: ProviderDeltaSink): Promise<ProviderTurn>
  cancel(): void
}

// 一条可用配置：主配置与备用配置共用同一结构，降级链按数组顺序尝试。
export interface LlmCandidate {
  label: string
  model: string
  baseUrl: string
  apiKey: string
  kind: string
}
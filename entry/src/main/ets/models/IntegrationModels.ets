import { AgentMessage } from './AppModels'
import { RetrievalResult } from './RagModels'
import { SourceCitation } from './RagModels'
import { ChatAttachment } from './AttachmentModels'
import { AgentToolCall, AgentToolDefinition } from './WorkspaceModels'

export interface AgentRequest {
  prompt: string
  featureId: string
  history: AgentMessage[]
  retrieval: RetrievalResult
  systemInstruction: string
  attachments?: ChatAttachment[]
  tools?: AgentToolDefinition[]
  executeTool?: (call: AgentToolCall) => Promise<string>
}

export interface StreamSink {
  onDelta(delta: string): void
  onProgress?(phase: string): void
  // 与回答无关但需要让用户知道的过程说明，例如已切换到备用模型配置。
  onNotice?(text: string): void
  isCancelled(): boolean
}

export interface AgentGateway {
  name: string
  generate(request: AgentRequest, sink: StreamSink): Promise<void>
  cancel(): void
}

export interface ModuleItem {
  id: string
  title: string
  detail: string
}

export interface ModuleResult {
  ok: boolean
  message: string
  items: ModuleItem[]
}

export interface ModuleAdapter {
  execute(action: string, input: string): Promise<ModuleResult>
}

export interface VoiceObserver {
  onPartial(text: string): void
  onComplete(text: string): void
  onError(message: string): void
}

export interface VoiceAdapter {
  start(observer?: VoiceObserver): Promise<void>
  stop(): Promise<string>
  cancel(): Promise<void>
  speak(text: string): Promise<void>
  stopSpeaking(): Promise<void>
}

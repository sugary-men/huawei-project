import { SourceCitation } from './RagModels'
import { ChatAttachment } from './AttachmentModels'

export interface AgentMessage {
  role: string
  content: string
  meta: string
  sources?: SourceCitation[]
  status?: string
  renderRevision?: number
  thinkingStartedAt?: number
  thinkingDurationMs?: number
  phase?: string
  attachments?: ChatAttachment[]
}

export interface FeatureDefinition {
  id: string
  icon: string
  name: string
  description: string
  category: string
}

export interface ActionItem {
  title: string
  subtitle: string
  status: string
}

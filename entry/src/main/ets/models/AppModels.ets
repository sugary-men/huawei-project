import { SourceCitation } from './RagModels'

export interface AgentMessage {
  role: string
  content: string
  meta: string
  sources?: SourceCitation[]
  status?: string
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

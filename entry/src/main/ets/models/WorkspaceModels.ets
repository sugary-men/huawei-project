import { InteractionRecord } from './InteractionModels'

export interface WorkspaceTask {
  id: string
  title: string
  detail: string
  status: string
}

export interface WorkspaceArtifact {
  id: string
  title: string
  content: string
}

export interface WorkspaceState {
  goal: string
  summary: string
  tasks: WorkspaceTask[]
  artifacts: WorkspaceArtifact[]
  updatedAt: number
  interactions?: InteractionRecord[]
}

export interface WorkspaceProfile {
  id: string
  name: string
  role: string
  instruction: string
  greeting: string
  starters: string[]
  steps: string[]
}

export interface WorkspaceOption {
  id: string
  name: string
  description?: string
}

export interface WorkspaceSnapshot {
  featureId: string
  name: string
  role: string
  instruction: string
  state: WorkspaceState
  workspaces: WorkspaceOption[]
}

export interface AgentToolProperty {
  type: string
  description?: string
  enum?: string[]
  properties?: Record<string, AgentToolProperty>
  required?: string[]
  additionalProperties?: boolean
  items?: AgentToolProperty
}

export interface AgentToolDefinition {
  type: string
  function: AgentToolFunction
}

export interface AgentToolFunction {
  name: string
  description: string
  parameters: AgentToolProperty
}

export interface AgentToolCall {
  id: string
  name: string
  arguments: string
}

export interface WorkspaceUpdate {
  goal?: string
  summary?: string
  tasks?: WorkspaceTask[]
  artifacts?: WorkspaceArtifact[]
  featureId?: string
  action?: string
  input?: string
  durationMinutes?: number
  useWhitelist?: boolean
}

export interface WorkspaceToolResult {
  featureId: string
  state: WorkspaceState
  message: string
  action?: string
  input?: string
}

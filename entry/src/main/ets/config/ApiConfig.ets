export class ApiConfig {
  static readonly requestTimeoutMs: number = 90000
  static readonly maxHistoryMessages: number = 12
  static readonly maxMessageChars: number = 4000
}

export interface AgentApiSettings {
  baseUrl: string
  model: string
  apiKey: string
}

export interface AgentApiProfile extends AgentApiSettings {
  id: string
  name: string
  // '' 表示按服务地址自动判断；'openai' / 'anthropic' 为显式指定。
  provider?: string
}

export interface AgentProfileSummary {
  id: string
  name: string
  model: string
  provider?: string
}

export interface AgentProfileArchive {
  version: number
  activeId: string
  items: AgentApiProfile[]
}

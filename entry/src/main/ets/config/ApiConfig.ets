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

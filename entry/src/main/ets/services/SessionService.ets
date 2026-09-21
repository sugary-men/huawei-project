import { AgentMessage } from '../models/AppModels'

export class SessionService {
  // 后续替换为 Preferences / 数据库实现，页面层不需要改动。
  static saveMessages(_sessionId: string, _messages: AgentMessage[]): void {}
  static loadMessages(_sessionId: string): AgentMessage[] { return [] }
}

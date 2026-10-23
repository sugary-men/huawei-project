import { AgentMessage } from '../models/AppModels'
import { SourceCitation } from '../models/RagModels'

export class SessionService {
  // 当前只保存在进程内。M8 可替换此契约接入加密存储。
  private static messages: Map<string, AgentMessage[]> = new Map<string, AgentMessage[]>()
  static saveMessages(sessionId: string, messages: AgentMessage[]): void {
    SessionService.messages.set(sessionId, SessionService.copy(messages.slice(-100)))
  }
  static loadMessages(sessionId: string): AgentMessage[] {
    return SessionService.copy(SessionService.messages.get(sessionId) || [])
  }
  private static copy(messages: AgentMessage[]): AgentMessage[] {
    return messages.map((message: AgentMessage): AgentMessage => ({
      role: message.role, content: message.content, meta: message.meta, status: message.status,
      sources: message.sources === undefined ? [] : message.sources.map((source: SourceCitation): SourceCitation => ({
        number: source.number, chunkId: source.chunkId, sourceId: source.sourceId, title: source.title,
        location: source.location, course: source.course, excerpt: source.excerpt, score: source.score
      }))
    }))
  }
}

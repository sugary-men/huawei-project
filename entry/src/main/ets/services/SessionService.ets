import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { AgentMessage } from '../models/AppModels'
import { SourceCitation } from '../models/RagModels'

export interface SessionSummary {
  id: string
  title: string
  featureId: string
  createdAt: number
  updatedAt: number
}

export interface ChatSession extends SessionSummary {
  messages: AgentMessage[]
  context: SourceCitation[]
  progress: number
}

interface SessionArchive {
  version: number
  activeSessionId: string
  sessions: ChatSession[]
}

export class SessionService {
  private static archive: SessionArchive = { version: 1, activeSessionId: '', sessions: [] }
  private static path: string = ''
  private static dirty: boolean = false
  private static storageBlocked: boolean = false
  private static timer: number = -1
  private static purgeBackup: boolean = false
  static storageNotice: string = ''

  static initialize(context: common.UIAbilityContext): void {
    if (SessionService.path.length > 0) return
    SessionService.path = `${context.filesDir}/chat_sessions.json`
    try {
      if (!fs.accessSync(SessionService.path) && !fs.accessSync(`${SessionService.path}.bak`)) return
    } catch (_error) {
      SessionService.storageNotice = '无法访问本地历史记录，请检查设备存储。'
      SessionService.storageBlocked = true
      return
    }
    let loaded = SessionService.readArchive(SessionService.path)
    if (loaded === undefined) {
      loaded = SessionService.readArchive(`${SessionService.path}.bak`)
      SessionService.storageNotice = loaded === undefined
        ? '本地历史记录读取失败，原文件已保留。' : '已从本地备份恢复历史对话。'
    }
    if (loaded === undefined) { SessionService.storageBlocked = true; return }
    SessionService.archive = loaded
    loaded.sessions.forEach((session: ChatSession) => {
      session.messages.forEach((message: AgentMessage) => {
        if (message.status === 'loading' || message.status === 'streaming') {
          if (message.thinkingStartedAt !== undefined) {
            message.thinkingDurationMs = Math.max(0, session.updatedAt - message.thinkingStartedAt)
          }
          message.content = message.status === 'loading' ? '上次生成已中断，可以继续发送消息。' : message.content
          message.status = 'stopped'
          message.meta = '上次生成已中断'
        }
      })
    })
  }

  private static readArchive(path: string): SessionArchive | undefined {
    try {
      if (!fs.accessSync(path)) return undefined
      const data = JSON.parse(fs.readTextSync(path)) as SessionArchive
      if (data.version !== 1 || typeof data.activeSessionId !== 'string' || !Array.isArray(data.sessions)) return undefined
      const ids = new Set<string>()
      for (const session of data.sessions) {
        if (typeof session.id !== 'string' || !session.id || ids.has(session.id) ||
          typeof session.title !== 'string' || typeof session.featureId !== 'string' ||
          typeof session.createdAt !== 'number' || typeof session.updatedAt !== 'number' ||
          !Array.isArray(session.messages) || !Array.isArray(session.context) ||
          typeof session.progress !== 'number') return undefined
        ids.add(session.id)
        for (const message of session.messages) {
          if (typeof message.role !== 'string' || typeof message.content !== 'string' ||
            typeof message.meta !== 'string') return undefined
        }
      }
      return data
    } catch (_error) { return undefined }
  }

  static list(): SessionSummary[] {
    return SessionService.archive.sessions.slice().sort((a: ChatSession, b: ChatSession) =>
      b.updatedAt - a.updatedAt || b.createdAt - a.createdAt || a.id.localeCompare(b.id))
      .map((session: ChatSession): SessionSummary => ({ id: session.id, title: session.title,
        featureId: session.featureId, createdAt: session.createdAt, updatedAt: session.updatedAt }))
  }

  static current(): ChatSession | undefined { return SessionService.get(SessionService.archive.activeSessionId) }

  static get(id: string): ChatSession | undefined {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    return session === undefined ? undefined : JSON.parse(JSON.stringify(session)) as ChatSession
  }

  static latestForFeature(featureId: string): ChatSession | undefined {
    const summary = SessionService.list().find((item: SessionSummary) => item.featureId === featureId)
    return summary === undefined ? undefined : SessionService.get(summary.id)
  }

  static create(featureId: string, title: string, messages: AgentMessage[]): ChatSession {
    const now = Date.now()
    const session: ChatSession = { id: util.generateRandomUUID(), title: title, featureId: featureId,
      createdAt: now, updatedAt: now, messages: SessionService.copy(messages), context: [], progress: 1 }
    SessionService.archive.sessions.push(session)
    SessionService.activate(session.id)
    return SessionService.get(session.id) as ChatSession
  }

  static activate(id: string): void {
    if (SessionService.archive.activeSessionId === id) return
    SessionService.archive.activeSessionId = id
    SessionService.schedule(true)
  }

  static saveMessages(id: string, messages: AgentMessage[], immediate: boolean = true): void {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    if (session === undefined) return
    // Saving a viewed conversation is not a new message and must not reorder history.
    if (JSON.stringify(session.messages) === JSON.stringify(messages)) {
      if (immediate) SessionService.flush()
      return
    }
    const firstPrompt = messages.find((message: AgentMessage) => message.role === 'user')
    if (!session.messages.some((message: AgentMessage) => message.role === 'user') && firstPrompt !== undefined) {
      session.title = firstPrompt.content.replace(/\s+/g, ' ').trim().slice(0, 24) || '新对话'
    }
    session.messages = SessionService.copy(messages)
    session.updatedAt = Date.now()
    SessionService.schedule(immediate)
  }

  static saveDetails(id: string, context: SourceCitation[], progress: number): void {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    if (session === undefined) return
    if (session.progress === progress && JSON.stringify(session.context) === JSON.stringify(context)) return
    session.context = JSON.parse(JSON.stringify(context)) as SourceCitation[]
    session.progress = progress
    SessionService.schedule(false)
  }

  static remove(id: string): boolean {
    const removed = SessionService.archive.sessions.find((session: ChatSession) => session.id === id)
    if (removed === undefined) return false
    const previous = SessionService.archive
    SessionService.archive = { version: 1, activeSessionId: previous.activeSessionId,
      sessions: previous.sessions.filter((session: ChatSession) => session.id !== id) }
    if (previous.activeSessionId === id) SessionService.archive.activeSessionId = SessionService.list()[0]?.id || ''
    SessionService.dirty = true
    // A recovery snapshot must not bring a deleted conversation back.
    SessionService.purgeBackup = true
    if (!SessionService.flush()) {
      SessionService.archive = previous
      SessionService.purgeBackup = false
      SessionService.dirty = true
      return false
    }
    const keptPaths = new Set<string>()
    SessionService.archive.sessions.forEach((session: ChatSession) => session.messages.forEach((message: AgentMessage) => {
      message.attachments?.forEach((attachment) => keptPaths.add(attachment.path))
    }))
    const directory = SessionService.path.slice(0, SessionService.path.lastIndexOf('/'))
    removed.messages.forEach((message: AgentMessage) => message.attachments?.forEach((attachment) => {
      if (!keptPaths.has(attachment.path) && attachment.path.startsWith(`${directory}/chat_attachments/`) &&
        !attachment.path.includes('/../')) {
        try { fs.unlinkSync(attachment.path) } catch (_error) {}
      }
    }))
    return true
  }

  private static schedule(immediate: boolean): void {
    SessionService.dirty = true
    if (immediate) { SessionService.flush(); return }
    if (SessionService.timer >= 0) return
    SessionService.timer = setTimeout(() => { SessionService.timer = -1; SessionService.flush() }, 700)
  }

  static flush(): boolean {
    if (SessionService.timer >= 0) { clearTimeout(SessionService.timer); SessionService.timer = -1 }
    if (!SessionService.path || SessionService.storageBlocked) return false
    if (!SessionService.dirty) return true
    try {
      // Keep the last valid snapshot and replace the main file atomically.
      if (SessionService.purgeBackup) {
        if (fs.accessSync(`${SessionService.path}.bak`)) fs.unlinkSync(`${SessionService.path}.bak`)
      } else if (SessionService.readArchive(SessionService.path) !== undefined) {
        fs.copyFileSync(SessionService.path, `${SessionService.path}.bak`)
      }
      const file = fs.openSync(`${SessionService.path}.tmp`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
      try {
        fs.writeSync(file.fd, JSON.stringify(SessionService.archive))
        fs.fsyncSync(file.fd)
      } finally { fs.closeSync(file) }
      fs.renameSync(`${SessionService.path}.tmp`, SessionService.path)
      SessionService.dirty = false
      SessionService.storageNotice = ''
      if (SessionService.purgeBackup) {
        SessionService.purgeBackup = false
        try { fs.copyFileSync(SessionService.path, `${SessionService.path}.bak`) }
        catch (_error) { SessionService.storageNotice = '会话已删除，本地备份暂不可用。' }
      }
      return true
    } catch (_error) {
      SessionService.storageNotice = '历史对话未能写入本地，请检查设备剩余空间。'
      return false
    }
  }

  static loadMessages(id: string): AgentMessage[] { return SessionService.get(id)?.messages || [] }

  private static copy(messages: AgentMessage[]): AgentMessage[] {
    return JSON.parse(JSON.stringify(messages)) as AgentMessage[]
  }
}

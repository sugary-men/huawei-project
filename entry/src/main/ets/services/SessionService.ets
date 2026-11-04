import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { AgentMessage, FeatureDefinition } from '../models/AppModels'
import { FEATURE_CATALOG } from '../config/FeatureCatalog'
import { SourceCitation } from '../models/RagModels'
import { WorkspaceState } from '../models/WorkspaceModels'
import { SidebarPreferences } from '../models/SidebarModels'
import { ExecutionRecord } from '../models/ExecutionModels'
import { ExecutionTraceService } from './ExecutionTraceService'

export interface SessionSummary {
  id: string
  title: string
  featureId: string
  createdAt: number
  updatedAt: number
  deletedAt?: number
  originFeatureId?: string
  originFeatureName?: string
}

export interface ChatSession extends SessionSummary {
  workspace?: WorkspaceState
  messages: AgentMessage[]
  context: SourceCitation[]
  progress: number
}

interface SessionArchive {
  version: number
  activeSessionId: string
  sessions: ChatSession[]
  sidebar?: SidebarPreferences
  workspaces?: FeatureDefinition[]
  workspaceCatalogVersion?: number
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
    if ((loaded.workspaceCatalogVersion || 1) < 2) {
      loaded.workspaceCatalogVersion = 2
      if (Array.isArray(loaded.workspaces) && !loaded.workspaces.some((item: FeatureDefinition) => item.id === 'privacy')) {
        const privacy = FEATURE_CATALOG.find((item: FeatureDefinition) => item.id === 'privacy')
        if (privacy !== undefined) loaded.workspaces.push(JSON.parse(JSON.stringify(privacy)) as FeatureDefinition)
        SessionService.dirty = true
      }
    }
    SessionService.archive = loaded
    if (SessionService.dirty) SessionService.schedule(false)
    loaded.sessions.forEach((session: ChatSession) => {
      session.messages.forEach((message: AgentMessage) => {
        message.executions = ExecutionTraceService.restore(message.executions)
        if (message.status === 'loading' || message.status === 'streaming') {
          const end = Number.isFinite(message.thinkingLastActiveAt) ? message.thinkingLastActiveAt! : session.updatedAt
          const settled = ExecutionTraceService.settle(message, 'stopped', end)
          message.thinkingDurationMs = settled.thinkingDurationMs
          message.thinkingLastActiveAt = settled.thinkingLastActiveAt
          message.executions = settled.executions
          if (Number.isFinite(message.createdAt) && message.createdAt! > 0 && !Number.isFinite(message.completedAt) &&
            Number.isFinite(end) && end > 0) message.completedAt = end
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
        featureId: session.featureId, createdAt: session.createdAt, updatedAt: session.updatedAt,
        deletedAt: session.deletedAt, originFeatureId: session.originFeatureId, originFeatureName: session.originFeatureName }))
  }

  static workspaces(): FeatureDefinition[] {
    const saved = SessionService.archive.workspaces
    const items = Array.isArray(saved) ? saved.filter((item: FeatureDefinition) => item !== null &&
      typeof item.id === 'string' && typeof item.name === 'string' && item.id !== 'home' && item.id !== 'trash')
      : FEATURE_CATALOG.filter((item: FeatureDefinition) => item.id !== 'home')
    const result: FeatureDefinition[] = [FEATURE_CATALOG[0]]
    const seen = new Set<string>(['home', 'trash'])
    items.forEach((item: FeatureDefinition) => {
      if (seen.has(item.id) || !item.name.trim()) return
      seen.add(item.id)
      result.push({ id: item.id, name: item.name.slice(0, 40), description: typeof item.description === 'string' ? item.description.slice(0, 160) : '',
        category: typeof item.category === 'string' ? item.category : '自定义', icon: typeof item.icon === 'string' ? item.icon : '▤',
        prompt: typeof item.prompt === 'string' ? item.prompt.slice(0, 3000) : undefined })
    })
    result.push({ id: 'trash', name: '回收站', description: '恢复会话或永久删除', category: '保留', icon: '♲' })
    return JSON.parse(JSON.stringify(result)) as FeatureDefinition[]
  }

  static addWorkspace(name: string, description: string = '', prompt: string = ''): FeatureDefinition | undefined {
    const title = name.trim()
    if (!title || title.length > 40 || description.length > 160 || prompt.length > 3000) throw new Error('请输入1–40字的分区名称，并缩短说明或提示词。')
    const current = SessionService.workspaces()
    if (current.length >= 30) throw new Error('最多保留30个工作区。')
    if (current.some((item: FeatureDefinition) => item.name.toLocaleLowerCase() === title.toLocaleLowerCase())) throw new Error('已有同名工作区。')
    const feature: FeatureDefinition = { id: `workspace-${util.generateRandomUUID()}`, name: title, description: description.trim(),
      category: '自定义', icon: '▤', prompt: prompt.trim() }
    const next = SessionService.copyArchive()
    next.workspaces = current.filter((item: FeatureDefinition) => item.id !== 'trash').concat([feature])
    return SessionService.commitArchive(next, false) ? feature : undefined
  }

  static deleteWorkspace(id: string): boolean {
    if (id === 'home' || id === 'trash' || !SessionService.workspaces().some((item: FeatureDefinition) => item.id === id)) return false
    const origin = SessionService.workspaces().find((item: FeatureDefinition) => item.id === id) as FeatureDefinition
    const next = SessionService.copyArchive()
    next.workspaces = SessionService.workspaces().filter((item: FeatureDefinition) => item.id !== id)
    next.sessions.forEach((session: ChatSession) => {
      if (session.featureId !== id) return
      session.originFeatureId = id
      session.originFeatureName = origin.name
      session.deletedAt = Date.now()
      session.featureId = 'trash'
    })
    if (next.sessions.some((session: ChatSession) => session.id === next.activeSessionId && session.featureId === 'trash')) {
      next.activeSessionId = next.sessions.filter((session: ChatSession) => session.featureId !== 'trash')
        .sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt)[0]?.id || ''
    }
    return SessionService.commitArchive(next, true)
  }

  static trash(id: string): boolean {
    const next = SessionService.copyArchive()
    const session = next.sessions.find((item: ChatSession) => item.id === id)
    if (session === undefined || session.featureId === 'trash') return false
    session.originFeatureId = session.featureId
    session.originFeatureName = SessionService.workspaces().find((item: FeatureDefinition) => item.id === session.featureId)?.name || '智能助理'
    session.deletedAt = Date.now()
    session.featureId = 'trash'
    if (next.activeSessionId === id) next.activeSessionId = next.sessions.filter((item: ChatSession) => item.featureId !== 'trash')
      .sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt)[0]?.id || ''
    return SessionService.commitArchive(next, true)
  }

  static restore(id: string): boolean {
    const next = SessionService.copyArchive()
    const session = next.sessions.find((item: ChatSession) => item.id === id)
    if (session === undefined || session.featureId !== 'trash') return false
    session.featureId = SessionService.workspaces().some((feature: FeatureDefinition) => feature.id === session.originFeatureId && feature.id !== 'trash')
      ? session.originFeatureId as string : 'home'
    session.originFeatureId = undefined
    session.originFeatureName = undefined
    session.deletedAt = undefined
    next.activeSessionId = id
    return SessionService.commitArchive(next, true)
  }

  private static copyArchive(): SessionArchive { return JSON.parse(JSON.stringify(SessionService.archive)) as SessionArchive }

  private static commitArchive(next: SessionArchive, purge: boolean): boolean {
    const previous = SessionService.archive
    SessionService.archive = next
    SessionService.dirty = true
    SessionService.purgeBackup = purge
    if (SessionService.flush()) return true
    SessionService.archive = previous
    SessionService.purgeBackup = false
    SessionService.dirty = true
    return false
  }

  static current(): ChatSession | undefined { return SessionService.get(SessionService.archive.activeSessionId) }

  static sidebar(): SidebarPreferences | undefined {
    return SessionService.archive.sidebar === undefined ? undefined
      : JSON.parse(JSON.stringify(SessionService.archive.sidebar)) as SidebarPreferences
  }

  static saveSidebar(preferences: SidebarPreferences): void {
    if (JSON.stringify(SessionService.archive.sidebar) === JSON.stringify(preferences)) return
    SessionService.archive.sidebar = JSON.parse(JSON.stringify(preferences)) as SidebarPreferences
    SessionService.schedule(true)
  }

  static get(id: string): ChatSession | undefined {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    return session === undefined ? undefined : JSON.parse(JSON.stringify(session)) as ChatSession
  }

  static latestForFeature(featureId: string): ChatSession | undefined {
    const summary = SessionService.list().find((item: SessionSummary) => item.featureId === featureId)
    return summary === undefined ? undefined : SessionService.get(summary.id)
  }

  static create(featureId: string, title: string, messages: AgentMessage[]): ChatSession {
    if (featureId === 'trash') throw new Error('回收站不能新建对话。')
    if (!SessionService.workspaces().some((feature: FeatureDefinition) => feature.id === featureId)) featureId = 'home'
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
    if (session === undefined || session.featureId === 'trash') return
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

  static recordExecution(id: string, executionId: string, record: ExecutionRecord): AgentMessage | undefined {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    if (!session) return undefined
    const index = session.messages.findIndex((message: AgentMessage) => message.executionId === executionId && message.role === 'agent')
    if (index < 0) return undefined
    const message = SessionService.copy([session.messages[index]])[0]
    message.executions = ExecutionTraceService.upsert(message.executions, record)
    if (!ExecutionTraceService.terminal(message.status)) message.thinkingLastActiveAt = Date.now()
    message.renderRevision = (message.renderRevision || 0) + 1
    session.messages[index] = message
    // A late receipt belongs to its original reply; never activate or resurrect a conversation.
    SessionService.schedule(true)
    return SessionService.copy([message])[0]
  }

  static saveDetails(id: string, context: SourceCitation[], progress: number): void {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    if (session === undefined || session.featureId === 'trash') return
    if (session.progress === progress && JSON.stringify(session.context) === JSON.stringify(context)) return
    session.context = JSON.parse(JSON.stringify(context)) as SourceCitation[]
    session.progress = progress
    SessionService.schedule(false)
  }

  static saveWorkspace(id: string, featureId: string, workspace: WorkspaceState, immediate: boolean = true): void {
    const session = SessionService.archive.sessions.find((item: ChatSession) => item.id === id)
    if (session === undefined || session.featureId === 'trash' || featureId === 'trash') return
    if (!SessionService.workspaces().some((feature: FeatureDefinition) => feature.id === featureId)) featureId = 'home'
    if (session.featureId === featureId && JSON.stringify(session.workspace) === JSON.stringify(workspace)) return
    session.featureId = featureId
    session.workspace = JSON.parse(JSON.stringify(workspace)) as WorkspaceState
    SessionService.schedule(immediate)
  }

  static remove(id: string): boolean {
    const removed = SessionService.archive.sessions.find((session: ChatSession) => session.id === id)
    if (removed === undefined) return false
    const previous = SessionService.archive
    SessionService.archive = { version: 1, activeSessionId: previous.activeSessionId, sidebar: previous.sidebar, workspaces: previous.workspaces,
      workspaceCatalogVersion: previous.workspaceCatalogVersion, sessions: previous.sessions.filter((session: ChatSession) => session.id !== id) }
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
      // Keep the recovery copy until the replacement primary is durable. A failed
      // delete write must not destroy the only valid copy after backup recovery.
      if (!SessionService.purgeBackup && SessionService.readArchive(SessionService.path) !== undefined) {
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
        try {
          if (fs.accessSync(`${SessionService.path}.bak`)) fs.unlinkSync(`${SessionService.path}.bak`)
          fs.copyFileSync(SessionService.path, `${SessionService.path}.bak`)
        } catch (_error) { SessionService.storageNotice = '修改已保存，本地备份暂不可用。' }
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

import { AgentMessage } from '../models/AppModels'
import { ExecutionRecord, ExecutionTarget } from '../models/ExecutionModels'
import { AgentToolCall, WorkspaceArtifact } from '../models/WorkspaceModels'
import { ChatAttachment } from '../models/AttachmentModels'
import { SourceCitation } from '../models/RagModels'

interface TraceEntry { id?: string; title?: string; calendarId?: number; eventId?: number; reminderId?: number }
interface TraceWorkspaceState { artifacts?: WorkspaceArtifact[] }
interface TraceWorkspace { state?: TraceWorkspaceState }
interface ToolReceipt { ok?: boolean; status?: string; message?: string; workspace?: string; entries?: TraceEntry[]; tasks?: TraceEntry[] }

// Only execution receipts enter this timeline. Never retain raw tool arguments or reasoning_content.
export class ExecutionTraceService {
  static readonly maximum: number = 24

  static text(value: string, secrets: string[] = [], limit: number = 360): string {
    let text = typeof value === 'string' ? value : ''
    secrets.filter((secret: string) => secret.length >= 4).forEach((secret: string) => text = text.split(secret).join('[已隐藏]'))
    return text.replace(/Bearer\s+[^\s"'<>]+/gi, 'Bearer [已隐藏]')
      .replace(/\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/g, '[已隐藏]')
      .replace(/((?:api[_-]?key|access[_-]?token|authorization|password|secret)\s*[=:：]\s*)[^\s,，;；]+/gi, '$1[已隐藏]')
      .slice(0, limit)
  }

  static restore(records?: ExecutionRecord[]): ExecutionRecord[] {
    if (!Array.isArray(records)) return []
    const result: ExecutionRecord[] = []
    records.slice(0, ExecutionTraceService.maximum).forEach((record: ExecutionRecord) => {
      if (!record || typeof record.id !== 'string' || !record.id || !Number.isFinite(record.startedAt) || record.startedAt < 0 ||
        !['tool', 'retrieval', 'attachment'].includes(record.kind) || !['running', 'success', 'error', 'cancelled', 'interrupted'].includes(record.status)) return
      const targets: ExecutionTarget[] = []
      if (Array.isArray(record.targets)) record.targets.slice(0, 12).forEach((target: ExecutionTarget) => {
        if (target && ['file', 'source', 'artifact', 'calendar', 'reminder', 'memo', 'task', 'workspace'].includes(target.kind) && typeof target.label === 'string') {
          targets.push({ kind: target.kind, label: ExecutionTraceService.text(target.label, [], 160),
            action: ExecutionTraceService.text(target.action, [], 40), id: typeof target.id === 'string' ? target.id.slice(0, 120) : undefined })
        }
      })
      result.push({ id: record.id.slice(0, 160), kind: record.kind, name: ExecutionTraceService.text(record.name, [], 100),
        title: ExecutionTraceService.text(record.title, [], 100), status: record.status, startedAt: record.startedAt,
        finishedAt: Number.isFinite(record.finishedAt) && record.finishedAt! >= record.startedAt ? record.finishedAt : undefined,
        input: ExecutionTraceService.text(record.input), detail: ExecutionTraceService.text(record.detail), targets: targets })
    })
    return result
  }

  static upsert(records: ExecutionRecord[] | undefined, record: ExecutionRecord): ExecutionRecord[] {
    const next = ExecutionTraceService.restore(records)
    const valid = ExecutionTraceService.restore([record])[0]
    if (!valid) return next
    const index = next.findIndex((item: ExecutionRecord) => item.id === valid.id)
    if (index >= 0) next[index] = valid
    else if (next.length < ExecutionTraceService.maximum) next.push(valid)
    return next
  }

  static tool(id: string, call: AgentToolCall, secrets: string[] = []): ExecutionRecord {
    const names: Record<string, string> = { 'search_session_history': '搜索其他会话', 'read_session_history': '读取历史消息', 'read_workspace': '读取任务面板', 'update_task_panel': '更新任务面板与产物', 'switch_workspace': '切换项目',
      'run_workspace_action': '调用项目服务', 'get_system_time': '读取设备时间', 'query_calendar_events': '查询系统日历',
      'create_calendar_event': '创建日程', 'update_calendar_event': '修改日程', 'delete_calendar_event': '删除日程',
      'create_system_reminder': '设置系统代理提醒', 'list_system_reminders': '查询系统代理提醒', 'cancel_system_reminder': '取消系统代理提醒',
      'manage_memo': '管理备忘录', 'manage_agent_task': '管理Agent定时任务' }
    let input = ''
    try {
      const args = JSON.parse(call.arguments) as Record<string, Object>
      if (args && !Array.isArray(args) && typeof args === 'object') {
        input = ['action', 'title', 'start', 'end', 'kind', 'at', 'hour', 'minute', 'featureId'].filter((key: string) =>
          typeof args[key] === 'string' || typeof args[key] === 'number').map((key: string) => `${key}: ${args[key]}`).join(' · ')
      }
    } catch (_error) {}
    return { id: id, kind: 'tool', name: ExecutionTraceService.text(call.name, secrets, 100), title: names[call.name] || '工具请求', status: 'running',
      startedAt: Date.now(), input: ExecutionTraceService.text(input, secrets), detail: '正在执行，等待实际回执。', targets: [] }
  }

  static finish(record: ExecutionRecord, call: AgentToolCall, output: string, before: WorkspaceArtifact[] = [], secrets: string[] = []): ExecutionRecord {
    const next = ExecutionTraceService.restore([record])[0]
    if (!next) return record
    next.finishedAt = Math.max(next.startedAt, Date.now())
    let receipt: ToolReceipt
    try { receipt = JSON.parse(output) as ToolReceipt } catch (_error) { receipt = { ok: false, message: '工具返回格式无法识别，未确认执行结果。' } }
    if (!receipt || typeof receipt !== 'object' || Array.isArray(receipt)) receipt = { ok: false, message: '未收到可验证的工具回执。' }
    next.status = receipt.ok === true ? 'success' : receipt.status === 'cancelled' ? 'cancelled' : 'error'
    next.detail = ExecutionTraceService.text(receipt.message || (receipt.ok === true ? '工具执行完成。' : '工具没有确认成功。'), secrets)
    next.targets = []
    if (receipt.ok !== true) return next
    const add = (kind: string, label: string, action: string, id?: string): void => {
      if (next.targets.length < 12) next.targets.push({ kind: kind, label: ExecutionTraceService.text(label, secrets, 160), action: action,
        id: id === undefined ? undefined : ExecutionTraceService.text(id, secrets, 120) })
    }
    if (call.name === 'read_workspace' || call.name === 'update_task_panel' || call.name === 'switch_workspace' || call.name === 'run_workspace_action') {
      if (call.name === 'read_workspace') add('workspace', '当前任务面板', '读取状态')
      else add('file', 'chat_sessions.json', '保存会话')
      if (call.name !== 'read_workspace' && receipt.workspace) {
        try {
          const workspace = JSON.parse(receipt.workspace) as TraceWorkspace
          const artifacts = workspace.state?.artifacts
          if (Array.isArray(artifacts)) artifacts.forEach((artifact: WorkspaceArtifact) => {
            const old = before.find((item: WorkspaceArtifact) => item.id === artifact.id)
            if (typeof artifact.id === 'string' && typeof artifact.title === 'string' &&
              (!old || old.title !== artifact.title || old.content !== artifact.content)) add('artifact', artifact.title, old ? '更新产物' : '新增产物', artifact.id)
          })
          if (Array.isArray(artifacts)) before.filter((artifact: WorkspaceArtifact) =>
            !artifacts.some((item: WorkspaceArtifact) => item.id === artifact.id)).forEach((artifact: WorkspaceArtifact) =>
              add('artifact', artifact.title, '移除产物', artifact.id))
        } catch (_error) {}
      }
    }
    if (call.name === 'manage_memo' || call.name === 'manage_agent_task') {
      let action = ''
      try { action = (JSON.parse(call.arguments) as Record<string, string>).action || '' } catch (_error) {}
      add('file', call.name === 'manage_memo' ? 'local_memos.json' : 'agent_tasks.json', ['list', 'read', 'share'].includes(action) ? '读取' : '更新')
    }
    if (Array.isArray(receipt.entries)) receipt.entries.forEach((entry: TraceEntry) => {
      const kind = call.name.includes('calendar') ? 'calendar' : call.name.includes('reminder') ? 'reminder' : 'memo'
      if (entry && typeof entry.title === 'string') add(kind, entry.title, receipt.status === 'already_exists' ? '已有记录' : receipt.status === 'share_opened' ? '打开分享' : '系统回执', entry.id)
    })
    if (Array.isArray(receipt.tasks)) receipt.tasks.forEach((task: TraceEntry) => { if (task && typeof task.title === 'string') add('task', task.title, '读取', task.id) })
    return next
  }

  static retrieval(id: string, startedAt: number, sources: SourceCitation[], secrets: string[] = []): ExecutionRecord {
    return { id: id, kind: 'retrieval', name: 'local_retrieval', title: '检索与引用资料', status: 'success', startedAt: startedAt, finishedAt: Date.now(), input: '',
      detail: `本轮使用${sources.length}条检索或主动加入的参考资料。`, targets: sources.slice(0, 6).map((source: SourceCitation): ExecutionTarget =>
        ({ kind: 'source', action: '参考', label: ExecutionTraceService.text(`${source.title} · ${source.location}`, secrets, 160) })) }
  }

  static attachments(files: ChatAttachment[], secrets: string[] = []): ExecutionRecord {
    const now = Date.now()
    return { id: 'attachments', kind: 'attachment', name: 'prepare_attachments', title: '准备本轮附件', status: 'success', startedAt: now, finishedAt: now,
      input: '', detail: '将已导入的文件正文或图片加入本轮请求；不代表修改了原文件。',
      targets: files.slice(0, 4).map((file: ChatAttachment): ExecutionTarget => ({ kind: 'file', action: '参考附件', label: ExecutionTraceService.text(file.name, secrets, 160) })) }
  }

  static terminal(status?: string): boolean { return !['loading', 'streaming'].includes(status || '') }

  static elapsed(message: AgentMessage, now: number = Date.now()): number | undefined {
    if (Number.isFinite(message.thinkingDurationMs) && message.thinkingDurationMs! >= 0) return message.thinkingDurationMs
    if (!Number.isFinite(message.thinkingStartedAt)) return undefined
    if (!ExecutionTraceService.terminal(message.status)) return Math.max(0, now - message.thinkingStartedAt!)
    return Number.isFinite(message.thinkingLastActiveAt) ? Math.max(0, message.thinkingLastActiveAt! - message.thinkingStartedAt!) : undefined
  }

  static settle(message: AgentMessage, status: string, now: number = Date.now()): AgentMessage {
    const next = JSON.parse(JSON.stringify(message)) as AgentMessage
    next.thinkingLastActiveAt = now
    if (ExecutionTraceService.terminal(status)) {
      if (next.thinkingDurationMs === undefined && Number.isFinite(next.thinkingStartedAt)) next.thinkingDurationMs = Math.max(0, now - next.thinkingStartedAt!)
      next.executions = ExecutionTraceService.restore(next.executions).map((record: ExecutionRecord): ExecutionRecord => {
        if (record.status === 'running') { record.status = 'interrupted'; record.finishedAt = Math.max(now, record.startedAt); record.detail = '执行已中断，结果尚未确认；请查询后再决定是否重试。' }
        return record
      })
    }
    next.status = status
    return next
  }

  static duration(milliseconds?: number): string {
    if (!Number.isFinite(milliseconds)) return '用时未记录'
    const seconds = Math.max(0, Math.floor(milliseconds! / 1000))
    if (seconds < 1) return '不足1秒'
    return seconds < 60 ? `${seconds}秒` : `${Math.floor(seconds / 60)}分${seconds % 60}秒`
  }
}

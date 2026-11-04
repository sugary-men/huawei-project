import { WorkspaceConfig } from '../config/WorkspaceConfig'
import { FEATURE_CATALOG } from '../config/FeatureCatalog'
import { FeatureDefinition } from '../models/AppModels'
import { InteractionService } from './InteractionService'
import { AgentToolDefinition, WorkspaceArtifact, WorkspaceOption, WorkspaceSnapshot, WorkspaceState, WorkspaceTask, WorkspaceToolResult, WorkspaceUpdate } from '../models/WorkspaceModels'

export class WorkspaceService {
  static create(featureId: string, features: FeatureDefinition[] = FEATURE_CATALOG): WorkspaceState {
    return { goal: '', summary: '', tasks: WorkspaceConfig.profile(featureId, features).steps.map((title: string, index: number): WorkspaceTask =>
      ({ id: `step-${index + 1}`, title: title, detail: '', status: 'pending' })), artifacts: [], updatedAt: 0 }
  }

  static copy(state: WorkspaceState): WorkspaceState { return JSON.parse(JSON.stringify(state)) as WorkspaceState }

  static restore(featureId: string, state?: WorkspaceState, features: FeatureDefinition[] = FEATURE_CATALOG): WorkspaceState {
    if (state === undefined) return WorkspaceService.create(featureId, features)
    try {
      const restored = WorkspaceService.update(WorkspaceService.create(featureId, features), {
        goal: state.goal, summary: state.summary, tasks: state.tasks, artifacts: state.artifacts })
      restored.updatedAt = Number.isFinite(state.updatedAt) ? state.updatedAt : 0
      restored.interactions = InteractionService.restore(state.interactions)
      return restored
    } catch (_error) {
      const fallback = WorkspaceService.create(featureId, features)
      fallback.interactions = InteractionService.restore(state.interactions)
      return fallback
    }
  }

  static snapshot(featureId: string, state: WorkspaceState, features: FeatureDefinition[] = FEATURE_CATALOG, includeInteractions: boolean = true): string {
    const profile = WorkspaceConfig.profile(featureId, features)
    const snapshot: WorkspaceSnapshot = { featureId: featureId, name: profile.name, role: profile.role, instruction: profile.instruction,
      state: WorkspaceService.copy(state), workspaces: features.filter((item: FeatureDefinition) => item.id !== 'trash')
        .map((item): WorkspaceOption => ({ id: item.id, name: item.name, description: item.description })) }
    if (!includeInteractions) snapshot.state.interactions = undefined
    else {
      const sources: Record<string, string> = { 'memory-summary': state.summary }
      state.artifacts.forEach((artifact: WorkspaceArtifact) => { sources[`artifact-${artifact.id}`] = artifact.content })
      snapshot.state.interactions = InteractionService.snapshotRecords(state.interactions, sources)
    }
    return JSON.stringify(snapshot)
  }

  static tools(features: FeatureDefinition[] = FEATURE_CATALOG): AgentToolDefinition[] {
    const tools = JSON.parse(`[
      {"type":"function","function":{"name":"read_workspace","description":"读取当前工作区、任务面板和已保存产物。","parameters":{"type":"object","properties":{},"additionalProperties":false}}},
      {"type":"function","function":{"name":"update_task_panel","description":"根据用户请求更新右侧任务面板并保存到当前会话。tasks、artifacts 提供时为完整替换，必须保留仍需保留的旧条目；未提供的字段保持原值。保存草稿不表示现实任务已完成。","parameters":{"type":"object","properties":{
        "goal":{"type":"string","description":"当前目标，最多500字"},"summary":{"type":"string","description":"已确认事实与当前进展，最多3000字"},
        "tasks":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"detail":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]}},"required":["id","title","status"],"additionalProperties":false}},
        "artifacts":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"content":{"type":"string","description":"用户可见的Markdown产物"}},"required":["id","title","content"],"additionalProperties":false}}
      },"additionalProperties":false}}},
      {"type":"function","function":{"name":"switch_workspace","description":"用户要求或当前目标适合专门工作区时切换。保留当前对话、目标、摘要和产物，更换任务模板；后续按返回的新角色要求处理。不要来回切换。","parameters":{"type":"object","properties":{"featureId":{"type":"string","enum":["home","career","schedule","budget","forms","focus","health","weather","study"]}},"required":["featureId"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"run_workspace_action","description":"按用户请求调用当前工作区已有业务适配器，只能根据实际返回结果判断成功。未接入服务会返回失败。","parameters":{"type":"object","properties":{"action":{"type":"string"},"input":{"type":"string"}},"required":["action","input"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"focus_lock","description":"在自律魔方工作区中开启、解除或查询鸿蒙健康使用设备的专注锁。仅在用户明确要求锁机、专注或限制其他应用时调用；开始时会拉起系统授权页和应用白名单选择器。只有工具返回 ok:true 才能声称设备锁已生效。","parameters":{"type":"object","properties":{"action":{"type":"string","enum":["start","stop","status"]},"durationMinutes":{"type":"integer","description":"专注时长，1-1440 分钟；action=start 时必填"},"useWhitelist":{"type":"boolean","description":"是否打开系统应用选择器确认白名单，默认 true"}},"required":["action"],"additionalProperties":false}}}
    ]`) as AgentToolDefinition[]
    const parameters = tools[2].function.parameters.properties
    if (parameters !== undefined) parameters['featureId'].enum = features.filter((item: FeatureDefinition) => item.id !== 'trash').map((item: FeatureDefinition) => item.id)
    return tools
  }

  private static text(value: string, limit: number): string {
    if (typeof value !== 'string' || value.length > limit) throw new Error('字段类型不正确或内容过长。')
    return value.trim()
  }

  static update(state: WorkspaceState, patch: WorkspaceUpdate): WorkspaceState {
    const next = WorkspaceService.copy(state)
    if (patch.goal === undefined && patch.summary === undefined && patch.tasks === undefined && patch.artifacts === undefined) {
      throw new Error('没有提供任务面板更新内容。')
    }
    if (patch.goal !== undefined) next.goal = WorkspaceService.text(patch.goal, 500)
    if (patch.summary !== undefined) next.summary = WorkspaceService.text(patch.summary, 3000)
    if (patch.tasks !== undefined) {
      if (!Array.isArray(patch.tasks) || patch.tasks.length > 12) throw new Error('任务数量不能超过12项。')
      const ids = new Set<string>()
      next.tasks = patch.tasks.map((task: WorkspaceTask): WorkspaceTask => {
        if (task === null || typeof task !== 'object') throw new Error('任务格式不正确。')
        const id = WorkspaceService.text(task.id, 80)
        const title = WorkspaceService.text(task.title, 120)
        if (!id || !title || ids.has(id) || !['pending', 'in_progress', 'completed'].includes(task.status)) throw new Error('任务ID、标题或状态不正确。')
        ids.add(id)
        return { id: id, title: title, detail: WorkspaceService.text(task.detail === undefined ? '' : task.detail, 1000), status: task.status }
      })
    }
    if (patch.artifacts !== undefined) {
      if (!Array.isArray(patch.artifacts) || patch.artifacts.length > 8) throw new Error('产物数量不能超过8项。')
      const ids = new Set<string>()
      next.artifacts = patch.artifacts.map((item: WorkspaceArtifact): WorkspaceArtifact => {
        if (item === null || typeof item !== 'object') throw new Error('产物格式不正确。')
        const id = WorkspaceService.text(item.id, 80)
        const title = WorkspaceService.text(item.title, 120)
        const content = WorkspaceService.text(item.content, 12000)
        if (!id || !title || !content || ids.has(id)) throw new Error('产物ID、标题或正文不正确。')
        ids.add(id)
        return { id: id, title: title, content: content }
      })
      if (JSON.stringify(next.artifacts).length > 30000) throw new Error('产物总量过大，请精简后保存。')
    }
    next.updatedAt = Date.now()
    return next
  }

  static applyTool(name: string, argumentsText: string, featureId: string, state: WorkspaceState,
    features: FeatureDefinition[] = FEATURE_CATALOG): WorkspaceToolResult {
    if (featureId === 'trash') throw new Error('请先恢复会话，再继续对话。')
    if (argumentsText.length > 40000) throw new Error('工具参数过长。')
    const args = JSON.parse(argumentsText || '{}') as WorkspaceUpdate
    if (args === null || typeof args !== 'object' || Array.isArray(args)) throw new Error('工具参数必须是对象。')
    if (name === 'read_workspace') return { featureId: featureId, state: WorkspaceService.copy(state), message: '已读取当前任务面板。' }
    if (name === 'update_task_panel') return { featureId: featureId, state: WorkspaceService.update(state, args), message: '任务面板已更新并保存在当前会话。' }
    if (name === 'switch_workspace') {
      if (args.featureId === 'trash' || !features.some((feature: FeatureDefinition) => feature.id === args.featureId)) throw new Error('目标分区不存在，保留当前会话；不自动创建分区。')
      const target = args.featureId as string
      const next = target === featureId ? WorkspaceService.copy(state) : WorkspaceService.create(target, features)
      next.goal = state.goal
      next.summary = state.summary
      next.artifacts = WorkspaceService.copy(state).artifacts
      next.interactions = InteractionService.restore(state.interactions)
      next.updatedAt = Date.now()
      return { featureId: target, state: next, message: `已归入${WorkspaceConfig.profile(target, features).name}，保留对话和产物。` }
    }
    if (name === 'focus_lock') {
      if (featureId !== 'focus') throw new Error('请先切换到“自律魔方”工作区，再使用设备专注锁。')
      if (args.action === 'start') {
        const minutes = typeof args.durationMinutes === 'number' ? Math.round(args.durationMinutes) : 0
        if (minutes < 1 || minutes > 1440) throw new Error('专注时长需在 1-1440 分钟之间。')
        return {
          featureId: 'focus', state: WorkspaceService.copy(state), message: '等待设备专注锁结果。',
          action: 'start', input: JSON.stringify({ durationMinutes: minutes, useWhitelist: args.useWhitelist !== false })
        }
      }
      if (args.action === 'stop') {
        return { featureId: 'focus', state: WorkspaceService.copy(state), message: '等待解除设备专注锁。', action: 'stop', input: '' }
      }
      if (args.action === 'status') {
        return { featureId: 'focus', state: WorkspaceService.copy(state), message: '等待设备专注锁状态。', action: 'status', input: '' }
      }
      throw new Error('action 必须是 start、stop 或 status。')
    }
    if (name === 'run_workspace_action') {
      const action = WorkspaceService.text(args.action as string, 80)
      const allowed = featureId === 'forms' ? ['templates', 'draft', 'export'] : featureId === 'study'
        ? ['timetable', 'reminders', 'plan', 'checkin']
        : featureId === 'focus' ? ['connect', 'start', 'stop', 'status', 'nfc', 'lock', 'interrupt', 'hardware-status'] : []
      if (!allowed.includes(action)) throw new Error('当前工作区不支持该业务操作。')
      return { featureId: featureId, state: WorkspaceService.copy(state), message: '等待业务服务结果。', action: action,
        input: WorkspaceService.text(args.input === undefined ? '' : args.input, 4000) }
    }
    throw new Error('不支持的工具。')
  }
}

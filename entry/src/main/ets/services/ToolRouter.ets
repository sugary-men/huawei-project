import { AgentToolCall, WorkspaceArtifact, WorkspaceToolResult } from '../models/WorkspaceModels'
import { ModuleItem, ModuleResult } from '../models/IntegrationModels'
import { ToolContext, ToolDescriptor, ToolExecution, ToolReceipt } from '../models/ToolModels'
import { ToolRegistry } from './ToolRegistry'
import { ToolValidator } from './ToolValidator'
import { WorkspaceService } from './WorkspaceService'

// 统一分发：结构校验 → 分类执行 → 回执归一化。系统能力由上下文注入，页面只负责落盘和提示。
// 不在此处设置墙钟超时：等待用户核对或系统授权不是网络延迟，模型超时由页面在工具执行期间暂停。
export class ToolRouter {
  static readonly maximumOutput: number = 24000

  static async execute(call: AgentToolCall, context: ToolContext): Promise<ToolExecution> {
    let descriptor: ToolDescriptor | undefined = undefined
    try {
      descriptor = ToolRegistry.descriptor(call.name, context.features)
    } catch (error) {
      return ToolRouter.failure((error as Error).message || '工具注册信息不完整。')
    }
    if (descriptor === undefined) return ToolRouter.failure('不支持的工具。')
    if (!context.isActive()) return ToolRouter.cancelled('会话已切换或生成已停止。')
    try {
      ToolValidator.validate(descriptor, call.arguments)
    } catch (error) {
      return ToolRouter.failure((error as Error).message || '工具参数不正确。')
    }
    try {
      return await ToolRouter.dispatch(call, descriptor, context)
    } catch (error) {
      // 注入的系统能力抛错时同样返回可核对回执，不让异常穿出到页面的生成流程。
      return ToolRouter.failure((error as Error).message || '工具操作失败。')
    }
  }

  private static async dispatch(call: AgentToolCall, descriptor: ToolDescriptor, context: ToolContext): Promise<ToolExecution> {
    if (descriptor.category === 'schedule') {
      if (context.schedule === undefined) return ToolRouter.failure('系统日程服务尚未初始化。')
      return ToolRouter.receipt(await context.schedule(call, context.isActive, context.confirm), descriptor.category)
    }
    if (descriptor.category === 'agentTask') {
      if (context.agentTask === undefined) return ToolRouter.failure('Agent定时任务服务尚未初始化。')
      return ToolRouter.receipt(await context.agentTask(call, context.isActive, context.confirm), descriptor.category)
    }
    if (descriptor.category === 'study') {
      if (context.study === undefined) return ToolRouter.failure('学习课程服务尚未初始化。')
      return ToolRouter.receipt(await context.study(call, context.isActive, context.confirm), descriptor.category)
    }
    if (descriptor.category !== 'workspace') return ToolRouter.failure('不支持的工具。')
    const result = WorkspaceService.applyTool(call.name, call.arguments, context.featureId, context.workspace, context.features)
    if (result.action !== undefined) return await ToolRouter.module(result, context)
    if (!context.isActive()) return ToolRouter.cancelled('生成已停止。')
    const output = JSON.stringify({ ok: true, message: result.message,
      workspace: WorkspaceService.snapshot(result.featureId, result.state, context.features) })
    // 读取面板不产生变更，页面无需落盘；其余工作区工具返回可保存的面板状态。
    return { output: ToolRouter.cap(output), ok: true, cancelled: false, message: result.message,
      workspace: call.name === 'read_workspace' ? undefined : result }
  }

  private static async module(result: WorkspaceToolResult, context: ToolContext): Promise<ToolExecution> {
    if (context.module === undefined) return ToolRouter.failure('业务服务尚未初始化。')
    const action = result.action === undefined ? '' : result.action
    const moduleResult: ModuleResult = await context.module(result.featureId, action, result.input === undefined ? '' : result.input)
    if (!context.isActive()) return ToolRouter.cancelled('操作结果已过期，不再更新当前会话。')
    if (!moduleResult.ok) {
      return { output: JSON.stringify({ ok: false, message: moduleResult.message }), ok: false, cancelled: false,
        message: moduleResult.message, moduleNotice: moduleResult.message, moduleItems: [] }
    }
    const id = `module-${result.featureId}-${action}`
    const artifacts: WorkspaceArtifact[] = result.state.artifacts.filter((item: WorkspaceArtifact) => item.id !== id)
    if (artifacts.length < 8) {
      const detail = moduleResult.items.map((item: ModuleItem): string => `### ${item.title}\n${item.detail}`).join('\n\n')
      artifacts.push({ id: id, title: `工具结果 · ${action}`, content: `${moduleResult.message}\n\n${detail}`.slice(0, 12000) })
    }
    const state = WorkspaceService.update(result.state, { summary: moduleResult.message.slice(0, 3000), artifacts: artifacts })
    const next: WorkspaceToolResult = { featureId: result.featureId, state: state, message: moduleResult.message }
    const output = JSON.stringify({ ok: true, message: moduleResult.message,
      workspace: WorkspaceService.snapshot(result.featureId, state, context.features) })
    return { output: ToolRouter.cap(output), ok: true, cancelled: false, message: moduleResult.message, workspace: next,
      moduleNotice: moduleResult.message, moduleItems: moduleResult.items }
  }

  private static receipt(output: string, category: string): ToolExecution {
    let parsed: ToolReceipt | undefined = undefined
    try {
      parsed = JSON.parse(output) as ToolReceipt
    } catch (_error) {
      parsed = undefined
    }
    if (parsed === undefined || parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return ToolRouter.failure('工具返回格式无法识别，未确认执行结果。')
    }
    const ok = parsed.ok === true
    const cancelled = !ok && parsed.status === 'cancelled'
    const reported = typeof parsed.message === 'string' ? parsed.message : ''
    const message = reported.length > 0 ? reported : ok ? '工具执行完成。' : '工具没有确认成功。'
    const execution: ToolExecution = { output: ToolRouter.cap(output), ok: ok, cancelled: cancelled, message: message }
    // 系统工具的真实回执同时作为页面提示；失败和取消照实显示，不伪装成完成。
    if (category === 'schedule') execution.moduleNotice = message
    return execution
  }

  private static failure(message: string): ToolExecution {
    const text = message.length > 0 ? message : '工具操作失败。'
    return { output: JSON.stringify({ ok: false, message: text }), ok: false, cancelled: false, message: text }
  }

  private static cancelled(message: string): ToolExecution {
    return { output: JSON.stringify({ ok: false, status: 'cancelled', message: message }), ok: false, cancelled: true, message: message }
  }

  // 超长回执会挤占上下文，保留可核对的原回执结论与截断说明，不静默丢弃成功事实。
  private static cap(output: string): string {
    if (output.length <= ToolRouter.maximumOutput) return output
    let ok = false
    let status: string | undefined = undefined
    let reported = ''
    try {
      const parsed = JSON.parse(output) as ToolReceipt
      ok = parsed.ok === true
      status = parsed.status
      reported = typeof parsed.message === 'string' ? parsed.message.slice(0, 2000) : ''
    } catch (_error) {
      reported = ''
    }
    const note = reported.length > 0 ? `${reported}\n\n（工具结果过长，已省略其余内容。）` : '工具返回内容过长，已省略详细结果。'
    return status === undefined ? JSON.stringify({ ok: ok, message: note })
      : JSON.stringify({ ok: ok, status: status, message: note })
  }
}
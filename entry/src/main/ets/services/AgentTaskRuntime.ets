import { common } from '@kit.AbilityKit'
import { workScheduler } from '@kit.BackgroundTasksKit'
import { AgentTask } from '../models/AgentTaskModels'
import { AgentGateway, StreamSink } from '../models/IntegrationModels'
import { AgentToolCall } from '../models/WorkspaceModels'
import { AgentTaskStore } from './AgentTaskStore'
import { ChatService } from './ChatService'
import { LibraryService } from './LibraryService'
import { RagService } from './RagService'
import { LocalAgentConfigService } from './LocalAgentConfigService'
import { LlmClient } from './LlmClient'
import { AgentCandidates } from './AgentCandidates'
import { ScheduleService } from './ScheduleService'
import { ToolRegistry } from './ToolRegistry'
import { StudyToolService } from './StudyToolService'
import { IntegrationService } from './IntegrationService'
import { HarmonyScheduleAdapter } from './HarmonyScheduleAdapter'

class TaskSink implements StreamSink {
  private active: () => boolean
  private append: (delta: string) => void
  constructor(active: () => boolean, append: (delta: string) => void) { this.active = active; this.append = append }
  isCancelled(): boolean { return !this.active() }
  onDelta(delta: string): void { if (this.active()) this.append(delta) }
}

export class AgentTaskRuntime {
  static readonly workId: number = 6101
  static backgroundNotice: string = '后台由系统择机执行，可能延迟；打开应用后会补执行到期任务。'
  private static timer: number = -1
  private static gateway: AgentGateway | undefined = undefined
  private static current: AgentTask | undefined = undefined
  private static stopped: boolean = false

  static work(context: common.Context): workScheduler.WorkInfo {
    return { workId: AgentTaskRuntime.workId, bundleName: context.applicationInfo.name, abilityName: 'AgentTaskAbility',
      isPersisted: true, networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY, isRepeat: true, repeatCycleTime: 7200000 }
  }
  static async register(context: common.Context): Promise<void> {
    try {
      const store = new AgentTaskStore(context.filesDir)
      const enabled = store.list().some((task: AgentTask) => task.enabled)
      let registered = false
      try { registered = (await workScheduler.obtainAllWorks()).some((work) => work.workId === AgentTaskRuntime.workId) } catch (_error) {}
      if (enabled && !registered) workScheduler.startWork(AgentTaskRuntime.work(context))
      if (!enabled && registered) workScheduler.stopWork(AgentTaskRuntime.work(context), true)
      AgentTaskRuntime.backgroundNotice = enabled ? '已申请系统后台调度；系统可能延迟，打开应用会补执行到期任务。' : '任务启用后会申请系统后台调度；打开应用可按时执行。'
    } catch (_error) { AgentTaskRuntime.backgroundNotice = '本设备未接受后台调度，任务将在应用打开时执行。' }
  }
  static foreground(context: common.Context): void {
    clearInterval(AgentTaskRuntime.timer)
    AgentTaskRuntime.stopped = false
    AgentTaskRuntime.register(context)
    AgentTaskRuntime.drain(context).catch(() => {})
    AgentTaskRuntime.timer = setInterval(() => AgentTaskRuntime.drain(context).catch(() => {}), 15000)
  }
  static background(): void { clearInterval(AgentTaskRuntime.timer); AgentTaskRuntime.timer = -1; AgentTaskRuntime.cancel() }
  static cancel(id?: string): void {
    if (id && AgentTaskRuntime.current?.id !== id) return
    AgentTaskRuntime.stopped = true; AgentTaskRuntime.gateway?.cancel()
  }
  static async drain(context: common.Context): Promise<void> {
    if (AgentTaskRuntime.current !== undefined) return
    const tasks = new AgentTaskStore(context.filesDir).list()
    const task = tasks.find((item: AgentTask) => (item.enabled && item.nextRunAt <= Date.now()) || (item.runId && Date.now() - item.runningSince > 180000))
    if (task !== undefined) await AgentTaskRuntime.run(context, task.id)
  }
  static async run(context: common.Context, id: string, manual: boolean = false): Promise<void> {
    if (AgentTaskRuntime.current !== undefined) throw new Error('已有Agent任务正在执行，请稍后。')
    const store = new AgentTaskStore(context.filesDir)
    const task = store.claim(id, manual)
    if (task === undefined) return
    AgentTaskRuntime.current = task; AgentTaskRuntime.stopped = false
    let output = '', status = 'success'
    const active = (): boolean => !AgentTaskRuntime.stopped
    const timeout = setTimeout(() => AgentTaskRuntime.cancel(task.id), 85000)
    const check = setInterval(() => {
      try { if (!store.active(task.id, task.runId)) AgentTaskRuntime.cancel(task.id) } catch (_error) { AgentTaskRuntime.cancel(task.id) }
    }, 1000)
    try {
      const settings = await LocalAgentConfigService.load(context)
      if (!settings || !settings.baseUrl || !settings.model) throw new Error('请先配置可用的模型API，再运行任务。')
      const library = new LibraryService(context.filesDir)
      const retrieval = await new RagService(library).search(task.prompt)
      if (!active()) throw new Error('任务已停止。')
      const native = new HarmonyScheduleAdapter(context, false)
      const request = ChatService.request(task.prompt, 'home', [], retrieval)
      request.systemInstruction += '\n这是用户创建的定时任务，只能读取已授权的日历、时间、提醒、备忘录和资料，生成结果。不能新增/修改/删除任何系统数据，不得声称已执行写操作。结果会保存在任务记录供用户查看。'
      request.tools = ToolRegistry.backgroundTools()
      const memo = request.tools.find((tool) => tool.function.name === 'manage_memo')
      if (memo?.function.parameters.properties) memo.function.parameters.properties['action'].enum = ['list', 'read']
      const study = request.tools.find((tool) => tool.function.name === 'manage_study')
      if (study?.function.parameters.properties) study.function.parameters.properties['action'].enum = ['summary', 'timetable', 'list_tasks']
      request.executeTool = async (call: AgentToolCall): Promise<string> => {
        if (!request.tools!.some((tool) => tool.function.name === call.name)) return JSON.stringify({ ok: false, message: '定时任务只允许读取。' })
        if (call.name === 'manage_memo') {
          const args = ScheduleService.validate(call.name, call.arguments)
          if (!['list', 'read'].includes(args.action || '')) return JSON.stringify({ ok: false, message: '定时任务不能修改备忘录。' })
        }
        if (call.name === 'manage_study') {
          const args = JSON.parse(call.arguments) as Record<string, Object>
          if (!['summary', 'timetable', 'list_tasks'].includes(String(args['action']))) {
            return JSON.stringify({ ok: false, message: '定时任务只能查看学习数据。' })
          }
          return await StudyToolService.execute(call, IntegrationService.studyStore, active, async () => false)
        }
        return JSON.stringify(await ScheduleService.execute(call, native, active, async () => false))
      }
      const gateway = new LlmClient(AgentCandidates.build(await LocalAgentConfigService.loadProfiles(context)))
      AgentTaskRuntime.gateway = gateway
      await gateway.generate(request, new TaskSink(active, (delta: string) => { output = (output + delta).slice(0, 16000) }))
      if (!active()) { status = 'interrupted'; output = output ? `${output}\n\n执行已中断，以上为部分结果。` : '执行已停止或超时，没有完整结果。' }
      else if (!output.trim()) { status = 'failed'; output = '模型没有返回内容，请检查API后重试。' }
    } catch (error) { status = active() ? 'failed' : 'interrupted'; output = (error as Error).message || '执行失败，请检查网络和模型配置。' }
    finally {
      clearTimeout(timeout); clearInterval(check)
      AgentTaskRuntime.gateway = undefined; AgentTaskRuntime.current = undefined
      store.finish(task, status, output)
      AgentTaskRuntime.register(context)
    }
  }
}

import { AgentGateway, StreamSink } from '../models/IntegrationModels'
import { AgentToolCall } from '../models/WorkspaceModels'
import { RetrievalResult, SourceCitation } from '../models/RagModels'
import { AgentOrchestratorOptions, AgentTurnInput, AgentTurnObserver, AgentTurnResult, AgentTurnState } from '../models/AgentTurnModels'
import { ApiConfig } from '../config/ApiConfig'
import { ChatService } from './ChatService'
import { RagService } from './RagService'
import { ToolRegistry } from './ToolRegistry'

// ArkTS 不允许用对象字面量实现纯函数属性接口，流式回调以类实现绑定回合令牌。
class OrchestratorSink implements StreamSink {
  private owner: AgentOrchestrator
  private serial: number
  constructor(owner: AgentOrchestrator, serial: number) {
    this.owner = owner
    this.serial = serial
  }
  isCancelled(): boolean { return this.owner.cancelled(this.serial) }
  onDelta(delta: string): void { this.owner.receive(delta, this.serial) }
  onProgress(phase: string): void { this.owner.notifyProgress(phase, this.serial) }
  onNotice(text: string): void { this.owner.notifyNotice(text, this.serial) }
}

// 一个回合的状态机：检索 → 连接 → 生成/工具 → 终态。取消、超时与工具等待都由这里统一判定，
// 页面只订阅阶段变化并渲染，不再各自维护 token、计时器和等待标记。
export class AgentOrchestrator {
  private gateway: AgentGateway
  private rag: RagService
  private observer: AgentTurnObserver
  private executeTool: (call: AgentToolCall) => Promise<string>
  private timeoutMs: number
  private intervalMs: number
  private graceMs: number
  private blocks: (name: string) => boolean

  private serial: number = 0
  private active: boolean = false
  private state: string = AgentTurnState.idle
  private detail: string = ''
  private content: string = ''
  private sources: SourceCitation[] = []
  private calls: number = 0
  private startedAt: number = 0
  private deadline: number = 0
  private timer: number = -1
  private suspended: boolean = false
  private stopped: boolean = false
  private stopReason: string = ''
  private timedOut: boolean = false
  private failure: string = ''
  private notified: boolean = false
  private release: (() => void) | undefined = undefined

  constructor(gateway: AgentGateway, rag: RagService, observer: AgentTurnObserver,
    executeTool: (call: AgentToolCall) => Promise<string>, options?: AgentOrchestratorOptions) {
    this.gateway = gateway
    this.rag = rag
    this.observer = observer
    this.executeTool = executeTool
    const settings: AgentOrchestratorOptions = options === undefined ? {} : options
    this.timeoutMs = settings.timeoutMs === undefined ? ApiConfig.requestTimeoutMs : settings.timeoutMs
    this.intervalMs = settings.intervalMs === undefined ? 1000 : settings.intervalMs
    this.graceMs = settings.graceMs === undefined ? 3000 : settings.graceMs
    this.blocks = settings.blocksTimeout === undefined ? ToolRegistry.blocksTimeout : settings.blocksTimeout
  }

  phase(): string { return this.state }
  isActive(): boolean { return this.active }
  current(): string { return this.content }
  toolCalls(): number { return this.calls }

  // 取消当前回合：令牌先失效，再销毁请求，最后通知等待中的 run() 立即返回。
  stop(reason: string = '已停止生成。'): void {
    this.serial++
    const wasActive = this.active
    this.active = false
    this.stopped = true
    this.stopReason = reason
    this.notified = wasActive
    this.clearTimer()
    AgentOrchestrator.destroy(this.gateway)
    this.releaseWait()
    if (wasActive) this.transition(AgentTurnState.cancelled, reason)
  }

  async run(input: AgentTurnInput): Promise<AgentTurnResult> {
    const serial = ++this.serial
    this.active = true
    this.state = AgentTurnState.idle
    this.detail = ''
    this.content = ''
    this.sources = []
    this.calls = 0
    this.startedAt = Date.now()
    this.deadline = this.startedAt + this.timeoutMs + this.graceMs
    this.suspended = false
    this.stopped = false
    this.stopReason = ''
    this.timedOut = false
    this.failure = ''
    this.notified = false
    const aborted = new Promise<void>((resolve: () => void): void => { this.release = (): void => resolve() })
    this.transition(AgentTurnState.retrieving, '正在检索资料')
    this.timer = setInterval(() => this.tick(serial), this.intervalMs)
    const sink: StreamSink = new OrchestratorSink(this, serial)
    const work: Promise<void> = ChatService.reply(input.prompt, input.featureId, input.history, input.retrievalOptions,
      this.rag, this.gateway, sink, (result: RetrievalResult): void => this.retrieved(result, serial),
      input.attachedSources, input.attachments, input.workspace,
      (call: AgentToolCall): Promise<string> => this.dispatch(call, serial), input.features, input.reviewContext)
      .then((): void => {}, (error: Error): void => {
        // 主动停止或超时的取消不算模型错误；HTTP 层先于截止时刻报超时时按超时处理。
        if (serial !== this.serial) return
        const message = error.message.length > 0 ? error.message : '连接模型服务失败，请检查配置和网络。'
        if (AgentOrchestrator.transportTimeout(message)) this.timedOut = true
        else this.failure = message
      })
    await Promise.race([work, aborted])
    this.clearTimer()
    this.active = false
    this.release = undefined
    const result = this.conclude()
    // 终态只更新内部状态，不再回调页面：页面按返回值渲染一次，避免重复写同一气泡。
    this.state = result.state
    return result
  }

  private conclude(): AgentTurnResult {
    const finishedAt = Date.now()
    let state = AgentTurnState.complete
    let reason = ''
    let empty = false
    if (this.timedOut) {
      state = AgentTurnState.failed
      reason = this.timeoutMessage()
    } else if (this.stopped) {
      state = AgentTurnState.cancelled
      reason = this.stopReason
    } else if (this.failure.length > 0) {
      state = AgentTurnState.failed
      reason = this.failure
    } else if (this.content.trim().length === 0) {
      state = AgentTurnState.failed
      empty = true
      reason = '服务未返回内容，请重试。'
    }
    return { state: state, content: this.content, sources: this.sources, calls: this.calls, reason: reason,
      startedAt: this.startedAt, finishedAt: finishedAt, empty: empty, timeout: this.timedOut, notified: this.notified }
  }

  // HTTP 客户端在读到超时后会先抛底层英文错误（如 Operation timeout），对外仍应是可理解的中文超时说明。
  private static transportTimeout(message: string): boolean {
    return /timeout|timed out|超时/i.test(message)
  }

  // 等待系统授权或用户核对期间不计入模型超时；其余时间按截止时刻判定。
  private tick(serial: number): void {
    if (serial !== this.serial) { this.clearTimer(); return }
    if (this.suspended) { this.deadline = Date.now() + this.timeoutMs + this.graceMs; return }
    if (Date.now() < this.deadline) return
    this.clearTimer()
    this.timedOut = true
    this.notified = true
    this.serial++
    this.active = false
    AgentOrchestrator.destroy(this.gateway)
    this.releaseWait()
    this.transition(AgentTurnState.failed, this.timeoutMessage())
  }

  private timeoutMessage(): string {
    return `等待 ${this.gateway.name} 返回超过 ${Math.round(this.timeoutMs / 1000)} 秒，请检查设备网络和模型服务后重试。`
  }

  // 供流式回调使用：令牌不匹配或回合已结束时立即判定为取消。
  cancelled(serial: number): boolean { return serial !== this.serial || !this.active }

  receive(delta: string, serial: number): void {
    if (serial !== this.serial) return
    this.content = (this.content + delta).slice(0, 16000)
    if (this.state !== AgentTurnState.answering) this.transition(AgentTurnState.answering, '')
    this.observer.onDelta(this.content)
  }

  notifyProgress(phase: string, serial: number): void {
    if (serial !== this.serial) return
    if (phase === 'analyzing' && this.content.length === 0 && this.state !== AgentTurnState.tool) {
      this.transition(AgentTurnState.analyzing, '')
    }
  }

  private retrieved(result: RetrievalResult, serial: number): void {
    if (serial !== this.serial) return
    this.sources = result.sources
    this.transition(AgentTurnState.connecting, '')
    this.observer.onRetrieved(result)
  }

  // 模型降级等过程说明只提示、不算终态，也不改变已生成内容。
  notifyNotice(text: string, serial: number): void {
    if (serial !== this.serial || !this.active) return
    if (this.observer.onNotice !== undefined) this.observer.onNotice(text)
  }

  private async dispatch(call: AgentToolCall, serial: number): Promise<string> {
    if (serial !== this.serial || !this.active) return JSON.stringify({ ok: false, status: 'cancelled', message: '生成已停止。' })
    this.calls++
    this.suspended = this.blocks(call.name)
    this.transition(AgentTurnState.tool, `正在执行${ToolRegistry.label(call.name)}`)
    try {
      return await this.executeTool(call)
    } finally {
      this.suspended = false
      if (this.active && this.state === AgentTurnState.tool) this.transition(AgentTurnState.analyzing, '')
    }
  }

  private transition(state: string, detail: string): void {
    this.state = state
    this.detail = detail
    this.observer.onPhase(state, detail)
  }

  private releaseWait(): void {
    const release = this.release
    this.release = undefined
    if (release !== undefined) release()
  }

  private clearTimer(): void {
    if (this.timer < 0) return
    clearInterval(this.timer)
    this.timer = -1
  }

  private static destroy(gateway: AgentGateway): void {
    try {
      gateway.cancel()
    } catch (_error) {
      // 已经销毁的请求再次取消不应打断状态迁移。
    }
  }
}
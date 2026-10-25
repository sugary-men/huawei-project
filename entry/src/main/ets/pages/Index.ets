import { FEATURE_CATALOG } from '../config/FeatureCatalog'
import { ActionItem, AgentMessage, FeatureDefinition } from '../models/AppModels'
import { AgentService } from '../services/AgentService'
import { SessionService, ChatSession, SessionSummary } from '../services/SessionService'
import { ToolService } from '../services/ToolService'
import { KnowledgeChunk, RetrievalOptions, RetrievalResult, SourceCitation } from '../models/RagModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagConfig } from '../config/RagConfig'
import { demoKnowledgeIndex, MemoryKnowledgeRepository } from '../services/KnowledgeService'
import { ChatService } from '../services/ChatService'
import { AgentGateway, StreamSink, ModuleAdapter, ModuleItem, ModuleResult, VoiceObserver } from '../models/IntegrationModels'
import { ApiConfig } from '../config/ApiConfig'
import { common } from '@kit.AbilityKit'
import { LocalAgentConfigService } from '../services/LocalAgentConfigService'
import { AgentAnswer } from '../components/AgentAnswer'
import { AttachmentService } from '../services/AttachmentService'
import { ChatAttachment } from '../models/AttachmentModels'
import { MarkdownParser } from '../services/MarkdownParser'

class ChatStreamSink implements StreamSink {
  private cancelled: () => boolean
  private receive: (delta: string) => void
  private progress: (phase: string) => void
  constructor(cancelled: () => boolean, receive: (delta: string) => void, progress: (phase: string) => void) {
    this.cancelled = cancelled
    this.receive = receive
    this.progress = progress
  }
  isCancelled(): boolean { return this.cancelled() }
  onDelta(delta: string): void { this.receive(delta) }
  onProgress(phase: string): void { this.progress(phase) }
}

class ChatVoiceObserver implements VoiceObserver {
  private partial: (text: string) => void
  private complete: (text: string) => void
  private error: (message: string) => void
  constructor(partial: (text: string) => void, complete: (text: string) => void, error: (message: string) => void) {
    this.partial = partial
    this.complete = complete
    this.error = error
  }
  onPartial(text: string): void { this.partial(text) }
  onComplete(text: string): void { this.complete(text) }
  onError(message: string): void { this.error(message) }
}

@Entry
@Component
struct Index {
  @State activeFeature: string = 'home'
  @State activeSession: string = ''
  @State sessions: SessionSummary[] = []
  @State storageNotice: string = ''
  @State expandedThoughts: string[] = []
  @State draftAttachments: ChatAttachment[] = []
  @State attachmentBusy: boolean = false
  private importSerial: number = 0
  private voiceDraft: string = ''
  private voiceFinished: boolean = false
  @State inputText: string = ''
  @State thinking: boolean = false
  @State sideExpanded: boolean = true
  @State recentsExpanded: boolean = true
  @State isTaskPanelVisible: boolean = true
  @State isLeftPanelVisible: boolean = true
  @State progress: number = 1
  @State messages: AgentMessage[] = AgentService.greeting('home')
  @State knowledgeQuery: string = ''
  @State contextPickerVisible: boolean = false
  @State selectedContext: SourceCitation[] = []
  @State knowledgeCourse: string = ''
  @State knowledgeCourses: string[] = []
  @State knowledgeCount: number = 0
  @State knowledgeRevision: string = 'empty'
  @State retrieval: RetrievalResult = { query: '', revision: '', status: 'empty', mode: 'keyword', notice: '', sources: [], context: '' }
  @State searchBusy: boolean = false
  @State expandedSourceId: string = ''
  @State notice: string = ''
  @State recording: boolean = false
  @State voiceBusy: boolean = false
  @State speaking: boolean = false
  @State actionBusy: boolean = false
  @State moduleNotice: string = ''
  @State moduleItems: ModuleItem[] = []
  @State moduleInput: string = ''
  @State apiSettingsVisible: boolean = false
  @State apiBaseUrl: string = ''
  @State apiModel: string = ''
  @State apiKey: string = ''
  @State apiConfigured: boolean = false
  @State apiNotice: string = ''
  private requestSerial: number = 0
  private searchSerial: number = 0
  private voiceSerial: number = 0
  private speechSerial: number = 0
  private actionSerial: number = 0
  private activeGateway: AgentGateway | undefined = undefined
  private readonly chatScroller: Scroller = new Scroller()
  private minScore: number = 0.20
  private topK: number = 4

  private selectedFeature(): FeatureDefinition {
    const feature = FEATURE_CATALOG.find((item: FeatureDefinition) => item.id === this.activeFeature)
    return feature === undefined ? FEATURE_CATALOG[0] : feature
  }

  aboutToAppear(): void {
    IntegrationService.initializeVoice(this.getUIContext().getHostContext() as common.UIAbilityContext)
    this.refreshKnowledge()
    const session = SessionService.current() || SessionService.create('home', '新对话', AgentService.greeting('home'))
    this.restoreSession(session)
    this.apiBaseUrl = IntegrationService.agentSettings.baseUrl
    this.apiModel = IntegrationService.agentSettings.model
    this.apiKey = IntegrationService.agentSettings.apiKey
    this.apiConfigured = this.apiBaseUrl.length > 0 && this.apiModel.length > 0
    this.loadLocalAgentConfig()
  }

  private async loadLocalAgentConfig(): Promise<void> {
    if (IntegrationService.agentSettings.baseUrl.length > 0) return
    const settings = await LocalAgentConfigService.load(this.getUIContext().getHostContext() as common.UIAbilityContext)
    if (settings === undefined || IntegrationService.agentSettings.baseUrl.length > 0) return
    IntegrationService.configureAgent(settings)
    this.apiBaseUrl = settings.baseUrl
    this.apiModel = settings.model
    this.apiKey = settings.apiKey
    this.apiConfigured = true
    this.apiNotice = '已从本地配置文件加载模型设置。'
  }

  aboutToDisappear(): void {
    this.importSerial++
    this.stopReply()
    this.persistSession()
    this.searchSerial++
    this.actionSerial++
    this.cancelVoice()
    this.stopSpeech()
  }

  private refreshKnowledge(): void {
    const index = IntegrationService.knowledge.snapshot()
    this.knowledgeCount = index.chunks.length
    this.knowledgeRevision = index.revision
    this.knowledgeCourses = Array.from(new Set<string>(index.chunks.map((chunk: KnowledgeChunk): string => chunk.course)))
      .filter((course: string) => course.length > 0)
    if (this.knowledgeCourses.indexOf(this.knowledgeCourse) < 0) this.knowledgeCourse = ''
    this.searchSerial++
    this.searchBusy = false
    this.retrieval = { query: '', revision: index.revision, status: 'empty', mode: 'keyword', notice: '', sources: [], context: '' }
  }

  private loadDemoKnowledge(): void {
    if (this.knowledgeCount > 0) return
    const repository = new MemoryKnowledgeRepository()
    repository.replace(demoKnowledgeIndex())
    IntegrationService.knowledge = repository
    this.refreshKnowledge()
    this.notice = '已载入 5 段离线演示资料，非学校官方资料。'
  }

  private retrievalOptions(): RetrievalOptions {
    const options = RagConfig.defaults()
    options.course = this.knowledgeCourse
    options.topK = this.topK
    options.minScore = this.minScore
    return options
  }

  private saveAgentApi(): void {
    const baseUrl = this.apiBaseUrl.trim()
    const model = this.apiModel.trim()
    if (!baseUrl.startsWith('https://') && !baseUrl.startsWith('http://')) {
      this.apiNotice = '服务地址需以 https:// 或 http:// 开头。'
      return
    }
    if (model.length === 0) {
      this.apiNotice = '请填写模型名称，例如 qwen-plus 或 gpt-4o-mini。'
      return
    }
    IntegrationService.configureAgent({ baseUrl: baseUrl, model: model, apiKey: this.apiKey })
    this.apiConfigured = true
    this.apiNotice = '已保存配置。新发送的消息将由该模型生成。'
    this.apiSettingsVisible = false
    this.notice = '外部模型已配置；发送消息后会将问题、对话历史和已选资料发送到该服务。'
  }

  private toggleApiSettings(): void {
    this.apiNotice = ''
    this.apiSettingsVisible = !this.apiSettingsVisible
  }

  private async searchKnowledge(): Promise<void> {
    if (!this.knowledgeQuery.trim()) { this.notice = '请输入检索问题。'; return }
    const token = ++this.searchSerial
    this.searchBusy = true
    this.expandedSourceId = ''
    try {
      const result = await IntegrationService.rag().search(this.knowledgeQuery, this.retrievalOptions())
      if (token === this.searchSerial) { this.retrieval = result; this.notice = result.notice }
    } catch (error) {
      if (token === this.searchSerial) this.notice = '检索服务暂不可用，请刷新资料后重试。'
    } finally {
      if (token === this.searchSerial) this.searchBusy = false
    }
  }

  private showCitation(source: SourceCitation): void {
    this.expandedSourceId = this.expandedSourceId === source.chunkId ? '' : source.chunkId
  }

  private toggleContextSource(source: SourceCitation): void {
    const exists = this.selectedContext.some((item: SourceCitation) => item.chunkId === source.chunkId)
    this.selectedContext = exists
      ? this.selectedContext.filter((item: SourceCitation) => item.chunkId !== source.chunkId)
      : [...this.selectedContext, source]
    this.persistSession()
  }

  private toggleContextPicker(): void {
    this.contextPickerVisible = !this.contextPickerVisible
  }

  private async runModule(action: string): Promise<void> {
    if (this.actionBusy) return
    const token = ++this.actionSerial
    this.actionBusy = true
    this.moduleNotice = '正在处理…'
    let adapter: ModuleAdapter = IntegrationService.forms
    if (this.activeFeature === 'study') adapter = IntegrationService.study
    if (this.activeFeature === 'focus') adapter = IntegrationService.hardware
    try {
      const result: ModuleResult = await adapter.execute(action, this.moduleInput.trim())
      if (token === this.actionSerial) {
        this.moduleNotice = result.message
        this.moduleItems = result.ok ? result.items : []
      }
    } catch (error) {
      if (token === this.actionSerial) { this.moduleNotice = '操作失败，请重试。'; this.moduleItems = [] }
    } finally {
      if (token === this.actionSerial) this.actionBusy = false
    }
  }

  private cancelVoice(): void {
    this.voiceSerial++
    if (this.recording || this.voiceBusy) {
      this.recording = false
      this.voiceBusy = false
      IntegrationService.voice.cancel().catch(() => {})
    }
  }

  private async pickAttachments(photos: boolean): Promise<void> {
    if (this.thinking || this.recording || this.voiceBusy || this.attachmentBusy) return
    const token = ++this.importSerial
    const session = this.activeSession
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.attachmentBusy = true
    try {
      const files = await AttachmentService.pick(context, photos, AttachmentService.maxFiles - this.draftAttachments.length)
      if (token !== this.importSerial || session !== this.activeSession) {
        files.forEach((item: ChatAttachment) => AttachmentService.removeDraft(item, context.filesDir))
        return
      }
      this.draftAttachments = [...this.draftAttachments, ...files]
      if (files.length > 0) this.notice = files.some((item: ChatAttachment) => item.truncated)
        ? '附件已添加。较长文档将只提供前 12000 个字符给模型。'
        : files.some((item: ChatAttachment) => item.kind === 'image') ? '图片已添加，发送后由当前模型处理；图片理解需要模型支持视觉。' : '附件已添加，发送后模型可读取其文字。'
    } catch (error) {
      if (token === this.importSerial) this.notice = (error as Error).message || '附件导入失败，请重新选择。'
    } finally { if (token === this.importSerial) this.attachmentBusy = false }
  }

  private removeAttachment(id: string): void {
    const attachment = this.draftAttachments.find((item: ChatAttachment) => item.id === id)
    if (attachment === undefined) return
    AttachmentService.removeDraft(attachment, (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir)
    this.draftAttachments = this.draftAttachments.filter((item: ChatAttachment) => item.id !== id)
  }

  private async toggleVoice(): Promise<void> {
    if (this.voiceBusy || this.thinking || this.attachmentBusy) return
    const token = this.recording ? this.voiceSerial : ++this.voiceSerial
    const stopping = this.recording
    this.voiceBusy = true
    try {
      if (stopping) {
        const transcript = await IntegrationService.voice.stop()
        if (token === this.voiceSerial) {
          this.recording = false
          this.inputText = `${this.voiceDraft}${this.voiceDraft && transcript ? ' ' : ''}${transcript}`.slice(0, 4000)
          this.notice = transcript ? '识别完成，请核对后再发送。' : '未识别到文字，请重试。'
        }
      } else {
        this.stopSpeech()
        this.voiceDraft = this.inputText
        this.voiceFinished = false
        const uiContext = this.getUIContext()
        const observer: VoiceObserver = new ChatVoiceObserver((text: string): void => {
            uiContext.runScopedTask(() => {
              if (token === this.voiceSerial) this.inputText = `${this.voiceDraft}${this.voiceDraft && text ? ' ' : ''}${text}`.slice(0, 4000)
            })
          },
          (text: string): void => {
            uiContext.runScopedTask(() => {
              if (token !== this.voiceSerial) return
              this.voiceFinished = true
              this.inputText = `${this.voiceDraft}${this.voiceDraft && text ? ' ' : ''}${text}`.slice(0, 4000)
              this.recording = false
              this.voiceBusy = false
              this.notice = text ? '识别完成，请核对后再发送。' : '未识别到文字，请靠近麦克风重试。'
            })
          },
          (message: string): void => {
            uiContext.runScopedTask(() => {
              if (token === this.voiceSerial) { this.voiceFinished = true; this.recording = false; this.voiceBusy = false; this.notice = message }
            })
          }
        )
        await IntegrationService.voice.start(observer)
        if (token === this.voiceSerial && !this.voiceFinished) { this.recording = true; this.notice = '录音中，结束后可以核对识别文字。' }
      }
    } catch (error) {
      if (token === this.voiceSerial) { this.recording = false; this.notice = (error as Error).message || '语音输入暂不可用。' }
    } finally {
      if (token === this.voiceSerial) this.voiceBusy = false
    }
  }

  private stopSpeech(): void {
    this.speechSerial++
    if (this.speaking) IntegrationService.voice.stopSpeaking().catch(() => {})
    this.speaking = false
  }

  private async toggleSpeech(content: string): Promise<void> {
    if (this.recording || this.voiceBusy) return
    if (this.speaking) { this.stopSpeech(); return }
    const token = ++this.speechSerial
    this.speaking = true
    const text = MarkdownParser.parse(MarkdownParser.answer(content).body).map((block) =>
      MarkdownParser.inline(block.text).map((run) => run.text).join('')).join('\n')
    try { await IntegrationService.voice.speak(text.slice(0, 8000)) }
    catch (error) { if (token === this.speechSerial) this.notice = (error as Error).message || '语音播报暂不可用。' }
    finally { if (token === this.speechSerial) this.speaking = false }
  }

  private stopReply(): void {
    this.requestSerial++
    if (!this.thinking) return
    this.activeGateway?.cancel()
    this.activeGateway = undefined
    const last = this.messages.length - 1
    this.updateReply(last, this.messages[last].content || '已停止生成。', '已停止', 'stopped', this.messages[last].sources || [])
    this.thinking = false
    SessionService.saveMessages(this.activeSession, this.messages)
  }

  private updateReply(position: number, content: string, meta: string, status: string, sources: SourceCitation[], phase: string = ''): void {
    this.messages = this.messages.map((item: AgentMessage, index: number): AgentMessage => index === position
      ? { role: 'agent', content: content, meta: meta, status: status, sources: sources,
        renderRevision: (item.renderRevision || 0) + 1, thinkingStartedAt: item.thinkingStartedAt,
        thinkingDurationMs: status === 'complete' || status === 'error' || status === 'stopped'
          ? (item.thinkingStartedAt === undefined ? undefined : Date.now() - item.thinkingStartedAt) : item.thinkingDurationMs,
        phase: phase || (status === 'streaming' ? 'answering' : item.phase) } : item)
    SessionService.saveMessages(this.activeSession, this.messages, false)
  }

  private toggleThought(position: number): void {
    const id = `${this.activeSession}-${position}`
    this.expandedThoughts = this.expandedThoughts.includes(id)
      ? this.expandedThoughts.filter((item: string) => item !== id) : [...this.expandedThoughts, id]
  }

  private persistSession(): void {
    SessionService.saveDetails(this.activeSession, this.selectedContext, this.progress)
    SessionService.saveMessages(this.activeSession, this.messages)
    this.sessions = SessionService.list()
    this.storageNotice = SessionService.storageNotice
  }

  private restoreSession(session: ChatSession): void {
    this.importSerial++
    this.attachmentBusy = false
    const filesDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir
    this.draftAttachments.forEach((item: ChatAttachment) => AttachmentService.removeDraft(item, filesDir))
    this.draftAttachments = []
    this.activeSession = session.id
    this.activeFeature = session.featureId
    this.messages = session.messages
    this.selectedContext = session.context
    this.progress = session.progress
    this.inputText = ''
    this.contextPickerVisible = false
    this.moduleInput = ''
    this.moduleItems = []
    this.moduleNotice = ''
    this.expandedSourceId = ''
    this.notice = ''
    SessionService.activate(session.id)
    this.sessions = SessionService.list()
    this.storageNotice = SessionService.storageNotice
    const sessionId = session.id
    setTimeout(() => {
      if (this.activeSession === sessionId) this.chatScroller.scrollEdge(Edge.Bottom)
    }, 50)
  }

  private steps(): ActionItem[] {
    if (this.activeFeature === 'forms') return ToolService.formSteps()
    if (this.activeFeature === 'focus') return ToolService.focusSteps()
    if (this.activeFeature === 'study') return ToolService.studySteps()
    if (this.activeFeature === 'schedule') return ToolService.scheduleSteps()
    if (this.activeFeature === 'budget') return ToolService.budgetSteps()
    return ToolService.careerSteps()
  }

  private chooseFeature(feature: FeatureDefinition): void {
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.actionSerial++
    this.actionBusy = false
    this.restoreSession(SessionService.latestForFeature(feature.id) ||
      SessionService.create(feature.id, feature.name, AgentService.greeting(feature.id)))
  }

  private openSession(session: string): void {
    if (session === this.activeSession) return
    const saved = SessionService.get(session)
    if (saved === undefined) return
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.actionSerial++
    this.actionBusy = false
    this.restoreSession(saved)
  }

  private sessionTime(timestamp: number): string {
    const date = new Date(timestamp)
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    const hour = `${date.getHours()}`.padStart(2, '0')
    const minute = `${date.getMinutes()}`.padStart(2, '0')
    return `${date.getFullYear()}/${month}/${day} ${hour}:${minute}`
  }

  private async confirmDeleteSession(id: string): Promise<void> {
    const session = SessionService.get(id)
    if (session === undefined) return
    let confirmed = false
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除会话',
        message: `删除“${session.title}”及其本地消息和附件？删除后无法撤销。`,
        buttons: [{ text: '取消', color: '#657165' }, { text: '删除', color: '#B34F42' }] })
      confirmed = result.index === 1
    } catch (_error) { return }
    if (!confirmed) return
    const active = id === this.activeSession
    if (active) {
      this.stopReply()
      this.cancelVoice()
      this.stopSpeech()
      this.actionSerial++
      this.actionBusy = false
    }
    if (!SessionService.remove(id)) {
      this.storageNotice = SessionService.storageNotice || '删除失败，请重试。'
      return
    }
    this.expandedThoughts = this.expandedThoughts.filter((item: string) => !item.startsWith(`${id}-`))
    if (active) this.restoreSession(SessionService.current() || SessionService.create('home', '新对话', AgentService.greeting('home')))
    else { this.sessions = SessionService.list(); this.storageNotice = SessionService.storageNotice }
  }

  private createChat(): void {
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.actionSerial++
    this.actionBusy = false
    this.restoreSession(SessionService.create('home', '新对话', AgentService.greeting('home')))
  }

  private sendMessage(prompt: string): void {
    const message = prompt.trim() || (this.draftAttachments.length > 0 ? '请分析这些附件。' : '')
    if (message.length === 0 || this.thinking || this.recording || this.voiceBusy || this.attachmentBusy) return
    const token = ++this.requestSerial
    const uiContext = this.getUIContext()
    const featureId = this.activeFeature
    const history = this.messages.slice()
    const gateway = IntegrationService.agent
    this.activeGateway = gateway
    const attachedContext = this.selectedContext.slice()
    const attachments = this.draftAttachments.slice()
    this.draftAttachments = []
    this.messages = [...this.messages, { role: 'user', content: message, meta: '现在', attachments: attachments }]
    this.messages = [...this.messages, { role: 'agent', content: '', meta: '正在检索资料', status: 'loading',
      sources: [], thinkingStartedAt: Date.now(), phase: 'retrieving' }]
    const replyIndex = this.messages.length - 1
    this.inputText = ''
    this.notice = ''
    this.thinking = true
    this.persistSession()
    // Wait for the new bubbles to be laid out before revealing the pending reply.
    setTimeout(() => {
      uiContext.runScopedTask(() => {
        if (token === this.requestSerial) this.chatScroller.scrollEdge(Edge.Bottom)
      })
    }, 50)
    let content = ''
    let sources: SourceCitation[] = []
    const timeout = setTimeout(() => {
      uiContext.runScopedTask(() => {
        if (token !== this.requestSerial) return
        gateway.cancel()
        this.requestSerial++
        this.activeGateway = undefined
        this.thinking = false
        const timeoutMessage = `等待 ${gateway.name} 返回超过 ${ApiConfig.requestTimeoutMs / 1000} 秒，请检查设备网络和模型服务后重试。`
        this.updateReply(replyIndex, content || timeoutMessage, '响应超时', 'error', sources)
        this.notice = timeoutMessage
        this.persistSession()
      })
    }, ApiConfig.requestTimeoutMs + 3000)
    const sink: StreamSink = new ChatStreamSink((): boolean => token !== this.requestSerial, (delta: string): void => {
      uiContext.runScopedTask(() => {
        if (token !== this.requestSerial) return
        content = (content + delta).slice(0, 16000)
        this.updateReply(replyIndex, content, `${gateway.name} · 正在流式生成`, 'streaming', sources)
      })
    }, (phase: string): void => {
      uiContext.runScopedTask(() => {
        if (token !== this.requestSerial) return
        this.updateReply(replyIndex, content, `${gateway.name} · 正在分析`, 'loading', sources, phase)
      })
    })
    ChatService.reply(message, featureId, history, this.retrievalOptions(), IntegrationService.rag(), gateway, sink,
      (result: RetrievalResult): void => {
        uiContext.runScopedTask(() => {
          if (token !== this.requestSerial) return
          sources = result.sources
          this.notice = result.notice
          this.updateReply(replyIndex, '', `${gateway.name} · ${sources.length} 条参考资料`, 'loading', sources, 'connecting')
        })
      }, attachedContext, attachments).then(() => {
        uiContext.runScopedTask(() => {
          if (token === this.requestSerial) this.updateReply(replyIndex, content || '服务未返回内容，请重试。', gateway.name, content ? 'complete' : 'error', sources)
        })
      }).catch((error: Error) => {
        uiContext.runScopedTask(() => {
          if (token === this.requestSerial) {
            const reason = error.message || '连接模型服务失败，请检查配置和网络。'
            this.updateReply(replyIndex, content || `生成失败：${reason}`, '生成失败', 'error', sources)
            this.notice = reason
          }
        })
      }).finally(() => {
        clearTimeout(timeout)
        uiContext.runScopedTask(() => {
          if (token === this.requestSerial) {
            this.thinking = false
            this.activeGateway = undefined
            this.persistSession()
          }
        })
      })
  }

  private advanceTask(): void {
    if (this.thinking) return
    this.thinking = true
    setTimeout(() => {
      if (this.progress < 3) this.progress += 1
      const nextText = this.progress === 2
        ? '工具已完成第一轮分析，结果已保存到右侧产物区。你可以继续编辑，或让 Agent 根据结果推进下一步。'
        : '流程已进入最后一步。完成后会生成一份可回看的总结报告，并保存到当前项目。'
      this.messages = [...this.messages, { role: 'agent', content: nextText, meta: '工具调用完成 · 现在' }]
      this.thinking = false
      this.persistSession()
    }, 650)
  }

  private toggleWorkspace(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.sideExpanded = !this.sideExpanded
    })
  }

  private toggleRecents(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.recentsExpanded = !this.recentsExpanded
    })
  }

  private toggleLeftPanel(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
      this.isLeftPanelVisible = !this.isLeftPanelVisible
    })
  }

  private toggleTaskPanel(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
      this.isTaskPanelVisible = !this.isTaskPanelVisible
    })
  }

  @Builder
  DashboardContent() {
    Column({ space: 14 }) {
      Text('今天，想推进哪一件事？').fontSize(25).fontWeight(FontWeight.Medium).fontColor('#252723')
      Text('CampusPilot 会保留项目记忆，并把目标拆成可回看的行动。').fontSize(14).fontColor('#777A72')
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          Text('求职实验室').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#2B2D28')
          Text('简历诊断、岗位匹配、模拟面试').fontSize(12).fontColor('#74766F')
          Text('开始准备 →').fontSize(12).fontColor('#356B58').fontWeight(FontWeight.Medium)
        }.alignItems(HorizontalAlign.Start).width('31%').padding(16).backgroundColor('#FDF7F0').borderRadius(14).onClick(() => this.chooseFeature(FEATURE_CATALOG[1]))
        Column({ space: 8 }) {
          Text('智能日程').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#2B2D28')
          Text('课程、作业和个人安排').fontSize(12).fontColor('#74766F')
          Text('整理本周 →').fontSize(12).fontColor('#356B58').fontWeight(FontWeight.Medium)
        }.alignItems(HorizontalAlign.Start).width('31%').padding(16).backgroundColor('#F1F7F2').borderRadius(14).onClick(() => this.chooseFeature(FEATURE_CATALOG[2]))
        Column({ space: 8 }) {
          Text('消费洞察').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#2B2D28')
          Text('记账、预算与消费复盘').fontSize(12).fontColor('#74766F')
          Text('查看账本 →').fontSize(12).fontColor('#356B58').fontWeight(FontWeight.Medium)
        }.alignItems(HorizontalAlign.Start).width('31%').padding(16).backgroundColor('#F4F4FB').borderRadius(14).onClick(() => this.chooseFeature(FEATURE_CATALOG[3]))
      }.width('100%').margin({ top: 8 })
      Text('快速开始').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#85877F').width('100%').margin({ top: 12 })
      Row({ space: 8 }) {
        Text('帮我制定秋招计划').fontSize(12).fontColor('#4E514B').padding(10).backgroundColor('#ECEDE8').borderRadius(9).onClick(() => this.sendMessage('帮我制定一份秋招计划。'))
        Text('安排本周任务').fontSize(12).fontColor('#4E514B').padding(10).backgroundColor('#ECEDE8').borderRadius(9).onClick(() => this.sendMessage('请帮我安排本周任务。'))
        Text('记录一笔消费').fontSize(12).fontColor('#4E514B').padding(10).backgroundColor('#ECEDE8').borderRadius(9).onClick(() => this.sendMessage('记录午餐 18 元。'))
      }.width('100%')
      Text('▤  搜索课程资料并加入当前对话  →').fontSize(12).fontColor('#356B58')
        .width('100%').padding(11).backgroundColor('#EFF6F0').borderRadius(9)
        .onClick(() => { this.contextPickerVisible = true })
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
  }

  @Builder
  CareerContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('求职实验室').fontSize(24).fontWeight(FontWeight.Medium).fontColor('#252723')
          Text('将岗位目标、简历版本和练习记录沉淀在同一项目。').fontSize(13).fontColor('#777A72')
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Text('产品经理 · 2027 届').fontSize(11).fontColor('#9B613D').padding(8).backgroundColor('#FFF3E8').borderRadius(8)
      }.width('100%')
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text('01').fontSize(12).fontColor('#9B613D')
          Text('简历诊断').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#33352F')
          Text('提取岗位关键词与量化成果').fontSize(11).fontColor('#7C7E76')
        }.alignItems(HorizontalAlign.Start).width('32%').padding(14).backgroundColor('#FFF8F1').borderRadius(12)
        Column({ space: 5 }) {
          Text('02').fontSize(12).fontColor('#356B58')
          Text('模拟面试').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#33352F')
          Text('多轮追问与反馈复盘').fontSize(11).fontColor('#7C7E76')
        }.alignItems(HorizontalAlign.Start).width('32%').padding(14).backgroundColor('#F1F7F2').borderRadius(12)
        Column({ space: 5 }) {
          Text('03').fontSize(12).fontColor('#5E6EBA')
          Text('投递追踪').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#33352F')
          Text('记录进展与复盘建议').fontSize(11).fontColor('#7C7E76')
        }.alignItems(HorizontalAlign.Start).width('32%').padding(14).backgroundColor('#F2F4FC').borderRadius(12)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
  }

  @Builder
  ScheduleContent() {
    Column({ space: 12 }) {
      Text('本周智能日程').fontSize(24).fontWeight(FontWeight.Medium).fontColor('#252723')
      Text('Agent 会根据截止日期、预计耗时和精力曲线调整安排。').fontSize(13).fontColor('#777A72')
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text('3').fontSize(28).fontWeight(FontWeight.Medium).fontColor('#356B58')
          Text('今日待完成').fontSize(11).fontColor('#777A72')
        }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor('#EFF6F0').borderRadius(12)
        Column({ space: 5 }) {
          Text('2h 40m').fontSize(22).fontWeight(FontWeight.Medium).fontColor('#356B58')
          Text('深度学习时间').fontSize(11).fontColor('#777A72')
        }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor('#EFF6F0').borderRadius(12)
        Column({ space: 5 }) {
          Text('85%').fontSize(28).fontWeight(FontWeight.Medium).fontColor('#356B58')
          Text('本周计划完成度').fontSize(11).fontColor('#777A72')
        }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor('#EFF6F0').borderRadius(12)
      }.width('100%')
      Column({ space: 10 }) {
        Text('今天的时间块').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#3A3C36')
        Row({ space: 10 }) { Text('14:00').fontSize(12).fontColor('#356B58').width(50); Text('数据结构作业').fontSize(14).fontColor('#3A3C36').layoutWeight(1); Text('50 分钟').fontSize(11).fontColor('#868880') }
        Divider().color('#E5E7E1')
        Row({ space: 10 }) { Text('16:00').fontSize(12).fontColor('#356B58').width(50); Text('产品分析小组讨论').fontSize(14).fontColor('#3A3C36').layoutWeight(1); Text('45 分钟').fontSize(11).fontColor('#868880') }
      }.width('100%').padding(15).backgroundColor('#FFFFFF').borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
  }

  @Builder
  BudgetContent() {
    Column({ space: 12 }) {
      Text('消费洞察').fontSize(24).fontWeight(FontWeight.Medium).fontColor('#252723')
      Text('每笔消费自动分类，预算变化和异常支出会及时提醒。').fontSize(13).fontColor('#777A72')
      Row({ space: 10 }) {
        Column({ space: 5 }) { Text('¥ 486').fontSize(25).fontWeight(FontWeight.Medium).fontColor('#3B5F9D'); Text('本月已支出').fontSize(11).fontColor('#777A72') }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor('#F1F4FC').borderRadius(12)
        Column({ space: 5 }) { Text('¥ 714').fontSize(25).fontWeight(FontWeight.Medium).fontColor('#3B5F9D'); Text('剩余预算').fontSize(11).fontColor('#777A72') }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor('#F1F4FC').borderRadius(12)
        Column({ space: 5 }) { Text('−8%').fontSize(25).fontWeight(FontWeight.Medium).fontColor('#3B5F9D'); Text('较上周变化').fontSize(11).fontColor('#777A72') }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor('#F1F4FC').borderRadius(12)
      }.width('100%')
      Column({ space: 8 }) {
        Text('最近流水').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#3A3C36')
        Row() { Text('午餐').fontSize(14).fontColor('#3A3C36').layoutWeight(1); Text('餐饮 · 今天').fontSize(11).fontColor('#878981').margin({ right: 18 }); Text('− ¥18').fontSize(14).fontColor('#3B5F9D') }.width('100%')
        Divider().color('#E5E7E1')
        Row() { Text('咖啡').fontSize(14).fontColor('#3A3C36').layoutWeight(1); Text('休闲 · 今天').fontSize(11).fontColor('#878981').margin({ right: 18 }); Text('− ¥16').fontSize(14).fontColor('#3B5F9D') }.width('100%')
      }.width('100%').padding(15).backgroundColor('#FFFFFF').borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
  }

  @Builder
  PlaceholderContent() {
    Column({ space: 10 }) {
      Text(this.selectedFeature().name).fontSize(24).fontWeight(FontWeight.Medium).fontColor('#252723')
      Text(this.selectedFeature().description).fontSize(14).fontColor('#777A72')
      Text('模块骨架已创建').fontSize(13).fontColor('#356B58').padding(9).backgroundColor('#EFF6F0').borderRadius(8)
      Text('后续将在 services/tools 中接入对应工具，并以当前任务面板承载执行步骤和结果。').fontSize(13).fontColor('#686A63').lineHeight(20)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 24, bottom: 8 })
  }

  @Builder
  ApiSettingsContent() {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 3 }) {
          Text('连接外部模型').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#252723')
          Text('兼容 OpenAI Chat Completions API').fontSize(12).fontColor('#777A72')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('关闭').fontSize(12).fontColor('#777A72').padding(8).onClick(() => this.toggleApiSettings())
      }.width('100%')
      TextInput({ text: this.apiBaseUrl, placeholder: '服务地址，例如 https://api.example.com/v1' })
        .height(44).backgroundColor('#FFFFFF').borderRadius(9).padding({ left: 12, right: 8 })
        .onChange((value: string) => this.apiBaseUrl = value)
      TextInput({ text: this.apiModel, placeholder: '模型名称，例如 qwen-plus、deepseek-chat' })
        .height(44).backgroundColor('#FFFFFF').borderRadius(9).padding({ left: 12, right: 8 })
        .onChange((value: string) => this.apiModel = value)
      TextInput({ text: this.apiKey, placeholder: 'API Key（无鉴权服务可留空）' })
        .type(InputType.Password).height(44).backgroundColor('#FFFFFF').borderRadius(9).padding({ left: 12, right: 8 })
        .onChange((value: string) => this.apiKey = value)
      Text('问题、近期对话和已选资料会发送给你填写的服务商。也可用本地文件 rawfile/local_api.json 配置；它已加入 Git 忽略，但会打入安装包，请勿公开分发含 Key 的安装包。')
        .fontSize(11).fontColor('#777A72').lineHeight(18).width('100%')
      if (this.apiNotice.length > 0) {
        Text(this.apiNotice).fontSize(12).fontColor('#88551A').lineHeight(18).width('100%')
          .padding(9).backgroundColor('#FFF6E8').borderRadius(8)
      }
      Row({ space: 8 }) {
        Button('保存并使用').height(44).fontSize(13).fontColor('#F7F8F3').backgroundColor('#356B58')
          .onClick(() => this.saveAgentApi())
        if (this.apiConfigured) {
          Button('清除配置').height(44).fontSize(12).fontColor('#596159').backgroundColor('#ECEDE8')
            .onClick(() => {
              this.apiBaseUrl = ''
              this.apiModel = ''
              this.apiKey = ''
              IntegrationService.configureAgent({ baseUrl: '', model: '', apiKey: '' })
              this.apiConfigured = false
              this.apiNotice = '已清除外部模型配置。'
            })
        }
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor('#F3F5EF').borderRadius(12)
  }

  @Builder
  ContextSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('添加上下文').fontSize(21).fontWeight(FontWeight.Medium).fontColor('#252723')
        Blank()
        Button('完成').fontSize(13).height(40).fontColor('#F7F8F3').backgroundColor('#356B58')
          .accessibilityText('完成并关闭上下文弹窗').onClick(() => this.contextPickerVisible = false)
      }.width('100%')
      Text(`已加入 ${this.selectedContext.length} 条资料，仅用于当前对话`).fontSize(12).fontColor('#7C897D').width('100%')
      Divider().color('#E0E6DD')
      Scroll() { this.KnowledgeContent() }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding(22).backgroundColor('#F7F9F4')
  }

  @Builder
  KnowledgeContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('为当前对话添加资料').fontSize(19).fontWeight(FontWeight.Medium).fontColor('#252723')
          Text(`${this.knowledgeCount} 个资料片段 · 索引 ${this.knowledgeRevision}`).fontSize(12).fontColor('#777A72')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('刷新').height(44).fontSize(12).fontColor('#356B58').backgroundColor('#EFF6F0').onClick(() => this.refreshKnowledge())
      }.width('100%')
      if (this.knowledgeRevision === 'demo-1') {
        Text('离线演示资料，不代表学校官方资料。').fontSize(12).fontColor('#88551A').width('100%').padding(10).backgroundColor('#FFF6E8').borderRadius(9)
      }
      if (this.knowledgeCount === 0) {
        Text('知识库尚未接入资料服务。可载入离线样例体验搜索和来源引用。').fontSize(13).fontColor('#777A72').lineHeight(21).width('100%')
        Button('载入演示资料').height(44).fontSize(13).fontColor('#F7F8F3').backgroundColor('#356B58').onClick(() => this.loadDemoKnowledge())
      }
      Row({ space: 7 }) {
        Button(this.knowledgeCourse === '' ? '全部课程 ✓' : '全部课程').fontSize(12).height(44)
          .fontColor('#356B58').backgroundColor(this.knowledgeCourse === '' ? '#EFF6F0' : '#F2F2ED')
          .onClick(() => { this.knowledgeCourse = ''; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
        ForEach(this.knowledgeCourses, (course: string) => {
          Button(this.knowledgeCourse === course ? `${course} ✓` : course).fontSize(12).height(44)
            .fontColor('#356B58').backgroundColor(this.knowledgeCourse === course ? '#EFF6F0' : '#F2F2ED')
            .onClick(() => { this.knowledgeCourse = course; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
        }, (course: string) => course)
      }.width('100%')
      TextInput({ text: this.knowledgeQuery, placeholder: '搜索问题，例如：黑盒测试有哪些方法？' })
        .height(44).backgroundColor('#FFFFFF').borderRadius(9).padding({ left: 12, right: 8 })
        .onChange((value: string) => this.knowledgeQuery = value).onSubmit(() => this.searchKnowledge())
      Row({ space: 8 }) {
        Button(this.searchBusy ? '检索中…' : '搜索资料').height(44).fontSize(13).fontColor('#F7F8F3')
          .backgroundColor('#356B58').enabled(!this.searchBusy).onClick(() => this.searchKnowledge())
        Button(this.minScore <= 0.10 ? '恢复默认阈值' : '放宽匹配').height(44).fontSize(12).fontColor('#356B58').backgroundColor('#EFF6F0')
          .onClick(() => { this.minScore = this.minScore <= 0.10 ? 0.35 : this.minScore - 0.05; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
        Button(`结果 ${this.topK}`).height(44).fontSize(12).fontColor('#356B58').backgroundColor('#EFF6F0')
          .onClick(() => { this.topK = this.topK >= 6 ? 2 : this.topK + 1; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
      }.width('100%')
      if (this.retrieval.query.length > 0) {
        Text(`找到 ${this.retrieval.sources.length} 条来源 · ${this.retrieval.mode === 'hybrid' ? '混合检索' : '关键词检索'}`)
          .fontSize(12).fontColor('#777A72').width('100%')
        ForEach(this.retrieval.sources, (source: SourceCitation) => {
          Column({ space: 7 }) {
            Text(`[${source.number}] ${source.title}`).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#33352F').width('100%')
            Text(`${source.course} · ${source.location}`).fontSize(11).fontColor('#777A72').width('100%')
            Text(source.excerpt).fontSize(13).fontColor('#4E514B').lineHeight(20)
              .maxLines(this.expandedSourceId === source.chunkId ? 0 : 3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              .onClick(() => this.showCitation(source))
            Button(this.expandedSourceId === source.chunkId ? '收起原文' : '查看并复制原文')
              .height(44).fontSize(12).fontColor('#356B58').backgroundColor('#EFF6F0')
              .accessibilityText(`查看引用 ${source.number} 的原文`)
              .onClick(() => this.showCitation(source))
            Button(this.selectedContext.some((item: SourceCitation) => item.chunkId === source.chunkId) ? '已加入当前对话 · 移除' : '加入当前对话')
              .height(44).fontSize(12).fontColor('#356B58').backgroundColor('#F5F7F2')
              .enabled(!this.thinking).onClick(() => this.toggleContextSource(source))
          }.width('100%').alignItems(HorizontalAlign.Start).padding(13).backgroundColor('#FFFFFF')
            .borderRadius(11).border({ width: 1, color: this.expandedSourceId === source.chunkId ? '#8BAF94' : '#E5E5DF' })
        }, (source: SourceCitation) => source.chunkId)
        if (this.retrieval.sources.length > 0) {
          Button('带着问题返回会话').height(44).fontSize(13).fontColor('#F7F8F3').backgroundColor('#356B58')
            .onClick(() => { this.contextPickerVisible = false; this.sendMessage(this.retrieval.query) })
        }
        if (this.retrieval.notice.length > 0) {
          Text(this.retrieval.notice).fontSize(12).fontColor('#88551A').width('100%').padding(10).backgroundColor('#FFF6E8').borderRadius(9)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
  }

  @Builder
  ModuleContent() {
    Column({ space: 10 }) {
      Text(this.selectedFeature().name).fontSize(24).fontWeight(FontWeight.Medium).fontColor('#252723')
      Text(this.selectedFeature().description).fontSize(14).fontColor('#777A72')
      TextInput({ text: this.moduleInput, placeholder: '输入编号或当前模块的操作内容' }).height(44)
        .backgroundColor('#FFFFFF').borderRadius(9).padding({ left: 12, right: 8 })
        .onChange((value: string) => this.moduleInput = value)
      if (this.activeFeature === 'forms') {
        this.ModuleAction('查看表单模板', 'templates')
        this.ModuleAction('生成填报草稿', 'draft')
        this.ModuleAction('导出 / 复制草稿', 'export')
        this.ModuleAction('辅助填写', 'fill')
      } else if (this.activeFeature === 'study') {
        this.ModuleAction('查看课程表', 'timetable')
        this.ModuleAction('查看提醒', 'reminders')
        this.ModuleAction('生成学习计划', 'plan')
        this.ModuleAction('计划打卡', 'checkin')
      } else {
        this.ModuleAction('连接 / 查询设备', 'connect')
        this.ModuleAction('开始专注', 'start')
        this.ModuleAction('结束专注', 'stop')
      }
      if (this.moduleNotice.length > 0) {
        Text(this.moduleNotice).fontSize(13).fontColor('#596159').lineHeight(21).width('100%').padding(12).backgroundColor('#EFF6F0').borderRadius(10)
      }
      ForEach(this.moduleItems, (item: ModuleItem) => {
        Column({ space: 6 }) {
          Text(item.title).fontSize(14).fontColor('#33352F').width('100%')
          Text(item.detail).fontSize(12).fontColor('#686A63').lineHeight(20).width('100%')
        }.width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(10)
      }, (item: ModuleItem) => item.id)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 20, bottom: 8 })
  }

  @Builder
  ModuleAction(label: string, action: string) {
    Button(label).width('100%').height(44).fontSize(13).fontColor('#356B58')
      .backgroundColor('#EFF6F0').enabled(!this.actionBusy).onClick(() => this.runModule(action))
  }

  @Builder
  TaskPanel() {
    Column({ space: 13 }) {
      Row() { Text('任务面板').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#272824'); Blank(); Text('•••').fontSize(18).fontColor('#777971') }.width('100%')
      Text(this.activeFeature === 'home' ? '项目记忆与快捷操作' : `${this.selectedFeature().name}进度`).fontSize(12).fontColor('#777A72')
      Column({ space: 8 }) {
        Row() { Text('当前流程').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#3A3C36'); Blank(); Text(`${this.progress}/3`).fontSize(12).fontColor('#356B58') }.width('100%')
        Row() { Row().width(this.progress === 1 ? '33%' : this.progress === 2 ? '66%' : '100%').height(5).backgroundColor('#356B58').borderRadius(4); Blank() }.width('100%').height(5).backgroundColor('#E1E3DD').borderRadius(4)
      }.width('100%').padding(13).backgroundColor('#EFF6F0').borderRadius(12)
      ForEach(this.steps(), (step: ActionItem, index: number) => {
        Row({ space: 9 }) {
          Text(index < this.progress ? '✓' : '○').fontSize(14).fontColor(index < this.progress ? '#356B58' : '#A1A39B')
          Column({ space: 2 }) { Text(step.title).fontSize(13).fontColor('#3D3F39'); Text(index < this.progress ? '已完成并保存' : step.subtitle).fontSize(10).fontColor('#8E9088') }.alignItems(HorizontalAlign.Start)
        }.width('100%').padding({ top: 6, bottom: 6 })
      }, (step: ActionItem) => step.title)
      Button(this.progress < 3 ? '推进下一步' : '生成总结报告').width('100%').height(40).fontSize(13).fontColor('#F7F8F3').backgroundColor('#356B58').borderRadius(9).onClick(() => this.advanceTask())
      Text('产物与记忆').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#777A72').width('100%').margin({ top: 4 })
      Text('▤  当前任务总结\n    可编辑 · 可导出 · 待接入本地持久化').fontSize(12).fontColor('#50524B').lineHeight(19).width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(10)
    }.width(274).height('100%').padding(16).backgroundColor('#F6F7F2')
  }

  build() {
    Row() {
      Column() {
        if (this.isLeftPanelVisible) {
        Column() {
        Row({ space: 9 }) { Text('C').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#151614').width(32).height(32).textAlign(TextAlign.Center).padding({ top: 6 }).backgroundColor('#D4F56A').borderRadius(9); Text('CampusPilot').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#F5F5F0'); Blank(); Text('‹').fontSize(24).fontColor('#B5B6B0').width(24).height(32).textAlign(TextAlign.Center).padding({ top: 1 }).onClick(() => this.toggleLeftPanel()) }.width('100%').margin({ bottom: 20 })
        Button('＋  新建对话').width('100%').height(42).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#151614').backgroundColor('#D4F56A').borderRadius(10).onClick(() => this.createChat())
        Row({ space: 7 }) { Text('⌕').fontSize(17).fontColor('#AFB0AB'); Text('搜索对话和记忆').fontSize(12).fontColor('#8B8C88') }.width('100%').height(38).padding({ left: 10 }).margin({ top: 12, bottom: 12 }).backgroundColor('#292A27').borderRadius(9)
        Column() {
          Scroll() {
            Column() {
            Row() { Text('工作区').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#80817D'); Blank(); Text('⌃').fontSize(13).fontColor('#9B9C96').rotate({ angle: this.sideExpanded ? 0 : 180 }) }.width('100%').height(28).padding({ left: 2, right: 7 }).onClick(() => this.toggleWorkspace())
            if (this.sideExpanded) {
              ForEach(FEATURE_CATALOG, (feature: FeatureDefinition) => {
                Row({ space: 10 }) { Text(feature.icon).fontSize(16).fontColor(this.activeFeature === feature.id ? '#D4F56A' : '#A5A6A1').width(20).textAlign(TextAlign.Center); Text(feature.name).fontSize(13).fontColor(this.activeFeature === feature.id ? '#F5F5F0' : '#C7C8C3').fontWeight(this.activeFeature === feature.id ? FontWeight.Medium : FontWeight.Regular).layoutWeight(1) }
                .width('100%').height(40).padding({ left: 8, right: 6 }).margin({ bottom: 2 }).backgroundColor(this.activeFeature === feature.id ? '#30312D' : '#1D1E1B').borderRadius(8).onClick(() => this.chooseFeature(feature))
              }, (feature: FeatureDefinition) => feature.id)
            }
            }.width('100%').justifyContent(FlexAlign.Start)
          }.height(this.sideExpanded ? '55%' : 28).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
        Row() { Text('最近对话').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#80817D'); Blank(); Text('⌃').fontSize(13).fontColor('#9B9C96').rotate({ angle: this.recentsExpanded ? 0 : 180 }) }.width('100%').height(28).padding({ left: 2, right: 7 }).margin({ top: 10 }).onClick(() => this.toggleRecents())
          Scroll() {
            Column() {
              ForEach(this.sessions, (session: SessionSummary) => {
                Row({ space: 3 }) {
                  Column({ space: 4 }) {
                    Text(session.title).fontSize(12).fontColor(this.activeSession === session.id ? '#F0F0E9' : '#B9BBB4')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(this.sessionTime(session.updatedAt)).fontSize(10).fontColor('#82877D').width('100%')
                  }.layoutWeight(1).height(54).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
                    .accessibilityText(`历史对话：${session.title}，最近消息 ${this.sessionTime(session.updatedAt)}`)
                    .onClick(() => this.openSession(session.id))
                  Button({ type: ButtonType.Normal }) {
                    Image($r('app.media.ic_more_horizontal')).width(20).height(20)
                  }.width(32).height(44).padding(0).borderRadius(8).backgroundColor('#34372F')
                    .accessibilityText(`会话操作：${session.title}`)
                    .bindMenu([{ value: '删除会话', action: () => this.confirmDeleteSession(session.id) }])
                }.width('100%').padding({ left: 9, right: 4 }).margin({ bottom: 3 })
                  .backgroundColor(this.activeSession === session.id ? '#292A27' : '#1D1E1B').borderRadius(7)
              }, (session: SessionSummary) => `${session.id}-${session.title}-${session.updatedAt}`)
            }.width('100%').justifyContent(FlexAlign.Start)
          }.height(this.recentsExpanded ? 'calc(45% - 38vp)' : 0).width('100%')
            .align(Alignment.TopStart).scrollBar(BarState.Auto).clip(true)
            .opacity(this.recentsExpanded ? 1 : 0)
          Blank().layoutWeight(1)
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Start)
        Text(this.apiConfigured ? '●  外部模型已配置' : '●  尚未连接外部模型').fontSize(11).fontColor('#8B8C88').width('100%').padding({ top: 9, bottom: 4 })
        }.width('100%').height('100%').padding(14)
        } else {
          Column({ space: 14 }) {
            Text('›').fontSize(26).fontColor('#D4F56A').width(32).height(38).textAlign(TextAlign.Center).padding({ top: 3 }).backgroundColor('#30312D').borderRadius(9).onClick(() => this.toggleLeftPanel())
            Text('C').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#151614').width(28).height(28).textAlign(TextAlign.Center).padding({ top: 4 }).backgroundColor('#D4F56A').borderRadius(8)
          }.width('100%').height('100%').alignItems(HorizontalAlign.Center).padding({ top: 14 })
        }
      }.width(this.isLeftPanelVisible ? 216 : 48).height('100%').backgroundColor('#1D1E1B')

      Column() {
        Row() {
          Column({ space: 3 }) { Text(this.selectedFeature().name).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#242521'); Text(this.selectedFeature().description).fontSize(11).fontColor('#85867E') }.alignItems(HorizontalAlign.Start)
          Blank()
          Text('＋ 上下文').fontSize(12).fontColor('#575951')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor('#EFEFEA').borderRadius(8)
            .accessibilityText(this.contextPickerVisible ? '关闭课程资料选择' : '为当前对话添加课程资料')
            .onClick(() => this.toggleContextPicker())
          Text(this.isTaskPanelVisible ? '☷' : '☰').fontSize(18).fontColor('#55564F').margin({ left: 12 }).padding(7).onClick(() => this.toggleTaskPanel())
        }.width('100%').height(68).padding({ left: 26, right: 20 }).backgroundColor('#FBFBF8').border({ width: { bottom: 1 }, color: '#E5E5DF' })
        Scroll(this.chatScroller) {
          Column({ space: 15 }) {
            if (this.activeFeature === 'home') { this.DashboardContent() }
            else if (this.activeFeature === 'career') { this.CareerContent() }
            else if (this.activeFeature === 'schedule') { this.ScheduleContent() }
            else if (this.activeFeature === 'budget') { this.BudgetContent() }
            else if (this.activeFeature === 'forms' || this.activeFeature === 'focus' || this.activeFeature === 'study') { this.ModuleContent() }
            else { this.PlaceholderContent() }
            if (this.notice.length > 0) {
              Text(this.notice).fontSize(12).fontColor('#88551A').lineHeight(19).width('100%')
                .padding(10).backgroundColor('#FFF6E8').borderRadius(9)
            }
            if (this.storageNotice.length > 0) {
              Text(this.storageNotice).fontSize(12).fontColor('#88551A').width('100%')
                .padding(10).backgroundColor('#FFF6E8').borderRadius(9)
            }
            if (this.apiSettingsVisible) { this.ApiSettingsContent() }
            Row({ space: 8 }) { Text('✦').fontSize(13).fontColor('#356B58'); Text('回答会结合当前对话和你主动加入的课程资料。').fontSize(12).fontColor('#596159') }.width('100%').padding(11).backgroundColor('#EFF6F0').borderRadius(10)
            ForEach(this.messages, (message: AgentMessage, index: number) => {
              Row() {
                Column({ space: 5 }) {
                  ForEach(message.attachments || [], (attachment: ChatAttachment) => {
                    if (attachment.kind === 'image') {
                      Image(`file://${attachment.path}`).width('100%').height(160).objectFit(ImageFit.Contain).borderRadius(8)
                    }
                    Text(`${attachment.kind === 'image' ? '▧' : '▤'} ${attachment.name}${attachment.truncated ? ' · 部分内容' : ''}`)
                      .fontSize(12).fontColor('#5C7160').maxLines(2).width('100%')
                  }, (attachment: ChatAttachment) => attachment.id)
                  if (message.role === 'agent') {
                    AgentAnswer({ message: message, expanded: this.expandedThoughts.includes(`${this.activeSession}-${index}`),
                      onToggle: () => this.toggleThought(index) })
                  } else {
                    Text(message.content).fontSize(15).fontColor('#292A27').lineHeight(23).copyOption(CopyOptions.InApp)
                  }
                  Text(message.meta).fontSize(10).fontColor('#9A9B94')
                  ForEach(message.sources || [], (source: SourceCitation) => {
                    Column({ space: 5 }) {
                      Text(`[${source.number}] ${source.title} · ${source.location}`).fontSize(11).fontColor('#356B58').width('100%')
                        .accessibilityText(`来源 ${source.number} ${source.title} ${source.location}`).onClick(() => this.showCitation(source))
                      if (this.expandedSourceId === source.chunkId) {
                        Text(source.excerpt).fontSize(12).fontColor('#4E514B').lineHeight(19).copyOption(CopyOptions.InApp).width('100%').onClick(() => this.showCitation(source))
                      }
                    }.width('100%').padding(8).backgroundColor('#EFF6F0').borderRadius(8)
                  }, (source: SourceCitation) => source.chunkId)
                  if (message.role === 'agent' && message.content.length > 0 && message.status !== 'loading') {
                    Button(this.speaking ? '停止朗读' : '朗读回答').height(44).fontSize(11).fontColor('#356B58').backgroundColor('#EFF6F0')
                      .onClick(() => this.toggleSpeech(message.content))
                  }
                }.alignItems(HorizontalAlign.Start).width('80%').padding(13).backgroundColor(message.role === 'agent' ? '#FFFFFF' : '#E9F3EB').borderRadius(13)
              }.width('100%').justifyContent(message.role === 'agent' ? FlexAlign.Start : FlexAlign.End)
            // ForEach reuses nodes with unchanged keys. Replacing an interface object alone
            // does not refresh its captured fields, so include the reply revision in its key.
            }, (message: AgentMessage, index: number) => `${this.activeSession}-${message.role}-${index}-${message.renderRevision || 0}`)
          }.width('100%').padding({ left: 26, right: 26, top: 2, bottom: 20 })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        Column({ space: 7 }) {
          if (this.draftAttachments.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.draftAttachments, (attachment: ChatAttachment) => {
                  Row({ space: 7 }) {
                    if (attachment.kind === 'image') { Image(`file://${attachment.path}`).width(44).height(44).objectFit(ImageFit.Cover).borderRadius(6) }
                    else { Text('▤').fontSize(22).fontColor('#58735E') }
                    Column({ space: 3 }) {
                      Text(attachment.name).fontSize(11).fontColor('#46574A').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width(130)
                      Text(`${Math.max(1, Math.round(attachment.size / 1024))} KB${attachment.truncated ? ' · 部分内容' : ''}`).fontSize(10).fontColor('#8A968B')
                    }.alignItems(HorizontalAlign.Start)
                    Button('×').fontSize(18).width(30).height(40).backgroundColor(Color.Transparent).fontColor('#738174')
                      .accessibilityText(`移除附件 ${attachment.name}`).onClick(() => this.removeAttachment(attachment.id))
                  }.padding(7).backgroundColor('#F0F5EF').borderRadius(9)
                }, (attachment: ChatAttachment) => attachment.id)
              }
            }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
          }
          if (this.attachmentBusy || this.voiceBusy || this.recording) {
            Text(this.attachmentBusy ? '正在读取附件…' : this.recording ? '● 正在聆听，再点麦克风结束' : '正在处理语音…')
              .fontSize(11).fontColor(this.recording ? '#B35443' : '#66816B').width('100%')
          }
          if (this.selectedContext.length > 0) {
            Row({ space: 5 }) {
              Text(`当前上下文 · ${this.selectedContext.length} 条资料`).fontSize(11).fontColor('#356B58').layoutWeight(1)
              ForEach(this.selectedContext, (source: SourceCitation) => {
                Button(`［${source.number}］${source.course} ×`).fontSize(10).height(38).fontColor('#356B58')
                  .backgroundColor('#EFF6F0').onClick(() => this.toggleContextSource(source))
              }, (source: SourceCitation) => source.chunkId)
            }.width('100%')
          }
          Row({ space: 10 }) {
            Text('＋').fontSize(19).fontColor('#4F514B').width(26).height(44).textAlign(TextAlign.Center)
              .accessibilityText('导入文件或图片').enabled(!this.thinking && !this.recording && !this.voiceBusy && !this.attachmentBusy)
              .bindMenu([{ value: '导入文件', action: () => this.pickAttachments(false) }, { value: '选择图片', action: () => this.pickAttachments(true) }])
            Button({ type: ButtonType.Normal }) {
              if (this.recording) { Text('■').fontSize(16).fontColor('#B35443') }
              else if (this.voiceBusy) { LoadingProgress().width(20).height(20).color('#66816B') }
              else { Image($r('app.media.ic_microphone')).width(23).height(23) }
            }.width(32).height(44).backgroundColor(Color.Transparent).borderRadius(6)
              .accessibilityText(this.recording ? '结束录音' : '麦克风语音识别').onClick(() => this.toggleVoice())
            TextInput({ text: this.inputText, placeholder: '向 CampusPilot 描述你的下一步…' }).layoutWeight(1).height(44).fontSize(14).backgroundColor('#F2F2ED').borderRadius(10).padding({ left: 12, right: 8 }).onChange((value: string) => this.inputText = value).onSubmit(() => this.sendMessage(this.inputText))
            Button({ type: ButtonType.Circle }) {
              Text('➤').fontSize(18).fontColor('#F9FAF6').rotate({ angle: -45 })
            }.width(42).height(42).backgroundColor('#356B58').onClick(() => this.sendMessage(this.inputText))
            if (this.thinking) { Text('停止').fontSize(12).fontColor('#356B58').height(44).padding({ left: 6, right: 6 }).onClick(() => this.stopReply()) }
          }.width('100%').padding(8).backgroundColor('#FFFFFF').borderRadius(14).border({ width: 1, color: '#E2E3DC' })
          Text(this.apiConfigured ? `● 已配置 ${IntegrationService.agent.name} · 管理 API` : '配置外部模型 API · 当前尚未连接模型')
            .fontSize(10).fontColor(this.apiConfigured ? '#356B58' : '#777A72').width('100%').textAlign(TextAlign.Center)
            .height(24).onClick(() => this.toggleApiSettings())
        }.width('100%').padding({ left: 26, right: 26, top: 10, bottom: 14 }).backgroundColor('#FBFBF8')
      }.layoutWeight(1).height('100%').backgroundColor('#FBFBF8')

      if (this.isTaskPanelVisible) { Divider().vertical(true).color('#E4E5DE').strokeWidth(1); this.TaskPanel() }
    }.width('100%').height('100%').backgroundColor('#FBFBF8')
      .bindSheet($$this.contextPickerVisible, this.ContextSheet(), { height: '80%', width: 680,
        preferType: SheetType.CENTER, showClose: false, dragBar: false,
        onDisappear: () => { this.contextPickerVisible = false; this.searchSerial++; this.searchBusy = false } })
  }
}

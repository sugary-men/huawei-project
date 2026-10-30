import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { FEATURE_CATALOG } from '../config/FeatureCatalog'
import { AgentMessage, FeatureDefinition } from '../models/AppModels'
import { SessionService, ChatSession, SessionSummary } from '../services/SessionService'
import { KnowledgeChunk, RetrievalOptions, RetrievalResult, SourceCitation } from '../models/RagModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagConfig } from '../config/RagConfig'
import { demoKnowledgeIndex, MemoryKnowledgeRepository } from '../services/KnowledgeService'
import { ChatService } from '../services/ChatService'
import { AgentGateway, StreamSink, ModuleAdapter, ModuleItem, ModuleResult, VoiceObserver } from '../models/IntegrationModels'
import { ApiConfig, AgentProfileArchive, AgentProfileSummary } from '../config/ApiConfig'
import { common } from '@kit.AbilityKit'
import { LocalAgentConfigService } from '../services/LocalAgentConfigService'
import { AgentAnswer } from '../components/AgentAnswer'
import { AttachmentService } from '../services/AttachmentService'
import { ChatAttachment } from '../models/AttachmentModels'
import { MarkdownParser } from '../services/MarkdownParser'
import { NfcFocusBridge } from '../services/NfcFocusBridge'
import { MarkdownContent } from '../components/MarkdownContent'
import { WorkspaceConfig } from '../config/WorkspaceConfig'
import { WorkspaceService } from '../services/WorkspaceService'
import { AgentToolCall, WorkspaceArtifact, WorkspaceProfile, WorkspaceState, WorkspaceTask } from '../models/WorkspaceModels'
import { SidebarPreferences, SidebarView, SidebarWorkspaceGroup } from '../models/SidebarModels'
import { SidebarService } from '../services/SidebarService'
import { InteractiveContent } from '../components/InteractiveContent'
import { InteractionChange, InteractionRecord } from '../models/InteractionModels'
import { InteractionService } from '../services/InteractionService'
import { ScheduleService } from '../services/ScheduleService'
import { TaskCenterPage } from '../components/TaskCenterPage'
import { LibraryPage } from '../components/LibraryPage'
import { AgentTaskManager } from '../services/AgentTaskManager'
import { util } from '@kit.ArkTS'
import { ExecutionRecord } from '../models/ExecutionModels'
import { ExecutionTraceService } from '../services/ExecutionTraceService'
import { MessageTimeService } from '../services/MessageTimeService'
import { ReplyActions } from '../components/ReplyActions'
import { ApiProfilesSheet } from '../components/ApiProfilesSheet'
import { ModelSelector } from '../components/ModelSelector'
import { ChatSendButton } from '../components/ChatSendButton'
import { FocusGuardService } from '../services/FocusGuardService'

// Drive native layout each frame instead of stretching the final text layout.
@AnimatableExtend(Row)
function panelLayoutWidth(value: number) {
  .width(value)
}

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

interface FocusTimerInput {
  durationMinutes?: number
}

@Entry
@Component
struct Index {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @State appearanceSettingsVisible: boolean = false
  @State appSection: string = 'chat'
  @State taskCenterTab: string = 'agent'
  @State features: FeatureDefinition[] = []
  @State workspaceEditorVisible: boolean = false
  @State workspaceName: string = ''
  @State workspaceDescription: string = ''
  @State workspacePrompt: string = ''
  @State workspaceEditorNotice: string = ''
  @State leftWidth: number = 256
  @State rightWidth: number = 274
  @State viewportWidth: number = 1280
  @State viewportHeight: number = 800
  @State resizingPanel: string = ''
  @State hoveredGrip: string = ''
  private dragStartWidth: number = 0
  private pendingPanelCollapse: string = ''
  @State activeFeature: string = 'home'
  @State isWelcomePage: boolean = true
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
  @State expandedWorkspaceIds: string[] = []
  @State expandedHistoryIds: string[] = []
  @State showAllRecent: boolean = false
  @State sidebarQuery: string = ''
  @State sidebarSelection: string = ''
  @State sidebarView: SidebarView = { workspaces: [], recent: [], recentCount: 0 }
  @State isTaskPanelVisible: boolean = true
  @State isLeftPanelVisible: boolean = true
  @State progress: number = 1
  @State workspace: WorkspaceState = WorkspaceService.create('home')
  @State artifactVisible: boolean = false
  @State artifactTitle: string = ''
  @State artifactId: string = ''
  @State artifactContent: string = ''
  @State messages: AgentMessage[] = []
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
  @State speakingReply: string = ''
  @State messageClock: number = Date.now()
  private messageClockTimer: number = -1
  @State actionBusy: boolean = false
  @State moduleNotice: string = ''
  @State moduleItems: ModuleItem[] = []
  @State moduleInput: string = ''
  @State focusWorkMinutes: number = 25
  @State focusBreakMinutes: number = 5
  @State focusRemainingSeconds: number = 25 * 60
  @State focusRunning: boolean = false
  @State focusPhase: string = 'focus'
  @State focusCompleted: number = 0
  @State focusWhitelistTokens: string[] = []
  @State focusGuardNotice: string = ''
  @State focusGuardActive: boolean = false
  @State focusGuardEnabled: boolean = true
  @State focusGuardBusy: boolean = false
  private focusTimerId: number = -1
  private focusEndAt: number = 0
  @State apiSettingsVisible: boolean = false
  @State apiConfigured: boolean = false
  @State apiProfiles: AgentProfileSummary[] = []
  @State apiActiveId: string = ''
  @State apiActiveModel: string = ''
  @State apiProfilesLoading: boolean = true
  private apiLoadSerial: number = 0
  private requestSerial: number = 0
  private searchSerial: number = 0
  private voiceSerial: number = 0
  private speechSerial: number = 0
  private actionSerial: number = 0
  private activeGateway: AgentGateway | undefined = undefined
  private readonly chatScroller: Scroller = new Scroller()
  private readonly workspaceScroller: Scroller = new Scroller()
  private minScore: number = 0.20
  private topK: number = 4

  private selectedFeature(): FeatureDefinition {
    const feature = this.features.find((item: FeatureDefinition) => item.id === this.activeFeature)
    return feature === undefined ? FEATURE_CATALOG[0] : feature
  }

  private workspaceProfile(id: string = this.activeFeature): WorkspaceProfile { return WorkspaceConfig.profile(id, this.features) }

  private nfcEvent: (tagId: string) => void = (tagId: string): void => {
    const focusFeature: FeatureDefinition | undefined = this.features.find((item: FeatureDefinition) => item.id === 'focus')
    if (focusFeature !== undefined) this.chooseFeature(focusFeature)
    this.moduleNotice = `NFC 标签 ${tagId} 已触发专注。`
    this.runModule('nfc')
  }

  aboutToAppear(): void {
    this.messageClock = Date.now()
    this.messageClockTimer = setInterval(() => { this.messageClock = Date.now() }, 60000)
    this.features = SessionService.workspaces()
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext
    IntegrationService.initializeLibrary(host)
    try {
      SessionService.list().forEach((summary: SessionSummary) => {
        const session = SessionService.get(summary.id)
        if (session === undefined) return
        session.messages.forEach((message: AgentMessage) => IntegrationService.library?.register(message.attachments || [], '对话附件'))
        session.context.forEach((source: SourceCitation) => IntegrationService.library?.registerContext(source))
      })
    } catch (_error) { this.storageNotice = '部分旧附件未迁入资料库，原对话文件仍保留。' }
    IntegrationService.initializeVoice(this.getUIContext().getHostContext() as common.UIAbilityContext)
    IntegrationService.initializeSchedule(this.getUIContext().getHostContext() as common.UIAbilityContext)
    IntegrationService.initializeFocus(host)
    IntegrationService.initializePrivacy(host)
    host.eventHub.on('focusNfcTap', this.nfcEvent)
    const pendingNfc = NfcFocusBridge.peek()
    this.refreshKnowledge()
    const savedSidebar = SessionService.sidebar()
    const sidebar = SidebarService.normalize(savedSidebar)
    this.fontScale = sidebar.fontScale || 0.9
    this.sideExpanded = sidebar.workspaceSectionExpanded
    this.recentsExpanded = sidebar.recentSectionExpanded
    this.expandedWorkspaceIds = savedSidebar === undefined ? ['home'] : sidebar.expandedWorkspaceIds
    this.expandedHistoryIds = sidebar.expandedHistoryIds
    this.showAllRecent = sidebar.showAllRecent
    this.isLeftPanelVisible = sidebar.panelVisible
    this.isTaskPanelVisible = sidebar.taskPanelVisible !== false
    this.leftWidth = sidebar.leftWidth || 256
    this.rightWidth = sidebar.rightWidth || 274
    this.chooseFeature(FEATURE_CATALOG[0])
    if (pendingNfc.length > 0) this.nfcEvent(pendingNfc)
    this.loadLocalAgentConfig()
  }

  private async loadLocalAgentConfig(): Promise<void> {
    const token = ++this.apiLoadSerial
    this.apiProfilesLoading = true
    try {
      const archive = await LocalAgentConfigService.loadProfiles(this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (token === this.apiLoadSerial) this.applyApiProfiles(archive)
    } catch (error) { if (token === this.apiLoadSerial) this.notice = (error as Error).message || '模型配置读取失败，请重新打开配置窗口。' }
    finally { if (token === this.apiLoadSerial) this.apiProfilesLoading = false }
  }

  aboutToDisappear(): void {
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext
    host.eventHub.off('focusNfcTap', this.nfcEvent)
    IntegrationService.disposeFocus()
    this.apiLoadSerial++
    if (this.messageClockTimer >= 0) clearInterval(this.messageClockTimer)
    this.importSerial++
    this.stopReply()
    this.persistSession()
    this.searchSerial++
    this.actionSerial++
    this.cancelVoice()
    this.stopSpeech()
    this.stopFocusTimer()
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
    if (IntegrationService.library !== undefined) IntegrationService.library.setBase(repository)
    else IntegrationService.knowledge = repository
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

  private applyApiProfiles(archive: AgentProfileArchive): void {
    const settings = LocalAgentConfigService.active(archive)
    IntegrationService.configureAgent(settings)
    this.apiProfiles = LocalAgentConfigService.summaries(archive)
    this.apiActiveId = archive.activeId
    this.apiActiveModel = settings.model
    this.apiConfigured = settings.baseUrl.length > 0 && settings.model.length > 0
  }

  private refreshApiProfiles(): void {
    try {
      const archive = LocalAgentConfigService.readProfiles(this.getUIContext().getHostContext() as common.UIAbilityContext)
      if (archive) this.applyApiProfiles(archive)
    } catch (_error) { this.notice = '模型配置读取失败，当前模型保持不变。' }
  }

  private selectApiProfile(id: string): void {
    if (this.thinking || this.apiProfilesLoading) return
    try { this.applyApiProfiles(LocalAgentConfigService.select(this.getUIContext().getHostContext() as common.UIAbilityContext, id)) }
    catch (error) { this.notice = (error as Error).message || '切换模型失败，请重试。' }
  }

  private toggleApiSettings(): void {
    if (this.thinking || this.apiProfilesLoading) return
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
    try { IntegrationService.library?.registerContext(source) } catch (_error) {}
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
    if (this.activeFeature === 'privacy') adapter = IntegrationService.privacy
    try {
      const result: ModuleResult = await adapter.execute(action, this.moduleInput.trim())
      if (token === this.actionSerial) {
        this.moduleNotice = result.message
        this.moduleItems = result.ok ? result.items : []
        if (result.ok) {
          const id = `module-${this.activeFeature}-${action}`
          const artifacts = this.workspace.artifacts.filter((item: WorkspaceArtifact) => item.id !== id)
          if (artifacts.length < 8) artifacts.push({ id: id, title: `工具结果 · ${action}`,
            content: `${result.message}\n\n${result.items.map((item: ModuleItem) => `### ${item.title}\n${item.detail}`).join('\n\n')}`.slice(0, 12000) })
          this.workspace = WorkspaceService.update(this.workspace, { summary: result.message.slice(0, 3000), artifacts: artifacts })
          this.persistSession()
        }
      }
    } catch (error) {
      if (token === this.actionSerial) { this.moduleNotice = '操作失败，请重试。'; this.moduleItems = [] }
    } finally {
      if (token === this.actionSerial) this.actionBusy = false
    }
  }

  private focusTotalSeconds(): number {
    return (this.focusPhase === 'focus' ? this.focusWorkMinutes : this.focusBreakMinutes) * 60
  }

  private focusProgress(): number {
    const total = this.focusTotalSeconds()
    if (total <= 0) return 0
    return Math.max(0, Math.min(100, ((total - this.focusRemainingSeconds) / total) * 100))
  }

  private formatFocusTime(seconds: number): string {
    const safe = Math.max(0, Math.floor(seconds))
    const minutes = Math.floor(safe / 60)
    const rest = safe % 60
    return `${minutes < 10 ? `0${minutes}` : `${minutes}`}:${rest < 10 ? `0${rest}` : `${rest}`}`
  }

  private startFocusTimer(): void {
    if (this.focusRunning) return
    if (this.focusRemainingSeconds <= 0) this.focusRemainingSeconds = this.focusTotalSeconds()
    this.focusRunning = true
    this.focusEndAt = Date.now() + this.focusRemainingSeconds * 1000
    this.focusTimerId = setInterval((): void => this.tickFocusTimer(), 1000)
  }

  private tickFocusTimer(): void {
    const remaining = Math.max(0, Math.ceil((this.focusEndAt - Date.now()) / 1000))
    this.focusRemainingSeconds = remaining
    if (remaining > 0) return
    this.stopFocusTimer()
    this.finishFocusPhase()
  }

  private stopFocusTimer(): void {
    if (this.focusTimerId >= 0) {
      clearInterval(this.focusTimerId)
      this.focusTimerId = -1
    }
    this.focusRunning = false
  }

  private pauseFocusTimer(): void {
    if (!this.focusRunning) return
    this.focusRemainingSeconds = Math.max(0, Math.ceil((this.focusEndAt - Date.now()) / 1000))
    this.stopFocusTimer()
  }

  private resetFocusTimer(): void {
    this.stopFocusTimer()
    this.focusPhase = 'focus'
    this.focusRemainingSeconds = this.focusWorkMinutes * 60
  }

  private finishFocusPhase(): void {
    if (this.focusPhase === 'focus') {
      this.focusCompleted += 1
      this.focusPhase = 'break'
      this.focusRemainingSeconds = this.focusBreakMinutes * 60
      this.focusGuardActive = false
      FocusGuardService.stopLock().catch(() => {})
      this.focusGuardNotice = '专注完成，设备锁已到期；休息一下吧。'
    } else {
      this.focusPhase = 'focus'
      this.focusRemainingSeconds = this.focusWorkMinutes * 60
    }
  }

  private adjustFocusMinutes(delta: number): void {
    if (this.focusRunning) return
    this.focusWorkMinutes = Math.max(5, Math.min(120, this.focusWorkMinutes + delta))
    if (this.focusPhase === 'focus') this.focusRemainingSeconds = this.focusWorkMinutes * 60
  }

  private async startFocusSession(): Promise<void> {
    if (this.focusRunning) {
      await this.pauseFocusSession()
      return
    }
    if (this.focusPhase !== 'focus') {
      this.focusPhase = 'focus'
      this.focusRemainingSeconds = this.focusWorkMinutes * 60
    }
    this.startFocusTimer()
    if (!this.focusGuardEnabled || this.focusGuardActive) return
    this.focusGuardBusy = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const remainingMinutes = Math.max(1, Math.ceil(this.focusRemainingSeconds / 60))
      const message = await FocusGuardService.startLock(context, remainingMinutes, true)
      this.focusGuardActive = true
      this.focusWhitelistTokens = FocusGuardService.whitelistTokens()
      this.focusGuardNotice = message
    } catch (error) {
      this.focusGuardNotice = `番茄钟已开始，设备锁未开启：${FocusGuardService.friendlyError(error as Error)}`
    } finally {
      this.focusGuardBusy = false
    }
  }

  private async pauseFocusSession(): Promise<void> {
    this.pauseFocusTimer()
    if (!this.focusGuardActive) return
    try {
      await FocusGuardService.stopLock()
    } catch (_error) {}
    this.focusGuardActive = false
    this.focusGuardNotice = '番茄钟已暂停，设备锁已解除；继续时会按剩余时长重新开启。'
  }

  private async enableFocusGuard(): Promise<void> {
    if (this.focusGuardBusy) return
    this.focusGuardBusy = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const remainingMinutes = Math.max(1, Math.ceil(this.focusRemainingSeconds / 60))
      const message = await FocusGuardService.startLock(context, remainingMinutes, true)
      this.focusGuardActive = true
      this.focusWhitelistTokens = FocusGuardService.whitelistTokens()
      this.focusGuardNotice = message
    } catch (error) {
      this.focusGuardNotice = FocusGuardService.friendlyError(error as Error)
    } finally {
      this.focusGuardBusy = false
    }
  }

  private async disableFocusGuard(): Promise<void> {
    if (this.focusGuardBusy) return
    this.focusGuardBusy = true
    try {
      this.focusGuardNotice = await FocusGuardService.stopLock()
      this.focusGuardActive = false
    } catch (error) {
      this.focusGuardNotice = FocusGuardService.friendlyError(error as Error)
    } finally {
      this.focusGuardBusy = false
    }
  }

  private async pickFocusWhitelist(): Promise<void> {
    if (this.focusGuardBusy) return
    this.focusGuardBusy = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      this.focusWhitelistTokens = await FocusGuardService.pickWhitelist(context)
      this.focusGuardNotice = `已选择 ${this.focusWhitelistTokens.length} 个白名单应用。`
    } catch (error) {
      this.focusGuardNotice = FocusGuardService.friendlyError(error as Error)
    } finally {
      this.focusGuardBusy = false
    }
  }

  private async queryFocusGuardStatus(): Promise<void> {
    if (this.focusGuardBusy) return
    this.focusGuardBusy = true
    try {
      const state = await FocusGuardService.snapshot()
      this.focusWhitelistTokens = FocusGuardService.whitelistTokens()
      this.focusGuardActive = state.activeStrategy.length > 0
      this.focusGuardNotice = `授权：${state.authorized ? '已授权' : '未授权'}；策略：${state.strategies.length} 个；白名单：${state.whitelistCount} 个应用。`
    } catch (error) {
      this.focusGuardNotice = FocusGuardService.friendlyError(error as Error)
    } finally {
      this.focusGuardBusy = false
    }
  }

  private applyFocusLockToolTimer(input: string): void {
    let minutes = this.focusWorkMinutes
    try {
      const parsed = JSON.parse(input || '{}') as FocusTimerInput
      if (typeof parsed.durationMinutes === 'number' && Number.isFinite(parsed.durationMinutes)) {
        minutes = Math.max(1, Math.min(1440, Math.round(parsed.durationMinutes)))
      }
    } catch (_error) {}
    this.stopFocusTimer()
    this.focusWorkMinutes = minutes
    this.focusPhase = 'focus'
    this.focusRemainingSeconds = minutes * 60
    this.focusGuardActive = true
    this.focusWhitelistTokens = FocusGuardService.whitelistTokens()
    this.startFocusTimer()
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
      try { IntegrationService.library?.register(files, '对话附件'); this.refreshKnowledge() }
      catch (_error) { this.notice += ' 资料库保存失败，可在资料库中重新导入。' }
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
    this.speakingReply = ''
  }

  private async toggleSpeech(content: string, reply: string): Promise<void> {
    if (this.recording || this.voiceBusy) return
    if (this.speaking && this.speakingReply === reply) { this.stopSpeech(); return }
    if (this.speaking) this.stopSpeech()
    const token = ++this.speechSerial
    this.speaking = true
    this.speakingReply = reply
    const text = MarkdownParser.parse(MarkdownParser.answer(content).body).map((block) =>
      MarkdownParser.inline(block.text).map((run) => run.text).join('')).join('\n')
    try { await IntegrationService.voice.speak(text.slice(0, 8000)) }
    catch (error) { if (token === this.speechSerial) this.notice = (error as Error).message || '语音播报暂不可用。' }
    finally { if (token === this.speechSerial) { this.speaking = false; this.speakingReply = '' } }
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
    this.messageClock = Date.now()
    this.messages = this.messages.map((item: AgentMessage, index: number): AgentMessage => {
      if (index !== position) return item
      const next = ExecutionTraceService.settle(item, status)
      next.completedAt = MessageTimeService.completed(item, status)
      next.role = 'agent'; next.content = content; next.meta = meta; next.sources = sources
      next.renderRevision = (item.renderRevision || 0) + 1
      next.phase = phase || (status === 'streaming' ? 'answering' : item.phase)
      return next
    })
    SessionService.saveMessages(this.activeSession, this.messages, false)
  }

  private recordExecution(sessionId: string, executionId: string, record: ExecutionRecord): void {
    const saved = SessionService.recordExecution(sessionId, executionId, record)
    if (!saved || sessionId !== this.activeSession) return
    try { this.getUIContext().runScopedTask(() => {
      if (sessionId !== this.activeSession) return
      this.messages = this.messages.map((item: AgentMessage): AgentMessage => {
        if (item.executionId !== executionId) return item
        const next = JSON.parse(JSON.stringify(item)) as AgentMessage
        next.executions = saved.executions; next.thinkingLastActiveAt = saved.thinkingLastActiveAt
        next.renderRevision = (item.renderRevision || 0) + 1
        return next
      })
      this.storageNotice = SessionService.storageNotice
    }) } catch (_error) { /* The persisted receipt remains valid after its view is destroyed. */ }
  }

  private toggleThought(position: number): void {
    const id = `${this.activeSession}-${position}`
    this.expandedThoughts = this.expandedThoughts.includes(id)
      ? this.expandedThoughts.filter((item: string) => item !== id) : [...this.expandedThoughts, id]
  }

  private persistSession(): void {
    if (this.isWelcomePage || this.activeFeature === 'trash' || !this.activeSession) return
    SessionService.saveWorkspace(this.activeSession, this.activeFeature, this.workspace)
    SessionService.saveDetails(this.activeSession, this.selectedContext, this.progress)
    SessionService.saveMessages(this.activeSession, this.messages)
    this.sessions = SessionService.list()
    this.refreshSidebar()
    this.storageNotice = SessionService.storageNotice
  }

  private restoreSession(session: ChatSession, reveal: boolean = true): void {
    this.isWelcomePage = false
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
    this.workspace = WorkspaceService.restore(session.featureId, session.workspace, this.features)
    this.artifactVisible = false
    this.inputText = ''
    this.contextPickerVisible = false
    this.moduleInput = ''
    this.moduleItems = []
    this.moduleNotice = ''
    this.expandedSourceId = ''
    this.notice = ''
    SessionService.activate(session.id)
    this.sessions = SessionService.list()
    this.refreshSidebar()
    this.storageNotice = SessionService.storageNotice
    const sessionId = session.id
    setTimeout(() => {
      if (this.activeSession === sessionId) {
        this.chatScroller.scrollEdge(Edge.Bottom)
        if (reveal) this.revealWorkspace()
      }
    }, 50)
  }

  private completedTasks(): number { return this.workspace.tasks.filter((task: WorkspaceTask) => task.status === 'completed').length }

  private revealWorkspace(): void {
    this.sideExpanded = true
    if (!this.expandedWorkspaceIds.includes(this.activeFeature)) this.expandedWorkspaceIds = [...this.expandedWorkspaceIds, this.activeFeature]
    const index = this.sessions.filter((item: SessionSummary) => item.featureId === this.activeFeature)
      .findIndex((item: SessionSummary) => item.id === this.activeSession)
    if (index >= SidebarService.workspacePreviewCount && !this.expandedHistoryIds.includes(this.activeFeature)) {
      this.expandedHistoryIds = [...this.expandedHistoryIds, this.activeFeature]
    }
    this.persistSidebar()
  }

  private sidebarPreferences(): SidebarPreferences {
    return { workspaceSectionExpanded: this.sideExpanded, recentSectionExpanded: this.recentsExpanded,
      expandedWorkspaceIds: this.expandedWorkspaceIds, expandedHistoryIds: this.expandedHistoryIds,
      showAllRecent: this.showAllRecent, panelVisible: this.isLeftPanelVisible, taskPanelVisible: this.isTaskPanelVisible,
      leftWidth: this.leftWidth, rightWidth: this.rightWidth, fontScale: this.fontScale }
  }

  private refreshSidebar(): void {
    this.sidebarView = SidebarService.view(this.sessions, this.features, this.sidebarPreferences(), this.sidebarQuery)
  }

  private persistSidebar(): void {
    SessionService.saveSidebar(this.sidebarPreferences())
    this.storageNotice = SessionService.storageNotice
    this.refreshSidebar()
  }

  private toggleWorkspaceGroup(id: string): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.expandedWorkspaceIds = this.expandedWorkspaceIds.includes(id)
        ? this.expandedWorkspaceIds.filter((item: string) => item !== id) : [...this.expandedWorkspaceIds, id]
      this.persistSidebar()
    })
  }

  private toggleWorkspaceHistory(id: string): void {
    this.expandedHistoryIds = this.expandedHistoryIds.includes(id)
      ? this.expandedHistoryIds.filter((item: string) => item !== id) : [...this.expandedHistoryIds, id]
    this.persistSidebar()
  }

  private toggleTask(id: string): void {
    if (this.thinking || this.activeFeature === 'trash') return
    const tasks = this.workspace.tasks.map((task: WorkspaceTask): WorkspaceTask => ({ id: task.id, title: task.title,
      detail: task.detail, status: task.id === id ? (task.status === 'completed' ? 'pending' : 'completed') : task.status }))
    this.workspace = WorkspaceService.update(this.workspace, { tasks: tasks })
    this.persistSession()
  }

  private showArtifact(item: WorkspaceArtifact): void {
    this.artifactId = item.id
    this.artifactTitle = item.title
    this.artifactContent = item.content
    this.artifactVisible = true
  }

  private feedbackFor(id: string): InteractionRecord { return InteractionService.record(this.workspace.interactions, id) }

  private changeInteraction(id: string, source: string, title: string, content: string, change: InteractionChange): void {
    if (this.thinking || this.isWelcomePage || this.activeFeature === 'trash' || !this.activeSession ||
      change.sessionId !== this.activeSession || change.documentId !== id) return
    if (change.submit === true && (this.recording || this.voiceBusy || this.attachmentBusy || this.actionBusy)) {
      this.notice = '请先结束录音或等待当前操作完成，再提交检查。'; return
    }
    try {
      const control = InteractionService.layout(content).controls.find((item) => item.id === change.controlId)
      if (change.submit !== true && change.reset !== true && control !== undefined && !InteractionService.isPreviousVersion(this.feedbackFor(id), content) &&
        InteractionService.controlValue(this.feedbackFor(id), control) === change.value) return
      const next = WorkspaceService.copy(this.workspace)
      next.interactions = InteractionService.update(next.interactions, id, source, title, content, change)
      next.updatedAt = Date.now()
      this.workspace = next
      SessionService.saveWorkspace(this.activeSession, this.activeFeature, this.workspace,
        change.reset === true || (change.controlId !== 'notes' && !change.controlId.includes('-cell-') && !change.controlId.includes('-blank-')))
      this.storageNotice = SessionService.storageNotice
      if (change.submit === true && change.controlId === 'decision' && change.value === 'confirmed') {
        const review = InteractionService.review(content, this.feedbackFor(id))
        this.artifactVisible = false
        this.sendMessage(`请检查我提交的「${title}」：根据当前填写和勾选情况回复，有缺失请指出，信息完整则给出结果。`, review)
      }
    } catch (error) {
      this.notice = (error as Error).message || '交互反馈保存失败，请重试。'
      try { this.getUIContext().getPromptAction().showToast({ message: this.notice, duration: 2000 }) } catch (_error) {}
    }
  }

  private changeMessageInteraction(index: number, change: InteractionChange): void {
    const message = this.messages[index]
    if (message === undefined || message.role !== 'agent' || message.status === 'loading' || message.status === 'streaming') return
    const body = MarkdownParser.answer(message.content).body
    this.changeInteraction(`message-${index}`, 'message', `对话回复 ${index + 1}`, body, change)
  }

  private async executeWorkspaceTool(call: AgentToolCall, token: number, sessionId: string): Promise<string> {
    if (token !== this.requestSerial || sessionId !== this.activeSession) return JSON.stringify({ ok: false, status: 'cancelled', message: '会话已切换或生成已停止。' })
    const uiContext = this.getUIContext()
    try {
      if (call.name === 'manage_agent_task') {
        const active = (): boolean => token === this.requestSerial && sessionId === this.activeSession
        return await AgentTaskManager.execute(this.getUIContext().getHostContext() as common.UIAbilityContext, call, active,
          async (title: string, detail: string): Promise<boolean> => {
            if (!active()) return false
            try {
              const choice = await uiContext.getPromptAction().showDialog({ title: title, message: detail,
                buttons: [{ text: '取消', color: '#777777' }, { text: '确认', color: '#202020' }] })
              return active() && choice.index === 1
            } catch (_error) { return false }
          })
      }
      if (ScheduleService.handles(call.name)) {
        const platform = IntegrationService.schedule
        if (platform === undefined) return JSON.stringify({ ok: false, message: '系统日程服务尚未初始化。' })
        const active = (): boolean => token === this.requestSerial && sessionId === this.activeSession
        const result = await ScheduleService.execute(call, platform, active, async (title: string, detail: string): Promise<boolean> => {
          if (!active()) return false
          try {
            const choice = await uiContext.getPromptAction().showDialog({ title: title, message: detail,
              buttons: [{ text: '取消', color: '#777777' }, { text: '确认', color: '#202020' }] })
            return active() && choice.index === 1
          } catch (_error) { return false }
        })
        // A completed native operation stays a real receipt even if the user changes conversation afterwards.
        if (active()) uiContext.runScopedTask(() => { this.moduleNotice = result.message })
        return JSON.stringify(result)
      }
      const result = WorkspaceService.applyTool(call.name, call.arguments, this.activeFeature, this.workspace, this.features)
      if (result.action !== undefined) {
        const adapter = result.featureId === 'forms' ? IntegrationService.forms : result.featureId === 'study'
          ? IntegrationService.study : IntegrationService.hardware
        const moduleResult = await adapter.execute(result.action, result.input || '')
        if (token !== this.requestSerial || sessionId !== this.activeSession) return JSON.stringify({ ok: false, status: 'cancelled', message: '操作结果已过期，不再更新当前会话。' })
        uiContext.runScopedTask(() => { this.moduleNotice = moduleResult.message; this.moduleItems = moduleResult.ok ? moduleResult.items : [] })
        if (!moduleResult.ok) return JSON.stringify({ ok: false, message: moduleResult.message })
        if (result.featureId === 'focus' && result.action === 'start') {
          uiContext.runScopedTask(() => {
            this.focusGuardActive = true
            this.focusGuardNotice = moduleResult.message
            this.applyFocusLockToolTimer(result.input || '')
          })
        } else if (result.featureId === 'focus' && result.action === 'stop') {
          uiContext.runScopedTask(() => {
            this.focusGuardActive = false
            this.focusGuardNotice = moduleResult.message
            this.stopFocusTimer()
          })
        } else if (result.featureId === 'focus') {
          uiContext.runScopedTask(() => { this.focusGuardNotice = moduleResult.message })
        }
        const id = `module-${result.featureId}-${result.action}`
        const artifacts = result.state.artifacts.filter((item: WorkspaceArtifact) => item.id !== id)
        if (artifacts.length < 8) artifacts.push({ id: id, title: `工具结果 · ${result.action}`,
          content: `${moduleResult.message}\n\n${moduleResult.items.map((item: ModuleItem) => `### ${item.title}\n${item.detail}`).join('\n\n')}`.slice(0, 12000) })
        result.state = WorkspaceService.update(result.state, { summary: moduleResult.message.slice(0, 3000), artifacts: artifacts })
        result.message = moduleResult.message
      }
      if (token !== this.requestSerial || sessionId !== this.activeSession) return JSON.stringify({ ok: false, status: 'cancelled', message: '生成已停止。' })
      if (call.name !== 'read_workspace') {
        uiContext.runScopedTask(() => {
          this.activeFeature = result.featureId
          this.workspace = result.state
          this.isTaskPanelVisible = true
          this.persistSession()
          if (call.name === 'switch_workspace') this.revealWorkspace()
        })
        if (SessionService.storageNotice) return JSON.stringify({ ok: false, message: `面板已更新，但保存失败：${SessionService.storageNotice}` })
      }
      return JSON.stringify({ ok: true, message: result.message, workspace: WorkspaceService.snapshot(result.featureId, result.state, this.features) })
    } catch (error) {
      return JSON.stringify({ ok: false, message: (error as Error).message || '工作区操作失败。' })
    }
  }

  private chooseFeature(feature: FeatureDefinition): void {
    this.appSection = 'chat'
    if (feature.id === 'trash') { this.openRecycleBin(); return }
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.actionSerial++
    this.actionBusy = false
    this.importSerial++
    this.attachmentBusy = false
    const filesDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir
    this.draftAttachments.forEach((item: ChatAttachment) => AttachmentService.removeDraft(item, filesDir))
    this.draftAttachments = []
    this.activeSession = ''
    this.activeFeature = feature.id
    this.isWelcomePage = true
    this.messages = []
    this.workspace = WorkspaceService.create(feature.id, this.features)
    this.progress = 0
    this.selectedContext = []
    this.expandedThoughts = []
    this.inputText = ''
    this.contextPickerVisible = false
    this.artifactVisible = false
    this.apiSettingsVisible = false
    this.moduleInput = ''
    this.moduleItems = []
    this.moduleNotice = ''
    this.notice = ''
    this.sidebarQuery = ''
    this.sessions = SessionService.list()
    this.refreshSidebar()
    this.storageNotice = SessionService.storageNotice
  }

  private openHome(): void {
    this.sidebarSelection = 'workspace-home'
    this.chooseFeature(FEATURE_CATALOG[0])
  }

  private welcomeGreeting(): string {
    const hour = new Date().getHours()
    return `${hour < 6 ? '夜深了' : hour < 12 ? '早上好' : hour < 18 ? '下午好' : '晚上好'}，欢迎回来`
  }

  private openSession(session: string): void {
    this.appSection = 'chat'
    if (session === this.activeSession) return
    const saved = SessionService.get(session)
    if (saved === undefined) return
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.actionSerial++
    this.actionBusy = false
    this.restoreSession(saved, false)
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
      const permanent = session.featureId === 'trash'
      const result = await this.getUIContext().getPromptAction().showDialog({ title: permanent ? '永久删除会话' : '移入回收站',
        message: permanent ? `永久删除“${session.title}”及其本地消息和附件？此操作无法撤销。` : `将“${session.title}”移入回收站？消息和附件会被保留，可以恢复。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: permanent ? '永久删除' : '移入回收站', color: '#666666' }] })
      confirmed = result.index === 1
    } catch (_error) { return }
    if (!confirmed) return
    const active = id === this.activeSession
    if (active) {
      this.stopReply()
      this.persistSession()
      this.cancelVoice()
      this.stopSpeech()
      this.actionSerial++
      this.actionBusy = false
    }
    if (!(session.featureId === 'trash' ? SessionService.remove(id) : SessionService.trash(id))) {
      this.storageNotice = SessionService.storageNotice || '删除失败，请重试。'
      return
    }
    this.expandedThoughts = this.expandedThoughts.filter((item: string) => !item.startsWith(`${id}-`))
    if (active) this.openRecycleBin()
    else { this.sessions = SessionService.list(); this.refreshSidebar(); this.storageNotice = SessionService.storageNotice }
  }

  private createChat(featureId: string = ''): void {
    const target = (featureId || this.activeFeature) === 'trash' ? 'home' : featureId || this.activeFeature
    this.chooseFeature(this.features.find((feature: FeatureDefinition) => feature.id === target) || FEATURE_CATALOG[0])
    this.revealWorkspace()
  }

  private openRecycleBin(): void {
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.importSerial++
    this.attachmentBusy = false
    const filesDir = (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir
    this.draftAttachments.forEach((item: ChatAttachment) => AttachmentService.removeDraft(item, filesDir))
    this.draftAttachments = []
    this.actionSerial++
    this.actionBusy = false
    this.activeFeature = 'trash'
    this.isWelcomePage = false
    this.activeSession = ''
    this.messages = []
    this.inputText = ''
    this.notice = ''
    this.contextPickerVisible = false
    this.apiSettingsVisible = false
    this.sidebarQuery = ''
    this.sessions = SessionService.list()
    this.revealWorkspace()
    setTimeout((): void => { this.chatScroller.scrollEdge(Edge.Top) }, 30)
  }

  private restoreTrashSession(id: string): void {
    this.stopReply()
    this.persistSession()
    this.cancelVoice()
    this.stopSpeech()
    this.actionSerial++
    this.actionBusy = false
    if (!SessionService.restore(id)) { this.storageNotice = SessionService.storageNotice || '恢复失败，请重试。'; return }
    const session = SessionService.get(id)
    if (session !== undefined) this.restoreSession(session)
  }

  private startWorkspaceEditor(): void {
    this.workspaceName = ''
    this.workspaceDescription = ''
    this.workspacePrompt = ''
    this.workspaceEditorNotice = ''
    this.workspaceEditorVisible = true
  }

  private saveNewWorkspace(): void {
    try {
      const feature = SessionService.addWorkspace(this.workspaceName, this.workspaceDescription, this.workspacePrompt)
      if (feature === undefined) { this.workspaceEditorNotice = SessionService.storageNotice || '保存失败，请重试。'; return }
      this.features = SessionService.workspaces()
      this.workspaceEditorVisible = false
      this.chooseFeature(feature)
    } catch (error) { this.workspaceEditorNotice = (error as Error).message }
  }

  private async confirmDeleteWorkspace(id: string): Promise<void> {
    if (id === 'home' || id === 'trash') return
    const feature = this.features.find((item: FeatureDefinition) => item.id === id)
    if (feature === undefined) return
    const count = this.sessions.filter((item: SessionSummary) => item.featureId === id).length
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: `删除工作区「${feature.name}」`,
        message: `其中 ${count} 个会话将全部移入回收站，消息、资料和附件会保留。恢复时，已删除工作区的会话会回到智能助理。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除工作区', color: '#666666' }] })
      if (result.index !== 1) return
    } catch (_error) { return }
    this.stopReply()
    this.persistSession()
    if (!SessionService.deleteWorkspace(id)) { this.storageNotice = SessionService.storageNotice || '删除失败，请重试。'; return }
    this.features = SessionService.workspaces()
    this.expandedWorkspaceIds = this.expandedWorkspaceIds.filter((value: string) => value !== id)
    this.expandedHistoryIds = this.expandedHistoryIds.filter((value: string) => value !== id)
    this.sessions = SessionService.list()
    if (this.activeFeature === id) {
      // The archived conversation has moved; do not persist the obsolete feature again.
      this.activeFeature = 'trash'
      this.activeSession = ''
      this.openRecycleBin()
    } else this.refreshSidebar()
    this.persistSidebar()
  }

  private panelWidth(side: string): number {
    const minimum = SidebarService.panelMinimum(side, this.fontScale)
    const available = Math.max(minimum, this.viewportWidth - this.globalRailWidth() - 360 -
      (side === 'left' ? (this.isTaskPanelVisible && !this.isWelcomePage && this.activeFeature !== 'trash' ? this.rightWidth + 8 : 0)
        : (this.isLeftPanelVisible ? Math.max(this.leftWidth, SidebarService.panelMinimum('left', this.fontScale)) : 0) + 8))
    return Math.min(Math.max(side === 'left' ? this.leftWidth : this.rightWidth, minimum), available)
  }

  private globalRailWidth(): number { return 52 * Math.max(1, this.fontScale) }

  private chatPlaceholder(): string {
    return this.activeFeature === 'home' ? '向 CampusPilot 描述你的下一步…' : `在${this.selectedFeature().name}中，想做些什么…`
  }

  private resizePanel(side: string, offset: number): void {
    const maximum = Math.max(SidebarService.panelMinimum(side, this.fontScale), this.viewportWidth - this.globalRailWidth() - 360 -
      (side === 'left' ? (this.isTaskPanelVisible && !this.isWelcomePage && this.activeFeature !== 'trash' ? this.rightWidth + 16 : 8)
        : (this.isLeftPanelVisible ? this.panelWidth('left') : 0) + 16))
    const result = SidebarService.resize(side, this.dragStartWidth, offset, Math.min(side === 'left' ? 400 : 420, maximum), this.fontScale)
    this.pendingPanelCollapse = result.collapsed ? side : ''
    if (side === 'left') this.leftWidth = result.width
    else this.rightWidth = result.width
  }

  private finishPanelResize(cancelled: boolean = false): void {
    const side = this.pendingPanelCollapse
    this.resizingPanel = ''
    this.pendingPanelCollapse = ''
    if (side && !cancelled) {
      if (side === 'left') { this.leftWidth = Math.max(this.dragStartWidth, SidebarService.panelMinimum(side, this.fontScale)); this.isLeftPanelVisible = false }
      else { this.rightWidth = Math.max(this.dragStartWidth, SidebarService.panelMinimum(side, this.fontScale)); this.isTaskPanelVisible = false }
    }
    this.persistSidebar()
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({
      normal: { .opacity(1).scale({ x: 1, y: 1 }) },
      pressed: { .opacity(0.76).scale({ x: 0.98, y: 0.98 }) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
  }

  @Styles
  inputFeedback() {
    .stateStyles({
      normal: { .border({ width: 1, color: Color.Transparent }) },
      focused: { .border({ width: 1, color: UiTheme.focus }).shadow({ radius: 8, color: UiTheme.shadow, offsetY: 0 }) }
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
  }

  private sendMessage(prompt: string, reviewContext: string = ''): void {
    if (this.activeFeature === 'trash') return
    if (this.apiProfilesLoading) { this.notice = '正在读取模型配置，请稍后发送。'; return }
    const message = prompt.trim() || (this.draftAttachments.length > 0 ? '请分析这些附件。' : '')
    if (message.length === 0 || this.thinking || this.recording || this.voiceBusy || this.attachmentBusy || this.actionBusy) return
    if (!this.apiConfigured) { this.toggleApiSettings(); return }
    if (!this.activeSession) {
      this.activeSession = SessionService.create(this.activeFeature, '新对话', []).id
    }
    this.isWelcomePage = false
    const token = ++this.requestSerial
    const uiContext = this.getUIContext()
    const featureId = this.activeFeature
    const sessionId = this.activeSession
    const workspace = WorkspaceService.copy(this.workspace)
    const history = this.messages.slice()
    const gateway = IntegrationService.agent
    this.activeGateway = gateway
    const attachedContext = this.selectedContext.slice()
    const attachments = reviewContext ? [] : this.draftAttachments.slice()
    const executionId = util.generateRandomUUID()
    const startedAt = Date.now()
    this.messageClock = startedAt
    const secrets = [IntegrationService.agentSettings.apiKey, IntegrationService.agentSettings.baseUrl]
    const retrievalRecord: ExecutionRecord = { id: 'retrieval', kind: 'retrieval', name: 'local_retrieval', title: '检索与引用资料',
      status: 'running', startedAt: startedAt, input: '', detail: '正在查找本地资料及已选上下文。', targets: [] }
    if (!reviewContext) this.draftAttachments = []
    this.messages = [...this.messages, { role: 'user', content: message, meta: '现在', attachments: attachments, createdAt: startedAt }]
    this.messages = [...this.messages, { role: 'agent', content: '', meta: '正在检索资料', status: 'loading',
      sources: [], createdAt: startedAt, thinkingStartedAt: startedAt, thinkingLastActiveAt: startedAt, phase: 'retrieving', executionId: executionId,
      executions: attachments.length > 0 ? [retrievalRecord, ExecutionTraceService.attachments(attachments, secrets)] : [retrievalRecord] }]
    const replyIndex = this.messages.length - 1
    if (!reviewContext) this.inputText = ''
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
    let waitingForSystem = false
    let toolOrdinal = 0
    let responseDeadline = Date.now() + ApiConfig.requestTimeoutMs + 3000
    const timeout = setInterval(() => {
      if (token !== this.requestSerial) { clearInterval(timeout); return }
      // OS authorization and the user's review are not model network latency.
      if (waitingForSystem) { responseDeadline = Date.now() + ApiConfig.requestTimeoutMs + 3000; return }
      if (Date.now() < responseDeadline) return
      clearInterval(timeout)
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
    }, 1000)
    const sink: StreamSink = new ChatStreamSink((): boolean => token !== this.requestSerial, (delta: string): void => {
      uiContext.runScopedTask(() => {
        if (token !== this.requestSerial) return
        content = (content + delta).slice(0, 16000)
        this.updateReply(replyIndex, content, `${gateway.name} · 正在流式生成`, 'streaming', sources)
      })
    }, (phase: string): void => {
      uiContext.runScopedTask(() => {
        if (token !== this.requestSerial) return
        this.updateReply(replyIndex, content, `${gateway.name} · 正在分析`, content.trim() ? 'streaming' : 'loading', sources, phase)
      })
    })
    ChatService.reply(message, featureId, history, this.retrievalOptions(), IntegrationService.rag(), gateway, sink,
      (result: RetrievalResult): void => {
        uiContext.runScopedTask(() => {
          if (token !== this.requestSerial) return
          sources = result.sources
          this.notice = result.notice
          this.updateReply(replyIndex, '', `${gateway.name} · ${sources.length} 条参考资料`, 'loading', sources, 'connecting')
          this.recordExecution(sessionId, executionId, ExecutionTraceService.retrieval('retrieval', startedAt, sources, secrets))
        })
      }, attachedContext, attachments, workspace, (call: AgentToolCall): Promise<string> => {
        waitingForSystem = ScheduleService.handles(call.name) || call.name === 'manage_agent_task'
        const record = ExecutionTraceService.tool(`tool-${++toolOrdinal}`, call, secrets)
        const before = WorkspaceService.copy(this.workspace).artifacts
        this.recordExecution(sessionId, executionId, record)
        return this.executeWorkspaceTool(call, token, sessionId).then((output: string): string => {
          this.recordExecution(sessionId, executionId, ExecutionTraceService.finish(record, call, output, before, secrets))
          return output
        }).catch((error: Error): string => {
          const output = JSON.stringify({ ok: false, message: error.message || '工具操作失败。' })
          this.recordExecution(sessionId, executionId, ExecutionTraceService.finish(record, call, output, before, secrets))
          return output
        }).finally(() => {
          if (waitingForSystem) responseDeadline = Date.now() + ApiConfig.requestTimeoutMs + 3000
          waitingForSystem = false
        })
      }, this.features, reviewContext).then(() => {
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
        clearInterval(timeout)
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
    const next = this.workspace.tasks.find((task: WorkspaceTask) => task.status !== 'completed')
    this.sendMessage('请先读取本会话最新的交互反馈，包括对话、产物及记忆中的勾选、表格填写、确认和补充说明，再决定下一步。' +
      (next === undefined ? '根据实际进展整理总结并保存为产物。'
        : `参考任务「${next.title}」${next.detail ? `，详情：${next.detail}` : ''}，保留用户已确认的信息，继续处理尚未完成的部分并更新任务面板。`) +
      '本地勾选或确认不代表外部提交已执行，不要假定未确认的现实任务已完成。')
  }

  private toggleWorkspace(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.sideExpanded = !this.sideExpanded
      this.persistSidebar()
    })
  }

  private toggleRecents(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.recentsExpanded = !this.recentsExpanded
      this.persistSidebar()
    })
  }

  private toggleLeftPanel(): void {
    this.isLeftPanelVisible = !this.isLeftPanelVisible
    this.leftWidth = Math.max(this.leftWidth, SidebarService.panelMinimum('left', this.fontScale))
    this.persistSidebar()
  }

  private toggleTaskPanel(): void {
    this.isTaskPanelVisible = !this.isTaskPanelVisible
    this.rightWidth = Math.max(this.rightWidth, SidebarService.panelMinimum('right', this.fontScale))
    this.persistSidebar()
  }

  @Builder
  CareerContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('求职实验室').fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('将岗位目标、简历版本和练习记录沉淀在同一项目。').fontSize(13 * this.fontScale).fontColor(UiTheme.muted)
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Text(this.workspace.goal || '先明确目标岗位').fontSize(11 * this.fontScale).fontColor('#666666').maxLines(2).constraintSize({ maxWidth: 200 })
          .padding(8).backgroundColor(UiTheme.raised).borderRadius(8)
      }.width('100%')
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text('01').fontSize(12 * this.fontScale).fontColor('#666666')
          Text('简历诊断').fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#303030')
          Text('提取岗位关键词与量化成果').fontSize(11 * this.fontScale).fontColor('#777777')
        }.alignItems(HorizontalAlign.Start).width('32%').padding(14).backgroundColor(UiTheme.raised).borderRadius(12)
          .enabled(!this.thinking).interactive().onClick(() => this.sendMessage('请根据我的目标岗位分析简历，列出需要提供的信息，并将优化清单同步到任务面板。'))
        Column({ space: 5 }) {
          Text('02').fontSize(12 * this.fontScale).fontColor(UiTheme.primary)
          Text('模拟面试').fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#303030')
          Text('多轮追问与反馈复盘').fontSize(11 * this.fontScale).fontColor('#777777')
        }.alignItems(HorizontalAlign.Start).width('32%').padding(14).backgroundColor(UiTheme.raised).borderRadius(12)
          .enabled(!this.thinking).interactive().onClick(() => this.sendMessage('开始一轮模拟面试，一次问一个问题，根据我的回答追问并保留复盘。'))
        Column({ space: 5 }) {
          Text('03').fontSize(12 * this.fontScale).fontColor(UiTheme.primary)
          Text('投递追踪').fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#303030')
          Text('记录进展与复盘建议').fontSize(11 * this.fontScale).fontColor('#777777')
        }.alignItems(HorizontalAlign.Start).width('32%').padding(14).backgroundColor(UiTheme.raised).borderRadius(12)
          .enabled(!this.thinking).interactive().onClick(() => this.sendMessage('帮我整理投递追踪清单，只记录我已提供的信息，并保存为产物。'))
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  ScheduleContent() {
    Column({ space: 12 }) {
      Text('本周智能日程').fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text('Agent 会根据截止日期、预计耗时和精力曲线调整安排。').fontSize(13 * this.fontScale).fontColor(UiTheme.muted)
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text(`${this.workspace.tasks.length - this.completedTasks()}`).fontSize(28 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary)
          Text('待完成任务').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
        }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor(UiTheme.raised).borderRadius(12)
        Column({ space: 5 }) {
          Text(`${this.workspace.artifacts.length}`).fontSize(28 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary)
          Text('已保存计划').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
        }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor(UiTheme.raised).borderRadius(12)
        Column({ space: 5 }) {
          Text(`${this.workspace.tasks.length ? Math.round(this.completedTasks() / this.workspace.tasks.length * 100) : 0}%`).fontSize(28 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary)
          Text('任务完成度').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
        }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor(UiTheme.raised).borderRadius(12)
      }.width('100%')
      Column({ space: 10 }) {
        Text('当前安排 · 与任务面板同步').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#404040')
        ForEach(this.workspace.tasks, (task: WorkspaceTask) => {
          Column({ space: 4 }) {
            Text(`${task.status === 'completed' ? '✓' : '○'} ${task.title}`).fontSize(14 * this.fontScale).fontColor('#404040')
            Text(task.detail || '待补充时间与要求').fontSize(11 * this.fontScale).fontColor('#888888')
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 5, bottom: 5 }).enabled(!this.thinking)
            .interactive().onClick(() => this.sendMessage(`请帮我细化安排「${task.title}」，已有详情：${task.detail || '无'}。更新任务面板。`))
        }, (task: WorkspaceTask) => `${task.id}-${task.title}-${task.detail}-${task.status}`)
      }.width('100%').padding(15).backgroundColor(UiTheme.surface).borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  BudgetContent() {
    Column({ space: 12 }) {
      Text('消费洞察').fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text('整理你提供的消费与预算，清单和分析保存在当前会话。').fontSize(13 * this.fontScale).fontColor(UiTheme.muted)
      Row({ space: 10 }) {
        Column({ space: 5 }) { Text(`${this.workspace.tasks.length - this.completedTasks()}`).fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary); Text('整理待办').fontSize(11 * this.fontScale).fontColor(UiTheme.muted) }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor(UiTheme.raised).borderRadius(12)
        Column({ space: 5 }) { Text(`${this.workspace.artifacts.length}`).fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary); Text('已保存产物').fontSize(11 * this.fontScale).fontColor(UiTheme.muted) }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor(UiTheme.raised).borderRadius(12)
        Column({ space: 5 }) { Text(`${this.completedTasks()}`).fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary); Text('已完成任务').fontSize(11 * this.fontScale).fontColor(UiTheme.muted) }.alignItems(HorizontalAlign.Start).width('31%').padding(15).backgroundColor(UiTheme.raised).borderRadius(12)
      }.width('100%')
      Column({ space: 8 }) {
        Text('消费整理与分析').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#404040')
        if (this.workspace.artifacts.length === 0) { Text('发送消费记录或预算后，让 Agent 整理并保存。').fontSize(12 * this.fontScale).fontColor('#888888') }
        ForEach(this.workspace.artifacts, (item: WorkspaceArtifact) => {
          Text(`▤ ${item.title} →`).fontSize(13 * this.fontScale).fontColor(UiTheme.primary).width('100%').padding({ top: 7, bottom: 7 })
            .interactive().onClick(() => { this.isTaskPanelVisible = true; this.showArtifact(item) })
        }, (item: WorkspaceArtifact) => `${item.id}-${item.title}-${item.content}`)
      }.width('100%').padding(15).backgroundColor(UiTheme.surface).borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  PlaceholderContent() {
    Column({ space: 10 }) {
      Text(this.selectedFeature().name).fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text(this.selectedFeature().description).fontSize(14 * this.fontScale).fontColor(UiTheme.muted)
      Text(this.workspaceProfile().greeting).fontSize(13 * this.fontScale).fontColor('#666666').lineHeight(20 * this.fontScale)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 24, bottom: 8 })
  }

  @Builder
  ApiSettingsSheet() {
    ApiProfilesSheet({ onChanged: () => this.refreshApiProfiles(), onClose: () => { this.apiSettingsVisible = false } })
  }
  @Builder
  ContextSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('添加上下文').fontSize(21 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Blank()
        Button('完成').fontSize(13 * this.fontScale).height(40).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
          .accessibilityText('完成并关闭上下文弹窗').interactive().onClick(() => this.contextPickerVisible = false)
      }.width('100%')
      Text(`已加入 ${this.selectedContext.length} 条资料，仅用于当前对话`).fontSize(12 * this.fontScale).fontColor(UiTheme.muted).width('100%')
      Divider().color('#E5E5E5')
      Scroll() { this.KnowledgeContent() }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding(22).backgroundColor(UiTheme.background)
  }

  @Builder
  KnowledgeContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('为当前对话添加资料').fontSize(19 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text(`${this.knowledgeCount} 个资料片段 · 从资料库统一管理`).fontSize(12 * this.fontScale).fontColor(UiTheme.muted)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('刷新').height(44).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised).interactive().onClick(() => this.refreshKnowledge())
      }.width('100%')
      if (this.knowledgeRevision.includes('demo-1')) {
        Text('离线演示资料，不代表学校官方资料。').fontSize(12 * this.fontScale).fontColor('#666666').width('100%').padding(10).backgroundColor(UiTheme.raised).borderRadius(9).transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
      }
      if (this.knowledgeCount === 0) {
        Text('还没有可检索的文字资料。请到资料库导入，也可载入离线样例体验检索。').fontSize(13 * this.fontScale).fontColor(UiTheme.muted).lineHeight(21 * this.fontScale).width('100%')
        Button('打开资料库').height(36 * this.fontScale).fontSize(12 * this.fontScale).fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .onClick(() => { this.contextPickerVisible = false; this.navigateSection('library') })
        Button('载入演示资料').height(44).fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary).interactive().onClick(() => this.loadDemoKnowledge())
      }
      Row({ space: 7 }) {
        Button(this.knowledgeCourse === '' ? '全部课程 ✓' : '全部课程').fontSize(12 * this.fontScale).height(44)
          .fontColor(UiTheme.primary).backgroundColor(this.knowledgeCourse === '' ? UiTheme.raised : UiTheme.raised)
          .interactive().onClick(() => { this.knowledgeCourse = ''; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
        ForEach(this.knowledgeCourses, (course: string) => {
          Button(this.knowledgeCourse === course ? `${course} ✓` : course).fontSize(12 * this.fontScale).height(44)
            .fontColor(UiTheme.primary).backgroundColor(this.knowledgeCourse === course ? UiTheme.raised : UiTheme.raised)
            .interactive().onClick(() => { this.knowledgeCourse = course; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
        }, (course: string) => course)
      }.width('100%')
      TextInput({ text: this.knowledgeQuery, placeholder: '搜索问题，例如：黑盒测试有哪些方法？' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale })
        .height(40 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(9).padding({ left: 12, right: 8 })
        .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').inputFeedback().onChange((value: string) => this.knowledgeQuery = value).onSubmit(() => this.searchKnowledge())
      Row({ space: 8 }) {
        Button(this.searchBusy ? '检索中…' : '搜索资料').height(44).fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary)
          .backgroundColor(UiTheme.primary).enabled(!this.searchBusy).interactive().onClick(() => this.searchKnowledge())
        Button(this.minScore <= 0.10 ? '恢复默认阈值' : '放宽匹配').height(44).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
          .interactive().onClick(() => { this.minScore = this.minScore <= 0.10 ? 0.35 : this.minScore - 0.05; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
        Button(`结果 ${this.topK}`).height(44).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
          .interactive().onClick(() => { this.topK = this.topK >= 6 ? 2 : this.topK + 1; if (this.knowledgeQuery.trim()) this.searchKnowledge() })
      }.width('100%')
      if (this.retrieval.query.length > 0) {
        Text(`找到 ${this.retrieval.sources.length} 条来源 · ${this.retrieval.mode === 'hybrid' ? '混合检索' : '关键词检索'}`)
          .fontSize(12 * this.fontScale).fontColor(UiTheme.muted).width('100%')
        ForEach(this.retrieval.sources, (source: SourceCitation) => {
          Column({ space: 7 }) {
            Text(`[${source.number}] ${source.title}`).fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#303030').width('100%')
            Text(`${source.course} · ${source.location}`).fontSize(11 * this.fontScale).fontColor(UiTheme.muted).width('100%')
            Text(source.excerpt).fontSize(13 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(20 * this.fontScale)
              .maxLines(this.expandedSourceId === source.chunkId ? 0 : 3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              .interactive().onClick(() => this.showCitation(source))
            Button(this.expandedSourceId === source.chunkId ? '收起原文' : '查看并复制原文')
              .height(44).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
              .accessibilityText(`查看引用 ${source.number} 的原文`)
              .interactive().onClick(() => this.showCitation(source))
            Button(this.selectedContext.some((item: SourceCitation) => item.chunkId === source.chunkId) ? '已加入当前对话 · 移除' : '加入当前对话')
              .height(44).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
              .enabled(!this.thinking).interactive().onClick(() => this.toggleContextSource(source))
          }.width('100%').alignItems(HorizontalAlign.Start).padding(13).backgroundColor(UiTheme.surface)
            .borderRadius(11).border({ width: 1, color: this.expandedSourceId === source.chunkId ? '#AAAAAA' : UiTheme.border })
        }, (source: SourceCitation) => source.chunkId)
        if (this.retrieval.sources.length > 0) {
          Button('带着问题返回会话').height(44).fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
            .interactive().onClick(() => { this.contextPickerVisible = false; this.sendMessage(this.retrieval.query) })
        }
        if (this.retrieval.notice.length > 0) {
          Text(this.retrieval.notice).fontSize(12 * this.fontScale).fontColor('#666666').width('100%').padding(10).backgroundColor(UiTheme.raised).borderRadius(9).transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  FocusContent() {
    Column({ space: 14 * this.fontScale }) {
      Row() {
        Column({ space: 4 * this.fontScale }) {
          Text('自律模式').fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('番茄钟 + 健康使用设备专注锁').fontSize(14 * this.fontScale).fontColor(UiTheme.muted)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.focusGuardActive ? '设备锁生效中' : '本地番茄钟')
          .fontSize(11 * this.fontScale).fontColor(this.focusGuardActive ? UiTheme.onPrimary : UiTheme.secondary)
          .padding({ left: 10 * this.fontScale, right: 10 * this.fontScale, top: 6 * this.fontScale, bottom: 6 * this.fontScale })
          .backgroundColor(this.focusGuardActive ? UiTheme.primary : UiTheme.raised).borderRadius(8)
      }.width('100%').alignItems(VerticalAlign.Center)

      Column({ space: 12 * this.fontScale }) {
        Progress({ value: this.focusProgress(), total: 100, type: ProgressType.Ring })
          .width(210 * this.fontScale).height(210 * this.fontScale).color(UiTheme.primary).style({ strokeWidth: 12 * this.fontScale })
        Text(this.formatFocusTime(this.focusRemainingSeconds))
          .fontSize(42 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text(this.focusPhase === 'focus' ? '专注中' : '休息中').fontSize(13 * this.fontScale).fontColor(UiTheme.secondary)
        Row({ space: 12 * this.fontScale }) {
          Button('− 5').height(38 * this.fontScale).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.focusRunning).onClick(() => this.adjustFocusMinutes(-5))
          Text(`${this.focusWorkMinutes} / ${this.focusBreakMinutes} 分钟`).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary)
          Button('+ 5').height(38 * this.fontScale).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.focusRunning).onClick(() => this.adjustFocusMinutes(5))
        }
        Row({ space: 10 * this.fontScale }) {
          Button(this.focusRunning ? '暂停番茄钟' : '开始专注')
            .width(150 * this.fontScale).height(44 * this.fontScale).fontSize(13 * this.fontScale)
            .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
            .enabled(!this.focusGuardBusy).onClick(() => this.startFocusSession())
          Button('重置').width(90 * this.fontScale).height(44 * this.fontScale).fontSize(13 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised).onClick(() => this.resetFocusTimer())
        }
        Text(`已完成 ${this.focusCompleted} 个番茄`).fontSize(12 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%').padding({ top: 18 * this.fontScale, bottom: 18 * this.fontScale }).alignItems(HorizontalAlign.Center)
        .backgroundColor(UiTheme.surface).borderRadius(10)

      Column({ space: 10 * this.fontScale }) {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text('设备专注锁').fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('调用鸿蒙“健康使用设备”，按白名单限制其他应用').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.focusGuardEnabled })
            .onChange((value: boolean) => this.focusGuardEnabled = value)
        }.width('100%').alignItems(VerticalAlign.Center)
        Row({ space: 8 * this.fontScale }) {
          Button(this.focusWhitelistTokens.length === 0 ? '选择 APP 白名单' : `白名单 ${this.focusWhitelistTokens.length} 个`)
            .height(40 * this.fontScale).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.focusGuardBusy).onClick(() => this.pickFocusWhitelist())
          Button('查询状态').height(40 * this.fontScale).fontSize(12 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.focusGuardBusy).onClick(() => this.queryFocusGuardStatus())
        }.width('100%')
        Row({ space: 8 * this.fontScale }) {
          Button(this.focusGuardActive ? '重新开启设备锁' : '立即开启设备锁')
            .height(40 * this.fontScale).fontSize(12 * this.fontScale).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
            .enabled(!this.focusGuardBusy).onClick(() => this.enableFocusGuard())
          Button('解除设备锁').height(40 * this.fontScale).fontSize(12 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.focusGuardBusy && this.focusGuardActive).onClick(() => this.disableFocusGuard())
        }.width('100%')
        Text(this.focusGuardNotice || '白名单内应用可继续使用，名单外应用在设定时长内被限制访问。')
          .fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(19 * this.fontScale).width('100%')
          .padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(9)
      }.width('100%').alignItems(HorizontalAlign.Start).padding(14 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(10)

      Column({ space: 10 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text('自律魔方硬件').fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('连接 CampusCube，或用 NFC 标签触发专注').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 8 * this.fontScale }) {
          Button('扫描魔方').layoutWeight(1).height(40 * this.fontScale).fontSize(12 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.actionBusy).onClick(() => this.runModule('connect'))
          Button('NFC 碰一碰').layoutWeight(1).height(40 * this.fontScale).fontSize(12 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.actionBusy).onClick(() => this.runModule('nfc'))
        }.width('100%')
        Row({ space: 8 * this.fontScale }) {
          Button('硬件状态').layoutWeight(1).height(40 * this.fontScale).fontSize(12 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.actionBusy).onClick(() => this.runModule('hardware-status'))
          Button('模拟姿态中断').layoutWeight(1).height(40 * this.fontScale).fontSize(12 * this.fontScale)
            .fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
            .enabled(!this.actionBusy).onClick(() => this.runModule('interrupt'))
        }.width('100%')
        if (this.moduleNotice.length > 0) {
          Text(this.moduleNotice).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(19 * this.fontScale)
            .width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(9)
        }
        ForEach(this.moduleItems, (item: ModuleItem) => {
          Column({ space: 3 * this.fontScale }) {
            Text(item.title).fontSize(12 * this.fontScale).fontColor(UiTheme.text).width('100%')
            Text(item.detail).fontSize(11 * this.fontScale).fontColor(UiTheme.muted).lineHeight(18 * this.fontScale).width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)
        }, (item: ModuleItem) => item.id)
      }.width('100%').alignItems(HorizontalAlign.Start).padding(14 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(10)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18 * this.fontScale, bottom: 8 * this.fontScale })
  }

  @Builder
  ModuleContent() {
    Column({ space: 10 }) {
      Text(this.selectedFeature().name).fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text(this.selectedFeature().description).fontSize(14 * this.fontScale).fontColor(UiTheme.muted)
      TextInput({ text: this.moduleInput, placeholder: this.activeFeature === 'privacy' ? '姓名,学号,手机号' : this.activeFeature === 'focus' ? '专注分钟数，如 25' : '输入编号或当前模块的操作内容' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(40 * this.fontScale)
        .backgroundColor(UiTheme.surface).borderRadius(9).padding({ left: 12, right: 8 })
        .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').inputFeedback().onChange((value: string) => this.moduleInput = value)
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
      } else if (this.activeFeature === 'privacy') {
        this.ModuleAction('保存演示档案', 'save-demo')
        this.ModuleAction('加密保存档案', 'save-profile')
        this.ModuleAction('解密并查看档案', 'load-profile')
        this.ModuleAction('允许上传前预览', 'consent-on')
        this.ModuleAction('撤销上传授权', 'consent-off')
        this.ModuleAction('查看授权状态', 'consent-status')
        this.ModuleAction('清除本机档案', 'clear-profile')
      } else {
        this.ModuleAction('扫描 / 查询魔方', 'connect')
        this.ModuleAction('开始专注', 'start')
        this.ModuleAction('结束专注', 'stop')
        this.ModuleAction('NFC 碰一碰', 'nfc')
        this.ModuleAction('锁机联动状态', 'lock')
        this.ModuleAction('模拟姿态中断', 'interrupt')
      }
      if (this.moduleNotice.length > 0) {
        Text(this.moduleNotice).fontSize(13 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(21 * this.fontScale).width('100%').padding(12).backgroundColor(UiTheme.raised).borderRadius(10)
      }
      ForEach(this.moduleItems, (item: ModuleItem) => {
        Column({ space: 6 }) {
          Text(item.title).fontSize(14 * this.fontScale).fontColor('#303030').width('100%')
          Text(item.detail).fontSize(12 * this.fontScale).fontColor('#666666').lineHeight(20 * this.fontScale).width('100%')
        }.width('100%').padding(12).backgroundColor(UiTheme.surface).borderRadius(10)
      }, (item: ModuleItem) => item.id)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 20, bottom: 8 })
  }

  @Builder
  ModuleAction(label: string, action: string) {
    Button(label).width('100%').height(44).fontSize(13 * this.fontScale).fontColor(UiTheme.primary)
      .backgroundColor(UiTheme.raised).enabled(!this.actionBusy && !this.thinking).interactive().onClick(() => this.runModule(action))
  }

  @Builder
  SidebarConversation(session: SessionSummary, nested: boolean) {
    Row({ space: 4 * this.fontScale }) {
      Column({ space: 3 * this.fontScale }) {
        Text(session.title).fontSize(12 * this.fontScale).fontColor(this.activeSession === session.id ? '#F1F1F1' : '#BDBDBD')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(`${nested ? '' : `${this.workspaceProfile(session.featureId).name} · `}${this.sessionTime(session.updatedAt)}`)
          .fontSize(9 * this.fontScale).fontColor('#777777').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.layoutWeight(1).height(44 * this.fontScale).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
        .id(`sidebar-chat-${nested ? 'workspace' : 'recent'}-${session.id}`)
        .accessibilityText(`${nested ? '工作区对话' : '最近对话'}：${session.title}，${this.workspaceProfile(session.featureId).name}，${this.sessionTime(session.updatedAt)}`)
        .interactive().onClick(() => {
          this.sidebarSelection = `chat-${nested ? 'workspace' : 'recent'}-${session.id}`
          this.openSession(session.id)
        })
      if (this.sidebarSelection === `chat-${nested ? 'workspace' : 'recent'}-${session.id}`) {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_more_horizontal')).width(18 * this.fontScale).height(18 * this.fontScale)
      }.width(28 * this.fontScale).height(36 * this.fontScale).padding(0).borderRadius(6 * this.fontScale).backgroundColor(Color.Transparent)
        .accessibilityText(`会话操作：${session.title}`)
        .id(`sidebar-chat-menu-${nested ? 'workspace' : 'recent'}-${session.id}`)
        .interactive().bindMenu(session.featureId === 'trash'
          ? [{ value: '恢复会话', action: () => this.restoreTrashSession(session.id) },
            { value: '永久删除', action: () => this.confirmDeleteSession(session.id) }]
          : [{ value: '移入回收站', action: () => this.confirmDeleteSession(session.id) }])
      }
    }.width('100%').padding({ left: nested ? 24 : 10 * this.fontScale, right: 4 * this.fontScale }).margin({ bottom: 2 * this.fontScale })
      .backgroundColor(this.activeSession === session.id ? '#303030' : Color.Transparent).borderRadius(7 * this.fontScale)
      .hoverEffect(HoverEffect.Highlight)
  }

  @Builder
  SidebarWorkspace(group: SidebarWorkspaceGroup) {
    Column({ space: 1 * this.fontScale }) {
      Row({ space: 4 * this.fontScale }) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_chevron_right')).width(14 * this.fontScale).height(14 * this.fontScale).rotate({ angle: group.expanded ? 90 : 0 })
        }.width(20 * this.fontScale).height(34 * this.fontScale).padding(0).backgroundColor(Color.Transparent)
          .id(`sidebar-folder-toggle-${group.feature.id}`)
          .enabled(this.sidebarQuery.trim().length === 0)
          .accessibilityText(`${group.expanded ? '收起' : '展开'}工作区：${group.feature.name}`)
          .interactive().onClick(() => {
            this.sidebarSelection = `workspace-${group.feature.id}`
            this.toggleWorkspaceGroup(group.feature.id)
          })
        Row({ space: 8 * this.fontScale }) {
          Image($r('app.media.ic_folder')).width(17 * this.fontScale).height(17 * this.fontScale)
          Text(group.feature.name).fontSize(12 * this.fontScale).fontColor(this.activeFeature === group.feature.id ? '#EEEEEE' : '#B5B5B5')
            .fontWeight(this.activeFeature === group.feature.id ? FontWeight.Medium : FontWeight.Regular).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (group.totalCount > 0) { Text(`${group.totalCount}`).fontSize(10 * this.fontScale).fontColor('#747474') }
        }.layoutWeight(1).height(34 * this.fontScale).id(`sidebar-folder-${group.feature.id}`).accessibilityText(`打开工作区：${group.feature.name}`)
          .interactive().onClick(() => {
            this.sidebarSelection = `workspace-${group.feature.id}`
            this.chooseFeature(group.feature)
          })
        if (this.sidebarSelection === `workspace-${group.feature.id}`) {
          Button({ type: ButtonType.Normal }) { Image($r('app.media.ic_more_horizontal')).width(18 * this.fontScale).height(18 * this.fontScale) }
            .width(28 * this.fontScale).height(34 * this.fontScale).padding(0).borderRadius(6 * this.fontScale).backgroundColor(Color.Transparent)
            .id(`sidebar-workspace-menu-${group.feature.id}`).accessibilityText(`管理工作区：${group.feature.name}`)
            .interactive().bindMenu(group.feature.id === 'trash'
              ? [{ value: group.expanded ? '收起会话' : '展开会话', action: () => this.toggleWorkspaceGroup(group.feature.id) }]
              : group.feature.id === 'home'
                ? [{ value: '新建对话', action: () => this.createChat(group.feature.id) }]
                : [{ value: '新建对话', action: () => this.createChat(group.feature.id) },
                  { value: '删除工作区', action: () => this.confirmDeleteWorkspace(group.feature.id) }])
        }
      }.width('100%').padding({ right: 4 * this.fontScale }).backgroundColor(this.sidebarSelection === `workspace-${group.feature.id}` ? '#303030' : Color.Transparent)
        .borderRadius(7 * this.fontScale).hoverEffect(HoverEffect.Highlight)
      if (group.expanded) {
        ForEach(group.sessions, (session: SessionSummary) => {
          this.SidebarConversation(session, true)
        }, (session: SessionSummary) => `workspace-${session.featureId}-${session.id}-${session.title}-${session.updatedAt}`)
        if (group.totalCount === 0) {
          Text(group.feature.id === 'trash' ? '回收站为空' : '暂无对话，选中工作区后从 ⋯ 新建').fontSize(10 * this.fontScale).fontColor('#686868').width('100%')
            .padding({ left: 42 * this.fontScale, top: 7 * this.fontScale, bottom: 9 * this.fontScale })
        }
        if (group.totalCount > SidebarService.workspacePreviewCount && this.sidebarQuery.trim().length === 0) {
          Text(group.showAll ? '收起较早对话' : `显示其余 ${group.totalCount - group.sessions.length} 条`)
            .fontSize(11 * this.fontScale).fontColor('#8D8D8D').width('100%').height(30 * this.fontScale).padding({ left: 42 * this.fontScale })
            .interactive().onClick(() => this.toggleWorkspaceHistory(group.feature.id))
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  SidebarContent() {
    Column() {
        Row({ space: 8 * this.fontScale }) {
          Row({ space: 8 * this.fontScale }) {
          Text('CampusPilot').fontSize(14 * this.fontScale).fontColor('#E1E1E1').layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).height(34 * this.fontScale).borderRadius(7 * this.fontScale).id('brand-home').accessibilityText('CampusPilot，返回首页')
            .interactive().onClick(() => this.openHome())
          Button({ type: ButtonType.Normal }) { Image($r('app.media.ic_sidebar')).width(19 * this.fontScale).height(19 * this.fontScale) }
            .width(32 * this.fontScale).height(34 * this.fontScale).padding(0).backgroundColor(Color.Transparent).id('sidebar-toggle').accessibilityText('收起左侧边栏')
            .interactive().onClick(() => this.toggleLeftPanel())
        }.width('100%').padding({ left: 6 * this.fontScale, right: 2 * this.fontScale }).margin({ bottom: 12 * this.fontScale })
        Row({ space: 4 * this.fontScale }) {
          Row({ space: 10 * this.fontScale }) {
            Image($r('app.media.ic_compose')).width(18 * this.fontScale).height(18 * this.fontScale)
            Text('对话').fontSize(13 * this.fontScale).fontColor('#DDDDDD')
          }.layoutWeight(1).height(38 * this.fontScale).id('sidebar-conversations').accessibilityText('选中对话入口')
            .interactive().onClick(() => this.sidebarSelection = 'section-conversations')
          if (this.sidebarSelection === 'section-conversations') {
            Button({ type: ButtonType.Normal }) { Image($r('app.media.ic_more_horizontal')).width(18 * this.fontScale).height(18 * this.fontScale) }
              .width(28 * this.fontScale).height(34 * this.fontScale).padding(0).borderRadius(6 * this.fontScale).backgroundColor(Color.Transparent)
              .id('sidebar-conversations-menu').accessibilityText('对话操作')
              .interactive().bindMenu([{ value: '新建对话', action: () => this.createChat() }])
          }
        }.width('100%').height(38 * this.fontScale).padding({ left: 10 * this.fontScale, right: 4 * this.fontScale }).borderRadius(7 * this.fontScale)
          .backgroundColor(this.sidebarSelection === 'section-conversations' ? '#303030' : '#252525')
        Row({ space: 8 * this.fontScale }) {
          Image($r('app.media.ic_search')).width(17 * this.fontScale).height(17 * this.fontScale)
          TextInput({ text: this.sidebarQuery, placeholder: '搜索对话' }).fontSize(12 * this.fontScale).placeholderFont({ size: 12 * this.fontScale }).layoutWeight(1).height(34 * this.fontScale).fontSize(12 * this.fontScale)
            .id('sidebar-search')
            .fontColor('#D0D0D0').placeholderColor('#777777').backgroundColor(Color.Transparent).padding(0)
            .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').inputFeedback().onChange((value: string) => { this.sidebarQuery = value; this.sidebarSelection = ''; this.refreshSidebar() })
          if (this.sidebarQuery.length > 0) {
            Button('×').width(22 * this.fontScale).height(28 * this.fontScale).padding(0).fontSize(16 * this.fontScale).fontColor('#AAAAAA').backgroundColor(Color.Transparent)
              .accessibilityText('清除对话搜索').interactive().onClick(() => { this.sidebarQuery = ''; this.refreshSidebar() })
          }
        }.height(36 * this.fontScale).width('100%').padding({ left: 10 * this.fontScale, right: 6 * this.fontScale }).margin({ top: 4 * this.fontScale, bottom: 12 * this.fontScale })
        Scroll(this.workspaceScroller) {
          Column({ space: 3 * this.fontScale }) {
            Row() {
              Row({ space: 7 * this.fontScale }) {
                Text('工作区').fontSize(11 * this.fontScale).fontColor('#808080')
                Image($r('app.media.ic_chevron_right')).width(13 * this.fontScale).height(13 * this.fontScale)
                  .rotate({ angle: this.sideExpanded || this.sidebarQuery.trim().length > 0 ? 90 : 0 })
              }.layoutWeight(1).height(30 * this.fontScale).enabled(this.sidebarQuery.trim().length === 0)
                .id('sidebar-workspaces-toggle')
                .accessibilityText(this.sideExpanded ? '收起工作区分组' : '展开工作区分组').interactive().onClick(() => {
                  this.sidebarSelection = 'section-workspaces'
                  this.toggleWorkspace()
                })
              if (this.sidebarSelection === 'section-workspaces') {
                Button({ type: ButtonType.Normal }) { Image($r('app.media.ic_more_horizontal')).width(18 * this.fontScale).height(18 * this.fontScale) }
                  .width(28 * this.fontScale).height(30 * this.fontScale).padding(0).borderRadius(6 * this.fontScale).backgroundColor(Color.Transparent)
                  .id('sidebar-workspaces-menu').accessibilityText('工作区操作')
                  .interactive().bindMenu([{ value: '新建工作区', action: () => this.startWorkspaceEditor() }])
              }
            }.width('100%').padding({ left: 10 * this.fontScale, right: 4 * this.fontScale })
            if (this.sideExpanded || this.sidebarQuery.trim().length > 0) {
              ForEach(this.sidebarView.workspaces, (group: SidebarWorkspaceGroup) => {
                this.SidebarWorkspace(group)
              }, (group: SidebarWorkspaceGroup) => `${group.feature.id}-${group.expanded}-${group.showAll}-${group.totalCount}-${group.sessions.map((session: SessionSummary) => `${session.id}-${session.title}-${session.updatedAt}`).join('|')}`)
            }
            Row() {
              Text(this.sidebarQuery.trim() ? '最近对话 · 搜索结果' : '最近对话').fontSize(11 * this.fontScale).fontColor('#808080').layoutWeight(1)
              Image($r('app.media.ic_chevron_right')).width(13 * this.fontScale).height(13 * this.fontScale)
                .rotate({ angle: this.recentsExpanded || this.sidebarQuery.trim().length > 0 ? 90 : 0 })
            }.width('100%').height(28 * this.fontScale).padding({ left: 10 * this.fontScale, right: 9 * this.fontScale }).margin({ top: 14 * this.fontScale })
              .id('sidebar-recents-toggle')
              .enabled(this.sidebarQuery.trim().length === 0).accessibilityText(this.recentsExpanded ? '收起最近对话' : '展开最近对话')
              .interactive().onClick(() => { this.sidebarSelection = 'section-recents'; this.toggleRecents() })
            if (this.recentsExpanded || this.sidebarQuery.trim().length > 0) {
              ForEach(this.sidebarView.recent, (session: SessionSummary) => {
                this.SidebarConversation(session, false)
              }, (session: SessionSummary) => `recent-${session.featureId}-${session.id}-${session.title}-${session.updatedAt}`)
              if (this.sidebarView.recentCount === 0) {
                Text(this.sidebarQuery.trim() ? '没有匹配的对话' : '暂无对话').fontSize(11 * this.fontScale).fontColor('#686868')
                  .width('100%').padding({ left: 10 * this.fontScale, top: 8 * this.fontScale, bottom: 8 * this.fontScale })
              }
              if (this.sidebarView.recentCount > SidebarService.recentPreviewCount && this.sidebarQuery.trim().length === 0) {
                Text(this.showAllRecent ? '收起较早对话' : `显示全部 ${this.sidebarView.recentCount} 条对话`)
                  .fontSize(11 * this.fontScale).fontColor('#8D8D8D').width('100%').height(32 * this.fontScale).padding({ left: 10 * this.fontScale })
                  .interactive().onClick(() => { this.showAllRecent = !this.showAllRecent; this.persistSidebar() })
              }
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 14 * this.fontScale, right: 12 * this.fontScale })
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto).scrollBarWidth(3).scrollBarColor('#666666')
        Row({ space: 7 * this.fontScale }) {
          Text('●').fontSize(8 * this.fontScale).fontColor(this.apiConfigured ? '#999999' : '#737373')
          Text(this.apiConfigured ? '模型已配置' : '尚未配置模型').fontSize(10 * this.fontScale).fontColor('#858585').layoutWeight(1)
          Text('本地保存').fontSize(10 * this.fontScale).fontColor('#686868')
        }.height(32 * this.fontScale).width('100%').padding({ left: 8 * this.fontScale, right: 8 * this.fontScale }).margin({ top: 6 * this.fontScale })
    }.width(this.panelWidth('left')).height('100%').padding(12 * this.fontScale).clip(true)
      .backgroundColor('#191919').alignItems(HorizontalAlign.Start)
      .bindSheet($$this.workspaceEditorVisible, this.WorkspaceEditor(), { height: '78%', width: 600,
        preferType: SheetType.CENTER, showClose: false, dragBar: false })
  }

  @Builder
  SettingsEntry() {
    Button({ type: ButtonType.Normal }) {
      Image($r('app.media.ic_settings')).width(20 * this.fontScale).height(20 * this.fontScale).colorFilter(this.railIconFilter(false, 102))
    }.width('100%').height(44 * Math.max(1, this.fontScale)).padding(0)
      .backgroundColor(Color.Transparent).borderRadius(7 * this.fontScale).id('appearance-settings').accessibilityText('设置')
      .interactive().onClick(() => this.appearanceSettingsVisible = true)
      .bindSheet($$this.appearanceSettingsVisible, this.AppearanceSettings(), { height: 420, width: 500,
        preferType: SheetType.CENTER, showClose: false, dragBar: false })
  }

  @Builder
  AppearanceSettings() {
    Column({ space: 18 }) {
      Row() {
        Text('设置').fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
        Button('完成').fontSize(13 * this.fontScale).height(36).backgroundColor(UiTheme.raised).fontColor(UiTheme.primary)
          .id('appearance-settings-close').onClick(() => { this.persistSidebar(); this.appearanceSettingsVisible = false })
      }.width('100%')
      Row() {
        Text('字号大小').fontSize(14 * this.fontScale).fontColor(UiTheme.text).layoutWeight(1)
        Text(`${Math.round(this.fontScale * 100)}%`).fontSize(13 * this.fontScale).fontColor(UiTheme.secondary).id('font-scale-value')
      }.width('100%')
      Slider({ value: this.fontScale * 100, min: 80, max: 130, step: 5 }).width('100%')
        .selectedColor(UiTheme.primary).trackColor(UiTheme.border).id('font-scale-slider')
        .onChange((value: number, mode: SliderChangeMode) => { this.fontScale = value / 100; if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.persistSidebar() })
      Row({ space: 10 }) {
        Button('小').fontSize(13 * this.fontScale).height(36).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .id('font-size-small').onClick(() => { this.fontScale = 0.8; this.persistSidebar() })
        Button('默认').fontSize(13 * this.fontScale).height(36).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .id('font-size-default').onClick(() => { this.fontScale = 0.9; this.persistSidebar() })
        Button('大').fontSize(13 * this.fontScale).height(36).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .id('font-size-large').onClick(() => { this.fontScale = 1.1; this.persistSidebar() })
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
      Column({ space: 8 }) {
        Text('今天准备做些什么？').fontSize(18 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text('这里是文字预览。对话、工作区和表单的字号会一起调整。').fontSize(14 * this.fontScale).lineHeight(22 * this.fontScale).fontColor(UiTheme.secondary)
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16).backgroundColor(UiTheme.raised).borderRadius(10)
    }.padding(24).width('100%').height('100%').backgroundColor(UiTheme.surface)
  }

  @Builder
  WorkspaceEditor() {
    Column({ space: 14 * this.fontScale }) {
      Row() {
        Text('新建工作区').fontSize(21 * this.fontScale).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('取消').height(40 * this.fontScale).fontSize(13 * this.fontScale).fontColor('#777777').backgroundColor(UiTheme.raised)
          .interactive().onClick(() => this.workspaceEditorVisible = false)
      }.width('100%')
      Text('智能助理会根据名称、说明和提示词，把适合的对话归入已有工作区。').fontSize(13 * this.fontScale).fontColor('#777777').width('100%')
      TextInput({ text: this.workspaceName, placeholder: '工作区名称（必填）' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(46 * this.fontScale).maxLength(40).id('workspace-name')
        .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').inputFeedback().onChange((value: string) => this.workspaceName = value)
      TextInput({ text: this.workspaceDescription, placeholder: '适合处理什么内容' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(46 * this.fontScale).maxLength(160).id('workspace-description')
        .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').inputFeedback().onChange((value: string) => this.workspaceDescription = value)
      TextArea({ text: this.workspacePrompt, placeholder: 'Agent 的角色与工作方式（可选）' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).layoutWeight(1).width('100%')
        .maxLength(3000).id('workspace-prompt').caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').inputFeedback().onChange((value: string) => this.workspacePrompt = value)
      if (this.workspaceEditorNotice) { Text(this.workspaceEditorNotice).fontSize(12 * this.fontScale).fontColor('#666666').width('100%') }
      Button('创建工作区').width('100%').height(46 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.surface)
        .id('workspace-save').enabled(this.workspaceName.trim().length > 0).interactive().onClick(() => this.saveNewWorkspace())
    }.padding(24 * this.fontScale).width('100%').height('100%').backgroundColor(UiTheme.background)
  }

  @Builder
  ResizeHandle(side: string) {
    Column() {
      Blank()
      Column().width(3).height(42).borderRadius(3)
        .backgroundColor(this.resizingPanel === side || this.hoveredGrip === side ? '#999999' : '#CCCCCC')
      Blank()
    }.width(8).height('100%').backgroundColor(this.resizingPanel === side || this.hoveredGrip === side ? '#EDEDED' : UiTheme.raised)
      .id(`resize-${side}`).accessibilityText(`拖动调整${side === 'left' ? '左' : '右'}侧栏宽度，向外侧拖至原宽度三分之一后松手收起，双击恢复默认`)
      .onHover((hover: boolean) => this.hoveredGrip = hover ? side : '')
      .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => { this.resizingPanel = side; this.pendingPanelCollapse = ''; this.dragStartWidth = this.panelWidth(side) })
        .onActionUpdate((event: GestureEvent) => this.resizePanel(side, event.offsetX))
        .onActionEnd((event: GestureEvent) => { this.resizePanel(side, event.offsetX); this.finishPanelResize() })
        .onActionCancel(() => this.finishPanelResize(true)))
      .parallelGesture(TapGesture({ count: 2 }).onAction(() => {
        if (side === 'left') this.leftWidth = Math.max(256, SidebarService.panelMinimum(side, this.fontScale))
        else this.rightWidth = Math.max(274, SidebarService.panelMinimum(side, this.fontScale))
        this.persistSidebar()
      }))
  }

  @Builder
  TrashContent() {
    Column({ space: 12 }) {
      Text('回收站').fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#303030')
      Text('会话及附件保存在本机。恢复到原工作区；原工作区已删除时，恢复到智能助理。')
        .fontSize(13 * this.fontScale).fontColor(UiTheme.muted).lineHeight(21 * this.fontScale)
      if (this.sessions.filter((session: SessionSummary) => session.featureId === 'trash').length === 0) {
        Text('回收站为空').fontSize(15 * this.fontScale).fontColor('#999999').padding({ top: 36, bottom: 36 })
      }
      ForEach(this.sessions.filter((session: SessionSummary) => session.featureId === 'trash')
        .sort((a: SessionSummary, b: SessionSummary) => (b.deletedAt || b.updatedAt) - (a.deletedAt || a.updatedAt)), (session: SessionSummary) => {
        Column({ space: 8 }) {
          Text(session.title).fontSize(15 * this.fontScale).fontColor('#303030').width('100%')
          Text(`${session.originFeatureName || '智能助理'} · 移入时间 ${this.sessionTime(session.deletedAt || session.updatedAt)}`)
            .fontSize(11 * this.fontScale).fontColor(UiTheme.muted).width('100%')
          Row({ space: 8 }) {
            Button('查看对话').height(38).fontSize(12 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
              .id(`trash-view-${session.id}`).interactive().onClick(() => this.openSession(session.id))
            Button('恢复').height(38).fontSize(12 * this.fontScale).fontColor(UiTheme.surface).backgroundColor(UiTheme.primary)
              .id(`trash-restore-${session.id}`).interactive().onClick(() => this.restoreTrashSession(session.id))
            Blank()
            Button('永久删除').height(38).fontSize(12 * this.fontScale).fontColor('#666666').backgroundColor(UiTheme.raised)
              .id(`trash-delete-${session.id}`).interactive().onClick(() => this.confirmDeleteSession(session.id))
          }.width('100%')
        }.width('100%').padding(16).backgroundColor(UiTheme.surface).borderRadius(12)
          .border({ width: 1, color: this.activeSession === session.id ? '#999999' : UiTheme.raised })
      }, (session: SessionSummary) => `trash-${session.id}-${session.deletedAt}`)
      if (this.activeSession) { Text('以下为所选会话的只读记录').fontSize(12 * this.fontScale).fontColor(UiTheme.muted).padding({ top: 20 }) }
    }.width('100%').padding({ top: 20, bottom: 14 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  ArtifactSheet() {
    Column({ space: 14 }) {
      Row() {
        Text(this.artifactTitle).fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
        Button('关闭').height(44).fontSize(13 * this.fontScale).fontColor(UiTheme.primary).backgroundColor(UiTheme.raised)
          .interactive().onClick(() => this.artifactVisible = false)
      }.width('100%')
      Text('可勾选清单、填写表格或补充说明；反馈保留在当前会话。').fontSize(12 * this.fontScale).fontColor(UiTheme.muted).width('100%')
      Scroll() {
        Column() {
        ForEach([`${this.activeSession}:${this.artifactId}`], (identity: string) => {
          InteractiveContent({ content: this.artifactContent, documentId: `artifact-${this.artifactId}`, sessionId: this.activeSession,
            editable: !this.thinking && this.activeFeature !== 'trash', feedback: this.feedbackFor(`artifact-${this.artifactId}`),
            onInteraction: (change: InteractionChange) => this.changeInteraction(`artifact-${this.artifactId}`, 'artifact', this.artifactTitle, this.artifactContent, change) })
        }, (identity: string) => identity)
        }.width('100%')
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      Button('带上反馈继续').height(44).width('100%').fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
        .id('artifact-continue').enabled(!this.thinking && this.activeFeature !== 'trash').interactive().onClick(() => {
          this.artifactVisible = false
          this.sendMessage(`请读取我在产物「${this.artifactTitle}」和本会话其他内容中的最新交互反馈，保留勾选、填写和确认结果，据此继续处理并更新任务面板。`)
        })
    }.width('100%').height('100%').padding(22).backgroundColor(UiTheme.background)
  }

  @Builder
  WelcomeContent() {
    Column({ space: 18 }) {
      Text(this.welcomeGreeting()).fontSize(14 * this.fontScale).fontColor(UiTheme.muted).id('welcome-greeting')
      Text(this.activeFeature === 'home' ? '今天准备做些什么？' : `准备在${this.selectedFeature().name}里做些什么？`)
        .fontSize(30 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).textAlign(TextAlign.Center)
        .lineHeight(42 * this.fontScale).width('100%').id('welcome-title')
      Text(this.activeFeature === 'home' ? '说说你的想法，我们一起把它变成下一步行动。' : this.workspaceProfile().greeting)
        .fontSize(14 * this.fontScale).fontColor(UiTheme.muted).textAlign(TextAlign.Center).lineHeight(23 * this.fontScale).width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.workspaceProfile().starters, (prompt: string) => {
          Text(prompt).fontSize(13 * this.fontScale).fontColor('#666666').padding({ left: 15, right: 15, top: 12, bottom: 12 })
            .margin({ left: 4, right: 4, bottom: 9 }).backgroundColor(UiTheme.raised).borderRadius(12)
            .interactive().onClick(() => this.sendMessage(prompt))
        }, (prompt: string) => `welcome-${this.activeFeature}-${prompt}`)
      }.width('100%').margin({ top: 8 })
      if (this.activeFeature === 'focus') {
        this.FocusContent()
      }
      if (this.activeFeature === 'home') {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.features.filter((feature: FeatureDefinition) => feature.id !== 'home' && feature.id !== 'trash').slice(0, 4), (feature: FeatureDefinition) => {
            Text(`${feature.name} →`).fontSize(12 * this.fontScale).fontColor(UiTheme.muted).padding(10).margin({ right: 5, bottom: 5 })
              .borderRadius(8).interactive().onClick(() => {
                this.sidebarSelection = `workspace-${feature.id}`
                this.chooseFeature(feature)
              })
          }, (feature: FeatureDefinition) => `welcome-link-${feature.id}`)
        }.width('100%')
      }
      if (this.notice) { Text(this.notice).fontSize(12 * this.fontScale).fontColor('#666666').lineHeight(20 * this.fontScale).textAlign(TextAlign.Center) }
      if (this.storageNotice) { Text(this.storageNotice).fontSize(12 * this.fontScale).fontColor('#666666').lineHeight(20 * this.fontScale).textAlign(TextAlign.Center) }
    }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 32, right: 32, top: 28, bottom: 28 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  WorkspaceAssistantContent() {
    Column({ space: 9 }) {
      Text(this.workspaceProfile().role).fontSize(12 * this.fontScale).fontColor(UiTheme.primary)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.workspaceProfile().starters, (prompt: string) => {
          Text(prompt).fontSize(12 * this.fontScale).fontColor('#666666').padding(10).margin({ right: 8, bottom: 8 })
            .backgroundColor(UiTheme.raised).borderRadius(9).enabled(!this.thinking)
            .interactive().onClick(() => this.sendMessage(prompt))
        }, (prompt: string) => `${this.activeFeature}-${prompt}`)
      }.width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 8, bottom: 8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  TaskPanel() {
    Scroll() {
    Column({ space: 10 * this.fontScale }) {
      Row() { Text('任务面板').fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#202020'); Blank(); Text('会话内保存').fontSize(10 * this.fontScale).fontColor('#777777') }.width('100%')
      Text(this.workspace.goal || `${this.selectedFeature().name} · 等待明确目标`).fontSize(13 * this.fontScale).fontColor('#666666').width('100%').copyOption(CopyOptions.InApp)
      Column({ space: 8 * this.fontScale }) {
        Row() { Text('任务进度').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor('#404040'); Blank(); Text(`${this.completedTasks()}/${this.workspace.tasks.length}`).fontSize(12 * this.fontScale).fontColor(UiTheme.primary) }.width('100%')
        Row() { Row().width(`${this.workspace.tasks.length === 0 ? 0 : this.completedTasks() / this.workspace.tasks.length * 100}%`).height(5 * this.fontScale).backgroundColor(UiTheme.primary).borderRadius(4 * this.fontScale); Blank() }.width('100%').height(5 * this.fontScale).backgroundColor('#E5E5E5').borderRadius(4 * this.fontScale)
      }.id('task-progress-card').width('100%').padding(11 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(12 * this.fontScale)
      ForEach(this.workspace.tasks, (task: WorkspaceTask) => {
        Row({ space: 9 * this.fontScale }) {
          Button(task.status === 'completed' ? '✓' : task.status === 'in_progress' ? '◐' : '○')
            .width(24 * this.fontScale).height(30 * this.fontScale).padding(0).fontSize(16 * this.fontScale).fontColor(task.status === 'completed' ? UiTheme.primary : '#999999')
            .backgroundColor(Color.Transparent).enabled(!this.thinking).accessibilityText(`切换任务完成状态：${task.title}`)
            .interactive().onClick(() => this.toggleTask(task.id))
          Column({ space: 4 * this.fontScale }) {
            Text(task.title).fontSize(13 * this.fontScale).fontColor('#404040').width('100%')
            Text(task.detail || (task.status === 'completed' ? '已完成' : task.status === 'in_progress' ? '进行中' : '待处理'))
              .fontSize(10 * this.fontScale).fontColor('#888888').maxLines(3).width('100%')
            Text('让 Agent 继续 →').fontSize(11 * this.fontScale).fontColor(UiTheme.primary).padding({ top: 5 * this.fontScale, bottom: 5 * this.fontScale })
              .enabled(!this.thinking).interactive().onClick(() => this.sendMessage(`请继续处理任务「${task.title}」，详情：${task.detail || '请根据对话补充'}。将实际进展同步到任务面板。`))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.id(`task-row-${task.id}`).width('100%').padding({ top: 4 * this.fontScale, bottom: 4 * this.fontScale })
      }, (task: WorkspaceTask) => `${this.activeSession}-${task.id}-${task.title}-${task.status}-${task.detail}`)
      Button(this.workspace.tasks.length > 0 && this.completedTasks() < this.workspace.tasks.length ? '推进下一步' : '生成总结报告')
        .width('100%').height(36 * this.fontScale).fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary).borderRadius(9 * this.fontScale)
        .id('task-next-step').enabled(!this.thinking).interactive().onClick(() => this.advanceTask())
      Text('产物与记忆').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.muted).width('100%').margin({ top: 4 * this.fontScale })
      if (this.workspace.summary) {
        ForEach([this.activeSession], (sessionId: string) => {
          Column() {
            InteractiveContent({ content: this.workspace.summary, documentId: 'memory-summary', sessionId: sessionId, compact: true,
              editable: !this.thinking && this.activeFeature !== 'trash', feedback: this.feedbackFor('memory-summary'),
              onInteraction: (change: InteractionChange) => this.changeInteraction('memory-summary', 'memory', '当前任务记忆', this.workspace.summary, change) })
          }.width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(10 * this.fontScale)
        }, (sessionId: string) => sessionId)
      } else {
        Text('对话中的目标、进展和产物会保存在这里。').fontSize(12 * this.fontScale).fontColor('#505050').lineHeight(19 * this.fontScale).width('100%')
          .padding(12 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(10 * this.fontScale)
      }
      ForEach(this.workspace.artifacts, (item: WorkspaceArtifact) => {
        Column({ space: 6 * this.fontScale }) {
          Text(`▤ ${item.title}`).fontSize(13 * this.fontScale).fontColor(UiTheme.primary).width('100%')
          Text(InteractionService.preview(item.content, this.feedbackFor(`artifact-${item.id}`))).fontSize(11 * this.fontScale).fontColor(UiTheme.muted).maxLines(3).width('100%')
          Text('查看并复制 →').fontSize(11 * this.fontScale).fontColor(UiTheme.primary)
          if (this.feedbackFor(`artifact-${item.id}`).updatedAt > 0) {
            Text(`含 ${this.feedbackFor(`artifact-${item.id}`).values.length} 项交互反馈`).fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          }
        }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(10 * this.fontScale)
          .interactive().onClick(() => this.showArtifact(item))
      }, (item: WorkspaceArtifact) => `${this.activeSession}-${item.id}-${item.title}-${item.content}`)
    }.width('100%').padding(14 * this.fontScale).alignItems(HorizontalAlign.Start)
    }.id('task-panel').width(this.panelWidth('right')).height('100%').backgroundColor(UiTheme.background).align(Alignment.TopStart).scrollBar(BarState.Auto).clip(true)
  }

  private navigateSection(section: string): void {
    if (this.appSection === section) return
    this.stopReply(); this.persistSession(); this.cancelVoice(); this.stopSpeech()
    this.contextPickerVisible = false; this.artifactVisible = false
    this.appSection = section
    if (section === 'library') this.refreshKnowledge()
  }

  private useLibraryDocument(id: string, attachment: boolean): void {
    try {
      if (this.activeFeature === 'trash') this.openHome()
      const library = IntegrationService.library
      if (library === undefined) throw new Error('资料库尚未初始化。')
      if (attachment) {
        if (this.draftAttachments.length >= AttachmentService.maxFiles) throw new Error('每条消息最多4个附件。')
        this.draftAttachments = this.draftAttachments.concat(library.attachment(id))
      } else {
        const incoming = library.citations(id)
        const sourceIds = new Set(incoming.map((source: SourceCitation) => source.sourceId))
        const retained = this.selectedContext.filter((source: SourceCitation) => !sourceIds.has(source.sourceId))
        if (retained.length + incoming.length > 12) throw new Error('当前上下文较多，请先移除部分资料后再添加。')
        this.selectedContext = retained.concat(incoming)
      }
      this.appSection = 'chat'; this.notice = attachment ? '已加入附件，发送消息后使用。' : '已加入当前对话上下文，发送消息后使用。'
      this.persistSession()
    } catch (error) {
      try { this.getUIContext().getPromptAction().showToast({ message: (error as Error).message, duration: 2000 }) } catch (_error) {}
    }
  }

  private railIconFilter(active: boolean = false, source: number = 85): ColorFilter {
    const scale = (active ? 241 : 189) / source
    return new ColorFilter([scale, 0, 0, 0, 0, 0, scale, 0, 0, 0, 0, 0, scale, 0, 0, 0, 0, 0, 1, 0])
  }

  @Builder
  RailItem(label: string, section: string, icon: Resource) {
    Button({ type: ButtonType.Normal }) {
      Image(icon).width(22 * this.fontScale).height(22 * this.fontScale).colorFilter(this.railIconFilter(this.appSection === section))
    }.width('100%').height(44 * Math.max(1, this.fontScale)).padding(0).borderRadius(9 * this.fontScale)
      .backgroundColor(this.appSection === section ? '#3B3B3B' : Color.Transparent).id(`nav-${section}`).accessibilityText(label)
      .interactive().onClick(() => {
        if (section === 'chat') this.openHome()
        else { if (section === 'tasks') this.taskCenterTab = 'agent'; this.navigateSection(section) }
      })
  }

  @Builder
  GlobalRail() {
    Column({ space: 6 * this.fontScale }) {
      this.RailItem('首页', 'chat', $r('app.media.ic_home'))
      this.RailItem('定时任务', 'tasks', $r('app.media.ic_clock'))
      this.RailItem('资料库', 'library', $r('app.media.ic_library'))
      if (this.appSection === 'chat' && !this.isLeftPanelVisible) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ic_sidebar')).width(20 * this.fontScale).height(20 * this.fontScale) }
          .width('100%').height(37 * this.fontScale).backgroundColor(Color.Transparent).id('sidebar-expand')
          .accessibilityText('展开会话侧栏').interactive().onClick(() => this.toggleLeftPanel())
      }
      Blank()
      this.SettingsEntry()
    }.width(this.globalRailWidth()).height('100%').padding({ left: 6, right: 6, top: 19 * this.fontScale, bottom: 14 * this.fontScale })
      .backgroundColor('#242424').border({ width: { right: 1 }, color: '#333333' }).id('global-navigation')
  }

  build() {
    Row() {
      this.GlobalRail()
      Stack({ alignContent: Alignment.TopStart }) {
      if (this.appSection === 'tasks') {
        TaskCenterPage({ initialTab: this.taskCenterTab }).width('100%').height('100%').transition(UiMotion.page())
      } else if (this.appSection === 'library') {
        LibraryPage({ onUse: (id: string, attachment: boolean) => this.useLibraryDocument(id, attachment), onChanged: () => this.refreshKnowledge() })
          .width('100%').height('100%').transition(UiMotion.page())
      } else {
      Row() {
      Row() { this.SidebarContent(); this.ResizeHandle('left') }
        .panelLayoutWidth(this.isLeftPanelVisible ? this.panelWidth('left') + 8 : 0)
        .animation({ duration: this.resizingPanel ? 0 : 220, curve: Curve.EaseInOut })
        .height('100%').clip(true).id('left-panel-slot')

      Column() {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text(this.selectedFeature().name).fontSize(18 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.selectedFeature().description).fontSize(11 * this.fontScale).fontColor('#888888').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ right: 10 * this.fontScale })
          if (this.activeFeature !== 'trash') {
          Text('＋ 上下文').fontSize(12 * this.fontScale).fontColor('#505050')
            .padding({ left: 10 * this.fontScale, right: 10 * this.fontScale, top: 8 * this.fontScale, bottom: 8 * this.fontScale }).backgroundColor(UiTheme.raised).borderRadius(8 * this.fontScale)
            .accessibilityText(this.contextPickerVisible ? '关闭课程资料选择' : '为当前对话添加课程资料')
            .interactive().onClick(() => this.toggleContextPicker())
          if (!this.isWelcomePage) {
            Text(this.isTaskPanelVisible ? '☷' : '☰').id('task-panel-toggle').accessibilityText(this.isTaskPanelVisible ? '收起任务面板' : '展开任务面板').fontSize(18 * this.fontScale).fontColor('#505050').margin({ left: 12 * this.fontScale }).padding(7 * this.fontScale).interactive().onClick(() => this.toggleTaskPanel())
          }
          }
        }.width('100%').height(68 * this.fontScale).padding({ left: 26 * this.fontScale, right: 20 * this.fontScale }).backgroundColor(UiTheme.background).border({ width: { bottom: 1 }, color: UiTheme.border })
        if (this.isWelcomePage) {
          Scroll() { this.WelcomeContent() }.layoutWeight(1).width('100%').align(Alignment.Center).scrollBar(BarState.Off)
        } else {
        Scroll(this.chatScroller) {
          Column({ space: 15 * this.fontScale }) {
            if (this.activeFeature === 'trash') { this.TrashContent() }
            else if (this.activeFeature === 'career') { this.CareerContent() }
            else if (this.activeFeature === 'schedule') { this.ScheduleContent() }
            else if (this.activeFeature === 'budget') { this.BudgetContent() }
// 合并保留：以下 main 旧实现停用，采用知识库分支（2026-10-30）。
//             else if (this.activeFeature === 'forms' || this.activeFeature === 'focus' || this.activeFeature === 'study' || this.activeFeature === 'privacy') { this.ModuleContent() }
            else if (this.activeFeature === 'focus') { this.FocusContent() }
            else if (this.activeFeature === 'forms' || this.activeFeature === 'study' || this.activeFeature === 'privacy') { this.ModuleContent() }
            else if (this.activeFeature !== 'home') { this.PlaceholderContent() }
            if (this.activeFeature !== 'trash') { this.WorkspaceAssistantContent() }
            if (this.notice.length > 0) {
              Text(this.notice).fontSize(12 * this.fontScale).fontColor('#666666').lineHeight(19 * this.fontScale).width('100%')
                .padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(9 * this.fontScale).transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
            }
            if (this.storageNotice.length > 0) {
              Text(this.storageNotice).fontSize(12 * this.fontScale).fontColor('#666666').width('100%')
                .padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(9 * this.fontScale).transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
            }
            if (this.activeFeature !== 'trash') {
              Row({ space: 8 * this.fontScale }) { Text('✦').fontSize(13 * this.fontScale).fontColor(UiTheme.primary); Text('回答会结合当前对话和你主动加入的课程资料。').fontSize(12 * this.fontScale).fontColor(UiTheme.secondary) }.width('100%').padding(11 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(10 * this.fontScale)
            }
            ForEach(this.messages, (message: AgentMessage, index: number) => {
              Row() {
                Column({ space: 5 * this.fontScale }) {
                  ForEach(message.attachments || [], (attachment: ChatAttachment) => {
                    if (attachment.kind === 'image') {
                      Image(`file://${attachment.path}`).width('100%').height(160 * this.fontScale).objectFit(ImageFit.Contain).borderRadius(8 * this.fontScale)
                    }
                    Text(`${attachment.kind === 'image' ? '▧' : '▤'} ${attachment.name}${attachment.truncated ? ' · 部分内容' : ''}`)
                      .fontSize(12 * this.fontScale).fontColor('#666666').maxLines(2).width('100%')
                  }, (attachment: ChatAttachment) => attachment.id)
                  if (message.role === 'agent') {
                    AgentAnswer({ message: message, expanded: this.expandedThoughts.includes(`${this.activeSession}-${index}`),
                      documentId: `message-${index}`, sessionId: this.activeSession,
                      editable: !this.thinking && this.activeFeature !== 'trash', feedback: this.feedbackFor(`message-${index}`),
                      onInteraction: (change: InteractionChange) => this.changeMessageInteraction(index, change), onToggle: () => this.toggleThought(index),
                      onOpenArtifact: (id: string): void => {
                        const artifact = this.workspace.artifacts.find((item: WorkspaceArtifact) => item.id === id)
                        if (artifact) this.showArtifact(artifact)
                        else this.getUIContext().getPromptAction().showToast({ message: '该产物已被后续内容移除或替换，执行记录仍然保留。' })
                      } })
                  } else {
                    Text(message.content).fontSize(15 * this.fontScale).fontColor(UiTheme.text).lineHeight(23 * this.fontScale).copyOption(CopyOptions.InApp)
                  }
                  ForEach(message.sources || [], (source: SourceCitation) => {
                    Column({ space: 5 * this.fontScale }) {
                      Text(`[${source.number}] ${source.title} · ${source.location}`).fontSize(11 * this.fontScale).fontColor(UiTheme.primary).width('100%')
                        .accessibilityText(`来源 ${source.number} ${source.title} ${source.location}`).interactive().onClick(() => this.showCitation(source))
                      if (this.expandedSourceId === source.chunkId) {
                        Text(source.excerpt).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(19 * this.fontScale).copyOption(CopyOptions.InApp).width('100%').interactive().onClick(() => this.showCitation(source))
                      }
                    }.width('100%').padding(8 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8 * this.fontScale)
                  }, (source: SourceCitation) => source.chunkId)
                  if (message.role === 'agent') {
                    Row({ space: 7 * this.fontScale }) {
                      if (message.status !== 'loading' && MarkdownParser.answer(message.content).body.trim().length > 0) {
                        ReplyActions({ content: message.content, documentId: `${index}`,
                          speaking: this.speaking && this.speakingReply === `${this.activeSession}-${index}`,
                          onSpeak: () => this.toggleSpeech(message.content, `${this.activeSession}-${index}`) })
                      }
                      Text(message.meta).fontSize(9 * this.fontScale).fontColor('#999999').maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      Text(MessageTimeService.label(message, this.messageClock)).fontSize(9 * this.fontScale).fontColor('#999999')
                        .id(`message-time-${index}`).accessibilityText(`回答时间：${MessageTimeService.full(MessageTimeService.timestamp(message))}`)
                    }.width('100%').margin({ top: 3 * this.fontScale })
                  } else {
                    Text(MessageTimeService.label(message, this.messageClock)).fontSize(9 * this.fontScale).fontColor('#999999')
                      .id(`message-time-${index}`).accessibilityText(`发送时间：${MessageTimeService.full(MessageTimeService.timestamp(message))}`)
                  }
                }.id(`message-bubble-${index}`).alignItems(message.role === 'agent' ? HorizontalAlign.Start : HorizontalAlign.End).width(message.role === 'agent' ? '100%' : 'auto')
                  .constraintSize({ maxWidth: (message.role === 'agent' ? 800 : 720) * this.fontScale })
                  .padding(13 * this.fontScale).backgroundColor(message.role === 'agent' ? UiTheme.agentBubble : UiTheme.userBubble).borderRadius(13 * this.fontScale)
              }.width('100%').justifyContent(message.role === 'agent' ? FlexAlign.Center : FlexAlign.End)
            // ForEach reuses nodes with unchanged keys. Replacing an interface object alone
            // does not refresh its captured fields, so include the reply revision in its key.
            }, (message: AgentMessage, index: number) => `${this.activeSession}-${message.role}-${index}-${message.renderRevision || 0}`)
          }.width('100%').padding({ left: 26 * this.fontScale, right: 26 * this.fontScale, top: 2 * this.fontScale, bottom: 20 * this.fontScale })
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
        }
        if (this.activeFeature !== 'trash') {
        Column({ space: 7 * this.fontScale }) {
          if (this.draftAttachments.length > 0) {
            Scroll() {
              Row({ space: 8 * this.fontScale }) {
                ForEach(this.draftAttachments, (attachment: ChatAttachment) => {
                  Row({ space: 7 * this.fontScale }) {
                    if (attachment.kind === 'image') { Image(`file://${attachment.path}`).width(44 * this.fontScale).height(44 * this.fontScale).objectFit(ImageFit.Cover).borderRadius(6 * this.fontScale) }
                    else { Text('▤').fontSize(22 * this.fontScale).fontColor('#666666') }
                    Column({ space: 3 * this.fontScale }) {
                      Text(attachment.name).fontSize(11 * this.fontScale).fontColor('#505050').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width(130 * this.fontScale)
                      Text(`${Math.max(1, Math.round(attachment.size / 1024))} KB${attachment.truncated ? ' · 部分内容' : ''}`).fontSize(10 * this.fontScale).fontColor('#999999')
                    }.alignItems(HorizontalAlign.Start)
                    Button('×').fontSize(18 * this.fontScale).width(30 * this.fontScale).height(40 * this.fontScale).backgroundColor(Color.Transparent).fontColor('#777777')
                      .accessibilityText(`移除附件 ${attachment.name}`).interactive().onClick(() => this.removeAttachment(attachment.id))
                  }.padding(7 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(9 * this.fontScale)
                }, (attachment: ChatAttachment) => attachment.id)
              }
            }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
          }
          if (this.attachmentBusy || this.voiceBusy || this.recording) {
            Text(this.attachmentBusy ? '正在读取附件…' : this.recording ? '● 正在聆听，再点麦克风结束' : '正在处理语音…')
              .fontSize(11 * this.fontScale).fontColor(this.recording ? '#666666' : '#777777').width('100%')
          }
          if (this.selectedContext.length > 0) {
            Row({ space: 5 * this.fontScale }) {
              Text(`当前上下文 · ${this.selectedContext.length} 条资料`).fontSize(11 * this.fontScale).fontColor(UiTheme.primary).layoutWeight(1)
              ForEach(this.selectedContext, (source: SourceCitation) => {
                Button(`［${source.number}］${source.course} ×`).fontSize(10 * this.fontScale).height(38 * this.fontScale).fontColor(UiTheme.primary)
                  .backgroundColor(UiTheme.raised).interactive().onClick(() => this.toggleContextSource(source))
              }, (source: SourceCitation) => source.chunkId)
            }.width('100%')
          }
          Column({ space: 4 * this.fontScale }) {
            TextArea({ text: this.inputText, placeholder: this.chatPlaceholder() })
              .inputFeedback()
              .fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).lineHeight(20 * this.fontScale)
              .id('chat-input').width('100%').constraintSize({ minHeight: 36 * this.fontScale, maxHeight: 160 * this.fontScale })
              .backgroundColor(Color.Transparent).borderRadius(6 * this.fontScale)
              .padding({ left: 6 * this.fontScale, right: 6 * this.fontScale, top: 8 * this.fontScale, bottom: 8 * this.fontScale })
              .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').enterKeyType(EnterKeyType.NEW_LINE)
              .onChange((value: string) => this.inputText = value)
            Row({ space: 8 * this.fontScale }) {
            Text('＋').fontSize(19 * this.fontScale).fontColor('#505050').width(28 * this.fontScale).height(36 * this.fontScale).textAlign(TextAlign.Center)
              .accessibilityText('导入文件或图片').enabled(!this.thinking && !this.recording && !this.voiceBusy && !this.attachmentBusy)
              .interactive().bindMenu([{ value: '导入文件', action: () => this.pickAttachments(false) }, { value: '选择图片', action: () => this.pickAttachments(true) }])
            Button({ type: ButtonType.Normal }) {
              if (this.recording) { Text('■').fontSize(16 * this.fontScale).fontColor('#666666') }
              else if (this.voiceBusy) { LoadingProgress().width(18 * this.fontScale).height(18 * this.fontScale).color('#777777') }
              else { Image($r('app.media.ic_microphone')).width(18 * this.fontScale).height(18 * this.fontScale) }
            }.width(32 * this.fontScale).height(36 * this.fontScale).backgroundColor(Color.Transparent).borderRadius(6 * this.fontScale)
              .accessibilityText(this.recording ? '结束录音' : '麦克风语音识别').interactive().onClick(() => this.toggleVoice())
            Row() {
            ModelSelector({ profiles: this.apiProfiles, activeId: this.apiActiveId, activeModel: this.apiActiveModel,
              loading: this.apiProfilesLoading, busy: this.thinking, viewportWidth: this.viewportWidth, viewportHeight: this.viewportHeight,
              onSelect: (id: string) => this.selectApiProfile(id), onManage: () => this.toggleApiSettings() })
              .width('100%').constraintSize({ maxWidth: 180 * this.fontScale })
            Blank()
            }.layoutWeight(1)
            if (this.thinking) { Text('停止').fontSize(12 * this.fontScale).fontColor(UiTheme.primary).height(36 * this.fontScale).padding({ left: 6 * this.fontScale, right: 6 * this.fontScale }).id('chat-stop').interactive().onClick(() => this.stopReply()) }
            ChatSendButton({ onSend: () => this.sendMessage(this.inputText) })
            }.id('chat-composer-actions').width('100%')
          }.id('chat-composer').width('100%').constraintSize({ maxWidth: 800 * this.fontScale })
            .padding(8 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(10 * this.fontScale).border({ width: 1, color: UiTheme.border })
        }.width('100%').constraintSize({ maxWidth: 852 * this.fontScale })
          .padding({ left: 26 * this.fontScale, right: 26 * this.fontScale, top: 10 * this.fontScale, bottom: 14 * this.fontScale }).backgroundColor(UiTheme.background)
        } else {
          Row({ space: 12 * this.fontScale }) {
            Text(this.activeSession ? '回收站中的会话为只读状态' : '已删除的会话和附件会一直保留，直到永久删除。').fontSize(12 * this.fontScale).fontColor(UiTheme.muted).layoutWeight(1)
            if (this.activeSession) {
              Button('恢复此会话').height(42 * this.fontScale).fontSize(13 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.surface)
                .interactive().onClick(() => this.restoreTrashSession(this.activeSession))
            }
          }.width('100%').padding(20 * this.fontScale).backgroundColor(UiTheme.raised)
        }
      }.layoutWeight(1).height('100%').backgroundColor(UiTheme.background).clip(true)
        .bindSheet($$this.apiSettingsVisible, this.ApiSettingsSheet(), { height: '78%', width: 620,
          preferType: SheetType.CENTER, showClose: false, dragBar: false,
          onDisappear: () => { this.apiSettingsVisible = false } })

      if (!this.isWelcomePage && this.activeFeature !== 'trash') {
        Row() { this.ResizeHandle('right'); this.TaskPanel() }
          .panelLayoutWidth(this.isTaskPanelVisible ? this.panelWidth('right') + 8 : 0)
          .animation({ duration: this.resizingPanel ? 0 : 220, curve: Curve.EaseInOut })
          .height('100%').clip(true).id('right-panel-slot')
      }
      }.width('100%').height('100%').transition(UiMotion.page())
      }
      }.layoutWeight(1).height('100%').clip(true)
        .bindSheet($$this.artifactVisible, this.ArtifactSheet(), { height: '80%', width: 680,
          preferType: SheetType.CENTER, showClose: false, dragBar: false })
    }.width('100%').height('100%').backgroundColor(UiTheme.background)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.viewportWidth = Number.parseFloat(`${newArea.width}`) || 1280
        this.viewportHeight = Number.parseFloat(`${newArea.height}`) || 800
      })
      .bindSheet($$this.contextPickerVisible, this.ContextSheet(), { height: '80%', width: 680,
        preferType: SheetType.CENTER, showClose: false, dragBar: false,
        onDisappear: () => { this.contextPickerVisible = false; this.searchSerial++; this.searchBusy = false } })
  }
}

import { FEATURE_CATALOG } from '../config/FeatureCatalog'
import { ActionItem, AgentMessage, FeatureDefinition } from '../models/AppModels'
import { AgentService } from '../services/AgentService'
import { SessionService } from '../services/SessionService'
import { ToolService } from '../services/ToolService'
import { KnowledgeChunk, RetrievalOptions, RetrievalResult, SourceCitation } from '../models/RagModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagConfig } from '../config/RagConfig'
import { demoKnowledgeIndex, MemoryKnowledgeRepository } from '../services/KnowledgeService'
import { ChatService } from '../services/ChatService'
import { StreamSink, ModuleAdapter, ModuleItem, ModuleResult } from '../models/IntegrationModels'

class ChatStreamSink implements StreamSink {
  private cancelled: () => boolean
  private receive: (delta: string) => void
  constructor(cancelled: () => boolean, receive: (delta: string) => void) {
    this.cancelled = cancelled
    this.receive = receive
  }
  isCancelled(): boolean { return this.cancelled() }
  onDelta(delta: string): void { this.receive(delta) }
}

@Entry
@Component
struct Index {
  @State activeFeature: string = 'home'
  @State activeSession: string = '秋招冲刺计划'
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
  private requestSerial: number = 0
  private searchSerial: number = 0
  private voiceSerial: number = 0
  private speechSerial: number = 0
  private actionSerial: number = 0
  private contextBySession: Map<string, SourceCitation[]> = new Map<string, SourceCitation[]>()
  private minScore: number = 0.20
  private topK: number = 4

  private readonly sessions: string[] = ['秋招冲刺计划', '本周学习规划', '9 月消费复盘']

  private selectedFeature(): FeatureDefinition {
    const feature = FEATURE_CATALOG.find((item: FeatureDefinition) => item.id === this.activeFeature)
    return feature === undefined ? FEATURE_CATALOG[0] : feature
  }

  aboutToAppear(): void {
    this.refreshKnowledge()
    this.messages = SessionService.loadMessages(this.activeSession)
  }

  aboutToDisappear(): void {
    this.stopReply()
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
  }

  private toggleContextPicker(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.contextPickerVisible = !this.contextPickerVisible
    })
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

  private async toggleVoice(): Promise<void> {
    if (this.voiceBusy || this.thinking) return
    const token = ++this.voiceSerial
    const stopping = this.recording
    this.voiceBusy = true
    try {
      if (stopping) {
        const transcript = await IntegrationService.voice.stop()
        if (token === this.voiceSerial) {
          this.recording = false
          this.inputText = transcript.slice(0, 2000)
          this.notice = transcript ? '识别完成，请核对后再发送。' : '未识别到文字，请重试。'
        }
      } else {
        await IntegrationService.voice.start()
        if (token === this.voiceSerial) { this.recording = true; this.notice = '录音中，结束后可以核对识别文字。' }
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
    try { await IntegrationService.voice.speak(content.slice(0, 8000)) }
    catch (error) { if (token === this.speechSerial) this.notice = (error as Error).message || '语音播报暂不可用。' }
    finally { if (token === this.speechSerial) this.speaking = false }
  }

  private stopReply(): void {
    this.requestSerial++
    if (!this.thinking) return
    const last = this.messages.length - 1
    this.updateReply(last, this.messages[last].content || '已停止生成。', '已停止', 'stopped', this.messages[last].sources || [])
    this.thinking = false
    SessionService.saveMessages(this.activeSession, this.messages)
  }

  private updateReply(position: number, content: string, meta: string, status: string, sources: SourceCitation[]): void {
    this.messages = this.messages.map((item: AgentMessage, index: number): AgentMessage => index === position
      ? { role: 'agent', content: content, meta: meta, status: status, sources: sources } : item)
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
    SessionService.saveMessages(this.activeSession, this.messages)
    this.cancelVoice()
    this.stopSpeech()
    this.contextBySession.set(this.activeSession, this.selectedContext.slice())
    this.actionSerial++
    this.actionBusy = false
    this.activeFeature = feature.id
    this.activeSession = feature.name
    this.selectedContext = this.contextBySession.get(this.activeSession) || []
    this.contextPickerVisible = false
    this.moduleInput = ''
    this.moduleItems = []
    this.moduleNotice = ''
    this.progress = 1
    this.messages = SessionService.loadMessages(this.activeSession)
    if (this.messages.length === 0) this.messages = AgentService.greeting(feature.id)
    this.notice = ''
  }

  private openSession(session: string): void {
    if (session === this.activeSession) return
    this.stopReply()
    SessionService.saveMessages(this.activeSession, this.messages)
    this.contextBySession.set(this.activeSession, this.selectedContext.slice())
    this.cancelVoice()
    this.stopSpeech()
    this.activeFeature = 'home'
    this.activeSession = session
    this.selectedContext = this.contextBySession.get(session) || []
    this.contextPickerVisible = false
    this.messages = SessionService.loadMessages(session)
    if (this.messages.length === 0) this.messages = AgentService.greeting('home')
    this.notice = ''
  }

  private createChat(): void {
    this.stopReply()
    SessionService.saveMessages(this.activeSession, this.messages)
    this.cancelVoice()
    this.stopSpeech()
    this.contextBySession.set(this.activeSession, this.selectedContext.slice())
    this.activeFeature = 'home'
    this.activeSession = '新对话'
    this.selectedContext = []
    this.contextPickerVisible = false
    this.progress = 1
    this.messages = AgentService.greeting('home')
  }

  private sendMessage(prompt: string): void {
    const message = prompt.trim()
    if (message.length === 0 || this.thinking || this.recording || this.voiceBusy) return
    const token = ++this.requestSerial
    const session = this.activeSession
    const featureId = this.activeFeature
    const history = this.messages.slice()
    const gateway = IntegrationService.agent
    const attachedContext = this.selectedContext.slice()
    this.messages = [...this.messages, { role: 'user', content: message, meta: '现在' }]
    this.messages = [...this.messages, { role: 'agent', content: '', meta: '正在检索资料', status: 'loading', sources: [] }]
    const replyIndex = this.messages.length - 1
    this.inputText = ''
    this.notice = ''
    this.thinking = true
    let content = ''
    let sources: SourceCitation[] = []
    const timeout = setTimeout(() => {
      if (token !== this.requestSerial) return
      this.requestSerial++
      this.thinking = false
      this.updateReply(replyIndex, content || '响应超时，请重试。', '响应超时', 'error', sources)
      SessionService.saveMessages(session, this.messages)
    }, 30000)
    const sink: StreamSink = new ChatStreamSink((): boolean => token !== this.requestSerial, (delta: string): void => {
      if (token !== this.requestSerial) return
      content = (content + delta).slice(0, 16000)
      this.updateReply(replyIndex, content, `${gateway.name} · 生成中`, 'streaming', sources)
    })
    ChatService.reply(message, featureId, history, this.retrievalOptions(), IntegrationService.rag(), gateway, sink,
      (result: RetrievalResult): void => {
        if (token !== this.requestSerial) return
        sources = result.sources
        this.notice = result.notice
        this.updateReply(replyIndex, '', `${gateway.name} · ${sources.length} 条参考资料`, 'loading', sources)
      }, attachedContext).then(() => {
        if (token === this.requestSerial) this.updateReply(replyIndex, content || '服务未返回内容，请重试。', gateway.name, content ? 'complete' : 'error', sources)
      }).catch((error: Error) => {
        if (token === this.requestSerial) this.updateReply(replyIndex, content || '服务暂不可用，请重试。', '生成失败', 'error', sources)
      }).finally(() => {
        clearTimeout(timeout)
        if (token === this.requestSerial) {
          this.thinking = false
          SessionService.saveMessages(session, this.messages)
        }
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
        Scroll() {
          Column() {
            Row() { Text('工作区').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#80817D'); Blank(); Text(this.sideExpanded ? '⌃' : '⌄').fontSize(13).fontColor('#9B9C96').rotate({ angle: this.sideExpanded ? 0 : 180 }) }.width('100%').height(28).padding({ left: 2, right: 7 }).onClick(() => this.toggleWorkspace())
            if (this.sideExpanded) {
              ForEach(FEATURE_CATALOG, (feature: FeatureDefinition) => {
                Row({ space: 10 }) { Text(feature.icon).fontSize(16).fontColor(this.activeFeature === feature.id ? '#D4F56A' : '#A5A6A1').width(20).textAlign(TextAlign.Center); Text(feature.name).fontSize(13).fontColor(this.activeFeature === feature.id ? '#F5F5F0' : '#C7C8C3').fontWeight(this.activeFeature === feature.id ? FontWeight.Medium : FontWeight.Regular).layoutWeight(1) }
                .width('100%').height(40).padding({ left: 8, right: 6 }).margin({ bottom: 2 }).backgroundColor(this.activeFeature === feature.id ? '#30312D' : '#1D1E1B').borderRadius(8).onClick(() => this.chooseFeature(feature))
              }, (feature: FeatureDefinition) => feature.id)
            }
            Row() { Text('最近对话').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#80817D'); Blank(); Text(this.recentsExpanded ? '⌃' : '⌄').fontSize(13).fontColor('#9B9C96').rotate({ angle: this.recentsExpanded ? 0 : 180 }) }.width('100%').height(28).padding({ left: 2, right: 7 }).margin({ top: 14 }).onClick(() => this.toggleRecents())
            if (this.recentsExpanded) {
              ForEach(this.sessions, (session: string) => { Text(session).fontSize(12).fontColor(this.activeSession === session ? '#F0F0E9' : '#A6A7A2').width('100%').height(33).padding({ left: 9, top: 8 }).margin({ bottom: 1 }).backgroundColor(this.activeSession === session ? '#292A27' : '#1D1E1B').borderRadius(7).onClick(() => this.openSession(session)) }, (session: string) => session)
            }
          }.width('100%').padding({ right: 10 }).justifyContent(FlexAlign.Start)
        }.layoutWeight(1).width('108%').margin({ right: -14 }).align(Alignment.TopStart).scrollBar(BarState.Auto)
        Text('●  本地演示 · 数据未上传').fontSize(11).fontColor('#8B8C88').width('100%').padding({ top: 9, bottom: 4 })
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
          Text(this.contextPickerVisible ? '关闭资料' : '＋ 上下文').fontSize(12).fontColor('#575951')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor('#EFEFEA').borderRadius(8)
            .accessibilityText(this.contextPickerVisible ? '关闭课程资料选择' : '为当前对话添加课程资料')
            .onClick(() => this.toggleContextPicker())
          Text(this.isTaskPanelVisible ? '☷' : '☰').fontSize(18).fontColor('#55564F').margin({ left: 12 }).padding(7).onClick(() => this.toggleTaskPanel())
        }.width('100%').height(68).padding({ left: 26, right: 20 }).backgroundColor('#FBFBF8').border({ width: { bottom: 1 }, color: '#E5E5DF' })
        Scroll() {
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
            if (this.contextPickerVisible) { this.KnowledgeContent() }
            Row({ space: 8 }) { Text('✦').fontSize(13).fontColor('#356B58'); Text('Agent 已载入当前工作区记忆；外部工具调用前会征求确认。').fontSize(12).fontColor('#596159') }.width('100%').padding(11).backgroundColor('#EFF6F0').borderRadius(10)
            ForEach(this.messages, (message: AgentMessage, index: number) => {
              Row() {
                if (message.role === 'agent') { Text('C').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#151614').width(27).height(27).textAlign(TextAlign.Center).padding({ top: 5 }).backgroundColor('#D4F56A').borderRadius(8).margin({ right: 9 }) }
                Column({ space: 5 }) {
                  Text(message.role === 'agent' ? 'CampusPilot' : '你').fontSize(11).fontColor('#82837C')
                  Text(message.content).fontSize(15).fontColor('#292A27').lineHeight(23).copyOption(CopyOptions.InApp)
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
            }, (message: AgentMessage, index: number) => `${message.role}-${index}`)
            if (this.thinking) { Text('CampusPilot 正在分析并规划下一步…').fontSize(13).fontColor('#666861').padding(10).backgroundColor('#F2F3EE').borderRadius(9) }
          }.width('100%').padding({ left: 26, right: 26, top: 2, bottom: 20 })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        Column({ space: 7 }) {
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
              .accessibilityText('添加资料上下文').onClick(() => this.toggleContextPicker())
            Text(this.recording ? '■' : '◉').fontSize(15).fontColor('#4F514B').width(30).height(44).textAlign(TextAlign.Center)
              .accessibilityText(this.recording ? '结束录音' : '语音输入').onClick(() => this.toggleVoice())
            TextInput({ text: this.inputText, placeholder: '向 CampusPilot 描述你的下一步…' }).layoutWeight(1).height(44).fontSize(14).backgroundColor('#F2F2ED').borderRadius(10).padding({ left: 12, right: 8 }).onChange((value: string) => this.inputText = value).onSubmit(() => this.sendMessage(this.inputText))
            Button({ type: ButtonType.Circle }) {
              Text('➤').fontSize(18).fontColor('#F9FAF6').rotate({ angle: -45 })
            }.width(42).height(42).backgroundColor('#356B58').onClick(() => this.sendMessage(this.inputText))
            if (this.thinking) { Text('停止').fontSize(12).fontColor('#356B58').height(44).padding({ left: 6, right: 6 }).onClick(() => this.stopReply()) }
          }.width('100%').padding(8).backgroundColor('#FFFFFF').borderRadius(14).border({ width: 1, color: '#E2E3DC' })
          Text('云端模型、ASR/TTS 与业务工具均通过 services 适配层预留。').fontSize(10).fontColor('#92938D').width('100%').textAlign(TextAlign.Center)
        }.width('100%').padding({ left: 26, right: 26, top: 10, bottom: 14 }).backgroundColor('#FBFBF8')
      }.layoutWeight(1).height('100%').backgroundColor('#FBFBF8')

      if (this.isTaskPanelVisible) { Divider().vertical(true).color('#E4E5DE').strokeWidth(1); this.TaskPanel() }
    }.width('100%').height('100%').backgroundColor('#FBFBF8')
  }
}

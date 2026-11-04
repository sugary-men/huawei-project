import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { AgentMessage } from '../models/AppModels'
import { MarkdownParser } from '../services/MarkdownParser'
import { MarkdownContent } from './MarkdownContent'
import { InteractiveContent } from './InteractiveContent'
import { InteractionChange, InteractionRecord } from '../models/InteractionModels'
import { ExecutionTraceService } from '../services/ExecutionTraceService'
import { ExecutionTimeline } from './ExecutionTimeline'

@Component
export struct AgentAnswer {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop message: AgentMessage = { role: 'agent', content: '', meta: '' }
  @Prop expanded: boolean = false
  @Prop documentId: string = ''
  @Prop sessionId: string = ''
  @Prop editable: boolean = true
  @Prop feedback: InteractionRecord = { id: '', source: '', title: '', values: [], updatedAt: 0 }
  onInteraction: (change: InteractionChange) => void = () => {}
  onToggle: () => void = () => {}
  onOpenArtifact: (id: string) => void = () => {}
  @State elapsedSeconds: number = 0
  @State durationText: string = ''
  private timer: number = -1

  private generating(): boolean { return this.message.status === 'loading' || this.message.status === 'streaming' }

  aboutToAppear(): void {
    this.tick()
    if (this.generating()) this.timer = setInterval(() => this.tick(), 1000)
  }

  aboutToDisappear(): void { if (this.timer >= 0) clearInterval(this.timer) }

  private tick(): void {
    const elapsed = ExecutionTraceService.elapsed(this.message)
    this.elapsedSeconds = Math.floor((elapsed || 0) / 1000)
    this.durationText = elapsed === undefined ? '用时未记录' : `思考用时 ${ExecutionTraceService.duration(elapsed)}`
    if (!this.generating() && this.timer >= 0) { clearInterval(this.timer); this.timer = -1 }
  }

  private label(): string {
    if (this.message.status === 'error') return '生成未完成'
    if (this.message.status === 'stopped') return '已停止'
    if (!this.generating()) return '思考与执行'
    if (this.message.phase === 'retrieving') return '正在检索资料'
    if (this.message.phase === 'connecting') return '正在连接模型'
    if (this.message.phase === 'updating') return '正在调用工具'
    if (this.message.phase === 'analyzing' || MarkdownParser.answer(this.message.content).summarizing) return '正在思考'
    return '正在生成回答'
  }

  build() {
    Column({ space: 12 * this.fontScale }) {
      if (this.message.thinkingStartedAt !== undefined || this.message.thinkingDurationMs !== undefined || (this.message.executions || []).length > 0 || MarkdownParser.answer(this.message.content).summary.length > 0) {
        Column({ space: 8 * this.fontScale }) {
          Row({ space: 7 * this.fontScale }) {
            if (this.generating()) { LoadingProgress().width(15 * this.fontScale).height(15 * this.fontScale).color('#777777') }
            else { Text(this.message.status === 'error' ? '!' : this.message.status === 'stopped' ? '◌' : '✓').fontSize(13 * this.fontScale).fontColor('#777777') }
            Text(this.label()).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary)
            Text(this.durationText).fontSize(11 * this.fontScale).fontColor('#999999').id(`thought-duration-${this.documentId}`)
            Blank()
            Text(this.expanded ? '⌃' : '⌄').fontSize(13 * this.fontScale).fontColor('#888888')
          }.width('100%').height(34 * this.fontScale).accessibilityText(`${this.label()}，${this.durationText}，${this.expanded ? '收起' : '展开'}执行记录`)
            .id(`thought-toggle-${this.documentId}`)
            .hoverEffect(HoverEffect.Highlight)
            .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.65) } })
            .animation({ duration: UiMotion.fast, curve: UiMotion.enterCurve })
            .onClick(() => this.getUIContext().animateTo({
              duration: UiMotion.section,
              curve: UiMotion.moveCurve
            }, () => this.onToggle()))
          if (this.expanded) {
            if (MarkdownParser.answer(this.message.content).summary.length > 0) {
              MarkdownContent({ content: MarkdownParser.answer(this.message.content).summary })
            }
            if ((this.message.executions || []).length > 0) {
              ExecutionTimeline({ records: this.message.executions || [], active: this.generating(),
                now: (this.message.thinkingStartedAt || 0) + this.elapsedSeconds * 1000,
                executionId: this.message.executionId || this.documentId, onOpenArtifact: this.onOpenArtifact })
            } else {
              Text(this.generating() ? '模型正在处理请求，执行记录将在这里更新。' : '这条历史回复没有保存工具执行记录。')
                .fontSize(12 * this.fontScale).fontColor('#888888').lineHeight(20 * this.fontScale)
            }
            if (this.message.executionId) { Text('本轮操作据实记录；未执行终端命令。').fontSize(10 * this.fontScale).fontColor(UiTheme.muted).width('100%') }
          }
        }.width('100%').padding({ left: 10 * this.fontScale, right: 10 * this.fontScale, bottom: this.expanded ? 10 : 0 * this.fontScale })
          .backgroundColor(UiTheme.raised).borderRadius(8 * this.fontScale)
      }
      if (this.message.status !== 'loading' && MarkdownParser.answer(this.message.content).body.trim().length > 0) {
        InteractiveContent({ content: MarkdownParser.answer(this.message.content).body, documentId: this.documentId,
          sessionId: this.sessionId, editable: this.editable, feedback: this.feedback, onInteraction: this.onInteraction })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

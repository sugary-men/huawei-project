import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { InteractionChange, InteractionRecord } from '../models/InteractionModels'
import { InteractionService } from '../services/InteractionService'
import { MarkdownContent } from './MarkdownContent'

@Component
export struct InteractiveContent {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop content: string = ''
  @Prop documentId: string = ''
  @Prop sessionId: string = ''
  @Prop editable: boolean = true
  @Prop compact: boolean = false
  @Prop feedback: InteractionRecord = { id: '', source: '', title: '', values: [], updatedAt: 0 }
  @State editing: boolean = false
  onInteraction: (change: InteractionChange) => void = () => {}

  private decision(): string {
    return InteractionService.isPreviousVersion(this.feedback, this.content) ? 'none' : InteractionService.value(this.feedback, 'decision', 'none')
  }
  private notes(): string { return InteractionService.value(this.feedback, 'notes') }
  private setEditing(value: boolean): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.editing = value)
  }
  private emit(change: InteractionChange): void {
    this.onInteraction({ controlId: change.controlId, value: change.value, reset: change.reset,
      sessionId: this.sessionId, documentId: this.documentId, submit: change.submit })
  }

  @Styles
  actionFeedback() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1).scale({ x: 1, y: 1 }) }, pressed: { .opacity(0.76).scale({ x: 0.98, y: 0.98 }) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }

  build() {
    Column({ space: 10 * this.fontScale }) {
      if (InteractionService.isPreviousVersion(this.feedback, this.content)) {
        Text('内容已更新；保留的勾选和填写来自上一版，请核对后重新确认。').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
          .lineHeight(18 * this.fontScale).width('100%').padding(8 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(6 * this.fontScale)
      }
      if (this.editing && InteractionService.layout(this.content).hasTables) {
        Text('填写表格中的实际信息，修改会自动保存。').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
      }
      MarkdownContent({ content: this.content, textSize: this.compact ? 13 : 15, interactive: true, editable: this.editable, editTables: this.editing,
        documentId: this.documentId, feedback: this.feedback, layout: InteractionService.layout(this.content),
        onInteraction: (change: InteractionChange) => this.emit(change) })
      Flex({ wrap: FlexWrap.Wrap }) {
        Button(this.decision() === 'confirmed' ? '再次检查' : '确认内容').height(28 * this.fontScale).fontSize((this.compact ? 10 : 11) * this.fontScale)
          .fontWeight(FontWeight.Regular).borderRadius(7 * this.fontScale).padding({ left: 12 * this.fontScale, right: 12 * this.fontScale, top: 0, bottom: 0 })
          .fontColor(this.decision() === 'confirmed' ? UiTheme.choiceSelectedText : UiTheme.choiceUnselectedText)
          .backgroundColor(this.decision() === 'confirmed' ?
            UiTheme.choiceSelectedBackground : UiTheme.raised).margin({ right: 6 * this.fontScale, bottom: 5 * this.fontScale })
          .enabled(this.editable).id(InteractionService.elementId(this.documentId, 'confirm'))
          .accessibilityText('提交当前填写内容，让Agent检查并回复').actionFeedback()
          .onClick(() => { this.setEditing(false); this.emit({ controlId: 'decision', value: 'confirmed', submit: true }) })
        Button(this.decision() === 'needs_changes' ? '✓ 需要调整' : '需要调整').height(28 * this.fontScale).fontSize((this.compact ? 10 : 11) * this.fontScale)
          .fontWeight(FontWeight.Regular).borderRadius(7 * this.fontScale).padding({ left: 12 * this.fontScale, right: 12 * this.fontScale, top: 0, bottom: 0 })
          .fontColor(this.decision() === 'needs_changes' ? UiTheme.choiceSelectedText : UiTheme.choiceUnselectedText)
          .backgroundColor(this.decision() === 'needs_changes' ?
            UiTheme.choiceSelectedBackground : UiTheme.raised).margin({ right: 6 * this.fontScale, bottom: 5 * this.fontScale })
          .enabled(this.editable).id(InteractionService.elementId(this.documentId, 'revise')).actionFeedback()
          .onClick(() => { this.setEditing(true); this.emit({ controlId: 'decision', value: this.decision() === 'needs_changes' ? 'none' : 'needs_changes' }) })
        Button(this.editing ? '收起填写' : '填写 / 补充').height(28 * this.fontScale).fontSize((this.compact ? 10 : 11) * this.fontScale)
          .fontWeight(FontWeight.Regular).borderRadius(7 * this.fontScale).padding({ left: 12 * this.fontScale, right: 12 * this.fontScale, top: 0, bottom: 0 }).fontColor(UiTheme.primary)
          .backgroundColor(UiTheme.raised).margin({ right: 6 * this.fontScale, bottom: 5 * this.fontScale }).enabled(this.editable)
          .id(InteractionService.elementId(this.documentId, 'edit')).actionFeedback().onClick(() => this.setEditing(!this.editing))
      }.width('100%')
      if (this.editing) {
        TextArea({ text: this.notes(), placeholder: '填写实际结果、补充信息或需要修改的内容…' }).placeholderFont({ size: 13 * this.fontScale })
          .width('100%').height(76 * this.fontScale).maxLength(1000).fontSize(13 * this.fontScale).fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').enabled(this.editable)
          .id(InteractionService.elementId(this.documentId, 'notes')).accessibilityText('补充说明或修改要求')
          .transition(UiMotion.reveal())
          .onChange((value: string) => this.emit({ controlId: 'notes', value: value }))
      } else if (this.notes()) {
        Text(`补充：${this.notes()}`).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(20 * this.fontScale).maxLines(3).width('100%')
          .copyOption(CopyOptions.InApp).actionFeedback().onClick(() => this.setEditing(true))
      }
      if (this.feedback.updatedAt > 0) {
        Row({ space: 8 * this.fontScale }) {
          Text(this.feedback.values.length > 0 ? '填写自动保存；确认内容后由 Agent 检查并回复' : '已重置此前反馈')
            .fontSize(10 * this.fontScale).fontColor(UiTheme.muted).layoutWeight(1)
          if (this.feedback.values.length > 0) {
            Button('重置反馈').height(24 * this.fontScale).borderRadius(6 * this.fontScale).padding({ left: 10 * this.fontScale, right: 10 * this.fontScale, top: 0, bottom: 0 }).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).backgroundColor(UiTheme.raised)
              .enabled(this.editable).actionFeedback().onClick(() => this.emit({ controlId: '', value: '', reset: true }))
          }
        }.width('100%').transition(UiMotion.fade())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

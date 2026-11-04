import { pasteboard } from '@kit.BasicServicesKit'
import { MarkdownParser } from '../services/MarkdownParser'
import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'

@Component
export struct ReplyActions {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop content: string = ''
  @Prop documentId: string = ''
  @Prop speaking: boolean = false
  onSpeak: () => void = () => {}
  @State copied: boolean = false
  private copiedTimer: number = -1
  private live: boolean = false

  aboutToAppear(): void { this.live = true }
  aboutToDisappear(): void { this.live = false; if (this.copiedTimer >= 0) clearTimeout(this.copiedTimer) }

  private async copyAnswer(): Promise<void> {
    const body = MarkdownParser.answer(this.content).body.trim()
    if (!body) return
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, body))
      if (!this.live) return
      this.copied = true
      if (this.copiedTimer >= 0) clearTimeout(this.copiedTimer)
      this.copiedTimer = setTimeout(() => { this.copied = false }, 1800)
      this.getUIContext().getPromptAction().showToast({ message: '回答已复制', duration: 1500 })
    } catch (_error) {
      if (this.live) this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试', duration: 1500 })
    }
  }

  @Styles
  actionFeedback() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1).scale({ x: 1, y: 1 }) }, pressed: { .opacity(0.6).scale({ x: 0.94, y: 0.94 }) } })
    .animation({ duration: UiMotion.press, curve: UiMotion.enterCurve })
  }

  build() {
    Row({ space: 2 * this.fontScale }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph(this.speaking ? $r('sys.symbol.speaker_slash') : $r('sys.symbol.speaker_wave_2'))
          .width(16 * this.fontScale).height(16 * this.fontScale).fontSize(16 * this.fontScale)
          .fontColor([UiTheme.iconIvory]).renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .effectStrategy(SymbolEffectStrategy.NONE)
      }.actionFeedback().width(32 * this.fontScale).height(32 * this.fontScale).padding(0).borderRadius(6 * this.fontScale)
        .backgroundColor(this.speaking ? UiTheme.accent : UiTheme.accentStrong)
        .id(`reply-speech-${this.documentId}`).accessibilityText(this.speaking ? '停止朗读' : '朗读回答').onClick(() => this.onSpeak())
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph(this.copied ? $r('sys.symbol.checkmark') : $r('sys.symbol.doc_text_on_doc_text'))
          .width(16 * this.fontScale).height(16 * this.fontScale).fontSize(16 * this.fontScale)
          .fontColor([UiTheme.iconIvory]).renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .effectStrategy(SymbolEffectStrategy.NONE)
      }.actionFeedback().width(32 * this.fontScale).height(32 * this.fontScale).padding(0).borderRadius(6 * this.fontScale)
        .backgroundColor(UiTheme.accentStrong).id(`reply-copy-${this.documentId}`)
        .accessibilityText(this.copied ? '回答已复制' : '复制回答').onClick(() => this.copyAnswer())
    }
  }
}

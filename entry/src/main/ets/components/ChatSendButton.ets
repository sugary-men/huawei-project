import { UiTheme } from '../config/UiTheme'

@Component
export struct ChatSendButton {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  onSend: () => void = () => {}

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.paperplane'))
        .width(16 * this.fontScale).height(16 * this.fontScale).fontSize(16 * this.fontScale)
        .fontColor([UiTheme.iconIvory]).renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .effectStrategy(SymbolEffectStrategy.NONE).id('chat-send-icon')
    }.width(32 * this.fontScale).height(32 * this.fontScale).padding(0).backgroundColor(UiTheme.accent)
      .id('chat-send').accessibilityText('发送消息').hoverEffect(HoverEffect.Highlight).onClick(() => this.onSend())
  }
}

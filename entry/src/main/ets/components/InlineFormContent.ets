import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { InteractionChange, InteractionRecord, InteractionToken } from '../models/InteractionModels'
import { InteractionService } from '../services/InteractionService'
import { MarkdownParser, MarkdownRun } from '../services/MarkdownParser'

@Component
export struct InlineFormContent {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop tokens: InteractionToken[] = []
  @Prop textSize: number = 15
  @Prop documentId: string = ''
  @Prop editable: boolean = true
  @Prop feedback: InteractionRecord = { id: '', source: '', title: '', values: [], updatedAt: 0 }
  onInteraction: (change: InteractionChange) => void = () => {}

  build() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      ForEach(this.tokens, (token: InteractionToken) => {
        if (token.kind === 'input' && token.control !== undefined) {
          TextInput({ text: InteractionService.inputValue(this.feedback, token.control), placeholder: '填写' })
            .width(96 * this.fontScale).height(28 * this.fontScale).fontSize(this.textSize * this.fontScale).placeholderFont({ size: (this.textSize - 2) * this.fontScale })
            .fontColor(UiTheme.text).backgroundColor('#F8F8F8').borderRadius(4 * this.fontScale)
            .border({ width: { bottom: 1 }, color: '#BBBBBB' })
            .padding({ left: 7 * this.fontScale, right: 7 * this.fontScale, top: 0, bottom: 0 })
            .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD').maxLength(1000).enabled(this.editable)
            .stateStyles({ normal: { .opacity(1) }, focused: { .backgroundColor('#F0F0F0').border({ width: { bottom: 1 }, color: '#555555' }) } })
            .animation({ duration: UiMotion.fast, curve: UiMotion.enterCurve })
            .margin({ left: 3 * this.fontScale, right: 3 * this.fontScale, bottom: 3 * this.fontScale })
            .id(InteractionService.elementId(this.documentId, token.control.id)).accessibilityText(token.control.label)
            .onChange((value: string) => this.onInteraction({ controlId: token.control!.id, value: value }))
        } else if (token.kind === 'check' && token.control !== undefined) {
          Row({ space: 7 * this.fontScale }) {
            Checkbox({ name: token.control.id }).shape(token.control.group ? CheckBoxShape.CIRCLE : CheckBoxShape.ROUNDED_SQUARE)
              .width(16 * this.fontScale).height(16 * this.fontScale).padding(0).selectedColor(UiTheme.primary).unselectedColor('#AAAAAA')
              .select(InteractionService.controlValue(this.feedback, token.control) === 'true').enabled(this.editable)
              .id(InteractionService.elementId(this.documentId, token.control.id)).accessibilityText(token.control.label)
              .onChange((checked: boolean) => this.onInteraction({ controlId: token.control!.id, value: checked ? 'true' : 'false' }))
            Text(token.text).fontSize(this.textSize * this.fontScale).fontColor(UiTheme.text)
              .lineHeight(this.textSize * this.fontScale * 1.6).layoutWeight(1)
              .onClick(() => { if (this.editable) this.onInteraction({ controlId: token.control!.id,
                value: InteractionService.controlValue(this.feedback, token.control!) === 'true' ? 'false' : 'true' }) })
          }.width('100%').padding({ top: 5 * this.fontScale, bottom: 5 * this.fontScale }).alignItems(VerticalAlign.Center)
        } else {
          Text() {
            ForEach(MarkdownParser.inline(token.text), (run: MarkdownRun) => {
              Span(run.text).fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
                .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal).fontFamily(run.code ? 'monospace' : 'HarmonyOS Sans')
            }, (run: MarkdownRun, index: number) => `${index}-${JSON.stringify(run)}`)
          }.fontSize(this.textSize * this.fontScale).fontColor(UiTheme.text).lineHeight(this.textSize * this.fontScale * 1.65)
            .copyOption(CopyOptions.InApp)
        }
      }, (token: InteractionToken, index: number) => `${index}-${token.control?.id || token.text}`)
    }.width('100%')
  }
}

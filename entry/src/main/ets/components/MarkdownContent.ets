import { InlineFormContent } from './InlineFormContent'
import { UiTheme } from '../config/UiTheme'
import { MarkdownParser, MarkdownBlock, MarkdownRun, MarkdownRow } from '../services/MarkdownParser'
import { InteractionChange, InteractionLayout, InteractionRecord } from '../models/InteractionModels'
import { InteractionService } from '../services/InteractionService'

@Component
struct MarkdownInline {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop text: string = ''
  @Prop textSize: number = 15
  @Prop strong: boolean = false
  @Prop color: string = UiTheme.text

  build() {
    Text() {
      ForEach(MarkdownParser.inline(this.text), (run: MarkdownRun) => {
        Span(run.text).fontSize(this.textSize * this.fontScale).fontWeight(run.bold || this.strong ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(run.code ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(run.link ? UiTheme.primary : run.code ? '#666666' : this.color)
          .decoration({ type: run.strike ? TextDecorationType.LineThrough : run.link ? TextDecorationType.Underline : TextDecorationType.None })
      }, (run: MarkdownRun, index: number) => `${index}-${JSON.stringify(run)}`)
    }.fontSize(this.textSize * this.fontScale).lineHeight(this.textSize * 1.65 * this.fontScale).copyOption(CopyOptions.InApp).width('100%')
      .textAlign(TextAlign.Start)
  }
}

@Component
export struct MarkdownContent {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop content: string = ''
  @Prop textSize: number = 15
  @Prop interactive: boolean = false
  @Prop editable: boolean = true
  @Prop editTables: boolean = false
  @Prop documentId: string = ''
  @Prop feedback: InteractionRecord = { id: '', source: '', title: '', values: [], updatedAt: 0 }
  @Prop layout: InteractionLayout = { lists: {}, cells: {}, controls: [], hasTables: false }
  onInteraction: (change: InteractionChange) => void = () => {}

  private cellValue(block: number, row: number, column: number, fallback: string): string {
    const control = this.layout.cells[`${block}:${row}:${column}`]
    return control === undefined ? fallback : InteractionService.controlValue(this.feedback, control)
  }

  private cellInputValue(block: number, row: number, column: number): string {
    const control = this.layout.cells[`${block}:${row}:${column}`]
    return control === undefined ? '' : InteractionService.inputValue(this.feedback, control)
  }

  build() {
    Column({ space: 10 * this.fontScale }) {
      ForEach(MarkdownParser.parse(this.content), (block: MarkdownBlock, blockIndex: number) => {
        if (block.kind === 'heading') {
          MarkdownInline({ text: block.text, textSize: (block.level === 1 ? 23 : block.level === 2 ? 20 : block.level === 3 ? 17 : 15) * this.textSize / 15, strong: true })
            .margin({ top: 7 * this.fontScale, bottom: 2 * this.fontScale })
        } else if (block.kind === 'divider') {
          Divider().color(UiTheme.border).strokeWidth(1).margin({ top: 5 * this.fontScale, bottom: 5 * this.fontScale })
        } else if (block.kind === 'list') {
          Row({ space: 8 * this.fontScale }) {
            if (this.interactive && this.layout.lists[`${blockIndex}`] !== undefined) {
              Checkbox({ name: this.layout.lists[`${blockIndex}`].id }).shape(CheckBoxShape.ROUNDED_SQUARE).width(16 * this.fontScale).height(16 * this.fontScale).padding(0).margin({ top: 5 * this.fontScale })
                .select(InteractionService.controlValue(this.feedback, this.layout.lists[`${blockIndex}`]) === 'true')
                .selectedColor(UiTheme.primary).unselectedColor(UiTheme.muted)
                .enabled(this.editable).id(InteractionService.elementId(this.documentId, this.layout.lists[`${blockIndex}`].id))
                .accessibilityText(`清单项：${this.layout.lists[`${blockIndex}`].label}`)
                .onChange((checked: boolean) => this.onInteraction({ controlId: this.layout.lists[`${blockIndex}`].id, value: checked ? 'true' : 'false' }))
              if (/^\d/.test(block.prefix)) { Text(block.prefix).fontSize(13 * this.fontScale).fontColor(UiTheme.muted).lineHeight(25 * this.fontScale) }
            } else {
              Text(block.prefix).fontSize(15 * this.fontScale).fontColor(UiTheme.primary).lineHeight(25 * this.fontScale).constraintSize({ minWidth: 16 })
            }
            if (this.interactive && InteractionService.inlineTokens(this.layout, `${blockIndex}`).length > 0) {
              InlineFormContent({ tokens: InteractionService.inlineTokens(this.layout, `${blockIndex}`), documentId: this.documentId, textSize: this.textSize,
                editable: this.editable, feedback: this.feedback, onInteraction: this.onInteraction }).layoutWeight(1)
            } else { MarkdownInline({ text: block.text, textSize: this.textSize }).layoutWeight(1) }
          }.width('100%').alignItems(VerticalAlign.Top).padding({ left: block.level * 14 })
        } else if (block.kind === 'code') {
          Column({ space: 6 * this.fontScale }) {
            if (block.language.length > 0) { Text(block.language).fontSize(11 * this.fontScale).fontColor('#777777') }
            Scroll() {
              Text(block.text || ' ').fontSize(13 * this.fontScale).fontFamily('monospace').fontColor('#404040')
                .lineHeight(21 * this.fontScale).copyOption(CopyOptions.InApp).constraintSize({ minWidth: '100%' })
            }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Auto)
              .scrollBarWidth(3).scrollBarColor('#777777').padding({ bottom: 4 * this.fontScale })
          }.alignItems(HorizontalAlign.Start).width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8 * this.fontScale)
        } else if (block.kind === 'quote') {
          Row({ space: 10 * this.fontScale }) {
            MarkdownInline({ text: block.text, textSize: this.textSize, color: '#777777' })
          }.width('100%').padding({ left: 12 * this.fontScale, top: 6 * this.fontScale, bottom: 6 * this.fontScale, right: 8 * this.fontScale })
            .border({ width: { left: 3 }, color: '#AAAAAA' }).backgroundColor(UiTheme.raised)
        } else if (block.kind === 'table') {
          Scroll() {
            Column() {
              ForEach(block.rows, (row: MarkdownRow, rowIndex: number) => {
                Flex({ alignItems: ItemAlign.Stretch }) {
                  ForEach(row.cells, (cell: string, column: number) => {
                    Column() {
                      if (this.interactive && InteractionService.inlineTokens(this.layout, `${blockIndex}:${rowIndex}:${column}`).length > 0) {
                        InlineFormContent({ tokens: InteractionService.inlineTokens(this.layout, `${blockIndex}:${rowIndex}:${column}`),
                          documentId: this.documentId, textSize: 13, editable: this.editable, feedback: this.feedback,
                          onInteraction: this.onInteraction }).width('100%')
                      } else if (this.interactive && (this.editTables || InteractionService.isPlaceholder(cell)) && rowIndex > 0 && this.layout.cells[`${blockIndex}:${rowIndex}:${column}`] !== undefined) {
                        TextInput({ text: this.cellInputValue(blockIndex, rowIndex, column), placeholder: '填写信息' }).placeholderFont({ size: 13 * this.fontScale })
                          .width('100%').height(28 * this.fontScale).maxLength(1000).fontSize(13 * this.fontScale).fontColor(UiTheme.text).backgroundColor(UiTheme.surface)
                          .caretColor(UiTheme.primary).selectedBackgroundColor('#DDDDDD')
                          .padding({ left: 4 * this.fontScale, right: 4 * this.fontScale, top: 0, bottom: 0 }).enabled(this.editable)
                          .id(InteractionService.elementId(this.documentId, this.layout.cells[`${blockIndex}:${rowIndex}:${column}`].id))
                          .accessibilityText(this.layout.cells[`${blockIndex}:${rowIndex}:${column}`].label)
                          .onChange((value: string) => this.onInteraction({ controlId: this.layout.cells[`${blockIndex}:${rowIndex}:${column}`].id, value: value }))
                      } else {
                        MarkdownInline({ text: this.interactive && rowIndex > 0 ? this.cellValue(blockIndex, rowIndex, column, cell) : cell,
                          textSize: 13, strong: rowIndex === 0 }).width('100%')
                      }
                    }.width(184 * this.fontScale).flexShrink(0).constraintSize({ minHeight: 42 * this.fontScale })
                      .padding({ left: 10 * this.fontScale, right: 10 * this.fontScale, top: 8 * this.fontScale, bottom: 8 * this.fontScale })
                      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
                      .border({ width: { right: column < row.cells.length - 1 ? 1 : 0 }, color: UiTheme.border })
                  }, (cell: string, index: number) => `${index}-${cell}`)
                }.width(block.rows[0].cells.length * 184 * this.fontScale)
                  .backgroundColor(rowIndex === 0 ? UiTheme.raised : rowIndex % 2 === 0 ? UiTheme.raised : UiTheme.surface)
                  .border({ width: { bottom: rowIndex < block.rows.length - 1 ? 1 : 0 }, color: UiTheme.border })
              }, (row: MarkdownRow, index: number) => `${index}-${JSON.stringify(row)}`)
            }.border({ width: 1, color: UiTheme.border }).borderRadius(6 * this.fontScale).clip(true)
          }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Auto)
            .scrollBarWidth(3).scrollBarColor('#777777').padding({ bottom: 4 * this.fontScale })
        } else if (this.interactive && InteractionService.inlineTokens(this.layout, `${blockIndex}`).length > 0) {
          InlineFormContent({ tokens: InteractionService.inlineTokens(this.layout, `${blockIndex}`), documentId: this.documentId, textSize: this.textSize,
            editable: this.editable, feedback: this.feedback, onInteraction: this.onInteraction })
        } else {
          MarkdownInline({ text: block.text, textSize: this.textSize })
        }
      }, (block: MarkdownBlock, index: number) => `${index}-${JSON.stringify(block)}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

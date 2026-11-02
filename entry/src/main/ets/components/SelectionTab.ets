import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'

@Component
export struct SelectionTab {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop label: string = ''
  @Prop selected: boolean = false
  @Prop itemId: string = ''
  @Prop itemWidth: number = 0
  @Prop showIndicator: boolean = true
  @Prop disabled: boolean = false
  onSelect: () => void = () => {}

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 * this.fontScale }) {
        Text(this.label).fontSize(11 * this.fontScale)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selected ? UiTheme.choiceSelectedText : UiTheme.choiceUnselectedText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.showIndicator) {
          Row().width(this.selected ? 18 * this.fontScale : 0)
            .height(2 * this.fontScale)
            .backgroundColor(this.selected ? UiTheme.choiceIndicator : UiTheme.choiceUnselectedBackground)
            .borderRadius(1)
        }
      }.height(34 * this.fontScale).justifyContent(FlexAlign.Center)
    }.height(38 * this.fontScale).constraintSize({ minWidth: this.itemWidth * this.fontScale })
      .padding({ left: 10 * this.fontScale, right: 10 * this.fontScale })
      .backgroundColor(this.selected ? UiTheme.choiceSelectedBackground : UiTheme.choiceUnselectedBackground)
      .border({
        width: this.selected ? 1 : 0,
        color: this.selected ? UiTheme.choiceSelectedBorder : UiTheme.choiceUnselectedBackground
      })
      .borderRadius(7)
      .id(this.itemId)
      .enabled(!this.disabled)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        normal: { .opacity(1).scale({ x: 1, y: 1 }) },
        pressed: { .opacity(0.78).scale({ x: 0.98, y: 0.98 }) }
      })
      .animation({ duration: UiMotion.press, curve: UiMotion.enterCurve })
      .onClick(() => this.onSelect())
  }
}

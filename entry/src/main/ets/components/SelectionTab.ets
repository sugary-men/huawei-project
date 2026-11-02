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
  onSelect: () => void = () => {}

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 * this.fontScale }) {
        Text(this.label).fontSize(11 * this.fontScale)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selected ? UiTheme.text : UiTheme.muted)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.showIndicator) {
          Row().width(this.selected ? 18 * this.fontScale : 0)
            .height(2 * this.fontScale)
            .backgroundColor(this.selected ? UiTheme.text : Color.Transparent)
            .borderRadius(1)
        }
      }.height(34 * this.fontScale).justifyContent(FlexAlign.Center)
    }.height(38 * this.fontScale).constraintSize({ minWidth: this.itemWidth * this.fontScale })
      .padding({ left: 10 * this.fontScale, right: 10 * this.fontScale })
      .backgroundColor(this.selected ? UiTheme.surface : Color.Transparent)
      .border({
        width: this.selected ? 1 : 0,
        color: this.selected ? UiTheme.border : Color.Transparent
      })
      .borderRadius(7)
      .id(this.itemId)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        normal: { .opacity(1).scale({ x: 1, y: 1 }) },
        pressed: { .opacity(0.78).scale({ x: 0.98, y: 0.98 }) }
      })
      .animation({ duration: UiMotion.press, curve: UiMotion.enterCurve })
      .onClick(() => this.onSelect())
  }
}

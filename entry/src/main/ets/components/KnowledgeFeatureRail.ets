import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'

interface KnowledgeFeatureItem {
  value: string
  label: string
  icon: string
}

@Component
export struct KnowledgeFeatureRail {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop selected: string = 'visualization'
  @Prop collapsed: boolean = false
  onSelect: (value: string) => void = () => {}
  onToggle: () => void = () => {}

  private features(): KnowledgeFeatureItem[] {
    return [
      { value: 'visualization', label: '数据可视化', icon: '◎' },
      { value: 'modelApi', label: '模型与 API', icon: '≋' },
      { value: 'settings', label: '算法与设置', icon: '⌁' },
      { value: 'operations', label: '其他', icon: '▦' }
    ]
  }

  @Builder
  FeatureButton(item: KnowledgeFeatureItem) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 * this.fontScale }) {
        Text(item.icon).fontSize(18 * this.fontScale)
          .fontColor(this.selected === item.value ? UiTheme.choiceSelectedText : UiTheme.choiceUnselectedText)
        if (!this.collapsed) {
          Text(item.label).fontSize(10 * this.fontScale)
            .fontColor(this.selected === item.value ? UiTheme.choiceSelectedText : UiTheme.choiceUnselectedText)
            .fontWeight(this.selected === item.value ? FontWeight.Medium : FontWeight.Regular)
            .textAlign(TextAlign.Center).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.width('100%').height(this.collapsed ? 40 * this.fontScale : 56 * this.fontScale)
        .justifyContent(FlexAlign.Center)
    }.width('100%').height(this.collapsed ? 40 * this.fontScale : 58 * this.fontScale)
      .padding(this.collapsed ? 0 : { left: 4, right: 4 })
      .backgroundColor(this.selected === item.value ? UiTheme.choiceSelectedBackground : UiTheme.choiceUnselectedBackground)
      .borderRadius(8).accessibilityText(item.label)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        normal: { .opacity(1).scale({ x: 1, y: 1 }) },
        pressed: { .opacity(0.72).scale({ x: 0.96, y: 0.96 }) }
      })
      .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
      .onClick(() => this.onSelect(item.value))
  }

  build() {
    Column() {
      Button(this.collapsed ? '‹' : '›').width('100%').height(34 * this.fontScale)
        .fontSize(16 * this.fontScale).padding(0)
        .backgroundColor(Color.Transparent).fontColor(UiTheme.muted)
        .accessibilityText(this.collapsed ? '展开功能栏' : '收起功能栏')
        .onClick(() => this.onToggle())
      Divider().color(UiTheme.border)
      Scroll() {
        Column({ space: 4 * this.fontScale }) {
          ForEach(this.features(), (item: KnowledgeFeatureItem) => {
            this.FeatureButton(item)
          }, (item: KnowledgeFeatureItem) => item.value)
        }.width('100%').padding({ left: 5, right: 5, top: 5, bottom: 8 })
      }.layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width(this.collapsed ? 46 : 92).height('100%')
      .backgroundColor(UiTheme.surface)
      .border({ width: { left: 1 }, color: UiTheme.border })
      .animation({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve })
  }
}

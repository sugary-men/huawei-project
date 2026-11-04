import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'

interface KnowledgeFeatureItem {
  value: string
  label: string
  icon: Resource
}

@Component
export struct KnowledgeFeatureRail {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop selected: string = 'visualization'
  @Prop collapsed: boolean = false
  @Prop horizontal: boolean = false
  onSelect: (value: string) => void = () => {}
  onToggle: () => void = () => {}

  private features(): KnowledgeFeatureItem[] {
    return [
      { value: 'library', label: '资料库', icon: $r('app.media.ic_library') },
      { value: 'visualization', label: '数据可视化', icon: $r('app.media.ic_image') },
      { value: 'settings', label: '算法与设置', icon: $r('app.media.ic_settings') }
    ]
  }

  @Builder
  FeatureButton(item: KnowledgeFeatureItem, compact: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      if (compact) {
        Row({ space: 6 * this.fontScale }) {
          Stack() {
            Image(item.icon).width(15 * this.fontScale).height(15 * this.fontScale)
              .objectFit(ImageFit.Contain).attributeModifier(UiTheme.glyph(this.selected === item.value ? UiTheme.iconNavIvory : UiTheme.iconIvory))
          }.width(24 * this.fontScale).height(24 * this.fontScale)
            .backgroundColor(this.selected === item.value ? UiTheme.accentStrong : UiTheme.primary)
            .borderRadius(6)
          Text(item.label).fontSize(10 * this.fontScale)
            .fontColor(this.selected === item.value ? UiTheme.accentStrong : UiTheme.softMuted)
            .fontWeight(this.selected === item.value ? FontWeight.Medium : FontWeight.Regular)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 4 * this.fontScale }) {
          Stack() {
            Image(item.icon).width(18 * this.fontScale).height(18 * this.fontScale)
              .objectFit(ImageFit.Contain).attributeModifier(UiTheme.glyph(this.selected === item.value ? UiTheme.iconNavIvory : UiTheme.iconIvory))
          }.width(30 * this.fontScale).height(30 * this.fontScale)
            .backgroundColor(this.selected === item.value ? UiTheme.accentStrong : UiTheme.primary)
            .borderRadius(7)
          if (!this.collapsed) {
            Text(item.label).fontSize(10 * this.fontScale)
              .fontColor(this.selected === item.value ? UiTheme.accentStrong : UiTheme.softMuted)
              .fontWeight(this.selected === item.value ? FontWeight.Medium : FontWeight.Regular)
              .textAlign(TextAlign.Center).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.width('100%').height(this.collapsed ? 40 * this.fontScale : 56 * this.fontScale)
          .justifyContent(FlexAlign.Center)
      }
    }.width('100%').height(compact ? 40 * this.fontScale : (this.collapsed ? 40 * this.fontScale : 58 * this.fontScale))
      .padding(compact ? { left: 6, right: 6 } : (this.collapsed ? 0 : { left: 4, right: 4 }))
      .backgroundColor(this.selected === item.value ? UiTheme.accentPale : UiTheme.surface)
      .border({ width: 1, color: this.selected === item.value ? UiTheme.accentBorder : UiTheme.softBorder })
      .borderRadius(8).accessibilityText(item.label)
      .accessibilitySelected(this.selected === item.value)
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        normal: { .opacity(1).scale({ x: 1, y: 1 }) },
        pressed: { .opacity(0.72).scale({ x: 0.96, y: 0.96 }) }
      })
      .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
      .onClick(() => { if (this.selected !== item.value) this.onSelect(item.value) })
  }

  @Builder
  HorizontalNavigation() {
    GridRow({ columns: 12, gutter: 7 * this.fontScale }) {
      ForEach(this.features(), (item: KnowledgeFeatureItem) => {
        GridCol({ span: 4 }) {
          this.FeatureButton(item, true)
        }
      }, (item: KnowledgeFeatureItem) => item.value)
    }.width('100%').padding({ left: 7 * this.fontScale, right: 7 * this.fontScale,
      top: 7 * this.fontScale, bottom: 7 * this.fontScale })
      .backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.softBorder }).borderRadius(14)
      .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 2 })
  }

  @Builder
  VerticalNavigation() {
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
        }.width('100%').padding({ left: 5, right: 8, top: 5, bottom: 8 })
      }.layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(3).scrollBarColor(UiTheme.softMuted)
        .align(Alignment.TopStart)
    }.width(this.collapsed ? 50 : 96).height('100%')
      .backgroundColor(UiTheme.surface)
      .border({ width: { left: 1 }, color: UiTheme.softBorder })
      .animation({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve })
  }

  build() {
    if (this.horizontal) {
      this.HorizontalNavigation()
    } else {
      this.VerticalNavigation()
    }
  }
}

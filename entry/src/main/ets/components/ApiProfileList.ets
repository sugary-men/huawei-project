import { AgentProfileSummary } from '../config/ApiConfig'
import { UiTheme } from '../config/UiTheme'

@Component
export struct ApiProfileList {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop profiles: AgentProfileSummary[] = []
  @Prop selectedId: string = ''
  @Prop activeId: string = ''
  @Prop maxHeight: number = 180
  @Prop prefix: string = 'api-profile'
  onSelect: (id: string) => void = () => {}
  @State query: string = ''

  private filtered(): AgentProfileSummary[] {
    const query = this.query.trim().toLocaleLowerCase()
    return query ? this.profiles.filter((profile: AgentProfileSummary) =>
      profile.name.toLocaleLowerCase().includes(query) || profile.model.toLocaleLowerCase().includes(query)) : this.profiles
  }

  build() {
    Column({ space: 6 * this.fontScale }) {
      if (this.profiles.length > 5 || this.query) {
        Row({ space: 4 * this.fontScale }) {
          TextInput({ text: this.query, placeholder: '搜索配置或模型' }).id(`${this.prefix}-search`)
            .fontSize(11 * this.fontScale).placeholderFont({ size: 11 * this.fontScale }).height(32 * this.fontScale)
            .layoutWeight(1).backgroundColor(UiTheme.raised).borderRadius(6 * this.fontScale).onChange((value: string) => this.query = value)
          if (this.query) {
            Button('×').fontSize(15 * this.fontScale).width(28 * this.fontScale).height(28 * this.fontScale).padding(0)
              .backgroundColor(Color.Transparent).fontColor(UiTheme.secondary).id(`${this.prefix}-clear`)
              .accessibilityText('清除模型搜索').onClick(() => this.query = '')
          }
        }.width('100%')
      }
      Scroll() {
        Column({ space: 0 }) {
          if (this.filtered().length === 0) {
            Text(this.profiles.length ? '没有匹配的模型' : '尚未保存模型配置').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
              .height(48 * this.fontScale).width('100%').textAlign(TextAlign.Center).id(`${this.prefix}-empty`)
          }
          ForEach(this.filtered(), (profile: AgentProfileSummary) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 * this.fontScale }) {
                Column({ space: 3 * this.fontScale }) {
                  Text(profile.name).fontSize(12 * this.fontScale)
                    .fontColor(profile.id === this.selectedId ? UiTheme.choiceSelectedText : UiTheme.choiceUnselectedText)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text(profile.model).fontSize(10 * this.fontScale).fontColor(UiTheme.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(profile.id === this.activeId ? '✓' : '').fontSize(12 * this.fontScale)
                  .fontColor(UiTheme.choiceIndicator).width(16 * this.fontScale)
              }.width('100%')
            }.hoverEffect(HoverEffect.Highlight).width('100%').height(48 * this.fontScale).padding({ left: 10 * this.fontScale, right: 10 * this.fontScale })
              .borderRadius(6 * this.fontScale)
              .backgroundColor(profile.id === this.selectedId ?
                UiTheme.choiceSelectedBackground : UiTheme.choiceUnselectedBackground)
              .id(`${this.prefix}-${profile.id}`).accessibilityText(`${profile.name}，${profile.model}${profile.id === this.activeId ? '，当前使用' : ''}`)
              .onClick(() => this.onSelect(profile.id))
          }, (profile: AgentProfileSummary) => `${profile.id}-${profile.name}-${profile.model}`)
        }.width('100%').padding({ right: 7 * this.fontScale })
      }.width('100%').height(Math.min(Math.max(1, this.filtered().length) * 48 * this.fontScale, this.maxHeight))
        .align(Alignment.TopStart).scrollBar(BarState.Auto).scrollBarWidth(3).id(`${this.prefix}-scroll`).clip(true)
    }.width('100%')
  }
}

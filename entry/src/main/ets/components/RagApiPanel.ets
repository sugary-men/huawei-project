import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { RagApiProfile, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'

@Component
export struct RagApiPanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 900
  onChanged: () => void = () => {}
  @State archive: RagWorkspaceArchive = RagWorkspaceService.empty()
  @State filter: string = 'all'
  @State selectedId: string = ''
  @State kind: string = 'embedding'
  @State name: string = ''
  @State baseUrl: string = ''
  @State model: string = ''
  @State apiKey: string = ''
  @State dimensions: string = '512'
  @State notice: string = ''
  @State panelWidth: number = 900

  aboutToAppear(): void { this.refresh() }

  private workspace(): RagWorkspaceService | undefined { return IntegrationService.ragWorkspace }
  private wide(): boolean { return (this.viewportWidth || this.panelWidth) >= 700 }
  private refresh(preferred: string = ''): void {
    const workspace = this.workspace()
    if (workspace === undefined) return
    this.archive = workspace.read()
    const profiles = this.visibleProfiles()
    const profile = profiles.find((item: RagApiProfile) => item.id === preferred) || profiles[0]
    if (profile !== undefined) this.edit(profile)
  }
  private visibleProfiles(): RagApiProfile[] {
    return this.archive.apiProfiles.filter((profile: RagApiProfile) =>
      this.filter === 'all' || profile.kind === this.filter)
  }
  private edit(profile: RagApiProfile): void {
    this.selectedId = profile.id
    this.kind = profile.kind
    this.name = profile.name
    this.baseUrl = profile.baseUrl
    this.model = profile.model
    this.apiKey = profile.apiKey
    this.dimensions = String(profile.dimensions)
    this.notice = ''
  }
  private add(kind: string): void {
    this.selectedId = ''
    this.kind = kind
    this.name = ''
    this.baseUrl = kind === 'embedding' ? 'https://open.bigmodel.cn/api/paas/v4' : ''
    this.model = kind === 'embedding' ? 'embedding-3' : ''
    this.apiKey = ''
    this.dimensions = kind === 'embedding' ? '512' : '0'
    this.notice = ''
  }
  private save(): void {
    const workspace = this.workspace()
    if (workspace === undefined) return
    try {
      const profile = workspace.saveProfile(this.selectedId, this.kind, this.name, this.baseUrl,
        this.model, this.apiKey, Number(this.dimensions))
      this.archive = workspace.read()
      this.selectedId = profile.id
      this.refresh(profile.id)
      this.notice = 'API配置已保存到本机。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '保存失败。' }
  }
  private async remove(): Promise<void> {
    const workspace = this.workspace()
    if (workspace === undefined || !this.selectedId) return
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除RAG API',
        message: `删除“${this.name || this.model}”？引用该配置的知识库会切换为本地方法。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#666666' }] })
      if (result.index !== 1) return
      workspace.removeProfile(this.selectedId)
      this.selectedId = ''
      this.refresh()
      this.notice = 'API配置已删除。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '删除失败。' }
  }
  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.7) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }
  @Builder
  FilterButton(label: string, value: string) {
    Button(label).height(29 * this.fontScale).fontSize(10 * this.fontScale)
      .backgroundColor(this.filter === value ? UiTheme.primary : UiTheme.raised)
      .fontColor(this.filter === value ? UiTheme.onPrimary : UiTheme.text).borderRadius(7)
      .onClick(() => { this.filter = value; this.refresh() })
  }
  @Builder
  ProfileList() {
    Column({ space: 9 * this.fontScale }) {
      Row({ space: 6 * this.fontScale }) {
        this.FilterButton('全部', 'all'); this.FilterButton('Embedding', 'embedding'); this.FilterButton('Rerank', 'rerank')
      }.width('100%')
      Row({ space: 6 * this.fontScale }) {
        Button('＋ Embedding').height(30 * this.fontScale).fontSize(9 * this.fontScale).layoutWeight(1)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).onClick(() => this.add('embedding'))
        Button('＋ Rerank').height(30 * this.fontScale).fontSize(9 * this.fontScale).layoutWeight(1)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).onClick(() => this.add('rerank'))
      }.width('100%')
      Scroll() {
        Column({ space: 6 * this.fontScale }) {
          ForEach(this.visibleProfiles(), (profile: RagApiProfile) => {
            Column({ space: 3 * this.fontScale }) {
              Row() {
                Text(profile.name || profile.model).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
                  .fontColor(UiTheme.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                Text(profile.kind === 'embedding' ? 'Embedding' : 'Rerank').fontSize(8 * this.fontScale).fontColor(UiTheme.muted)
              }.width('100%')
              Text(`${profile.model}${profile.dimensions > 0 ? ` · ${profile.dimensions}维` : ''}`)
                .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').padding(9 * this.fontScale).alignItems(HorizontalAlign.Start)
              .backgroundColor(this.selectedId === profile.id ? UiTheme.surface : Color.Transparent)
              .border({ width: 1, color: this.selectedId === profile.id ? '#BDBDBD' : UiTheme.border }).borderRadius(7)
              .interactive().onClick(() => this.edit(profile))
          }, (profile: RagApiProfile) => profile.id)
          if (this.visibleProfiles().length === 0) {
            Text('暂无此类API，使用上方按钮添加。').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
              .width('100%').padding(15 * this.fontScale)
          }
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width(this.wide() ? 270 : '100%').height(this.wide() ? '100%' : 210).padding(12 * this.fontScale).backgroundColor('#F7F7F7')
      .border({ width: { right: 1 }, color: UiTheme.border })
  }
  @Builder
  ProfileForm() {
    Scroll() {
      Column({ space: 9 * this.fontScale }) {
        Text(this.selectedId ? '编辑RAG API' : '新建RAG API').fontSize(17 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text(this.kind === 'embedding' ? '兼容 OpenAI /embeddings，支持自定义维度。' : '兼容 /rerank，接收 query、documents 和 top_n。')
          .fontSize(10 * this.fontScale).fontColor(UiTheme.muted).width('100%')
        TextInput({ text: this.name, placeholder: '配置名称（可选）' }).height(37 * this.fontScale).fontSize(11 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(8).onChange((value: string) => this.name = value)
        TextInput({ text: this.baseUrl, placeholder: '服务根地址，例如 https://api.example.com/v1' }).height(37 * this.fontScale)
          .fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8).onChange((value: string) => this.baseUrl = value)
        TextInput({ text: this.model, placeholder: '模型名称' }).height(37 * this.fontScale).fontSize(11 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(8).onChange((value: string) => this.model = value)
        TextInput({ text: this.apiKey, placeholder: 'API Key，仅保存在本机' }).type(InputType.Password)
          .height(37 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
          .onChange((value: string) => this.apiKey = value)
        if (this.kind === 'embedding') {
          TextInput({ text: this.dimensions, placeholder: '向量维度，例如 512' }).type(InputType.Number)
            .height(37 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
            .onChange((value: string) => this.dimensions = value)
        }
        Text('密钥不会显示在日志中。公开部署建议通过自有后端代理，不把长期密钥写入HAP。')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).lineHeight(15 * this.fontScale).width('100%')
          .padding(9 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(7)
        if (this.notice) Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          .width('100%').padding(9 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(7)
        Row({ space: 8 * this.fontScale }) {
          Button('保存API').layoutWeight(1).height(38 * this.fontScale).fontSize(11 * this.fontScale)
            .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).onClick(() => this.save())
          if (this.selectedId) {
            Button('删除').height(38 * this.fontScale).fontSize(11 * this.fontScale)
              .backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary).onClick(() => this.remove())
          }
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start).padding(16 * this.fontScale)
    }.height('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
  }
  build() {
    if (this.wide()) {
      Row() { this.ProfileList(); this.ProfileForm() }
        .width('100%').height('100%').alignItems(VerticalAlign.Top).backgroundColor(UiTheme.surface)
        .border({ width: 1, color: UiTheme.border }).borderRadius(10).clip(true)
        .onAreaChange((_oldValue: Area, newValue: Area) => this.panelWidth = parseFloat(String(newValue.width)))
    } else {
      Column() { this.ProfileList(); this.ProfileForm() }
        .width('100%').height('100%').backgroundColor(UiTheme.surface)
        .border({ width: 1, color: UiTheme.border }).borderRadius(10).clip(true)
        .onAreaChange((_oldValue: Area, newValue: Area) => this.panelWidth = parseFloat(String(newValue.width)))
    }
  }
}

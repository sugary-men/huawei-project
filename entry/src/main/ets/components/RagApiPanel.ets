import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { KnowledgeChunk, RankedChunk } from '../models/RagModels'
import { RagApiProfile, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { OpenAiCompatibleEmbeddingService } from '../services/OpenAiCompatibleEmbeddingService'
import { OpenAiCompatibleRerankService } from '../services/OpenAiCompatibleRerankService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'
import { SelectionTab } from './SelectionTab'

@Component
export struct RagApiPanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 900
  @Prop embedded: boolean = false
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
  @State profileEnabled: boolean = true
  @State testing: boolean = false

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
    this.profileEnabled = profile.enabled !== false
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
    this.profileEnabled = true
    this.notice = ''
  }
  private save(): void {
    const workspace = this.workspace()
    if (workspace === undefined) return
    try {
      const profile = workspace.saveProfile(this.selectedId, this.kind, this.name, this.baseUrl,
        this.model, this.apiKey, Number(this.dimensions))
      workspace.setProfileEnabled(profile.id, this.profileEnabled)
      this.archive = workspace.read()
      this.selectedId = profile.id
      this.refresh(profile.id)
      this.notice = 'API配置已保存到本机。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '保存失败。' }
  }
  private async testConnection(): Promise<void> {
    if (this.testing) return
    this.testing = true
    this.notice = '正在测试连接…'
    try {
      if (this.kind === 'embedding') {
        const service = new OpenAiCompatibleEmbeddingService({ baseUrl: this.baseUrl, model: this.model,
          apiKey: this.apiKey, dimensions: Number(this.dimensions) })
        const vectors = await service.embedBatch(['RAG connectivity test'])
        if (vectors.length !== 1 || vectors[0].length === 0) throw new Error('服务没有返回有效向量。')
        this.notice = `连接正常，返回 ${vectors[0].length} 维向量。`
      } else {
        const service = new OpenAiCompatibleRerankService({ baseUrl: this.baseUrl, model: this.model,
          apiKey: this.apiKey })
        const chunk: KnowledgeChunk = { id: 'connectivity', sourceId: 'connectivity', title: '连通性测试',
          location: '本地测试', course: '系统', content: '用于验证重排序 API 是否可用。',
          vector: [], vectorModel: 'none' }
        const ranked: RankedChunk[] = await service.rerank('连通性测试', [{ chunk: chunk, score: 1 }])
        if (ranked.length === 0) throw new Error('服务没有返回有效排序结果。')
        this.notice = '连接正常，重排序响应格式有效。'
      }
      const workspace = this.workspace()
      if (workspace !== undefined && this.selectedId) {
        workspace.updateProfileTest(this.selectedId, true, this.notice)
        this.archive = workspace.read()
        this.onChanged()
      }
    } catch (error) {
      this.notice = (error as Error).message || '连接测试失败，请检查地址、模型和密钥。'
      const workspace = this.workspace()
      if (workspace !== undefined && this.selectedId) {
        workspace.updateProfileTest(this.selectedId, false, this.notice)
        this.archive = workspace.read()
      }
    } finally {
      this.testing = false
    }
  }
  private toggleEnabled(): void {
    const workspace = this.workspace()
    if (workspace === undefined || !this.selectedId) return
    try {
      workspace.setProfileEnabled(this.selectedId, !this.profileEnabled)
      this.profileEnabled = !this.profileEnabled
      this.archive = workspace.read()
      this.notice = this.profileEnabled ? 'API 配置已启用。' : 'API 配置已停用。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '状态切换失败。' }
  }
  private async remove(): Promise<void> {
    const workspace = this.workspace()
    if (workspace === undefined || !this.selectedId) return
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除RAG API',
        message: `删除“${this.name || this.model}”？引用该配置的知识库会切换为本地方法。`,
        buttons: [{ text: '取消', color: UiTheme.secondary }, { text: '删除', color: UiTheme.secondary }] })
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
    SelectionTab({ label: label, selected: this.filter === value, showIndicator: false,
      onSelect: () => { this.filter = value; this.refresh() } })
  }
  @Builder
  ProfileList() {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 6 * this.fontScale }) {
        this.FilterButton('全部', 'all'); this.FilterButton('Embedding', 'embedding'); this.FilterButton('Rerank', 'rerank')
      }.width('100%')
      Row({ space: 6 * this.fontScale }) {
        Button('＋ Embedding').height(30 * this.fontScale).fontSize(10 * this.fontScale).layoutWeight(1)
          .backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8).onClick(() => this.add('embedding'))
        Button('＋ Rerank').height(30 * this.fontScale).fontSize(10 * this.fontScale).layoutWeight(1)
          .backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8).onClick(() => this.add('rerank'))
      }.width('100%')
      ForEach(this.visibleProfiles(), (profile: RagApiProfile) => {
        Column({ space: 3 * this.fontScale }) {
          Row({ space: 6 * this.fontScale }) {
            Text(profile.name || profile.model).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(this.selectedId === profile.id ?
                UiTheme.choiceSelectedText : UiTheme.text)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text(profile.kind === 'embedding' ? 'Embedding' : 'Rerank')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          }.width('100%')
          Text(`${profile.model}${profile.dimensions > 0 ? ` · ${profile.dimensions}维` : ''}`)
            .fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(profile.enabled === false ? '已停用' : profile.lastTestStatus || '未测试')
            .fontSize(9 * this.fontScale).fontColor(profile.enabled === false ? UiTheme.muted : UiTheme.secondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').padding(10 * this.fontScale).alignItems(HorizontalAlign.Start)
          .backgroundColor(this.selectedId === profile.id ?
            UiTheme.choiceSelectedBackground : UiTheme.surface)
          .border({ width: 1, color: this.selectedId === profile.id ?
            UiTheme.choiceSelectedBorder : UiTheme.softBorder }).borderRadius(8)
          .interactive().onClick(() => this.edit(profile))
      }, (profile: RagApiProfile) => profile.id)
      if (this.visibleProfiles().length === 0) {
        Text('暂无此类API，使用上方按钮添加。').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          .width('100%').padding(10 * this.fontScale)
      }
    }.width(this.wide() ? 270 * this.fontScale : '100%').padding(12 * this.fontScale)
      .backgroundColor(UiTheme.softSurface).borderRadius(12).alignItems(HorizontalAlign.Start)
  }
  @Builder
  ProfileForm() {
    Column({ space: 12 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        Text(this.selectedId ? '编辑配置' : '新建配置').fontSize(11 * this.fontScale)
          .fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text(this.kind === 'embedding' ? 'Embedding' : 'Rerank').fontSize(9 * this.fontScale)
          .fontColor(UiTheme.secondary).padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(UiTheme.raised).borderRadius(4)
      }.width('100%')
      Text(this.kind === 'embedding' ? '兼容 OpenAI /embeddings 接口，支持自定义向量维度。' :
        '兼容 /rerank 接口，接收 query、documents 与 top_n。')
        .fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
      GridRow({ columns: 12, gutter: 10 * this.fontScale }) {
        GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
          Column({ space: 5 * this.fontScale }) {
            Text('配置名称').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.name, placeholder: '例如 智谱 Embedding' }).height(36 * this.fontScale)
              .fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface)
              .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8)
              .onChange((value: string) => this.name = value)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
          Column({ space: 5 * this.fontScale }) {
            Text('模型名称').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.model, placeholder: '例如 embedding-3' }).height(36 * this.fontScale)
              .fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface)
              .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8)
              .onChange((value: string) => this.model = value)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
          Column({ space: 5 * this.fontScale }) {
            Text('服务根地址').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.baseUrl, placeholder: 'https://api.example.com/v1' }).height(36 * this.fontScale)
              .fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface)
              .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8)
              .onChange((value: string) => this.baseUrl = value)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
          Column({ space: 5 * this.fontScale }) {
            Text('API Key（仅保存在本机）').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
            TextInput({ text: this.apiKey, placeholder: 'sk-…' }).type(InputType.Password)
              .height(36 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface)
              .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8)
              .onChange((value: string) => this.apiKey = value)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        if (this.kind === 'embedding') {
          GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
            Column({ space: 5 * this.fontScale }) {
              Text('向量维度').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
              TextInput({ text: this.dimensions, placeholder: '例如 512' }).type(InputType.Number)
                .height(36 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface)
                .border({ width: 1, color: UiTheme.softBorder }).borderRadius(8)
                .onChange((value: string) => this.dimensions = value)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
        }
      }.width('100%')
      Row({ space: 9 * this.fontScale }) {
        Column({ space: 2 * this.fontScale }) {
          Text('启用此配置').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('停用后引用该配置的知识库会回退本地方法。').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.profileEnabled })
          .enabled(!this.selectedId).onChange((value: boolean) => this.profileEnabled = value)
        if (this.selectedId) {
          Button('切换状态').height(30 * this.fontScale).fontSize(10 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).onClick(() => this.toggleEnabled())
        }
      }.width('100%')
      Text('密钥不会显示在日志中。公开部署建议通过自有后端代理，不把长期密钥写入HAP。')
        .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted).lineHeight(15 * this.fontScale).width('100%')
        .padding(10 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(8)
      if (this.notice) Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
        .width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
      Row({ space: 8 * this.fontScale }) {
        Button('保存API').layoutWeight(1).height(38 * this.fontScale).fontSize(11 * this.fontScale)
          .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).onClick(() => this.save())
        Button(this.testing ? '测试中' : '测试连接').height(38 * this.fontScale).fontSize(11 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).enabled(!this.testing)
          .onClick(() => this.testConnection())
        if (this.selectedId) {
          Button('删除').height(38 * this.fontScale).fontSize(11 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary).onClick(() => this.remove())
        }
      }.width('100%')
    }.width('100%').layoutWeight(this.wide() ? 1 : 0).alignItems(HorizontalAlign.Start)
  }
  @Builder
  Content() {
    Column({ space: 12 * this.fontScale }) {
      Row() {
        Column({ space: 3 * this.fontScale }) {
          Text('RAG API 管理').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
          Text('管理 Embedding 与 Rerank 服务地址、模型与密钥，配置仅保存在本机。')
            .fontSize(10 * this.fontScale).fontColor(UiTheme.softMuted).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      if (this.wide()) {
        Row({ space: 12 * this.fontScale }) { this.ProfileList(); this.ProfileForm() }
          .width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 12 * this.fontScale }) { this.ProfileList(); this.ProfileForm() }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    if (this.embedded) {
      Column() { this.Content() }.width('100%').padding(16 * this.fontScale)
        .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
        .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
        .onAreaChange((_oldValue: Area, newValue: Area) => this.panelWidth = parseFloat(String(newValue.width)))
    } else {
      Scroll() {
        Column() { this.Content() }.width('100%').padding(16 * this.fontScale)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
          .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
      }.width('100%').height('100%').scrollBar(BarState.On).scrollBarWidth(6)
        .scrollBarColor(UiTheme.secondary).align(Alignment.TopStart)
        .onAreaChange((_oldValue: Area, newValue: Area) => this.panelWidth = parseFloat(String(newValue.width)))
    }
  }
}

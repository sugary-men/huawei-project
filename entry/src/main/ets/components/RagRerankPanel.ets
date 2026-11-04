import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { RagApiProfile, RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'

interface RerankMenuOption {
  value: string
  action: () => void
}

@Component
export struct RagRerankPanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop baseId: string = ''
  @Prop viewportWidth: number = 900
  @Prop embedded: boolean = false
  onChanged: () => void = () => {}
  @State archive: RagWorkspaceArchive = RagWorkspaceService.empty()
  @State notice: string = ''

  aboutToAppear(): void { this.reload() }

  private reload(): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace !== undefined) this.archive = workspace.read()
  }
  private workspace(): RagWorkspaceService | undefined { return IntegrationService.ragWorkspace }
  private base(): RagKnowledgeBase | undefined {
    return this.archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === this.baseId) ||
      this.archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === this.archive.activeBaseId)
  }
  private profiles(): RagApiProfile[] {
    return this.archive.apiProfiles.filter((profile: RagApiProfile) =>
      profile.kind === 'rerank' && profile.enabled !== false)
  }
  private onlineMenu(): RerankMenuOption[] {
    return this.profiles().map((profile: RagApiProfile): RerankMenuOption => ({
      value: `${profile.name || profile.model}${profile.lastTestStatus ? ` · ${profile.lastTestStatus}` : ''}`,
      action: () => this.select('online', profile.id)
    }))
  }
  private profileName(id: string): string {
    const profile = this.archive.apiProfiles.find((item: RagApiProfile) => item.id === id)
    return profile === undefined ? '选择在线模型' : `${profile.name || profile.model}`
  }
  private currentLabel(): string {
    const base = this.base()
    if (base === undefined) return '未选择知识库'
    if (base.rerankMode === 'none') return '关闭重排序'
    if (base.rerankMode === 'local') return '本地重排序 · 已启用'
    return this.profileName(base.rerankProfileId)
  }
  private select(mode: string, profileId: string = ''): void {
    const workspace = this.workspace()
    const base = this.base()
    if (workspace === undefined || base === undefined) return
    try {
      if (mode === 'online' && !this.profiles().some((profile: RagApiProfile) => profile.id === profileId)) {
        throw new Error('请选择已启用的在线重排序模型。')
      }
      workspace.saveBase(base.id, base.name, base.description, base.embeddingMode,
        base.embeddingProfileId, mode, profileId, base.includeBuiltIn, base.includeAllLocal, base.documentIds)
      this.reload()
      this.notice = mode === 'none' ? '重排序已停用，将直接使用混合检索排序。' :
        mode === 'local' ? '已切换为本地重排序。' : `已启用在线重排序：${this.profileName(profileId)}。`
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '切换失败。' }
  }

  @Builder
  MethodCard(title: string, detail: string, selected: boolean, action: () => void) {
    Row({ space: 11 * this.fontScale }) {
      Column({ space: 4 * this.fontScale }) {
        Row({ space: 7 * this.fontScale }) {
          Text(title).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          if (selected) {
            Text('当前生效').fontSize(9 * this.fontScale).fontColor(UiTheme.accentStrong)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(UiTheme.accentPale)
              .border({ width: 1, color: UiTheme.accentBorder }).borderRadius(4)
          }
        }
        Text(detail).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          .lineHeight(16 * this.fontScale).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button(selected ? '已选择' : '启用').height(30 * this.fontScale).fontSize(10 * this.fontScale)
        .backgroundColor(selected ? UiTheme.raised : UiTheme.primary)
        .fontColor(selected ? UiTheme.secondary : UiTheme.onPrimary)
        .enabled(!selected).onClick(action)
    }.width('100%')
      .padding({ left: 14 * this.fontScale, right: 14 * this.fontScale, top: 13 * this.fontScale, bottom: 13 * this.fontScale })
      .backgroundColor(selected ? UiTheme.accentPale : UiTheme.softSurface)
      .border({ width: 1, color: selected ? UiTheme.accentBorder : UiTheme.softBorder }).borderRadius(12)
      .hoverEffect(HoverEffect.Highlight)
      .animation({ duration: UiMotion.section, curve: UiMotion.enterCurve })
  }

  @Builder
  Content() {
    Column({ space: 12 * this.fontScale }) {
      Row() {
        Column({ space: 3 * this.fontScale }) {
          Text('重排序模型管理').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
          Text('统一管理在线与本地重排序方法，切换后立即参与当前知识库检索。')
            .fontSize(10 * this.fontScale).fontColor(UiTheme.softMuted).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 2 * this.fontScale }) {
          Text('当前生效').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
          Text(this.currentLabel()).fontSize(10 * this.fontScale).fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.softText).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: 200 * this.fontScale })
      }.width('100%')
      if (this.notice) {
        Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
          .padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
      }
      this.MethodCard('不重排序', '保留关键词、向量与 BM25 的混合检索结果，响应最快。',
        this.base()?.rerankMode === 'none', () => this.select('none'))
      this.MethodCard('本地重排序', '基于查询词覆盖与短语精确度在本机重排，不发送资料内容。',
        this.base()?.rerankMode === 'local', () => this.select('local'))
      this.MethodCard('在线重排序', this.profiles().length === 0 ? '暂无已启用的 Rerank API，可在下方 API 管理中添加。' :
        `可用模型 ${this.profiles().length} 个，按需发送候选片段完成服务端重排。`,
        this.base()?.rerankMode === 'online', () => {
          if (this.profiles().length > 0) this.select('online', this.profiles()[0].id)
        })
      if (this.profiles().length > 0) {
        Button(`${this.profileName(this.base()?.rerankProfileId || '')} ▾`).height(34 * this.fontScale)
          .fontSize(10 * this.fontScale).width('100%').backgroundColor(UiTheme.softSurface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.softBorder })
          .bindMenu(this.onlineMenu())
      }
      Column({ space: 5 * this.fontScale }) {
        Text('模型切换会影响检索排序，不会删除已有索引或资料。').fontSize(9 * this.fontScale)
          .fontColor(UiTheme.softMuted)
        Text('在线模型密钥由 API 管理统一保存，本面板只展示配置名称与状态。')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
      }.width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.softSurface)
        .border({ width: 1, color: UiTheme.softBorder }).borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    if (this.embedded) {
      Column() { this.Content() }.width('100%').padding(16 * this.fontScale)
        .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
        .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
    } else {
      Scroll() {
        Column() { this.Content() }.width('100%').padding(16 * this.fontScale)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
          .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
      }.width('100%').height('100%').scrollBar(BarState.On).scrollBarWidth(6)
        .scrollBarColor(UiTheme.secondary).align(Alignment.TopStart)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.PARENT_FIRST
        })
    }
  }
}

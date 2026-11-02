import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { LibraryDocument } from '../models/LibraryModels'
import { RagApiProfile, RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagMaintenanceService } from '../services/RagMaintenanceService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'

interface RagMenuItem {
  value: string
  action: () => void
}

@Component
export struct RagKnowledgeBasePanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 900
  onChanged: () => void = () => {}
  @State archive: RagWorkspaceArchive = RagWorkspaceService.empty()
  @State documents: LibraryDocument[] = []
  @State selectedId: string = ''
  @State name: string = ''
  @State description: string = ''
  @State embeddingMode: string = 'local'
  @State embeddingProfileId: string = ''
  @State rerankMode: string = 'local'
  @State rerankProfileId: string = ''
  @State includeBuiltIn: boolean = true
  @State includeAllLocal: boolean = true
  @State documentIds: string[] = []
  @State busy: boolean = false
  @State notice: string = ''
  @State panelWidth: number = 900

  aboutToAppear(): void { this.refresh() }

  private workspace(): RagWorkspaceService | undefined { return IntegrationService.ragWorkspace }
  private wide(): boolean { return (this.viewportWidth || this.panelWidth) >= 700 }

  private refresh(preferred: string = ''): void {
    const workspace = this.workspace()
    if (workspace === undefined) return
    this.archive = workspace.read()
    this.documents = IntegrationService.library?.documents() || []
    const id = preferred || this.selectedId || this.archive.activeBaseId
    const base = this.archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === id)
    if (base !== undefined) this.editBase(base)
    else if (this.archive.knowledgeBases.length > 0) this.editBase(this.archive.knowledgeBases[0])
  }

  private editBase(base: RagKnowledgeBase): void {
    this.selectedId = base.id
    this.name = base.name
    this.description = base.description
    this.embeddingMode = base.embeddingMode
    this.embeddingProfileId = base.embeddingProfileId
    this.rerankMode = base.rerankMode
    this.rerankProfileId = base.rerankProfileId
    this.includeBuiltIn = base.includeBuiltIn
    this.includeAllLocal = base.includeAllLocal
    this.documentIds = base.documentIds.slice()
    this.notice = ''
  }

  private profiles(kind: string): RagApiProfile[] {
    return this.archive.apiProfiles.filter((profile: RagApiProfile) => profile.kind === kind)
  }

  private profileName(id: string): string {
    return this.archive.apiProfiles.find((profile: RagApiProfile) => profile.id === id)?.name || '未选择'
  }
  private embeddingMenu(): RagMenuItem[] {
    return this.profiles('embedding').map((profile: RagApiProfile): RagMenuItem => {
      return { value: `${profile.name} · ${profile.model}`, action: () => this.embeddingProfileId = profile.id }
    })
  }
  private rerankMenu(): RagMenuItem[] {
    return this.profiles('rerank').map((profile: RagApiProfile): RagMenuItem => {
      return { value: `${profile.name} · ${profile.model}`, action: () => this.rerankProfileId = profile.id }
    })
  }

  private toggleDocument(id: string): void {
    if (id.startsWith('rag:') && this.includeBuiltIn) return
    this.documentIds = this.documentIds.includes(id)
      ? this.documentIds.filter((value: string) => value !== id)
      : this.documentIds.concat(id)
  }

  private save(): void {
    const workspace = this.workspace()
    if (workspace === undefined) return
    try {
      const base = workspace.saveBase(this.selectedId, this.name, this.description, this.embeddingMode,
        this.embeddingProfileId, this.rerankMode, this.rerankProfileId, this.includeBuiltIn,
        this.includeAllLocal, this.documentIds)
      this.archive = workspace.read()
      this.selectedId = base.id
      this.notice = '知识库设置已保存。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '保存失败。' }
  }

  private async remove(): Promise<void> {
    const workspace = this.workspace()
    if (workspace === undefined || !this.selectedId || this.selectedId === 'kb-local') return
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除知识库',
        message: `删除“${this.name}”？资料文件不会删除，只移除知识库配置和索引。`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除', color: '#666666' }] })
      if (result.index !== 1) return
      workspace.removeBase(this.selectedId)
      this.selectedId = ''
      this.refresh('kb-local')
      this.notice = '知识库已删除。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '删除失败。' }
  }

  private async buildIndex(): Promise<void> {
    if (this.busy) return
    const workspace = this.workspace()
    const library = IntegrationService.library
    if (workspace === undefined || library === undefined || !this.selectedId) return
    const profile = this.archive.apiProfiles.find((item: RagApiProfile) =>
      item.id === this.embeddingProfileId && item.kind === 'embedding' && item.enabled !== false)
    if (this.embeddingMode !== 'online' || profile === undefined) {
      this.notice = '请先选择在线 Embedding API 配置。'
      return
    }
    this.busy = true
    try {
      const base = workspace.saveBase(this.selectedId, this.name, this.description, this.embeddingMode,
        this.embeddingProfileId, this.rerankMode, this.rerankProfileId, this.includeBuiltIn,
        this.includeAllLocal, this.documentIds)
      this.selectedId = base.id
      const result = await RagMaintenanceService.rebuild(workspace, library, base.id)
      this.refresh(base.id)
      this.notice = `索引构建完成：${result.chunkCount} 个片段，模型 ${result.modelId}。`
      this.onChanged()
    } catch (error) {
      this.notice = (error as Error).message || '在线索引构建失败。'
    } finally {
      this.busy = false
    }
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.7) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }

  @Builder
  ModeButton(label: string, current: string, value: string, apply: (value: string) => void) {
    Button(label).height(30 * this.fontScale).fontSize(10 * this.fontScale)
      .backgroundColor(current === value ? UiTheme.primary : UiTheme.raised)
      .fontColor(current === value ? UiTheme.onPrimary : UiTheme.text).borderRadius(7)
      .interactive().onClick(() => apply(value))
  }

  @Builder
  CurrentBaseSummary() {
    Column({ space: 8 * this.fontScale }) {
      Text('当前知识库').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium)
        .fontColor(UiTheme.muted).width('100%')
      if (this.archive.knowledgeBases.find((base: RagKnowledgeBase) =>
        base.id === this.archive.activeBaseId) !== undefined) {
        Column({ space: 7 * this.fontScale }) {
          Text(this.archive.knowledgeBases.find((base: RagKnowledgeBase) =>
            base.id === this.archive.activeBaseId)?.name || '').fontSize(15 * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.archive.knowledgeBases.find((base: RagKnowledgeBase) =>
            base.id === this.archive.activeBaseId)?.embeddingMode === 'online'
            ? '在线 Embedding' : '未启用语义检索 · 本地检索可用')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
          Text(`${this.archive.knowledgeBases.find((base: RagKnowledgeBase) =>
            base.id === this.archive.activeBaseId)?.chunkCount || '待索引'} 个知识片段`)
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).width('100%')
        }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(8)
      } else {
        Text('暂无知识库').fontSize(11 * this.fontScale).fontColor(UiTheme.muted).width('100%')
      }
      Text('如需切换或新建知识库，请使用页面顶部的知识库入口。')
        .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).lineHeight(15 * this.fontScale)
        .width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
    }.width(this.wide() ? 270 : '100%').height(this.wide() ? '100%' : 205).padding(12 * this.fontScale).backgroundColor('#F7F7F7')
      .border({ width: { right: 1 }, color: UiTheme.border })
  }

  @Builder
  BaseForm() {
    Scroll() {
      Column({ space: 10 * this.fontScale }) {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text('知识库设置').fontSize(17 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text(this.selectedId ? `ID ${this.selectedId}` : '使用顶部入口选择或新建知识库')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
        TextInput({ text: this.name, placeholder: '知识库名称' }).height(38 * this.fontScale).fontSize(12 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(8).onChange((value: string) => this.name = value)
        TextArea({ text: this.description, placeholder: '用途、范围或数据说明' }).height(72 * this.fontScale).fontSize(12 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(8).onChange((value: string) => this.description = value)
        Column({ space: 7 * this.fontScale }) {
          Text('向量化方式').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
          Row({ space: 7 * this.fontScale }) {
            this.ModeButton('本地算法', this.embeddingMode, 'local', (value: string) => this.embeddingMode = value)
            this.ModeButton('在线 Embedding', this.embeddingMode, 'online', (value: string) => this.embeddingMode = value)
            Button(this.profileName(this.embeddingProfileId)).height(30 * this.fontScale).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).layoutWeight(1)
              .bindMenu(this.embeddingMenu())
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 7 * this.fontScale }) {
          Text('重排序方式').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
          Row({ space: 7 * this.fontScale }) {
            this.ModeButton('不重排', this.rerankMode, 'none', (value: string) => this.rerankMode = value)
            this.ModeButton('本地', this.rerankMode, 'local', (value: string) => this.rerankMode = value)
            this.ModeButton('在线', this.rerankMode, 'online', (value: string) => this.rerankMode = value)
            if (this.rerankMode === 'online') {
              Button(this.profileName(this.rerankProfileId)).height(30 * this.fontScale).fontSize(10 * this.fontScale)
                .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).layoutWeight(1)
                .bindMenu(this.rerankMenu())
            }
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 12 * this.fontScale }) {
          Row({ space: 6 * this.fontScale }) {
            Toggle({ type: ToggleType.Switch, isOn: this.includeBuiltIn })
              .onChange((value: boolean) => this.includeBuiltIn = value)
            Text('包含内置资料').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          }
          Row({ space: 6 * this.fontScale }) {
            Toggle({ type: ToggleType.Switch, isOn: this.includeAllLocal })
              .onChange((value: boolean) => this.includeAllLocal = value)
            Text('包含全部本地资料').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          }
        }.width('100%')
        Text('资料范围').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
        Column({ space: 4 * this.fontScale }) {
          ForEach(this.documents, (document: LibraryDocument) => {
            Row({ space: 8 * this.fontScale }) {
              Text(document.id.startsWith('rag:') ? '内置' : '本地').fontSize(8 * this.fontScale)
                .fontColor(UiTheme.muted).width(28)
              Text(document.title).fontSize(10 * this.fontScale).fontColor(UiTheme.text).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.documentIds.includes(document.id) || (document.id.startsWith('rag:') && this.includeBuiltIn) ||
                (!document.id.startsWith('rag:') && this.includeAllLocal) ? '已纳入' : '未纳入')
                .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
            }.width('100%').height(30 * this.fontScale).padding({ left: 7, right: 7 })
              .backgroundColor(this.documentIds.includes(document.id) ? '#EEEEEE' : Color.Transparent)
              .borderRadius(6).interactive().onClick(() => this.toggleDocument(document.id))
          }, (document: LibraryDocument) => document.id)
        }.width('100%').padding(5 * this.fontScale).backgroundColor('#F8F8F8').border({ width: 1, color: UiTheme.border }).borderRadius(8)
        if (this.notice) {
          Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
            .padding(9 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
        }
        Row({ space: 8 * this.fontScale }) {
          Button(this.busy ? '正在构建' : '构建在线索引').layoutWeight(1).height(38 * this.fontScale)
            .fontSize(11 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary)
            .enabled(!this.busy && this.selectedId.length > 0 && this.embeddingMode === 'online')
            .onClick(() => this.buildIndex())
          Button('保存知识库').height(38 * this.fontScale).fontSize(11 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).onClick(() => this.save())
          if (this.selectedId && this.selectedId !== 'kb-local') {
            Button('删除').height(38 * this.fontScale).fontSize(11 * this.fontScale)
              .backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary).onClick(() => this.remove())
          }
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start).padding(16 * this.fontScale)
    }.height('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
  }

  build() {
    if (this.wide()) {
      Row() {
        this.CurrentBaseSummary()
        this.BaseForm()
      }.width('100%').height('100%').alignItems(VerticalAlign.Top).backgroundColor(UiTheme.surface)
        .border({ width: 1, color: UiTheme.border }).borderRadius(10).clip(true)
        .onAreaChange((_oldValue: Area, newValue: Area) => this.panelWidth = parseFloat(String(newValue.width)))
    } else {
      Column() {
        this.CurrentBaseSummary()
        this.BaseForm()
      }.width('100%').height('100%').backgroundColor(UiTheme.surface)
        .border({ width: 1, color: UiTheme.border }).borderRadius(10).clip(true)
        .onAreaChange((_oldValue: Area, newValue: Area) => this.panelWidth = parseFloat(String(newValue.width)))
    }
  }
}

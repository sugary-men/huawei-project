import { common } from '@kit.AbilityKit'
import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { LibraryDocument } from '../models/LibraryModels'
import { SourceCitation } from '../models/RagModels'
import { RagApiProfile, RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { AttachmentService } from '../services/AttachmentService'
import { IntegrationService } from '../services/IntegrationService'
import { ScheduleService } from '../services/ScheduleService'
import { KnowledgeFeatureRail } from './KnowledgeFeatureRail'
import { MarkdownContent } from './MarkdownContent'
import { RagAlgorithmPanel } from './RagAlgorithmPanel'
import { RagApiPanel } from './RagApiPanel'
import { RagDataVisualization } from './RagDataVisualization'
import { RagKnowledgeBasePanel } from './RagKnowledgeBasePanel'
import { RagOperationsPanel } from './RagOperationsPanel'
import { RagRerankPanel } from './RagRerankPanel'
import { SelectionTab } from './SelectionTab'

interface LibraryMenuOption {
  value: string
  action: () => void
}

@Component
export struct LibraryPage {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 1280
  @State section: string = 'visualization'
  @State pageWidth: number = 1000
  @State query: string = ''
  @State filter: string = 'all'
  @State modelApiTab: string = 'rerank'
  @State settingsTab: string = 'knowledge'
  @State documents: LibraryDocument[] = []
  @State selected: string = ''
  @State busy: boolean = false
  @State notice: string = ''
  @State editing: boolean = false
  @State editingImage: boolean = false
  @State editId: string = ''
  @State draftTitle: string = ''
  @State draftText: string = ''
  @State activeBaseId: string = 'kb-local'
  @State ragRevision: number = 0
  @State archive: RagWorkspaceArchive | undefined = undefined
  @State railCollapsed: boolean = false
  @State createVisible: boolean = false
  @State createName: string = ''
  @State createDescription: string = ''
  @State createEmbeddingId: string = ''
  @State createNotice: string = ''
  @State creating: boolean = false
  private alive: boolean = true
  onUse: (id: string, attachment: boolean) => void = () => {}
  onUseSource: (source: SourceCitation) => void = () => {}
  onChanged: () => void = () => {}

  aboutToAppear(): void {
    UiMotion.initialize()
    this.alive = true
    if (this.viewportWidth < 760) this.railCollapsed = true
    this.syncWorkspace()
    this.refresh()
  }
  aboutToDisappear(): void { this.alive = false }

  private refresh(): void {
    try {
      this.documents = IntegrationService.library?.documents(this.query) || []
      if (!this.documents.some((document: LibraryDocument) => document.id === this.selected)) {
        this.selected = this.visible().length > 0 ? this.visible()[0].id : ''
      }
      this.syncWorkspace()
    } catch (error) { this.notice = (error as Error).message }
  }
  private visible(): LibraryDocument[] {
    return this.documents.filter((document: LibraryDocument) =>
      this.filter === 'all' || (this.filter === 'indexed' ? document.indexed : document.kind === 'image'))
  }
  private selectedDocument(): LibraryDocument | undefined {
    return this.documents.find((document: LibraryDocument) => document.id === this.selected)
  }
  private railWidth(): number { return this.railCollapsed ? 46 : (this.viewportWidth >= 900 ? 92 : 58) }
  private contentWidth(): number { return Math.max(220, (this.viewportWidth || this.pageWidth) - this.railWidth() - 48) }
  private wide(): boolean { return this.contentWidth() >= 760 }
  private contextWidth(): number { return Math.max(210, Math.min(320, this.contentWidth() * 0.28)) }
  private syncWorkspace(): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace === undefined) return
    this.archive = workspace.read()
    this.activeBaseId = workspace.activeBase().id
  }
  private currentBase(): RagKnowledgeBase | undefined {
    return this.archive?.knowledgeBases.find((base: RagKnowledgeBase) => base.id === this.activeBaseId)
  }
  private embeddingProfiles(): RagApiProfile[] {
    return this.archive?.apiProfiles.filter((profile: RagApiProfile) =>
      profile.kind === 'embedding' && profile.enabled !== false) || []
  }
  private embeddingName(id: string): string {
    const profile = this.archive?.apiProfiles.find((item: RagApiProfile) => item.id === id)
    return profile === undefined ? '选择在线 Embedding' : `${profile.name || profile.model} · ${profile.model}`
  }
  private embeddingMenu(): LibraryMenuOption[] {
    return this.embeddingProfiles().map((profile: RagApiProfile): LibraryMenuOption => ({
      value: `${profile.name || profile.model} · ${profile.model}`,
      action: () => this.createEmbeddingId = profile.id
    }))
  }
  private knowledgeMenu(): LibraryMenuOption[] {
    return this.archive?.knowledgeBases.map((base: RagKnowledgeBase): LibraryMenuOption => ({
      value: `${base.id === this.activeBaseId ? '✓ ' : ''}${base.name}`,
      action: () => this.switchBase(base.id)
    })) || []
  }
  private databaseMenu(): LibraryMenuOption[] {
    return [
      { value: '导入文件到资料库', action: () => this.pick(false) },
      { value: '导入图片到资料库', action: () => this.pick(true) },
      { value: '资料管理', action: () => { this.setSection('settings'); this.settingsTab = 'documents' } },
      { value: '索引、导出与运行状态', action: () => this.setSection('operations') },
      { value: '本地存储：应用沙箱 JSON', action: () => {
        this.getUIContext().getPromptAction().showToast({ message: '知识库与资料索引保存在应用沙箱，本地 RAG 直接读取该存储。' })
      } }
    ]
  }
  private switchBase(id: string): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace === undefined || id === this.activeBaseId) return
    try {
      workspace.activateBase(id)
      this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve }, () => {
        this.syncWorkspace()
        this.selected = ''
        this.ragRevision++
      })
      this.refresh()
      this.onChanged()
      this.notice = `已切换到「${this.currentBase()?.name || '知识库'}」。`
    } catch (error) { this.notice = (error as Error).message || '切换知识库失败。' }
  }
  private openCreate(): void {
    this.syncWorkspace()
    this.createName = ''
    this.createDescription = ''
    this.createEmbeddingId = this.embeddingProfiles()[0]?.id || ''
    this.createNotice = ''
    this.creating = false
    this.createVisible = true
  }
  private createKnowledgeBase(): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace === undefined || this.creating) return
    this.creating = true
    this.createNotice = '正在创建知识库配置…'
    try {
      if (!this.createName.trim()) throw new Error('请填写知识库名称。')
      const embeddingMode = this.createEmbeddingId ? 'online' : 'local'
      const base = workspace.saveBase('', this.createName, this.createDescription, embeddingMode,
        this.createEmbeddingId, 'local', '', false, true, [])
      this.syncWorkspace()
      this.activeBaseId = base.id
      this.ragRevision++
      this.createNotice = embeddingMode === 'online'
        ? '知识库已创建，可继续构建在线索引。'
        : '知识库已以本地模式创建，可先导入资料并检索，稍后配置在线 Embedding。'
      this.notice = `已新建「${base.name}」，当前已自动切换。`
      this.createVisible = false
      this.section = 'settings'
      this.settingsTab = 'knowledge'
      this.refresh()
      this.onChanged()
    } catch (error) {
      this.createNotice = (error as Error).message || '创建知识库失败。'
    } finally {
      this.creating = false
    }
  }

  private async pick(photos: boolean): Promise<void> {
    if (this.busy) return
    this.busy = true
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const files = await AttachmentService.pick(context, photos, 4)
      try {
        IntegrationService.library?.register(files)
        if (this.alive) {
          this.notice = files.length ? `已导入 ${files.length} 份资料。` : ''
          this.refresh()
          this.onChanged()
        }
      } finally { files.forEach((file) => AttachmentService.removeDraft(file, context.filesDir)) }
    } catch (error) {
      if (this.alive) this.notice = (error as Error).message || '导入失败。'
    } finally {
      if (this.alive) this.busy = false
    }
  }
  private toggle(id: string): void {
    try {
      IntegrationService.library?.toggle(id)
      this.refresh()
      this.onChanged()
      this.notice = '检索范围已更新。'
    } catch (error) { this.notice = (error as Error).message }
  }
  private async remove(document: LibraryDocument): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除资料',
        message: `从资料库删除「${document.title}」？已加入对话的附件和引用副本会保留。`,
        buttons: [{ text: '取消', color: '#777777' }, { text: '删除', color: '#202020' }] })
      if (!this.alive || result.index !== 1) return
      IntegrationService.library?.remove(document.id)
      this.selected = ''
      this.refresh()
      this.onChanged()
      this.notice = '资料已删除。'
    } catch (error) {
      if (this.alive) this.notice = (error as Error).message === 'cancel' ? '' : (error as Error).message
    }
  }
  private edit(document?: LibraryDocument): void {
    this.editId = document?.id || ''
    this.editingImage = document?.kind === 'image'
    this.draftTitle = document?.title || ''
    this.draftText = document?.text || ''
    this.setEditing(true)
  }
  private setEditing(value: boolean): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.enterCurve },
      () => this.editing = value)
  }
  private saveText(): void {
    try {
      if (this.editingImage) {
        IntegrationService.library?.saveImageDescription(this.editId, this.draftText)
        this.notice = '图片描述已保存并用于检索。'
      } else {
        IntegrationService.library?.saveText(this.draftTitle, this.draftText, this.editId || undefined)
        this.notice = '文本资料已保存并加入检索。'
      }
      this.setEditing(false)
      this.refresh()
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message }
  }
  private documentStatus(document: LibraryDocument): string {
    if (document.kind === 'image') {
      return document.indexed ? '参与检索' : document.text ? '描述待启用' : '待添加描述'
    }
    return document.indexed ? '参与检索' : '已停用检索'
  }
  private documentIcon(document: LibraryDocument): string {
    if (document.kind === 'image') return '▧'
    if (document.kind === 'index') return '◇'
    return '▤'
  }
  private modalityLabel(document: LibraryDocument): string {
    if (document.kind === 'image') return '图片'
    if (document.kind === 'index') return '索引'
    return '文档'
  }
  private selectDocument(id: string): void {
    this.selected = id
    this.editing = false
  }
  private setSection(value: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve }, () => {
      this.section = value
      this.syncWorkspace()
    })
    if (value === 'documents') this.refresh()
    if (value === 'operations') this.syncWorkspace()
  }
  private ragChanged(): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve }, () => {
      this.syncWorkspace()
      this.ragRevision++
    })
    this.onChanged()
  }
  private sectionTitle(): string {
    if (this.section === 'modelApi') return '模型与 API'
    if (this.section === 'settings') return '算法与设置'
    if (this.section === 'operations') return '其他'
    return '数据可视化'
  }
  private sectionDetail(): string {
    if (this.section === 'visualization') return '当前知识库的关系图与数据分析卡片。'
    if (this.section === 'modelApi') return '统一管理重排序模型和服务 API。'
    if (this.section === 'settings') return '知识库、资料范围与检索算法。'
    return '存储、导入导出、索引任务与操作日志。'
  }
  private workspaceKey(): string {
    return `${this.section}:${this.activeBaseId}:${this.ragRevision}`
  }
  private setModelApiTab(value: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve },
      () => this.modelApiTab = value)
  }
  private setSettingsTab(value: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve },
      () => this.settingsTab = value)
    if (value === 'documents') this.refresh()
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1).scale({ x: 1, y: 1 }) }, pressed: { .opacity(0.76).scale({ x: 0.985, y: 0.985 }) } })
    .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
  }
  @Styles
  focusFeedback() {
    .border({ width: 1, color: Color.Transparent })
    .stateStyles({ normal: { .borderColor(Color.Transparent) }, focused: { .borderColor(UiTheme.focus) } })
    .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
  }
  @Builder
  Filter(label: string, value: string) {
    Button(label).height(29 * this.fontScale).fontSize(10 * this.fontScale)
      .backgroundColor(this.filter === value ? UiTheme.primary : UiTheme.raised)
      .fontColor(this.filter === value ? UiTheme.onPrimary : UiTheme.text).borderRadius(7)
      .interactive().onClick(() => {
        this.filter = value
        if (!this.visible().some((document: LibraryDocument) => document.id === this.selected)) {
          this.selected = this.visible()[0]?.id || ''
        }
      })
  }
  @Builder
  KnowledgeSelector() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 7 * this.fontScale }) {
        Text('◇').fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary)
        Text(this.currentBase()?.name || '选择知识库').fontSize(10 * this.fontScale)
          .fontColor(UiTheme.onPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('▾').fontSize(9 * this.fontScale).fontColor('#D8D8D8')
      }.width('100%')
    }.width(180 * this.fontScale).height(36 * this.fontScale).padding({ left: 12, right: 10 })
      .backgroundColor(UiTheme.primary).borderRadius(8)
      .clip(true)
      .id('knowledge-base-switcher').bindMenu(this.knowledgeMenu())
  }
  @Builder
  DocumentQuickMenu() {
    Button('＋').width(36 * this.fontScale).height(36 * this.fontScale).fontSize(18 * this.fontScale)
      .padding(0).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
      .id('library-menu').bindMenu([
        { value: '新建文本资料', action: () => this.edit() },
        { value: '导入文件', action: () => this.pick(false) },
        { value: '导入图片', action: () => this.pick(true) }
      ])
  }
  @Builder
  Header() {
    if (this.contentWidth() >= 700) {
      Row({ space: 9 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text(this.sectionTitle()).fontSize(22 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text(this.sectionDetail()).fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.KnowledgeSelector()
        Button('＋ 新建知识库').height(36 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .id('knowledge-base-create-wide').onClick(() => this.openCreate())
        Button('数据库').height(36 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.surface).fontColor(UiTheme.secondary)
          .border({ width: 1, color: UiTheme.border }).borderRadius(8)
          .bindMenu(this.databaseMenu())
        if (this.section === 'settings' && this.settingsTab === 'documents') this.DocumentQuickMenu()
      }.width('100%')
    } else {
      Column({ space: 8 * this.fontScale }) {
        Row({ space: 8 * this.fontScale }) {
          Column({ space: 2 * this.fontScale }) {
            Text(this.sectionTitle()).fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text(this.sectionDetail()).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('数据库').height(32 * this.fontScale).fontSize(9 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary)
            .bindMenu(this.databaseMenu())
        }.width('100%')
        Row({ space: 7 * this.fontScale }) {
          Column() { this.KnowledgeSelector() }.layoutWeight(1)
          Button('＋ 新建').height(36 * this.fontScale).fontSize(10 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
            .id('knowledge-base-create-compact').onClick(() => this.openCreate())
          if (this.section === 'settings' && this.settingsTab === 'documents') this.DocumentQuickMenu()
        }.width('100%')
      }.width('100%')
    }
  }
  @Builder
  DocumentListRow(document: LibraryDocument) {
    Column({ space: 5 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        Text(this.documentIcon(document)).fontSize(16 * this.fontScale).fontColor(UiTheme.secondary).width(20 * this.fontScale)
        Text(document.title).fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(this.documentStatus(document)).fontSize(8 * this.fontScale)
          .fontColor(document.indexed ? UiTheme.secondary : UiTheme.muted)
          .padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .backgroundColor(document.indexed ? '#ECECEC' : Color.Transparent).borderRadius(4)
      }.width('100%')
      Text(`${this.modalityLabel(document)} · ${document.course || '未分类'} · ${document.origin}`)
        .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (document.text) {
        Text(document.text).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(16 * this.fontScale).width('100%')
      }
    }.width('100%').padding(10 * this.fontScale).alignItems(HorizontalAlign.Start)
      .backgroundColor(this.selected === document.id ? UiTheme.surface : '#F8F8F8')
      .border({ width: 1, color: this.selected === document.id ? '#BDBDBD' : UiTheme.border })
      .borderRadius(8).interactive().onClick(() => this.selectDocument(document.id))
  }
  @Builder
  DocumentListContent() {
    Column({ space: 7 * this.fontScale }) {
      ForEach(this.visible(), (document: LibraryDocument) => {
        this.DocumentListRow(document)
      }, (document: LibraryDocument) => `${document.id}-${document.indexed}`)
      if (this.visible().length === 0) {
        Text(this.query ? '没有匹配的资料' : '暂无资料').fontSize(12 * this.fontScale).fontColor(UiTheme.muted)
          .width('100%').padding(28 * this.fontScale).textAlign(TextAlign.Center)
      }
    }.width('100%')
  }
  @Builder
  DocumentActions(document: LibraryDocument) {
    Flex({ wrap: FlexWrap.Wrap }) {
      if (document.text) {
        Button('加入上下文').height(29 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).margin({ right: 6, bottom: 6 })
          .interactive().onClick(() => this.onUse(document.id, false))
        Button(document.indexed ? '停用检索' : '参与检索').height(29 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).margin({ right: 6, bottom: 6 })
          .interactive().onClick(() => this.toggle(document.id))
      }
      if (document.kind === 'image') {
        Button(document.text ? '编辑图片描述' : '添加图片描述').height(29 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).margin({ right: 6, bottom: 6 })
          .interactive().onClick(() => this.edit(document))
      }
      if (document.path) {
        Button('作为附件发送').height(29 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).margin({ right: 6, bottom: 6 })
          .interactive().onClick(() => this.onUse(document.id, true))
      }
      if (!document.id.startsWith('rag:')) {
        if (document.origin === '文本资料') {
          Button('修改').height(29 * this.fontScale).fontSize(10 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).margin({ right: 6, bottom: 6 })
            .interactive().onClick(() => this.edit(document))
        }
        Button('删除').height(29 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.secondary).margin({ right: 6, bottom: 6 })
          .interactive().onClick(() => this.remove(document))
      }
    }.width('100%')
  }
  @Builder
  Editor() {
    Column({ space: 9 * this.fontScale }) {
      Text(this.editingImage ? '编辑图片描述' : this.editId ? '编辑文本资料' : '新建文本资料')
        .fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
      if (!this.editingImage) {
        TextInput({ text: this.draftTitle, placeholder: '资料名称' }).height(37 * this.fontScale)
          .fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
          .focusFeedback().onChange((value: string) => this.draftTitle = value)
      }
      TextArea({ text: this.draftText, placeholder: this.editingImage ? '描述图片中的场景、文字、图表或可用于检索的信息' : '粘贴要保留的资料或上下文' })
        .height(180 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
        .focusFeedback().onChange((value: string) => this.draftText = value)
      Row({ space: 8 * this.fontScale }) {
        Button('取消').height(32 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).onClick(() => this.setEditing(false))
        Button(this.editingImage ? '保存图片描述' : '保存资料').height(32 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).onClick(() => this.saveText())
      }
    }.width('100%').padding(13 * this.fontScale).backgroundColor('#F7F7F7')
      .border({ width: 1, color: UiTheme.border }).borderRadius(9).transition(UiMotion.reveal())
  }
  @Builder
  DocumentDetailContent() {
    Column({ space: 11 * this.fontScale }) {
      if (this.editing) {
        this.Editor()
      } else if (this.selectedDocument() !== undefined) {
        Row({ space: 9 * this.fontScale }) {
          Text(this.documentIcon(this.selectedDocument() as LibraryDocument)).fontSize(22 * this.fontScale).fontColor(UiTheme.secondary)
          Column({ space: 3 * this.fontScale }) {
            Text(this.selectedDocument()?.title || '').fontSize(17 * this.fontScale)
              .fontWeight(FontWeight.Medium).fontColor(UiTheme.text).maxLines(2)
            Text(`${this.modalityLabel(this.selectedDocument() as LibraryDocument)} · ${this.selectedDocument()?.course || '未分类'} · ${this.documentStatus(this.selectedDocument() as LibraryDocument)}`)
              .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if ((this.selectedDocument() as LibraryDocument).createdAt > 0) {
            Text(ScheduleService.localLabel((this.selectedDocument() as LibraryDocument).createdAt))
              .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          }
        }.width('100%')
        this.DocumentActions(this.selectedDocument() as LibraryDocument)
        if ((this.selectedDocument() as LibraryDocument).kind === 'image') {
          Image(`file://${(this.selectedDocument() as LibraryDocument).path}`)
            .width('100%').height(300 * this.fontScale).objectFit(ImageFit.Contain)
            .backgroundColor('#F5F5F5').borderRadius(9)
          if ((this.selectedDocument() as LibraryDocument).text) {
            Text((this.selectedDocument() as LibraryDocument).text).fontSize(11 * this.fontScale)
              .fontColor(UiTheme.secondary).lineHeight(18 * this.fontScale).width('100%')
          }
        } else {
          Column() {
            MarkdownContent({ content: (this.selectedDocument() as LibraryDocument).text || '暂无可读取正文', textSize: 12 })
          }.width('100%').padding(14 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(9)
        }
        if ((this.selectedDocument() as LibraryDocument).truncated) {
          Text('当前显示已提取的部分正文，原始文件仍保留。').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        }
      } else {
        Column({ space: 5 * this.fontScale }) {
          Text('选择一份资料').fontSize(15 * this.fontScale).fontColor(UiTheme.text)
          Text('在左侧列表查看正文、图片描述和检索状态。').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
        }.width('100%').padding(32 * this.fontScale).backgroundColor('#F8F8F8').borderRadius(9)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  DocumentsView() {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 7 * this.fontScale }) {
        TextInput({ text: this.query, placeholder: '搜索资料名称、课程或正文' }).fontSize(11 * this.fontScale)
          .placeholderFont({ size: 11 * this.fontScale }).layoutWeight(1).height(35 * this.fontScale)
          .backgroundColor(UiTheme.raised).id('library-search').focusFeedback()
          .onChange((value: string) => { this.query = value; this.refresh() })
        this.Filter('全部', 'all')
        this.Filter('检索', 'indexed')
        this.Filter('图片', 'images')
      }.width('100%')
      if (this.notice) {
        Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
          .padding(8 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(7)
      }
      if (this.wide()) {
        Row() {
          Scroll() {
            Column({ space: 8 * this.fontScale }) {
              Text(`${this.visible().length} 份资料`).fontSize(10 * this.fontScale).fontColor(UiTheme.muted).width('100%')
              this.DocumentListContent()
            }.width('100%')
          }.width(this.contextWidth()).height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
          Column().width(1).height('100%').backgroundColor(UiTheme.border).margin({ left: 13 * this.fontScale, right: 16 * this.fontScale })
          Scroll() {
            this.DocumentDetailContent()
          }.layoutWeight(1).height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
        }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
      } else {
        Scroll() {
          Column({ space: 14 * this.fontScale }) {
            Text(`${this.visible().length} 份资料`).fontSize(10 * this.fontScale).fontColor(UiTheme.muted).width('100%')
            this.DocumentListContent()
            if (this.selected.length > 0 || this.editing) this.DocumentDetailContent()
          }.width('100%')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
      }
    }.width('100%').layoutWeight(1)
  }
  @Builder
  CreateKnowledgeSheet() {
    Scroll() {
      Column({ space: 13 * this.fontScale }) {
        Row() {
          Column({ space: 4 * this.fontScale }) {
            Text('新建知识库').fontSize(21 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('在线 Embedding 可后置配置；未配置时直接使用本地检索。')
              .fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('关闭').height(30 * this.fontScale).fontSize(10 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
            .onClick(() => this.createVisible = false)
        }.width('100%')
        Column({ space: 7 * this.fontScale }) {
          Text('知识库名称').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          TextInput({ text: this.createName, placeholder: '例如：操作系统课程知识库' })
            .height(40 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(8)
            .onChange((value: string) => this.createName = value)
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 7 * this.fontScale }) {
          Text('知识库说明').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          TextArea({ text: this.createDescription, placeholder: '用途、课程范围或资料来源' })
            .height(74 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(8)
            .onChange((value: string) => this.createDescription = value)
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 8 * this.fontScale }) {
          Row() {
            Column({ space: 3 * this.fontScale }) {
              Text('在线 Embedding 配置（可选）').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.text)
              Text('不选择时创建本地知识库，之后可在设置中补充。')
                .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('在线').fontSize(8 * this.fontScale).fontColor(UiTheme.onPrimary)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .backgroundColor(UiTheme.primary).borderRadius(4)
          }.width('100%')
          if (this.embeddingProfiles().length > 0) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 * this.fontScale }) {
                Text('↗').fontSize(14 * this.fontScale).fontColor(UiTheme.secondary)
                Text(this.embeddingName(this.createEmbeddingId)).fontSize(10 * this.fontScale)
                  .fontColor(UiTheme.text).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('▾').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
              }.width('100%')
            }.height(38 * this.fontScale).width('100%').padding({ left: 11, right: 11 })
              .backgroundColor(UiTheme.raised).borderRadius(8).bindMenu(this.embeddingMenu())
          } else {
            Row({ space: 8 * this.fontScale }) {
              Text('未配置在线 Embedding，将使用本地检索创建。').fontSize(10 * this.fontScale)
                .fontColor(UiTheme.secondary).layoutWeight(1)
              Button('仍可创建').height(30 * this.fontScale).fontSize(9 * this.fontScale)
                .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).onClick(() => {
                  this.createNotice = '创建后将使用本地检索，可在“模型与 API”中补充在线配置。'
                })
            }.width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
          }
        }.width('100%').padding(13 * this.fontScale).backgroundColor('#F7F7F7')
          .border({ width: 1, color: UiTheme.border }).borderRadius(9)
        if (this.createNotice) {
          Text(this.createNotice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
            .padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
        }
        Row({ space: 8 * this.fontScale }) {
          Button(this.creating ? '创建中' : '创建知识库').layoutWeight(1).height(40 * this.fontScale)
            .fontSize(11 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary)
            .enabled(!this.creating)
            .onClick(() => this.createKnowledgeBase())
          Button('取消').height(40 * this.fontScale).fontSize(11 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
            .onClick(() => this.createVisible = false)
        }.width('100%')
        Text('创建只会保存知识库配置；在线索引可在知识库设置或运行管理中构建。')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).width('100%')
      }.width('100%').padding(18 * this.fontScale).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      .backgroundColor(UiTheme.background)
  }
  @Builder
  ModelApiSwitcher() {
    Row({ space: 3 * this.fontScale }) {
      SelectionTab({ label: '重排序模型', selected: this.modelApiTab === 'rerank',
        onSelect: () => this.setModelApiTab('rerank') })
      SelectionTab({ label: 'API 管理', selected: this.modelApiTab === 'api',
        onSelect: () => this.setModelApiTab('api') })
    }.padding(3 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8).alignSelf(ItemAlign.Start)
  }
  @Builder
  SettingsSwitcher() {
    Row({ space: 3 * this.fontScale }) {
      SelectionTab({ label: '知识库', selected: this.settingsTab === 'knowledge',
        onSelect: () => this.setSettingsTab('knowledge') })
      SelectionTab({ label: '本地算法', selected: this.settingsTab === 'algorithm',
        onSelect: () => this.setSettingsTab('algorithm') })
      SelectionTab({ label: '资料管理', selected: this.settingsTab === 'documents',
        onSelect: () => this.setSettingsTab('documents') })
    }.padding(3 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8).alignSelf(ItemAlign.Start)
  }
  @Builder
  WorkspaceContent() {
    if (this.section === 'visualization') {
      ForEach([`${this.activeBaseId}:${this.ragRevision}`], (key: string) => {
        RagDataVisualization({ baseId: this.activeBaseId, viewportWidth: this.contentWidth(),
          onUse: (source: SourceCitation) => this.onUseSource(source) })
          .layoutWeight(1).transition(UiMotion.reveal())
      }, (key: string) => key)
    } else if (this.section === 'modelApi') {
      Column({ space: 10 * this.fontScale }) {
        this.ModelApiSwitcher()
        ForEach([`${this.workspaceKey()}:${this.modelApiTab}`], (key: string) => {
          if (this.modelApiTab === 'rerank') {
            RagRerankPanel({ baseId: this.activeBaseId, viewportWidth: this.contentWidth(),
              onChanged: () => this.ragChanged() }).layoutWeight(1).transition(UiMotion.reveal())
          } else {
            RagApiPanel({ viewportWidth: this.contentWidth(), onChanged: () => this.ragChanged() })
              .layoutWeight(1).transition(UiMotion.reveal())
          }
        }, (key: string) => key)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
    } else if (this.section === 'settings') {
      Column({ space: 10 * this.fontScale }) {
        this.SettingsSwitcher()
        ForEach([`${this.workspaceKey()}:${this.settingsTab}`], (key: string) => {
          if (this.settingsTab === 'knowledge') {
            RagKnowledgeBasePanel({ viewportWidth: this.contentWidth(), onChanged: () => this.ragChanged() })
              .layoutWeight(1).transition(UiMotion.reveal())
          } else if (this.settingsTab === 'algorithm') {
            RagAlgorithmPanel({ viewportWidth: this.contentWidth(), onChanged: () => this.ragChanged() })
              .layoutWeight(1).transition(UiMotion.reveal())
          } else {
            this.DocumentsView()
          }
        }, (key: string) => key)
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
    } else {
      ForEach([this.workspaceKey()], (key: string) => {
        RagOperationsPanel({ baseId: this.activeBaseId, viewportWidth: this.contentWidth(),
          onImportFiles: () => this.pick(false), onImportImages: () => this.pick(true),
          onOpenKnowledge: () => { this.setSection('settings'); this.settingsTab = 'knowledge' },
          onChanged: () => this.ragChanged() })
          .layoutWeight(1).transition(UiMotion.reveal())
      }, (key: string) => key)
    }
  }
  build() {
    Column({ space: 12 * this.fontScale }) {
      this.Header()
      Row({ space: 8 * this.fontScale }) {
        Column() { this.WorkspaceContent() }.layoutWeight(1).height('100%').clip(true)
        KnowledgeFeatureRail({ selected: this.section, collapsed: this.railCollapsed,
          onSelect: (value: string) => this.setSection(value),
          onToggle: () => {
            this.getUIContext().animateTo({ duration: UiMotion.duration(UiMotion.section), curve: UiMotion.moveCurve },
              () => this.railCollapsed = !this.railCollapsed)
          } }).height('100%')
      }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
    }.padding({ left: 22 * this.fontScale, right: 22 * this.fontScale, top: 20 * this.fontScale, bottom: 14 * this.fontScale })
      .width('100%').height('100%').backgroundColor(UiTheme.background).id('library-page')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = parseFloat(String(newValue.width))
        if (Number.isFinite(width) && width > 0) this.pageWidth = width
      })
      .bindSheet($$this.createVisible, this.CreateKnowledgeSheet(), { height: '76%', width: 620,
        preferType: SheetType.CENTER, showClose: false, dragBar: false,
        onDisappear: () => { this.createVisible = false } })
  }
}

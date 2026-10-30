import { common } from '@kit.AbilityKit'
import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { LibraryDocument } from '../models/LibraryModels'
import { SourceCitation } from '../models/RagModels'
import { AttachmentService } from '../services/AttachmentService'
import { IntegrationService } from '../services/IntegrationService'
import { ScheduleService } from '../services/ScheduleService'
import { MarkdownContent } from './MarkdownContent'
import { RagAlgorithmPanel } from './RagAlgorithmPanel'
import { RagApiPanel } from './RagApiPanel'
import { RagDataVisualization } from './RagDataVisualization'
import { RagKnowledgeBasePanel } from './RagKnowledgeBasePanel'

@Component
export struct LibraryPage {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 1280
  @State section: string = 'documents'
  @State pageWidth: number = 1000
  @State query: string = ''
  @State filter: string = 'all'
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
  private alive: boolean = true
  onUse: (id: string, attachment: boolean) => void = () => {}
  onUseSource: (source: SourceCitation) => void = () => {}
  onChanged: () => void = () => {}

  aboutToAppear(): void {
    this.alive = true
    this.activeBaseId = IntegrationService.ragWorkspace?.activeBase().id || 'kb-local'
    this.refresh()
  }
  aboutToDisappear(): void { this.alive = false }

  private refresh(): void {
    try {
      this.documents = IntegrationService.library?.documents(this.query) || []
      if (!this.documents.some((document: LibraryDocument) => document.id === this.selected)) {
        this.selected = this.visible().length > 0 ? this.visible()[0].id : ''
      }
      this.activeBaseId = IntegrationService.ragWorkspace?.activeBase().id || 'kb-local'
    } catch (error) { this.notice = (error as Error).message }
  }
  private visible(): LibraryDocument[] {
    return this.documents.filter((document: LibraryDocument) =>
      this.filter === 'all' || (this.filter === 'indexed' ? document.indexed : document.kind === 'image'))
  }
  private selectedDocument(): LibraryDocument | undefined {
    return this.documents.find((document: LibraryDocument) => document.id === this.selected)
  }
  private contentWidth(): number { return Math.max(320, (this.viewportWidth || this.pageWidth) - 92) }
  private wide(): boolean { return this.contentWidth() >= 760 }
  private contextWidth(): number { return Math.max(210, Math.min(320, this.contentWidth() * 0.28)) }

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
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.editing = value)
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
    this.section = value
    this.activeBaseId = IntegrationService.ragWorkspace?.activeBase().id || this.activeBaseId
    if (value === 'documents') this.refresh()
  }
  private ragChanged(): void {
    this.activeBaseId = IntegrationService.ragWorkspace?.activeBase().id || this.activeBaseId
    this.onChanged()
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1).scale({ x: 1, y: 1 }) }, pressed: { .opacity(0.76).scale({ x: 0.985, y: 0.985 }) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }
  @Styles
  focusFeedback() {
    .border({ width: 1, color: Color.Transparent })
    .stateStyles({ normal: { .borderColor(Color.Transparent) }, focused: { .borderColor(UiTheme.focus) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }
  @Builder
  SectionTab(label: string, value: string) {
    Button(label).height(32 * this.fontScale).fontSize(11 * this.fontScale)
      .backgroundColor(this.section === value ? UiTheme.primary : Color.Transparent)
      .fontColor(this.section === value ? UiTheme.onPrimary : UiTheme.secondary)
      .borderRadius(7).padding({ left: 12 * this.fontScale, right: 12 * this.fontScale })
      .id(`library-tab-${value}`)
      .interactive().onClick(() => this.setSection(value))
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
  Header() {
    Row({ space: 12 * this.fontScale }) {
      Column({ space: 4 * this.fontScale }) {
        Text('资料库').fontSize(24 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        Text('资料、知识库与本地检索工作台').fontSize(11 * this.fontScale).fontColor(UiTheme.muted)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.section === 'documents') {
        Button('导入图片').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).enabled(!this.busy)
          .id('library-import-image').interactive().onClick(() => this.pick(true))
        Button(this.busy ? '正在导入' : '导入文件').height(34 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).enabled(!this.busy)
          .id('library-import-file').interactive().onClick(() => this.pick(false))
        Button('＋').height(34 * this.fontScale).width(36 * this.fontScale).fontSize(18 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.raised).fontColor(UiTheme.text).id('library-menu')
          .bindMenu([{ value: '新建文本资料', action: () => this.edit() }])
      }
    }.width('100%')
  }
  @Builder
  Tabs() {
    Row({ space: 3 * this.fontScale }) {
      this.SectionTab('资料', 'documents')
      this.SectionTab('知识库', 'knowledge')
      this.SectionTab('数据可视化', 'visualization')
      this.SectionTab('模型与 API', 'api')
      this.SectionTab('本地算法', 'algorithm')
    }.padding(3 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(9 * this.fontScale)
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
  build() {
    Column({ space: 12 * this.fontScale }) {
      this.Header()
      this.Tabs()
      if (this.section === 'documents') {
        this.DocumentsView()
      } else if (this.section === 'knowledge') {
        RagKnowledgeBasePanel({ viewportWidth: this.contentWidth(), onChanged: () => this.ragChanged() }).layoutWeight(1)
      } else if (this.section === 'visualization') {
        RagDataVisualization({ baseId: this.activeBaseId, viewportWidth: this.contentWidth(),
          onUse: (source: SourceCitation) => this.onUseSource(source) })
          .layoutWeight(1)
      } else if (this.section === 'api') {
        RagApiPanel({ viewportWidth: this.contentWidth(), onChanged: () => this.ragChanged() }).layoutWeight(1)
      } else {
        RagAlgorithmPanel({ viewportWidth: this.contentWidth(), onChanged: () => this.ragChanged() }).layoutWeight(1)
      }
    }.padding({ left: 22 * this.fontScale, right: 22 * this.fontScale, top: 20 * this.fontScale, bottom: 14 * this.fontScale })
      .width('100%').height('100%').backgroundColor(UiTheme.background).id('library-page')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = parseFloat(String(newValue.width))
        if (Number.isFinite(width) && width > 0) this.pageWidth = width
      })
  }
}

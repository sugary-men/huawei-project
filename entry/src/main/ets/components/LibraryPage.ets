import { common } from '@kit.AbilityKit'
import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { LibraryDocument } from '../models/LibraryModels'
import { AttachmentService } from '../services/AttachmentService'
import { IntegrationService } from '../services/IntegrationService'
import { ScheduleService } from '../services/ScheduleService'
import { MarkdownContent } from './MarkdownContent'

@Component
export struct LibraryPage {
  @StorageLink('campusFontScale') fontScale: number = 0.9
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
  private alive: boolean = true
  onUse: (id: string, attachment: boolean) => void = () => {}
  onChanged: () => void = () => {}
  aboutToAppear(): void { this.alive = true; this.refresh() }
  aboutToDisappear(): void { this.alive = false }
  private refresh(): void {
    try {
      this.documents = IntegrationService.library?.documents(this.query) || []
      if (!this.documents.some((d: LibraryDocument) => d.id === this.selected)) this.selected = ''
    } catch (error) { this.notice = (error as Error).message }
  }
  private async pick(photos: boolean): Promise<void> {
    if (this.busy) return
    this.busy = true
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const files = await AttachmentService.pick(context, photos, 4)
      try {
        IntegrationService.library?.register(files)
        if (this.alive) { this.notice = files.length ? `已导入${files.length}份资料，文字资料可参与检索。` : ''; this.refresh(); this.onChanged() }
      } finally { files.forEach((file) => AttachmentService.removeDraft(file, context.filesDir)) }
    } catch (error) { if (this.alive) this.notice = (error as Error).message || '导入失败。' }
    finally { if (this.alive) this.busy = false }
  }
  private toggle(id: string): void {
    try { IntegrationService.library?.toggle(id); this.refresh(); this.onChanged(); this.notice = '检索范围已更新。' }
    catch (error) { this.notice = (error as Error).message }
  }
  private async remove(document: LibraryDocument): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除资料',
        message: `从资料库删除「${document.title}」？已加入对话的附件和引用副本会保留。`, buttons: [{ text: '取消', color: '#777777' }, { text: '删除', color: '#202020' }] })
      if (!this.alive || result.index !== 1) return
      IntegrationService.library?.remove(document.id); this.refresh(); this.onChanged(); this.notice = '资料已删除。'
    } catch (error) { if (this.alive) this.notice = (error as Error).message === 'cancel' ? '' : (error as Error).message }
  }
  private visible(): LibraryDocument[] {
    return this.documents.filter((d: LibraryDocument) => this.filter === 'all' || (this.filter === 'indexed' ? d.indexed : d.kind === 'image'))
  }
  private edit(document?: LibraryDocument): void {
    this.editId = document?.id || ''; this.editingImage = document?.kind === 'image'
    this.draftTitle = document?.title || ''; this.draftText = document?.text || ''; this.setEditing(true)
  }
  private setEditing(value: boolean): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.editing = value)
  }
  private togglePreview(id: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.selected = this.selected === id ? '' : id)
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
      this.setEditing(false); this.refresh(); this.onChanged()
    } catch (error) { this.notice = (error as Error).message }
  }
  private documentStatus(document: LibraryDocument): string {
    if (document.kind === 'image') {
      return document.indexed ? '图片描述参与检索' : document.text ? '图片描述待启用' : '图片待添加描述'
    }
    return document.indexed ? '参与检索' : '已停用检索'
  }
  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1).scale({ x: 1, y: 1 }) }, pressed: { .opacity(0.78).scale({ x: 0.98, y: 0.98 }) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }

  @Styles
  focusFeedback() {
    .border({ width: 1, color: Color.Transparent })
    .stateStyles({ normal: { .borderColor(Color.Transparent) }, focused: { .borderColor(UiTheme.focus) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }

  @Builder
  Filter(label: string, id: string) {
    Button(label).height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(this.filter === id ? UiTheme.primary : UiTheme.raised)
      .fontColor(this.filter === id ? UiTheme.surface : UiTheme.text).borderRadius(7).interactive().onClick(() =>
        this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.filter = id))
  }
  build() {
    Column({ space: 16 * this.fontScale }) {
      Row() {
        Column({ space: 5 }) {
          Text('资料库').fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('统一管理文件、图片、对话上下文与检索资料').fontSize(12 * this.fontScale).fontColor(UiTheme.secondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('导入图片').fontSize(12 * this.fontScale).height(34 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .enabled(!this.busy).id('library-import-image').interactive().onClick(() => this.pick(true))
        Button(this.busy ? '正在导入' : '导入文件').fontSize(12 * this.fontScale).height(34 * this.fontScale).margin({ left: 8 })
          .backgroundColor(UiTheme.primary).fontColor(UiTheme.surface).enabled(!this.busy).id('library-import-file').interactive().onClick(() => this.pick(false))
        Button('⋯').fontSize(20 * this.fontScale).height(34 * this.fontScale).width(35 * this.fontScale).padding(0).margin({ left: 8 })
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).id('library-menu')
          .bindMenu([{ value: '新建文本资料', action: () => this.edit() }])
      }.width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: '搜索资料名称、课程或正文' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale })
          .layoutWeight(1).height(36 * this.fontScale).backgroundColor(UiTheme.raised).id('library-search').focusFeedback().onChange((value: string) => { this.query = value; this.refresh() })
        this.Filter('全部', 'all'); this.Filter('参与检索', 'indexed'); this.Filter('图片', 'images')
      }.width('100%')
      if (this.busy) {
        Row({ space: 8 * this.fontScale }) {
          LoadingProgress().width(16 * this.fontScale).height(16 * this.fontScale).color(UiTheme.secondary)
          Text('正在读取并整理资料…').fontSize(12 * this.fontScale).fontColor(UiTheme.secondary)
        }.width('100%').id('library-loading').transition(UiMotion.fade())
      }
      if (this.notice) { Text(this.notice).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).width('100%').id('library-notice').transition(UiMotion.fade()) }
      Scroll() {
        Column({ space: 10 * this.fontScale }) {
          if (this.editing) {
            Column({ space: 9 * this.fontScale }) {
              if (!this.editingImage) {
                TextInput({ text: this.draftTitle, placeholder: '资料名称' }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale })
                  .height(36 * this.fontScale).width('100%').maxLength(120).id('library-text-title').focusFeedback().onChange((value: string) => this.draftTitle = value)
              }
              TextArea({ text: this.draftText, placeholder: this.editingImage ? '描述图片中的场景、文字、图表或可用于检索的信息' : '粘贴要保留的资料或上下文' })
                .fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale })
                .height(125 * this.fontScale).width('100%').maxLength(12000).id('library-text-content').focusFeedback().onChange((value: string) => this.draftText = value)
              Row({ space: 9 }) {
                Button('取消').height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text).interactive().onClick(() => this.setEditing(false))
                Button(this.editingImage ? '保存图片描述' : '保存资料').height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.surface)
                  .id('library-text-save').interactive().onClick(() => this.saveText())
              }
            }.padding(14 * this.fontScale).width('100%').backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(12)
              .transition(UiMotion.reveal()).id('library-editor')
          }
          if (this.visible().length === 0) {
            Column({ space: 9 }) {
              Text(this.query ? '没有匹配的资料' : '让资料在这里汇集').fontSize(20 * this.fontScale).fontColor(UiTheme.text)
              Text('导入的文件会保存在本机；文字和图片描述可用于检索，图片也可加入对话。也支持导入RAG索引JSON。')
                .fontSize(13 * this.fontScale).lineHeight(22 * this.fontScale).fontColor(UiTheme.secondary).textAlign(TextAlign.Center)
            }.width('100%').padding(45 * this.fontScale).transition(UiMotion.fade())
          }
          ForEach(this.visible(), (document: LibraryDocument) => {
            Column({ space: 9 * this.fontScale }) {
              Row({ space: 10 }) {
                Image(document.kind === 'image' ? $r('app.media.ic_image') : $r('app.media.ic_library')).width(23 * this.fontScale).height(23 * this.fontScale)
                Column({ space: 4 }) {
                  Text(document.title).fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).maxLines(2).width('100%')
                  Text(`${document.origin} · ${document.course || '未分类'} · ${this.documentStatus(document)}`)
                    .fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (document.createdAt > 0) { Text(ScheduleService.localLabel(document.createdAt)).fontSize(10 * this.fontScale).fontColor(UiTheme.muted) }
              }.width('100%').id(`library-item-${document.id}`).interactive().onClick(() => this.togglePreview(document.id))
              if (this.selected === document.id) {
                Column({ space: 9 * this.fontScale }) {
                if (document.kind === 'image') {
                  Image(`file://${document.path}`).height(190 * this.fontScale).width('100%').objectFit(ImageFit.Contain)
                  if (document.text) {
                    Text(document.text).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(20 * this.fontScale).width('100%')
                  }
                } else { MarkdownContent({ content: document.text || '暂无可读取正文', textSize: 13 }) }
                if (document.truncated) { Text('当前为已提取的部分正文，原始文件仍保留。').fontSize(11 * this.fontScale).fontColor(UiTheme.muted) }
                }.width('100%').alignItems(HorizontalAlign.Start).transition(UiMotion.reveal())
              } else if (document.text) { Text(document.text).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).maxLines(2).width('100%').transition(UiMotion.fade()) }
              Flex({ wrap: FlexWrap.Wrap }) {
                Button(this.selected === document.id ? '收起' : '预览').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                  .margin({ right: 7, bottom: 4 }).id(`library-preview-${document.id}`).interactive().onClick(() => this.togglePreview(document.id))
                if (document.text) {
                  Button('加入上下文').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 7, bottom: 4 }).id(`library-use-${document.id}`).interactive().onClick(() => this.onUse(document.id, false))
                  Button(document.indexed ? '停用检索' : '参与检索').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 7, bottom: 4 }).id(`library-toggle-${document.id}`).interactive().onClick(() => this.toggle(document.id))
                }
                if (document.kind === 'image') {
                  Button(document.text ? '编辑图片描述' : '添加图片描述').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 7, bottom: 4 }).id(`library-describe-${document.id}`).interactive().onClick(() => this.edit(document))
                }
                if (document.path) {
                  Button('作为附件发送').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 7, bottom: 4 }).id(`library-attach-${document.id}`).interactive().onClick(() => this.onUse(document.id, true))
                }
                if (!document.id.startsWith('rag:')) {
                  if (document.origin === '文本资料') {
                    Button('修改').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                      .margin({ right: 7, bottom: 4 }).interactive().onClick(() => this.edit(document))
                  }
                  Button('删除').fontSize(11 * this.fontScale).height(28 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 7, bottom: 4 }).id(`library-delete-${document.id}`).interactive().onClick(() => this.remove(document))
                }
              }.width('100%')
            }.width('100%').padding(15 * this.fontScale).backgroundColor(UiTheme.surface)
              .border({ width: 1, color: this.selected === document.id ? '#BDBDBD' : UiTheme.border }).borderRadius(12)
              .animation({ duration: UiMotion.press, curve: Curve.EaseOut }).transition(UiMotion.reveal())
          }, (document: LibraryDocument) => `${document.id}-${document.indexed}`)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.padding(26 * this.fontScale).width('100%').height('100%').backgroundColor(UiTheme.background).id('library-page')
  }
}

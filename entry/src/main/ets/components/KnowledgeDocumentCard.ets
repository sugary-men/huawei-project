import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { LibraryDocument } from '../models/LibraryModels'

const EMPTY_DOCUMENT: LibraryDocument = {
  id: '',
  title: '',
  course: '',
  kind: 'text',
  origin: '',
  path: '',
  mimeType: '',
  size: 0,
  text: '',
  truncated: false,
  indexed: false,
  createdAt: 0
}

@Component
export struct KnowledgeDocumentCard {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop document: LibraryDocument = EMPTY_DOCUMENT
  @Prop selected: boolean = false
  onSelect: (id: string) => void = () => {}
  onUse: (id: string, attachment: boolean) => void = () => {}
  onToggle: (id: string) => void = () => {}
  onEdit: (document: LibraryDocument) => void = () => {}
  onRemove: (document: LibraryDocument) => void = () => {}

  private typeLabel(): string {
    if (this.document.kind === 'image') return '图片资料'
    if (this.document.kind === 'index') return '索引资料'
    return '文本资料'
  }

  private statusLabel(): string {
    if (this.document.kind === 'image' && !this.document.text.trim()) return '待描述'
    return this.document.indexed ? '可检索' : '已停用'
  }

  private description(): string {
    const text = this.document.text.trim()
    if (text.length > 0) return text
    if (this.document.kind === 'image') return '补充图片描述后，可参与资料检索。'
    return '打开详情查看资料内容。'
  }

  private canEditText(): boolean {
    return !this.document.id.startsWith('rag:') && this.document.origin === '文本资料'
  }

  private typeIcon(): Resource {
    if (this.document.kind === 'image') return $r('app.media.ic_image')
    if (this.document.kind === 'index') return $r('app.media.ic_library')
    return $r('app.media.ic_folder')
  }

  private cardMenu(): MenuElement[] {
    const actions: MenuElement[] = []
    actions.push({ value: '查看资料', action: () => this.onSelect(this.document.id) })
    if (this.document.text) {
      actions.push({ value: '加入当前上下文', action: () => this.onUse(this.document.id, false) })
      actions.push({ value: this.document.indexed ? '停用检索' : '参与检索',
        action: () => this.onToggle(this.document.id) })
    }
    if (this.document.kind === 'image') {
      actions.push({ value: this.document.text ? '编辑图片描述' : '添加图片描述',
        action: () => this.onEdit(this.document) })
    }
    if (this.document.path) {
      actions.push({ value: '作为附件发送', action: () => this.onUse(this.document.id, true) })
    }
    if (this.canEditText()) {
      actions.push({ value: '修改文本资料', action: () => this.onEdit(this.document) })
    }
    if (!this.document.id.startsWith('rag:')) {
      actions.push({ value: '删除资料', action: () => this.onRemove(this.document) })
    }
    return actions
  }

  @Builder
  ContextMenu() {
    Menu() {
      MenuItem({ content: '查看资料' }).onClick(() => this.onSelect(this.document.id))
      if (this.document.text) {
        MenuItem({ content: '加入当前上下文' }).onClick(() => this.onUse(this.document.id, false))
        MenuItem({ content: this.document.indexed ? '停用检索' : '参与检索' })
          .onClick(() => this.onToggle(this.document.id))
      }
      if (this.document.kind === 'image') {
        MenuItem({ content: this.document.text ? '编辑图片描述' : '添加图片描述' })
          .onClick(() => this.onEdit(this.document))
      }
      if (this.document.path) {
        MenuItem({ content: '作为附件发送' }).onClick(() => this.onUse(this.document.id, true))
      }
      if (this.canEditText()) {
        MenuItem({ content: '修改文本资料' }).onClick(() => this.onEdit(this.document))
      }
      if (!this.document.id.startsWith('rag:')) {
        MenuItem({ content: '删除资料' }).onClick(() => this.onRemove(this.document))
      }
    }
  }

  build() {
    Column({ space: 8 * this.fontScale }) {
      Row({ space: 9 * this.fontScale }) {
        Stack() {
          Image(this.typeIcon())
            .width(17 * this.fontScale).height(17 * this.fontScale)
            .objectFit(ImageFit.Contain)
            .attributeModifier(UiTheme.glyph(UiTheme.iconIvory))
        }.width(32 * this.fontScale).height(32 * this.fontScale)
          .backgroundColor(this.selected ? UiTheme.accent : UiTheme.accentStrong)
          .borderRadius(8)
        Column({ space: 3 * this.fontScale }) {
          Text(this.document.title || '未命名资料')
            .fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.text).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(`${this.typeLabel()} · ${this.document.course || '未分类'}`)
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Row({ space: 5 * this.fontScale }) {
          Row().width(6 * this.fontScale).height(6 * this.fontScale).borderRadius(3)
            .backgroundColor(this.document.indexed ? UiTheme.accent : UiTheme.muted)
          Text(this.statusLabel()).fontSize(9 * this.fontScale)
            .fontColor(this.document.indexed ? UiTheme.accentStrong : UiTheme.muted)
        }
      }.width('100%').alignItems(VerticalAlign.Center)
      Text(this.description())
        .fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
        .lineHeight(15 * this.fontScale).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 6 * this.fontScale }) {
        Text(this.document.origin || '本地资料')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.document.indexed ? '参与检索' : '未参与检索')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
        Stack() {
          Image($r('app.media.ic_chevron_right'))
            .width(12 * this.fontScale).height(12 * this.fontScale)
            .attributeModifier(UiTheme.glyph(UiTheme.iconIvory))
        }.width(20 * this.fontScale).height(20 * this.fontScale)
          .backgroundColor(UiTheme.accentStrong).borderRadius(5)
      }.width('100%').height(20 * this.fontScale).alignItems(VerticalAlign.Center)
    }
    .width('100%').height(116 * this.fontScale)
    .padding({ left: 14 * this.fontScale, right: 14 * this.fontScale,
      top: 10 * this.fontScale, bottom: 9 * this.fontScale })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.selected ? UiTheme.accentPale : Color.Transparent)
    .border({ width: { bottom: 1 }, color: this.selected ? UiTheme.accentBorder : UiTheme.softBorder })
    .borderRadius(8)
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.84) } })
    .animation({ duration: UiMotion.duration(UiMotion.press), curve: UiMotion.enterCurve })
    .onClick(() => this.onSelect(this.document.id))
    .bindMenu(this.cardMenu())
    .bindContextMenu(this.ContextMenu, ResponseType.LongPress)
  }
}

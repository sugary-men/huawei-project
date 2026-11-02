import { common } from '@kit.AbilityKit'
import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { LibraryDocument } from '../models/LibraryModels'
import { RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagMaintenanceService } from '../services/RagMaintenanceService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'
import { ScheduleService } from '../services/ScheduleService'

@Component
export struct RagOperationsPanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop baseId: string = ''
  @Prop viewportWidth: number = 900
  onChanged: () => void = () => {}
  onImportFiles: () => void = () => {}
  onImportImages: () => void = () => {}
  onOpenKnowledge: () => void = () => {}
  @State archive: RagWorkspaceArchive = RagWorkspaceService.empty()
  @State documents: LibraryDocument[] = []
  @State busy: string = ''
  @State notice: string = ''
  @State logs: string[] = []

  aboutToAppear(): void { this.reload() }
  private reload(): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace !== undefined) this.archive = workspace.read()
    this.documents = IntegrationService.library?.documents() || []
  }
  private base(): RagKnowledgeBase | undefined {
    return this.archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === this.baseId) ||
      this.archive.knowledgeBases.find((item: RagKnowledgeBase) => item.id === this.archive.activeBaseId)
  }
  private includedDocuments(): LibraryDocument[] {
    const base = this.base()
    if (base === undefined) return []
    return this.documents.filter((document: LibraryDocument) => {
      if (document.id.startsWith('rag:')) return base.includeBuiltIn
      return base.includeAllLocal || base.documentIds.includes(document.id)
    })
  }
  private statusLabel(): string {
    const base = this.base()
    if (base === undefined) return '无知识库'
    if (base.embeddingMode === 'local') return '本地即时索引'
    return base.lastIndexedAt > 0 ? '在线索引可用' : '等待构建索引'
  }
  private appendLog(message: string): void {
    const time = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    this.logs = [`${time} · ${message}`, ...this.logs].slice(0, 8)
  }
  private async rebuild(): Promise<void> {
    const workspace = IntegrationService.ragWorkspace
    const library = IntegrationService.library
    const base = this.base()
    if (this.busy || workspace === undefined || library === undefined || base === undefined) return
    this.busy = 'rebuild'
    this.notice = '正在重新构建索引，请保持网络连接。'
    try {
      const result = await RagMaintenanceService.rebuild(workspace, library, base.id)
      this.reload()
      this.notice = `索引重建完成：${result.chunkCount} 个片段。`
      this.appendLog(`重建索引 · ${result.chunkCount} 个片段 · ${result.modelId}`)
      this.onChanged()
    } catch (error) {
      this.notice = (error as Error).message || '索引重建失败。'
      this.appendLog(`重建失败 · ${this.notice}`)
    } finally {
      this.busy = ''
    }
  }
  private async exportBase(): Promise<void> {
    const workspace = IntegrationService.ragWorkspace
    const library = IntegrationService.library
    const base = this.base()
    if (this.busy || workspace === undefined || library === undefined || base === undefined) return
    this.busy = 'export'
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await RagMaintenanceService.exportBase(context, workspace, library, base.id)
      this.notice = '知识库索引已导出为 JSON。'
      this.appendLog(`导出知识库 · ${base.name}`)
    } catch (error) {
      this.notice = (error as Error).message || '导出失败。'
      this.appendLog(`导出失败 · ${this.notice}`)
    } finally {
      this.busy = ''
    }
  }

  @Builder
  StatusTile(label: string, value: string, detail: string) {
    Column({ space: 5 * this.fontScale }) {
      Text(label).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
      Text(value).fontSize(19 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.muted).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.layoutWeight(1).constraintSize({ minWidth: 112 }).padding(13 * this.fontScale)
      .alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface)
      .border({ width: 1, color: UiTheme.border }).borderRadius(8)
  }

  @Builder
  ActionButton(label: string, detail: string, action: () => void, disabled: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text(label).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('›').fontSize(18 * this.fontScale).fontColor(UiTheme.secondary)
      }.width('100%')
    }.width('100%').height(56 * this.fontScale).padding({ left: 12, right: 12 })
      .backgroundColor(UiTheme.raised).borderRadius(8).enabled(!disabled)
      .hoverEffect(HoverEffect.Highlight).onClick(action)
  }

  build() {
    Scroll() {
      Column({ space: 14 * this.fontScale }) {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text('运行与数据管理').fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('索引、导入导出、存储与最近任务状态。')
              .fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.busy) {
            Row({ space: 6 * this.fontScale }) {
              LoadingProgress().width(16 * this.fontScale).height(16 * this.fontScale).color(UiTheme.secondary)
              Text(this.busy === 'rebuild' ? '构建中' : '导出中').fontSize(9 * this.fontScale).fontColor(UiTheme.secondary)
            }
          }
        }.width('100%')
        if (this.base() === undefined) {
          Column({ space: 6 * this.fontScale }) {
            Text('暂无可用知识库').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('先在顶部新建知识库，再导入资料并构建索引。').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          }.width('100%').padding(18 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
        } else {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            this.StatusTile('文档', `${this.includedDocuments().length}`, '当前知识库资料范围')
            this.StatusTile('知识节点', `${this.base()?.chunkCount || 0}`, '已存储索引片段')
            this.StatusTile('索引状态', this.statusLabel(),
              this.base()?.lastIndexedAt ? ScheduleService.localLabel(this.base()?.lastIndexedAt || 0) : '尚未构建')
          }.width('100%')
        }
        if (this.notice) {
          Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
            .padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
            .transition(UiMotion.reveal())
        }
        Row({ space: 10 * this.fontScale }) {
          Column({ space: 7 * this.fontScale }) {
            Text('数据操作').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            this.ActionButton('导入文件', 'TXT、Markdown、PDF、DOCX 等', () => this.onImportFiles())
            this.ActionButton('导入图片', '添加图片描述后参与多模态检索', () => this.onImportImages())
            this.ActionButton('重建索引', '使用当前在线 Embedding 重新分块向量化',
              () => this.rebuild(), this.busy.length > 0 || this.base()?.embeddingMode !== 'online')
            this.ActionButton('导出知识库', '导出配置与索引 JSON，不包含 API Key',
              () => this.exportBase(), this.busy.length > 0)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Column({ space: 7 * this.fontScale }) {
            Text('本地存储').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Column({ space: 5 * this.fontScale }) {
              Text('JSON 本地数据库').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
              Text('知识库配置、资料索引与算法参数保存在应用沙箱；原文只在本机处理。')
                .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).lineHeight(15 * this.fontScale)
            }.width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.surface)
              .border({ width: 1, color: UiTheme.border }).borderRadius(8)
            this.ActionButton('知识库管理', '资料范围、索引与知识库设置', () => this.onOpenKnowledge())
            Column({ space: 4 * this.fontScale }) {
              Text('运行提示').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
              Text('在线 Embedding 会发送待索引文本；本地算法、原文存储和图谱计算仍在设备内完成。')
                .fontSize(9 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(15 * this.fontScale)
            }.width('100%').padding(11 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Top)
        Column({ space: 7 * this.fontScale }) {
          Text('最近任务').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          if (this.logs.length === 0) {
            Text('本次会话暂无运行记录。导入、构建或导出后会显示在这里。')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          } else {
            ForEach(this.logs, (item: string) => {
              Text(item).fontSize(9 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
                .padding({ top: 4, bottom: 4 })
            }, (item: string, index: number) => `${index}-${item}`)
          }
        }.width('100%').padding(13 * this.fontScale).alignItems(HorizontalAlign.Start)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(8)
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 18 * this.fontScale })
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
  }
}

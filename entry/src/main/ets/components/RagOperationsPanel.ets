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
  @Prop embedded: boolean = false
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
    if (base.embeddingMode === 'local') return '未启用语义检索 · 本地可用'
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
  MetricItem(label: string, value: string, detail: string) {
    Column({ space: 4 * this.fontScale }) {
      Text(label).fontSize(10 * this.fontScale).fontColor(UiTheme.softMuted)
      Text(value).fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.layoutWeight(1).constraintSize({ minHeight: 68 * this.fontScale })
      .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SectionCard(title: string) {
    Text(title).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
      .fontColor(UiTheme.softText).width('100%')
  }

  @Builder
  ActionRow(label: string, detail: string, action: () => void, disabled: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 * this.fontScale }) {
        Column({ space: 3 * this.fontScale }) {
          Text(label).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
          Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Stack() {
          Image($r('app.media.ic_chevron_right'))
            .width(12 * this.fontScale).height(12 * this.fontScale)
            .colorFilter(UiTheme.iconIvory)
        }.width(22 * this.fontScale).height(22 * this.fontScale)
          .backgroundColor(UiTheme.accentStrong).borderRadius(5)
      }.width('100%')
    }.width('100%').height(48 * this.fontScale).padding({ left: 2, right: 4 })
      .backgroundColor(Color.Transparent).borderRadius(6).enabled(!disabled)
      .opacity(disabled ? 0.48 : 1).hoverEffect(HoverEffect.Highlight).onClick(action)
  }

  build() {
    Column({ space: 12 * this.fontScale }) {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text('资料与索引').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
            Text('索引、导入导出、存储与最近任务状态。')
              .fontSize(10 * this.fontScale).fontColor(UiTheme.softMuted)
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
            Text('暂无可用知识库').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.softText)
            Text('先在顶部新建知识库，再导入资料并构建索引。').fontSize(10 * this.fontScale)
              .fontColor(UiTheme.softMuted)
          }.width('100%').padding(16 * this.fontScale).backgroundColor(UiTheme.softSurface)
            .borderRadius(8)
        } else {
          if (this.viewportWidth < 620) {
            Column({ space: 10 * this.fontScale }) {
              this.MetricItem('文档', `${this.includedDocuments().length}`, '当前知识库资料范围')
              Divider().color(UiTheme.softBorder)
              this.MetricItem('知识节点', `${this.base()?.chunkCount || 0}`, '已存储索引片段')
              Divider().color(UiTheme.softBorder)
              this.MetricItem('索引状态', this.statusLabel(),
                this.base()?.lastIndexedAt ? ScheduleService.localLabel(this.base()?.lastIndexedAt || 0) : '尚未构建')
            }.width('100%').padding(14 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(8)
          } else {
            Row({ space: 14 * this.fontScale }) {
              this.MetricItem('文档', `${this.includedDocuments().length}`, '当前知识库资料范围')
              Divider().vertical(true).height(44 * this.fontScale).color(UiTheme.softBorder)
              this.MetricItem('知识节点', `${this.base()?.chunkCount || 0}`, '已存储索引片段')
              Divider().vertical(true).height(44 * this.fontScale).color(UiTheme.softBorder)
              this.MetricItem('索引状态', this.statusLabel(),
                this.base()?.lastIndexedAt ? ScheduleService.localLabel(this.base()?.lastIndexedAt || 0) : '尚未构建')
            }.width('100%').padding(14 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(8)
          }
        }
        if (this.notice) {
          Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.softText).width('100%')
            .padding(10 * this.fontScale).backgroundColor(UiTheme.accentPale)
            .border({ width: 1, color: UiTheme.accentBorder }).borderRadius(8)
            .transition(UiMotion.reveal())
        }
        Column({ space: 2 * this.fontScale }) {
          this.SectionCard('数据操作')
          Divider().color(UiTheme.softBorder)
          this.ActionRow('导入文件', 'TXT、Markdown、PDF、DOCX 等', () => this.onImportFiles())
          this.ActionRow('导入图片', '添加图片描述后参与多模态检索', () => this.onImportImages())
          this.ActionRow('重建索引', '使用当前在线 Embedding 重新分块向量化',
            () => this.rebuild(), this.busy.length > 0 || this.base()?.embeddingMode !== 'online')
          this.ActionRow('导出知识库', '导出配置与索引 JSON，不包含 API Key',
            () => this.exportBase(), this.busy.length > 0)
          Divider().color(UiTheme.softBorder).margin({ top: 10 * this.fontScale, bottom: 10 * this.fontScale })
          this.SectionCard('本地存储')
          Column({ space: 5 * this.fontScale }) {
            Text('JSON 本地数据库').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.softText)
            Text('知识库配置、资料索引与算法参数保存在应用沙箱；原文只在本机处理。')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted).lineHeight(15 * this.fontScale)
          }.width('100%').padding({ top: 8 * this.fontScale, bottom: 8 * this.fontScale })
          this.ActionRow('知识库管理', '资料范围、索引与知识库设置', () => this.onOpenKnowledge())
          Column({ space: 4 * this.fontScale }) {
            Text('运行提示').fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
            Text('在线 Embedding 会发送待索引文本；本地算法、原文存储和图谱计算仍在设备内完成。')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.softText).lineHeight(15 * this.fontScale)
          }.width('100%').padding({ left: 10 * this.fontScale, top: 8 * this.fontScale, bottom: 8 * this.fontScale })
            .border({ width: { left: 2 }, color: UiTheme.accentBorder })
          Divider().color(UiTheme.softBorder).margin({ top: 10 * this.fontScale, bottom: 10 * this.fontScale })
          this.SectionCard('最近任务')
          if (this.logs.length === 0) {
            Text('本次会话暂无运行记录。导入、构建或导出后会显示在这里。')
              .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
          } else {
            ForEach(this.logs, (item: string) => {
              Text(item).fontSize(9 * this.fontScale).fontColor(UiTheme.softText).width('100%')
                .padding({ top: 4, bottom: 4 })
            }, (item: string, index: number) => `${index}-${item}`)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

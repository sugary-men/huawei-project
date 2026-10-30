import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { KnowledgeChunk, RetrievalResult, SourceCitation } from '../models/RagModels'
import { IntegrationService } from '../services/IntegrationService'

interface GraphSource {
  sourceId: string
  title: string
  course: string
  modality: string
  count: number
}

interface GraphNode {
  id: string
  sourceId: string
  chunkId: string
  label: string
  detail: string
  x: number
  y: number
  width: number
  root: boolean
}

@Component
export struct RagDataVisualization {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop baseId: string = 'kb-local'
  @Prop viewportWidth: number = 1280
  onUse: (source: SourceCitation) => void = () => {}
  @State mode: string = 'graph'
  @State query: string = ''
  @State busy: boolean = false
  @State chunks: KnowledgeChunk[] = []
  @State result: RetrievalResult | undefined = undefined
  @State selectedSource: string = ''
  @State selectedChunk: string = ''
  @State graphWidth: number = 680
  private render: RenderingContextSettings = new RenderingContextSettings(true)
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.render)

  aboutToAppear(): void {
    this.graphWidth = Math.max(420, this.viewportWidth - 120)
    this.refresh()
  }

  private refresh(): void {
    try {
      const workspace = IntegrationService.ragWorkspace
      const library = IntegrationService.library
      if (workspace === undefined || library === undefined) return
      this.chunks = workspace.repository(library, this.baseId).snapshot().chunks
    } catch (error) {
      this.chunks = []
    }
  }

  private sources(): GraphSource[] {
    const grouped = new Map<string, KnowledgeChunk[]>()
    this.chunks.forEach((chunk: KnowledgeChunk) => {
      const rows = grouped.get(chunk.sourceId) || []
      rows.push(chunk)
      grouped.set(chunk.sourceId, rows)
    })
    const result: GraphSource[] = []
    grouped.forEach((rows: KnowledgeChunk[], sourceId: string) => {
      result.push({ sourceId: sourceId, title: rows[0].title, course: rows[0].course,
        modality: rows[0].modality || 'text', count: rows.length })
    })
    return result.sort((a: GraphSource, b: GraphSource): number => a.title.localeCompare(b.title))
  }

  private chunksFor(sourceId: string): KnowledgeChunk[] {
    return this.chunks.filter((chunk: KnowledgeChunk) => chunk.sourceId === sourceId)
  }

  private currentChunk(): KnowledgeChunk | undefined {
    return this.chunks.find((chunk: KnowledgeChunk) => chunk.id === this.selectedChunk)
  }

  private sourceFor(sourceId: string): GraphSource | undefined {
    return this.sources().find((source: GraphSource) => source.sourceId === sourceId)
  }

  private modalityLabel(value: string): string {
    if (value === 'image') return '图片'
    if (value === 'table') return '表格'
    if (value === 'audio') return '音频'
    if (value === 'video') return '视频'
    return '文本'
  }

  private short(value: string, max: number): string {
    return value.length > max ? `${value.slice(0, max)}…` : value
  }

  private graphNodes(): GraphNode[] {
    const nodes: GraphNode[] = []
    const width = Math.max(420, this.graphWidth)
    const nodeWidth = Math.min(190, (width - 70) / 2)
    nodes.push({ id: 'root', sourceId: '', chunkId: '', label: '当前知识库', detail: `${this.sources().length} 份来源 · ${this.chunks.length} 个片段`,
      x: (width - nodeWidth) / 2, y: 18, width: nodeWidth, root: true })
    const sources = this.sources()
    if (sources.length >= 4) {
      sources.slice(0, 8).forEach((source: GraphSource, index: number) => {
        const column = index % 2
        const row = Math.floor(index / 2)
        nodes.push({ id: `source:${source.sourceId}`, sourceId: source.sourceId, chunkId: '',
          label: this.short(source.title, 16), detail: `${this.modalityLabel(source.modality)} · ${source.count} 段`,
          x: column === 0 ? 18 : width - nodeWidth - 18, y: 104 + row * 64, width: nodeWidth, root: false })
      })
    } else {
      this.chunks.slice(0, 8).forEach((chunk: KnowledgeChunk, index: number) => {
        const column = index % 2
        const row = Math.floor(index / 2)
        nodes.push({ id: `chunk:${chunk.id}`, sourceId: chunk.sourceId, chunkId: chunk.id,
          label: this.short(chunk.title, 16), detail: `${this.modalityLabel(chunk.modality || 'text')} · ${this.short(chunk.location, 10)}`,
          x: column === 0 ? 18 : width - nodeWidth - 18, y: 104 + row * 64, width: nodeWidth, root: false })
      })
    }
    return nodes
  }

  private nodeSelected(node: GraphNode): boolean {
    if (node.chunkId.length > 0) return this.selectedChunk === node.chunkId
    return node.sourceId.length > 0 && this.selectedSource === node.sourceId && this.selectedChunk.length === 0
  }

  private drawGraph(): void {
    const width = Math.max(420, this.graphWidth)
    const height = 390
    this.canvas.clearRect(0, 0, width, height)
    const nodes = this.graphNodes()
    const root = nodes.find((node: GraphNode) => node.root)
    if (root === undefined) return
    const rootX = root.x + root.width / 2
    const rootY = root.y + 27
    this.canvas.strokeStyle = '#D2D2D2'
    this.canvas.lineWidth = 1
    nodes.filter((node: GraphNode) => !node.root).forEach((node: GraphNode) => {
      this.canvas.beginPath()
      this.canvas.moveTo(rootX, rootY)
      this.canvas.lineTo(node.x + node.width / 2, node.y + 27)
      this.canvas.stroke()
    })
  }

  private async search(): Promise<void> {
    if (this.busy) return
    const query = this.query.trim()
    if (!query) { this.result = undefined; return }
    this.busy = true
    try {
      const workspace = IntegrationService.ragWorkspace
      const library = IntegrationService.library
      if (workspace === undefined || library === undefined) throw new Error('RAG服务尚未初始化。')
      const policy = workspace.algorithm()
      this.result = await workspace.createRag(library, this.baseId).search(query, {
        course: '', topK: policy.topK, minScore: policy.minScore,
        maxPerSource: policy.maxPerSource, contextChars: policy.contextChars
      })
      if (this.result.sources.length > 0) {
        this.selectedSource = this.result.sources[0].sourceId
        this.selectedChunk = this.result.sources[0].chunkId
      }
    } catch (error) {
      this.result = { query: query, revision: '', status: 'miss', mode: 'keyword',
        notice: (error as Error).message || '检索失败。', sources: [], context: '' }
    } finally {
      this.busy = false
    }
  }

  private useChunk(chunk: KnowledgeChunk): void {
    this.onUse({ number: 1, chunkId: chunk.id, sourceId: chunk.sourceId, title: chunk.title,
      location: chunk.location, course: chunk.course, excerpt: chunk.content, score: 1,
      modality: chunk.modality || 'text', mediaPath: chunk.mediaPath || '',
      mediaMimeType: chunk.mediaMimeType || '' })
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.72) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }

  @Builder
  ModeButton(label: string, value: string) {
    Button(label).height(30 * this.fontScale).fontSize(11 * this.fontScale)
      .backgroundColor(this.mode === value ? UiTheme.primary : UiTheme.raised)
      .fontColor(this.mode === value ? UiTheme.onPrimary : UiTheme.text)
      .borderRadius(7).interactive().onClick(() => {
        this.mode = value
        if (value === 'graph') setTimeout(() => this.drawGraph(), 30)
      })
  }

  @Builder
  GraphView() {
    Column({ space: 10 * this.fontScale }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.canvas).width('100%').height(390)
          .onReady(() => this.drawGraph())
        ForEach(this.graphNodes(), (node: GraphNode) => {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 2 * this.fontScale }) {
              Text(node.label).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
                .fontColor(this.nodeSelected(node) ? UiTheme.onPrimary : UiTheme.text)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(node.detail).fontSize(9 * this.fontScale)
                .fontColor(this.nodeSelected(node) ? '#DDDDDD' : UiTheme.muted)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width(node.width).height(54 * this.fontScale).padding({ left: 12, right: 12 })
            .position({ x: node.x, y: node.y })
            .backgroundColor(this.nodeSelected(node) ? UiTheme.primary : UiTheme.surface)
            .border({ width: 1, color: this.nodeSelected(node) ? UiTheme.primary : UiTheme.border })
            .borderRadius(8).interactive().onClick(() => {
              if (node.sourceId.length === 0) return
              if (node.chunkId.length > 0) {
                this.selectedSource = node.sourceId
                this.selectedChunk = this.selectedChunk === node.chunkId ? '' : node.chunkId
              } else {
                this.selectedSource = this.selectedSource === node.sourceId ? '' : node.sourceId
                this.selectedChunk = ''
              }
            })
        }, (node: GraphNode) => node.id)
      }.width('100%').height(390).backgroundColor('#F8F8F8').border({ width: 1, color: UiTheme.border })
        .borderRadius(10).clip(true)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const width = parseFloat(String(newValue.width))
          if (Number.isFinite(width) && width > 0 && Math.abs(width - this.graphWidth) > 2) {
            this.graphWidth = width
            setTimeout(() => this.drawGraph(), 30)
          }
        })
      Text('点击来源节点可查看其片段；深色节点表示当前选择。')
        .fontSize(10 * this.fontScale).fontColor(UiTheme.muted).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  NodeView() {
    Scroll() {
      Column({ space: 10 * this.fontScale }) {
        ForEach(this.sources(), (source: GraphSource) => {
          Column({ space: 8 * this.fontScale }) {
            Row({ space: 8 * this.fontScale }) {
              Column({ space: 3 * this.fontScale }) {
                Text(source.title).fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
                Text(`${source.course || '未分类'} · ${this.modalityLabel(source.modality)} · ${source.count} 个节点`)
                  .fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(this.selectedSource === source.sourceId ? '收起' : '展开').height(28 * this.fontScale)
                .fontSize(10 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                .onClick(() => this.selectedSource = this.selectedSource === source.sourceId ? '' : source.sourceId)
            }.width('100%').interactive()
            if (this.selectedSource === source.sourceId) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.chunksFor(source.sourceId), (chunk: KnowledgeChunk, index: number) => {
                  Button(`节点 ${index + 1}`).height(28 * this.fontScale).fontSize(10 * this.fontScale)
                    .fontColor(this.selectedChunk === chunk.id ? UiTheme.onPrimary : UiTheme.text)
                    .backgroundColor(this.selectedChunk === chunk.id ? UiTheme.primary : UiTheme.raised)
                    .margin({ right: 6, bottom: 6 }).onClick(() => {
                      this.selectedChunk = chunk.id
                      this.selectedSource = source.sourceId
                    })
                }, (chunk: KnowledgeChunk) => chunk.id)
              }.width('100%')
            }
          }.width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: this.selectedSource === source.sourceId ? '#BDBDBD' : UiTheme.border }).borderRadius(9)
        }, (source: GraphSource) => source.sourceId)
      }.width('100%')
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
  }

  @Builder
  TableView() {
    Column({ space: 0 }) {
      Row() {
        Text('来源').width('30%'); Text('模态').width('12%'); Text('课程').width('20%')
        Text('位置').width('18%'); Text('片段').width('20%')
      }.width('100%').height(34 * this.fontScale).padding({ left: 10, right: 10 })
        .backgroundColor(UiTheme.raised).border({ width: { bottom: 1 }, color: UiTheme.border })
      Scroll() {
        Column() {
          ForEach(this.chunks.slice(0, 120), (chunk: KnowledgeChunk) => {
            Row() {
              Text(chunk.title).width('30%'); Text(this.modalityLabel(chunk.modality || 'text')).width('12%')
              Text(chunk.course || '未分类').width('20%'); Text(chunk.location).width('18%')
              Text(chunk.content).width('20%')
            }.width('100%').height(38 * this.fontScale).padding({ left: 10, right: 10 })
              .backgroundColor(this.selectedChunk === chunk.id ? '#EEEEEE' : UiTheme.surface)
              .border({ width: { bottom: 1 }, color: UiTheme.border }).interactive().onClick(() => {
                this.selectedChunk = chunk.id
                this.selectedSource = chunk.sourceId
              })
          }, (chunk: KnowledgeChunk) => chunk.id)
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width('100%').layoutWeight(1).border({ width: 1, color: UiTheme.border }).borderRadius(9).clip(true)
  }

  build() {
    Column({ space: 12 * this.fontScale }) {
      Row({ space: 8 * this.fontScale }) {
        TextInput({ text: this.query, placeholder: '检索当前知识库，查看命中与关系' }).fontSize(12 * this.fontScale)
          .placeholderFont({ size: 12 * this.fontScale }).layoutWeight(1).height(36 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(8).onChange((value: string) => this.query = value)
          .onSubmit(() => this.search())
        Button(this.busy ? '检索中' : '检索').height(36 * this.fontScale).fontSize(11 * this.fontScale)
          .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary).enabled(!this.busy).onClick(() => this.search())
      }.width('100%')
      Row({ space: 8 * this.fontScale }) {
        Column({ space: 2 * this.fontScale }) {
          Text(`${this.sources().length} 个来源`).fontSize(12 * this.fontScale).fontColor(UiTheme.text)
          Text(`${this.chunks.length} 个片段 · ${this.chunks.filter((chunk: KnowledgeChunk) =>
            chunk.vector.length > 0).length} 个可用向量`).fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.ModeButton('关系图', 'graph'); this.ModeButton('节点', 'nodes'); this.ModeButton('表格', 'table')
      }.width('100%')
      if (this.result !== undefined) {
        Column({ space: 5 * this.fontScale }) {
          Row() {
            Text(this.result.status === 'hit' ? `命中 ${this.result.sources.length} 个片段` : '没有命中')
              .fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
            Text(this.result.mode === 'hybrid' ? '混合检索' : '关键词检索').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          }.width('100%')
          if (this.result.notice) Text(this.result.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          ForEach(this.result.sources, (source: SourceCitation) => {
            Button(`${source.title} · ${source.location} · ${(source.score * 100).toFixed(0)}%`)
              .width('100%').height(32 * this.fontScale).fontSize(10 * this.fontScale).fontColor(UiTheme.text)
              .backgroundColor(UiTheme.raised).borderRadius(7).onClick(() => {
                this.selectedSource = source.sourceId
                this.selectedChunk = source.chunkId
              })
          }, (source: SourceCitation) => source.chunkId)
        }.width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.surface)
          .border({ width: 1, color: UiTheme.border }).borderRadius(9)
      }
      if (this.mode === 'graph') { this.GraphView() }
      else if (this.mode === 'nodes') { this.NodeView() }
      else { this.TableView() }
      if (this.currentChunk() !== undefined) {
        Column({ space: 8 * this.fontScale }) {
          Row() {
            Text(this.currentChunk()?.title || '').fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.text).layoutWeight(1)
            Button('加入上下文').height(28 * this.fontScale).fontSize(10 * this.fontScale)
              .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary)
              .onClick(() => {
                const chunk = this.currentChunk()
                if (chunk !== undefined) this.useChunk(chunk)
              })
          }.width('100%')
          Text(this.currentChunk()?.content || '').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
            .lineHeight(18 * this.fontScale).maxLines(6).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').padding(11 * this.fontScale).backgroundColor(UiTheme.surface)
          .border({ width: 1, color: '#BDBDBD' }).borderRadius(9).transition(UiMotion.reveal())
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
}

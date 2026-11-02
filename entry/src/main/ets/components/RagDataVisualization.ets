import { UiMotion } from '../config/UiMotion'
import { UiTheme } from '../config/UiTheme'
import { KnowledgeChunk, RetrievalResult, SourceCitation } from '../models/RagModels'
import { RagKnowledgeBase, RagWorkspaceArchive } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'

interface SourceGroup {
  sourceId: string
  title: string
  course: string
  modality: string
  chunks: KnowledgeChunk[]
}

interface BaseNetwork {
  base: RagKnowledgeBase
  sources: SourceGroup[]
  sourceIds: Set<string>
}

interface MindNode {
  id: string
  kind: string
  baseId: string
  sourceId: string
  title: string
  detail: string
  x: number
  y: number
  width: number
  height: number
}

interface MindEdge {
  from: string
  to: string
  kind: string
}

@Component
export struct RagDataVisualization {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop baseId: string = 'kb-local'
  @Prop viewportWidth: number = 1280
  onUse: (source: SourceCitation) => void = () => {}
  @State mode: string = 'mind'
  @State query: string = ''
  @State busy: boolean = false
  @State archive: RagWorkspaceArchive | undefined = undefined
  @State networks: BaseNetwork[] = []
  @State nodes: MindNode[] = []
  @State selectedBase: string = ''
  @State selectedSource: string = ''
  @State selectedChunk: string = ''
  @State result: RetrievalResult | undefined = undefined
  @State graphWidth: number = 900
  @State graphHeight: number = 520
  @State graphScale: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  private edges: MindEdge[] = []
  private render: RenderingContextSettings = new RenderingContextSettings(true)
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.render)
  private panStartX: number = 0
  private panStartY: number = 0
  private pinchStartScale: number = 1
  private pinchStartDistance: number = 0
  private pinchActive: boolean = false

  aboutToAppear(): void {
    this.graphWidth = Math.max(560, this.viewportWidth - 370)
    this.graphHeight = 540
    this.refresh()
  }

  private wide(): boolean { return this.viewportWidth >= 900 }

  private refresh(): void {
    try {
      const workspace = IntegrationService.ragWorkspace
      const library = IntegrationService.library
      if (workspace === undefined || library === undefined) return
      this.archive = workspace.read()
      const networks: BaseNetwork[] = []
      this.archive.knowledgeBases.forEach((base: RagKnowledgeBase) => {
        try {
          const chunks = workspace.repository(library, base.id).snapshot().chunks
          const sourceIds = new Set<string>()
          chunks.forEach((chunk: KnowledgeChunk) => sourceIds.add(chunk.sourceId))
          networks.push({ base: base, sources: this.groupSources(chunks), sourceIds: sourceIds })
        } catch (_error) {}
      })
      this.networks = networks
      this.buildMindMap()
      this.selectedBase = this.archive.activeBaseId
    } catch (_error) {
      this.networks = []
      this.nodes = []
      this.edges = []
    }
  }

  private groupSources(chunks: KnowledgeChunk[]): SourceGroup[] {
    const grouped = new Map<string, KnowledgeChunk[]>()
    chunks.forEach((chunk: KnowledgeChunk) => {
      const rows = grouped.get(chunk.sourceId) || []
      rows.push(chunk)
      grouped.set(chunk.sourceId, rows)
    })
    const result: SourceGroup[] = []
    grouped.forEach((rows: KnowledgeChunk[], sourceId: string) => {
      result.push({ sourceId: sourceId, title: rows[0].title, course: rows[0].course,
        modality: rows[0].modality || 'text', chunks: rows })
    })
    return result.sort((a: SourceGroup, b: SourceGroup): number => a.title.localeCompare(b.title))
  }

  private rootNodeId(baseId: string): string { return `kb:${baseId}` }

  private buildMindMap(): void {
    const width = Math.max(560, this.graphWidth)
    const height = Math.max(420, this.graphHeight)
    const count = Math.max(1, this.networks.length)
    const columns = count <= 2 ? count : Math.ceil(Math.sqrt(count))
    const rows = Math.ceil(count / columns)
    const cellWidth = width / columns
    const cellHeight = height / rows
    const leafLimit = count <= 2 ? 10 : count <= 4 ? 7 : 5
    const nodes: MindNode[] = []
    const edges: MindEdge[] = []
    this.networks.forEach((network: BaseNetwork, index: number) => {
      const column = index % columns
      const row = Math.floor(index / columns)
      const centerX = cellWidth * (column + 0.5)
      const centerY = cellHeight * (row + 0.52)
      const baseNode: MindNode = {
        id: this.rootNodeId(network.base.id), kind: 'base', baseId: network.base.id, sourceId: '',
        title: network.base.name, detail: `${network.sources.length} 来源 · ${network.base.chunkCount || '待索引'} 片段`,
        x: centerX - 78, y: centerY - 24, width: 156, height: 48
      }
      nodes.push(baseNode)
      const sources = network.sources.slice(0, leafLimit)
      const sourceNodes = new Map<string, MindNode>()
      const radiusX = count === 1 ? Math.min(width * 0.31, 310) : Math.max(110, cellWidth * 0.34)
      const radiusY = count === 1 ? Math.min(height * 0.32, 210) : Math.max(84, cellHeight * 0.31)
      sources.forEach((source: SourceGroup, sourceIndex: number) => {
        const angle = -Math.PI / 2 + Math.PI * 2 * sourceIndex / Math.max(1, sources.length)
        const node: MindNode = {
          id: `source:${network.base.id}:${source.sourceId}`, kind: 'source',
          baseId: network.base.id, sourceId: source.sourceId, title: source.title,
          detail: `${this.modalityLabel(source.modality)} · ${source.chunks.length} 片段`,
          x: centerX + Math.cos(angle) * radiusX - 66,
          y: centerY + Math.sin(angle) * radiusY - 18,
          width: 132, height: 36
        }
        nodes.push(node)
        sourceNodes.set(source.sourceId, node)
        edges.push({ from: baseNode.id, to: node.id, kind: 'branch' })
      })
      const isCurrent = network.base.id === this.baseId
      const chunkBudget = isCurrent ? (count === 1 ? 12 : count <= 4 ? 6 : 3) : 0
      if (chunkBudget > 0) {
        const sourceCount = Math.max(1, sources.length)
        const perSource = Math.max(1, Math.ceil(chunkBudget / sourceCount))
        let added = 0
        sources.forEach((source: SourceGroup) => {
          const parent = sourceNodes.get(source.sourceId)
          if (parent === undefined) return
          const take = Math.min(perSource, chunkBudget - added, source.chunks.length)
          for (let chunkIndex = 0; chunkIndex < take; chunkIndex++) {
            const chunk = source.chunks[chunkIndex]
            const angle = -Math.PI / 2 + Math.PI * 2 * chunkIndex / Math.max(1, take)
            const chunkRadiusX = count === 1 ? 190 : Math.max(62, cellWidth * 0.2)
            const chunkRadiusY = count === 1 ? 125 : Math.max(54, cellHeight * 0.2)
            const node: MindNode = {
              id: `chunk:${network.base.id}:${chunk.id}`, kind: 'chunk',
              baseId: network.base.id, sourceId: source.sourceId, title: chunk.location,
              detail: this.modalityLabel(chunk.modality || 'text'),
              x: centerX + Math.cos(angle) * chunkRadiusX - 50,
              y: centerY + Math.sin(angle) * chunkRadiusY - 15,
              width: 100, height: 30
            }
            nodes.push(node)
            edges.push({ from: parent.id, to: node.id, kind: 'chunk' })
            added++
            if (added >= chunkBudget) return
          }
        })
      }
    })
    this.resolveCollisions(nodes, width, height)
    this.nodes = nodes
    this.edges = edges
  }

  private resolveCollisions(nodes: MindNode[], width: number, height: number): void {
    for (let iteration = 0; iteration < 45; iteration++) {
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const a = nodes[i]
          const b = nodes[j]
          const overlapX = (a.width + b.width) / 2 + 10 - Math.abs((a.x + a.width / 2) - (b.x + b.width / 2))
          const overlapY = (a.height + b.height) / 2 + 8 - Math.abs((a.y + a.height / 2) - (b.y + b.height / 2))
          if (overlapX <= 0 || overlapY <= 0) continue
          if (overlapX < overlapY) {
            const direction = a.x + a.width / 2 < b.x + b.width / 2 ? -1 : 1
            const push = overlapX * (a.kind === 'base' ? 0.25 : 0.5)
            a.x += direction * push
            b.x -= direction * push
          } else {
            const direction = a.y + a.height / 2 < b.y + b.height / 2 ? -1 : 1
            const push = overlapY * (a.kind === 'base' ? 0.25 : 0.5)
            a.y += direction * push
            b.y -= direction * push
          }
        }
      }
      nodes.forEach((node: MindNode) => {
        node.x = Math.max(18, Math.min(width - node.width - 18, node.x))
        node.y = Math.max(18, Math.min(height - node.height - 18, node.y))
      })
    }
  }

  private node(id: string): MindNode | undefined {
    return this.nodes.find((item: MindNode) => item.id === id)
  }
  private selectedBaseData(): RagKnowledgeBase | undefined {
    return this.networks.find((network: BaseNetwork) => network.base.id === this.selectedBase)?.base
  }
  private selectedSourceData(): SourceGroup | undefined {
    return this.networks.find((network: BaseNetwork) => network.base.id === this.selectedBase)
      ?.sources.find((source: SourceGroup) => source.sourceId === this.selectedSource)
  }
  private currentChunk(): KnowledgeChunk | undefined {
    return this.selectedSourceData()?.chunks.find((chunk: KnowledgeChunk) => chunk.id === this.selectedChunk)
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
  private nodeSelected(node: MindNode): boolean {
    if (node.kind === 'base') return node.baseId === this.selectedBase && this.selectedSource.length === 0
    if (node.kind === 'chunk') return this.selectedChunk === this.chunkIdFromNode(node)
    return node.baseId === this.selectedBase && node.sourceId === this.selectedSource
  }
  private chunkIdFromNode(node: MindNode): string {
    return node.id.substring(node.id.indexOf(':', 6) + 1)
  }
  private nodeHit(node: MindNode): boolean {
    if (this.result === undefined) return false
    if (node.kind === 'chunk') {
      const chunkId = this.chunkIdFromNode(node)
      return this.result.sources.some((source: SourceCitation) => source.chunkId === chunkId)
    }
    if (node.kind === 'source') {
      return this.result.sources.some((source: SourceCitation) =>
        source.sourceId === node.sourceId &&
        this.networks.find((network: BaseNetwork) => network.base.id === node.baseId)?.sourceIds.has(source.sourceId) === true)
    }
    return false
  }
  private nodeLeft(node: MindNode): number { return node.x * this.graphScale + this.offsetX }
  private nodeTop(node: MindNode): number { return node.y * this.graphScale + this.offsetY }
  private nodeWidth(node: MindNode): number { return node.width * this.graphScale }
  private nodeHeight(node: MindNode): number { return node.height * this.graphScale }

  private selectNode(node: MindNode): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => {
      this.selectedBase = node.baseId
      if (node.kind === 'chunk') {
        this.selectedSource = node.sourceId
        this.selectedChunk = this.chunkIdFromNode(node)
      } else {
        this.selectedSource = node.kind === 'base' || this.selectedSource === node.sourceId ? '' : node.sourceId
        if (node.kind === 'base') this.selectedChunk = ''
      }
    })
    this.drawMindMap()
  }

  private drawMindMap(): void {
    const width = Math.max(560, this.graphWidth)
    const height = Math.max(420, this.graphHeight)
    this.canvas.clearRect(0, 0, width, height)
    this.canvas.fillStyle = '#FAFAFA'
    this.canvas.fillRect(0, 0, width, height)
    this.canvas.save()
    this.canvas.translate(this.offsetX, this.offsetY)
    this.canvas.scale(this.graphScale, this.graphScale)
    this.edges.forEach((edge: MindEdge) => {
      const from = this.node(edge.from)
      const to = this.node(edge.to)
      if (from === undefined || to === undefined) return
      const fromX = from.x + from.width
      const fromY = from.y + from.height / 2
      const toX = to.x
      const toY = to.y + to.height / 2
      this.canvas.beginPath()
      this.canvas.moveTo(fromX, fromY)
      this.canvas.setLineDash([])
      this.canvas.strokeStyle = edge.kind === 'chunk' ? '#D5D5D5' : '#C4C4C4'
      this.canvas.lineWidth = edge.kind === 'chunk' ? 0.9 : 1.15
      const direction = toX >= fromX ? 1 : -1
      this.canvas.bezierCurveTo(fromX + 45 * direction, fromY, toX - 35 * direction, toY, toX, toY)
      this.canvas.stroke()
    })
    this.canvas.setLineDash([])
    this.nodes.forEach((node: MindNode) => {
      if (!this.nodeSelected(node) && !this.nodeHit(node)) return
      this.canvas.beginPath()
      this.canvas.roundRect(node.x - 4, node.y - 4, node.width + 8, node.height + 8, 10)
      this.canvas.strokeStyle = this.nodeSelected(node) ? '#303030' : '#8A8A8A'
      this.canvas.lineWidth = this.nodeSelected(node) ? 2 : 1.3
      this.canvas.stroke()
    })
    this.canvas.restore()
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
      this.result = await workspace.createRag(library, this.baseId || this.selectedBase).search(query, {
        course: '', topK: policy.topK, minScore: policy.minScore,
        maxPerSource: policy.maxPerSource, contextChars: policy.contextChars
      })
      if (this.result.sources.length > 0) {
        const source = this.result.sources[0]
        const owner = this.networks.find((network: BaseNetwork) => network.sourceIds.has(source.sourceId))
        if (owner !== undefined) {
          this.selectedBase = owner.base.id
          this.selectedSource = source.sourceId
          this.selectedChunk = source.chunkId
        }
      }
      this.drawMindMap()
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
  private resetView(): void {
    this.offsetX = 0
    this.offsetY = 0
    this.graphScale = 1
    this.drawMindMap()
  }
  private zoomBy(value: number): void {
    this.graphScale = Math.max(0.65, Math.min(2.2, this.graphScale + value))
    this.drawMindMap()
  }
  private handleTouch(event: TouchEvent): void {
    if (event.touches.length >= 2) {
      const dx = event.touches[0].x - event.touches[1].x
      const dy = event.touches[0].y - event.touches[1].y
      const distance = Math.sqrt(dx * dx + dy * dy)
      if (!this.pinchActive || this.pinchStartDistance <= 0) {
        this.pinchActive = true
        this.pinchStartDistance = Math.max(1, distance)
        this.pinchStartScale = this.graphScale
      } else if (event.type === TouchType.Move) {
        this.graphScale = Math.max(0.65, Math.min(2.2,
          this.pinchStartScale * distance / this.pinchStartDistance))
        this.drawMindMap()
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pinchActive = false
      this.pinchStartDistance = 0
    }
  }

  @Styles
  interactive() {
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.68).scale({ x: 0.94, y: 0.94 }) } })
    .animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }
  @Builder
  ModeButton(label: string, value: string) {
    Button(label).height(30 * this.fontScale).fontSize(10 * this.fontScale)
      .backgroundColor(this.mode === value ? UiTheme.primary : UiTheme.raised)
      .fontColor(this.mode === value ? UiTheme.onPrimary : UiTheme.text).borderRadius(7)
      .id(`rag-viz-${value}`).interactive().onClick(() => {
        this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseInOut }, () => this.mode = value)
      })
  }
  @Builder
  MindNodeButton(node: MindNode) {
    Button({ type: ButtonType.Normal }) {
      if (node.kind === 'base') {
        Row({ space: 8 * this.fontScale }) {
          Text('◇').fontSize(13 * this.fontScale).fontColor(UiTheme.onPrimary)
          Column({ space: 2 * this.fontScale }) {
            Text(this.short(node.title, 14)).fontSize(10 * this.fontScale).fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.onPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(node.detail).fontSize(7 * this.fontScale).fontColor('#CFCFCF').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
      } else if (node.kind === 'source') {
        Column({ space: 1 * this.fontScale }) {
          Text(this.short(node.title, 15)).fontSize(8 * this.fontScale).fontColor(UiTheme.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(node.detail).fontSize(7 * this.fontScale).fontColor(UiTheme.muted).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      } else {
        Row({ space: 4 * this.fontScale }) {
          Text('·').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          Text(this.short(node.title, 11)).fontSize(7 * this.fontScale).fontColor(UiTheme.text)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%')
      }
    }.width(this.nodeWidth(node)).height(this.nodeHeight(node)).padding({ left: 8, right: 8 })
      .backgroundColor(node.kind === 'base' ? UiTheme.primary : UiTheme.surface)
      .border({ width: this.nodeSelected(node) || this.nodeHit(node) ? 2 : 1,
        color: this.nodeSelected(node) ? UiTheme.primary : this.nodeHit(node) ? '#787878' : UiTheme.border })
      .borderRadius(node.kind === 'base' ? 8 * this.fontScale : node.kind === 'source' ? 18 * this.fontScale : 15 * this.fontScale)
      .position({ x: this.nodeLeft(node), y: this.nodeTop(node) })
      .accessibilityText(node.kind === 'base' ? `知识库 ${node.title}` : `资料来源 ${node.title}`)
      .interactive().onClick(() => this.selectNode(node))
  }
  @Builder
  MindMapCanvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.canvas).width('100%').height('100%').onReady(() => this.drawMindMap())
      ForEach(this.nodes, (node: MindNode) => {
        this.MindNodeButton(node)
      }, (node: MindNode) => node.id)
      Row({ space: 4 * this.fontScale }) {
        Button('−').width(25 * this.fontScale).height(25 * this.fontScale).fontSize(13 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5).id('rag-zoom-out')
          .onClick(() => this.zoomBy(-0.15))
        Text(`${Math.round(this.graphScale * 100)}%`).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          .width(38 * this.fontScale).textAlign(TextAlign.Center)
        Button('＋').width(25 * this.fontScale).height(25 * this.fontScale).fontSize(13 * this.fontScale)
          .padding(0).backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5).id('rag-zoom-in')
          .onClick(() => this.zoomBy(0.15))
        Button('重置').height(25 * this.fontScale).fontSize(9 * this.fontScale)
          .backgroundColor(UiTheme.surface).fontColor(UiTheme.text)
          .border({ width: 1, color: UiTheme.border }).borderRadius(5).id('rag-graph-reset')
          .onClick(() => this.resetView())
      }.padding(8 * this.fontScale).position({ x: Math.max(10, this.graphWidth - 182), y: 10 })
    }.width('100%').height('100%').backgroundColor('#FAFAFA')
      .border({ width: 1, color: UiTheme.border }).borderRadius(9).clip(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width = parseFloat(String(newValue.width))
        const height = parseFloat(String(newValue.height))
        if (Number.isFinite(width) && width > 0) this.graphWidth = width
        if (Number.isFinite(height) && height > 0) this.graphHeight = height
        this.buildMindMap()
        setTimeout(() => this.drawMindMap(), 25)
      })
      .onTouch((event: TouchEvent) => this.handleTouch(event))
      .gesture(
        PanGesture({ fingers: 1, distance: 2 })
          .onActionStart(() => {
            this.panStartX = this.offsetX
            this.panStartY = this.offsetY
          })
          .onActionUpdate((event: GestureEvent) => {
            this.offsetX = this.panStartX + event.offsetX
            this.offsetY = this.panStartY + event.offsetY
            this.drawMindMap()
          })
      )
  }
  @Builder
  NodeView() {
    Scroll() {
      Column({ space: 8 * this.fontScale }) {
        ForEach(this.networks, (network: BaseNetwork) => {
          Column({ space: 7 * this.fontScale }) {
            Row({ space: 7 * this.fontScale }) {
              Text(network.base.name).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.text).layoutWeight(1)
              Text(`${network.sources.length} 来源`).fontSize(8 * this.fontScale).fontColor(UiTheme.muted)
              Button(this.selectedBase === network.base.id ? '收起' : '展开').height(25 * this.fontScale)
                .fontSize(8 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                .onClick(() => this.selectedBase = this.selectedBase === network.base.id ? '' : network.base.id)
            }.width('100%')
            if (this.selectedBase === network.base.id) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(network.sources, (source: SourceGroup) => {
                  Button(source.title).height(28 * this.fontScale).fontSize(8 * this.fontScale)
                    .fontColor(this.selectedSource === source.sourceId ? UiTheme.onPrimary : UiTheme.text)
                    .backgroundColor(this.selectedSource === source.sourceId ? UiTheme.primary : UiTheme.raised)
                    .margin({ right: 5, bottom: 5 }).onClick(() => {
                      this.selectedBase = network.base.id
                      this.selectedSource = source.sourceId
                    })
                }, (source: SourceGroup) => source.sourceId)
              }.width('100%')
            }
          }.width('100%').padding(9 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: this.selectedBase === network.base.id ? '#B8B8B8' : UiTheme.border }).borderRadius(8)
        }, (network: BaseNetwork) => network.base.id)
      }.width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
  }
  @Builder
  TableView() {
    Column({ space: 0 }) {
      Row() {
        Text('知识库').width('26%'); Text('来源').width('34%'); Text('课程').width('22%'); Text('片段').width('18%')
      }.width('100%').height(32 * this.fontScale).padding({ left: 9, right: 9 })
        .backgroundColor(UiTheme.raised).border({ width: { bottom: 1 }, color: UiTheme.border })
      Scroll() {
        Column() {
          ForEach(this.networks, (network: BaseNetwork, index: number) => {
            ForEach(network.sources, (source: SourceGroup) => {
              Row() {
                Text(network.base.name).width('26%'); Text(source.title).width('34%')
                Text(source.course || '未分类').width('22%'); Text(`${source.chunks.length}`).width('18%')
              }.width('100%').height(35 * this.fontScale).padding({ left: 9, right: 9 })
                .backgroundColor(this.selectedSource === source.sourceId ? '#EAEAEA' :
                  index % 2 === 0 ? UiTheme.surface : '#FBFBFB')
                .border({ width: { bottom: 1 }, color: UiTheme.border }).interactive().onClick(() => {
                  this.selectedBase = network.base.id
                  this.selectedSource = source.sourceId
                })
            }, (source: SourceGroup) => `${network.base.id}:${source.sourceId}`)
          }, (network: BaseNetwork) => network.base.id)
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width('100%').height('100%').border({ width: 1, color: UiTheme.border }).borderRadius(8).clip(true)
  }
  @Builder
  Inspector() {
    Scroll() {
      Column({ space: 9 * this.fontScale }) {
        Text('知识网络').fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
        Text(`${this.networks.length} 个知识库 · ${this.nodes.filter((node: MindNode) => node.kind === 'source').length} 个来源`)
          .fontSize(8 * this.fontScale).fontColor(UiTheme.muted).width('100%')
        if (this.result !== undefined) {
          Divider().color(UiTheme.border)
          Text(this.result.notice || `${this.result.sources.length} 个检索命中`).fontSize(9 * this.fontScale)
            .fontColor(UiTheme.muted).width('100%')
          ForEach(this.result.sources, (source: SourceCitation) => {
            Button(source.title).height(29 * this.fontScale).fontSize(8 * this.fontScale)
              .fontColor(UiTheme.text).backgroundColor(UiTheme.raised).width('100%')
              .onClick(() => {
                const owner = this.networks.find((network: BaseNetwork) => network.sourceIds.has(source.sourceId))
                if (owner !== undefined) {
                  this.selectedBase = owner.base.id
                  this.selectedSource = source.sourceId
                  this.selectedChunk = source.chunkId
                }
              })
          }, (source: SourceCitation) => source.chunkId)
        }
        Divider().color(UiTheme.border)
        if (this.selectedSourceData() !== undefined) {
          Text((this.selectedSourceData() as SourceGroup).title).fontSize(12 * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
          Text(`${this.modalityLabel((this.selectedSourceData() as SourceGroup).modality)} · ` +
            `${(this.selectedSourceData() as SourceGroup).course || '未分类'} · ` +
            `${(this.selectedSourceData() as SourceGroup).chunks.length} 片段`)
            .fontSize(8 * this.fontScale).fontColor(UiTheme.muted).width('100%')
          if (this.currentChunk() !== undefined) {
            Text((this.currentChunk() as KnowledgeChunk).content).fontSize(10 * this.fontScale)
              .fontColor(UiTheme.secondary).lineHeight(17 * this.fontScale).width('100%')
            Button('加入当前对话').height(31 * this.fontScale).fontSize(9 * this.fontScale)
              .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).width('100%')
              .onClick(() => {
                const chunk = this.currentChunk()
                if (chunk !== undefined) this.useChunk(chunk)
              })
          } else {
            ForEach((this.selectedSourceData() as SourceGroup).chunks.slice(0, 6),
              (chunk: KnowledgeChunk, index: number) => {
                Button(`片段 ${index + 1} · ${chunk.location}`).height(28 * this.fontScale)
                  .fontSize(8 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                  .width('100%').onClick(() => this.selectedChunk = chunk.id)
              }, (chunk: KnowledgeChunk) => chunk.id)
          }
        } else if (this.selectedBaseData() !== undefined) {
          Text((this.selectedBaseData() as RagKnowledgeBase).name).fontSize(12 * this.fontScale)
            .fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
          Text((this.selectedBaseData() as RagKnowledgeBase).description || '未填写说明')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.muted).lineHeight(15 * this.fontScale).width('100%')
          Text(`${(this.selectedBaseData() as RagKnowledgeBase).embeddingMode === 'online' ? '在线 Embedding' : '本地哈希'} · ` +
            `${(this.selectedBaseData() as RagKnowledgeBase).rerankMode === 'none' ? '不重排' :
              (this.selectedBaseData() as RagKnowledgeBase).rerankMode === 'online' ? '在线重排' : '本地重排'}`)
            .fontSize(8 * this.fontScale).fontColor(UiTheme.muted).width('100%')
          ForEach(this.selectedBaseData() !== undefined ?
            this.networks.find((network: BaseNetwork) =>
              network.base.id === this.selectedBase)?.sources.slice(0, 8) || [] : [],
            (source: SourceGroup) => {
              Button(source.title).height(27 * this.fontScale).fontSize(8 * this.fontScale)
                .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).width('100%')
                .onClick(() => this.selectedSource = source.sourceId)
            }, (source: SourceGroup) => source.sourceId)
        } else {
          Text('点击知识库或资料来源节点查看详情。').fontSize(9 * this.fontScale)
            .fontColor(UiTheme.muted).width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(10 * this.fontScale)
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      .backgroundColor('#FAFAFA').border({ width: { left: 1 }, color: UiTheme.border })
  }
  build() {
    Column({ space: 10 * this.fontScale }) {
      Row({ space: 7 * this.fontScale }) {
        TextInput({ text: this.query, placeholder: '检索知识网络并高亮资料来源' }).fontSize(11 * this.fontScale)
          .placeholderFont({ size: 11 * this.fontScale }).layoutWeight(1).height(35 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(7).onChange((value: string) => this.query = value)
          .onSubmit(() => this.search())
        Button(this.busy ? '检索中' : '检索').height(35 * this.fontScale).fontSize(10 * this.fontScale)
          .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary).enabled(!this.busy).onClick(() => this.search())
      }.width('100%')
      Row({ space: 6 * this.fontScale }) {
        Text(`${this.networks.length} 知识库 · ${this.nodes.length} 节点`).fontSize(9 * this.fontScale)
          .fontColor(UiTheme.muted).layoutWeight(1)
        this.ModeButton('思维导图', 'mind'); this.ModeButton('节点', 'nodes'); this.ModeButton('表格', 'table')
      }.width('100%')
      if (this.wide()) {
        Row() {
          Column() {
            if (this.mode === 'mind') { this.MindMapCanvas() }
            else if (this.mode === 'nodes') { this.NodeView() }
            else { this.TableView() }
          }.layoutWeight(1).height('100%')
          Column() { this.Inspector() }.width(286).height('100%')
        }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
      } else {
        Scroll() {
          Column({ space: 10 * this.fontScale }) {
            Column() {
              if (this.mode === 'mind') { this.MindMapCanvas() }
              else if (this.mode === 'nodes') { this.NodeView() }
              else { this.TableView() }
            }.width('100%').height(500 * this.fontScale)
            Column() { this.Inspector() }.width('100%').height(360 * this.fontScale)
          }.width('100%')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
      .transition(UiMotion.reveal())
  }
}

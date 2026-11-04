import { common } from '@kit.AbilityKit'
import { UiTheme } from '../config/UiTheme'
import { LocalAlgorithmEntry, LocalModelEntry } from '../models/LocalAlgorithmModels'
import { RagAlgorithmSettings } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { LocalAlgorithmService } from '../services/LocalAlgorithmService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'

@Component
export struct RagAlgorithmPanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 900
  @Prop embedded: boolean = false
  onChanged: () => void = () => {}
  @State value: RagAlgorithmSettings = RagWorkspaceService.emptyAlgorithm()
  @State notice: string = ''
  @State pageWidth: number = 900
  @State showAlgorithmInfo: boolean = true
  @State localModels: LocalModelEntry[] = []
  @State localAlgorithms: LocalAlgorithmEntry[] = []
  @State localBusy: boolean = false
  @State localNotice: string = ''
  @State addingAlgorithm: boolean = false
  @State algorithmName: string = ''
  @State algorithmDescription: string = ''
  private localService: LocalAlgorithmService | undefined = undefined

  aboutToAppear(): void {
    this.reload()
    this.initializeLocalConfiguration()
  }
  private wide(): boolean { return (this.viewportWidth || this.pageWidth) >= 700 }
  private reload(): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace !== undefined) this.value = workspace.algorithm()
  }
  private copy(changes: Partial<RagAlgorithmSettings>): void {
    this.value = {
      lexicalWeight: changes.lexicalWeight ?? this.value.lexicalWeight,
      semanticWeight: changes.semanticWeight ?? this.value.semanticWeight,
      bm25K1: changes.bm25K1 ?? this.value.bm25K1,
      bm25B: changes.bm25B ?? this.value.bm25B,
      rerankWeight: changes.rerankWeight ?? this.value.rerankWeight,
      topK: changes.topK ?? this.value.topK,
      minScore: changes.minScore ?? this.value.minScore,
      maxPerSource: changes.maxPerSource ?? this.value.maxPerSource,
      contextChars: changes.contextChars ?? this.value.contextChars,
      chunkChars: changes.chunkChars ?? this.value.chunkChars,
      chunkOverlap: changes.chunkOverlap ?? this.value.chunkOverlap
    }
  }
  private save(): void {
    const workspace = IntegrationService.ragWorkspace
    if (workspace === undefined) return
    try {
      workspace.saveAlgorithm(this.value)
      this.reload()
      this.notice = '本地检索参数已保存，并用于对话与数据可视化检索。'
      this.onChanged()
    } catch (error) { this.notice = (error as Error).message || '保存失败。' }
  }
  private initializeLocalConfiguration(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      this.localService = new LocalAlgorithmService(context.filesDir)
      this.reloadLocalConfiguration()
    } catch (error) {
      this.localNotice = (error as Error).message || '本地算法配置读取失败。'
    }
  }
  private reloadLocalConfiguration(): void {
    const archive = this.localService?.read()
    this.localModels = archive?.models || []
    this.localAlgorithms = archive?.algorithms || []
  }
  private async uploadLocalModel(): Promise<void> {
    if (this.localBusy || this.localService === undefined) return
    this.localBusy = true
    this.localNotice = '正在选择并导入本地模型…'
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const model = await this.localService.pickAndAddModel(context)
      this.reloadLocalConfiguration()
      this.localNotice = model === undefined ? '未选择模型文件。' : `已添加本地模型：${model.name}`
      if (model !== undefined) this.onChanged()
    } catch (error) {
      this.localNotice = (error as Error).message || '本地模型导入失败。'
    } finally {
      this.localBusy = false
    }
  }
  private addLocalAlgorithm(): void {
    if (this.localService === undefined) return
    try {
      const algorithm = this.localService.addAlgorithm(this.algorithmName, this.algorithmDescription)
      this.algorithmName = ''
      this.algorithmDescription = ''
      this.addingAlgorithm = false
      this.reloadLocalConfiguration()
      this.localNotice = `已添加本地算法：${algorithm.name}`
      this.onChanged()
    } catch (error) {
      this.localNotice = (error as Error).message || '算法添加失败。'
    }
  }
  private sizeLabel(size: number): string {
    if (size >= 1024 * 1024) return `${(size / 1024 / 1024).toFixed(1)} MB`
    return `${Math.max(1, Math.round(size / 1024))} KB`
  }
  @Builder
  SectionTitle(title: string, detail: string) {
    Column({ space: 2 * this.fontScale }) {
      Text(title).fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  NumberSetting(label: string, value: number, min: number, max: number, step: number,
    apply: (value: number) => void, suffix: string = '') {
    Column({ space: 5 * this.fontScale }) {
      Row() {
        Text(label).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).layoutWeight(1)
        Text(`${value.toFixed(step < 1 ? 2 : 0)}${suffix}`).fontSize(10 * this.fontScale).fontColor(UiTheme.text)
      }.width('100%')
      Slider({ value: value, min: min, max: max, step: step }).width('100%').selectedColor(UiTheme.primary)
        .onChange((next: number) => apply(next))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  AlgorithmInfoCard() {
    Column({ space: 9 * this.fontScale }) {
      Row() {
        Column({ space: 2 * this.fontScale }) {
          Text('本地算法说明').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.text)
          Text('当前检索在本机完成混合召回、阈值过滤与可选重排。')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.showAlgorithmInfo ? '收起' : '展开').height(28 * this.fontScale)
          .fontSize(10 * this.fontScale).fontColor(UiTheme.text).backgroundColor(UiTheme.surface)
          .border({ width: 1, color: UiTheme.softBorder })
          .onClick(() => this.showAlgorithmInfo = !this.showAlgorithmInfo)
      }.width('100%')
      if (this.showAlgorithmInfo) {
        Text('检索流程：资料分块 → 本地关键词 / BM25 / 哈希向量评分 → 权重归一化 → 相似度阈值过滤 → 来源数量限制 → 可选本地或在线重排。')
          .fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          .lineHeight(16 * this.fontScale).width('100%')
        Text('本地向量使用 FNV-1a 哈希、符号交替与 L2 归一化；BM25 综合词频、逆文档频率和文档长度。所有评分在设备内完成。')
          .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
          .lineHeight(15 * this.fontScale).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          Text(`关键词权重 ${this.value.lexicalWeight.toFixed(2)}`).fontSize(9 * this.fontScale)
            .fontColor(UiTheme.text).padding(6).margin({ right: 6, bottom: 6 })
            .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(6)
          Text(`向量权重 ${this.value.semanticWeight.toFixed(2)}`).fontSize(9 * this.fontScale)
            .fontColor(UiTheme.text).padding(6).margin({ right: 6, bottom: 6 })
            .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(6)
          Text(`Top K ${this.value.topK}`).fontSize(9 * this.fontScale)
            .fontColor(UiTheme.text).padding(6).margin({ right: 6, bottom: 6 })
            .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(6)
          Text(`阈值 ${this.value.minScore.toFixed(2)}`).fontSize(9 * this.fontScale)
            .fontColor(UiTheme.text).padding(6).margin({ right: 6, bottom: 6 })
            .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(6)
        }.width('100%')
      }
    }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start)
      .backgroundColor(UiTheme.softSurface).borderRadius(12)
  }
  @Builder
  LocalModelCard() {
    Column({ space: 8 * this.fontScale }) {
      Row() {
        Column({ space: 2 * this.fontScale }) {
          Text('本地模型').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.text)
          Text('模型文件保存在应用沙箱，本列表更新不代表自动加载推理。')
            .fontSize(9 * this.fontScale).fontColor(UiTheme.softMuted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.localBusy ? '导入中' : '上传/添加').height(30 * this.fontScale)
          .fontSize(10 * this.fontScale).fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
          .enabled(!this.localBusy).opacity(this.localBusy ? 0.55 : 1)
          .onClick(() => this.uploadLocalModel())
      }.width('100%')
      if (this.localModels.length === 0) {
        Text('暂无本地模型。支持 ONNX、BIN、GGUF 和 JSON。').fontSize(9 * this.fontScale)
          .fontColor(UiTheme.muted).width('100%').padding(9 * this.fontScale)
          .backgroundColor(UiTheme.surface).borderRadius(8)
      } else {
        ForEach(this.localModels, (model: LocalModelEntry) => {
          Row({ space: 8 * this.fontScale }) {
            Column({ space: 2 * this.fontScale }) {
              Text(model.name).fontSize(10 * this.fontScale).fontColor(UiTheme.text)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${model.format} · ${this.sizeLabel(model.size)}`).fontSize(9 * this.fontScale)
                .fontColor(UiTheme.muted)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(model.enabled ? '可用' : '停用').fontSize(9 * this.fontScale)
              .fontColor(model.enabled ? UiTheme.text : UiTheme.muted)
          }.width('100%').padding(8 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
        }, (model: LocalModelEntry) => model.id)
      }
    }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start)
      .backgroundColor(UiTheme.softSurface).borderRadius(12)
  }
  @Builder
  LocalAlgorithmCard() {
    Column({ space: 8 * this.fontScale }) {
      Row() {
        Column({ space: 2 * this.fontScale }) {
          Text('本地算法列表').fontSize(11 * this.fontScale).fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.text)
          Text('内置算法与后续添加的算法统一展示。').fontSize(9 * this.fontScale)
            .fontColor(UiTheme.softMuted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.addingAlgorithm ? '取消' : '＋ 添加算法').height(30 * this.fontScale)
          .fontSize(10 * this.fontScale).fontColor(UiTheme.text).backgroundColor(UiTheme.surface)
          .border({ width: 1, color: UiTheme.softBorder })
          .onClick(() => this.addingAlgorithm = !this.addingAlgorithm)
      }.width('100%')
      if (this.addingAlgorithm) {
        Column({ space: 7 * this.fontScale }) {
          TextInput({ text: this.algorithmName, placeholder: '算法名称' }).height(34 * this.fontScale)
            .fontSize(10 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(7).maxLength(60)
            .onChange((value: string) => this.algorithmName = value)
          TextArea({ text: this.algorithmDescription, placeholder: '算法用途和实现说明' })
            .height(58 * this.fontScale).fontSize(10 * this.fontScale)
            .backgroundColor(UiTheme.surface).borderRadius(7).maxLength(300)
            .onChange((value: string) => this.algorithmDescription = value)
          Button('保存算法').height(30 * this.fontScale).fontSize(10 * this.fontScale)
            .fontColor(UiTheme.onPrimary).backgroundColor(UiTheme.primary)
            .enabled(this.algorithmName.trim().length > 0)
            .opacity(this.algorithmName.trim().length > 0 ? 1 : 0.45)
            .onClick(() => this.addLocalAlgorithm())
        }.width('100%')
      }
      ForEach(this.localAlgorithms, (algorithm: LocalAlgorithmEntry) => {
        Column({ space: 2 * this.fontScale }) {
          Row() {
            Text(algorithm.name).fontSize(10 * this.fontScale).fontColor(UiTheme.text).layoutWeight(1)
            Text(algorithm.builtIn ? '内置' : '自定义').fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
          }.width('100%')
          Text(algorithm.description || '未填写说明').fontSize(9 * this.fontScale)
            .fontColor(UiTheme.muted).lineHeight(14 * this.fontScale).width('100%')
        }.width('100%').padding(8 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
      }, (algorithm: LocalAlgorithmEntry) => algorithm.id)
      if (this.localNotice) {
        Text(this.localNotice).fontSize(9 * this.fontScale).fontColor(UiTheme.secondary)
          .width('100%').padding(8 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(8)
      }
    }.width('100%').padding(12 * this.fontScale).alignItems(HorizontalAlign.Start)
      .backgroundColor(UiTheme.softSurface).borderRadius(12)
  }
  @Builder
  Content() {
    Column({ space: 12 * this.fontScale }) {
      Row() {
        Column({ space: 3 * this.fontScale }) {
          Text('本地算法调整').fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.softText)
          Text('调整关键词、向量、BM25 与本地重排序参数，不改变资料原文。')
            .fontSize(10 * this.fontScale).fontColor(UiTheme.softMuted).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('恢复默认').height(30 * this.fontScale).fontSize(10 * this.fontScale)
          .backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .onClick(() => this.value = RagWorkspaceService.emptyAlgorithm())
      }.width('100%')
      this.AlgorithmInfoCard()
      GridRow({ columns: 12, gutter: 10 * this.fontScale }) {
        GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
          this.LocalModelCard()
        }
        GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
          this.LocalAlgorithmCard()
        }
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Column({ space: 12 * this.fontScale }) {
          this.SectionTitle('混合检索权重', '关键词与向量分数会按权重比例归一化。')
          this.NumberSetting('关键词权重', this.value.lexicalWeight, 0, 1, 0.05,
            (next: number) => this.copy({ lexicalWeight: next }))
          this.NumberSetting('向量权重', this.value.semanticWeight, 0, 1, 0.05,
            (next: number) => this.copy({ semanticWeight: next }))
          this.NumberSetting('BM25 K1', this.value.bm25K1, 0.1, 5, 0.1,
            (next: number) => this.copy({ bm25K1: next }))
          this.NumberSetting('BM25 B', this.value.bm25B, 0, 1, 0.05,
            (next: number) => this.copy({ bm25B: next }))
        }.width(this.wide() ? '48.5%' : '100%').margin({ bottom: this.wide() ? 0 : 10 * this.fontScale })
          .padding(13 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(12)
        Column({ space: 12 * this.fontScale }) {
          this.SectionTitle('召回与上下文', '控制返回数量、阈值和上下文预算。')
          this.NumberSetting('Top K', this.value.topK, 1, 10, 1,
            (next: number) => this.copy({ topK: next }), ' 条')
          this.NumberSetting('最低分数', this.value.minScore, 0, 1, 0.01,
            (next: number) => this.copy({ minScore: next }))
          this.NumberSetting('单来源上限', this.value.maxPerSource, 1, 10, 1,
            (next: number) => this.copy({ maxPerSource: next }), ' 条')
          this.NumberSetting('上下文预算', this.value.contextChars, 200, 8000, 100,
            (next: number) => this.copy({ contextChars: next }), ' 字符')
        }.width(this.wide() ? '48.5%' : '100%').padding(13 * this.fontScale)
          .backgroundColor(UiTheme.softSurface).borderRadius(12)
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Column({ space: 12 * this.fontScale }) {
          this.SectionTitle('本地重排序权重', '是否启用由“重排序模型管理”中的选择统一决定。')
          this.NumberSetting('重排序权重', this.value.rerankWeight, 0, 1, 0.05,
            (next: number) => this.copy({ rerankWeight: next }))
        }.width(this.wide() ? '48.5%' : '100%').margin({ bottom: this.wide() ? 0 : 10 * this.fontScale })
          .padding(13 * this.fontScale).backgroundColor(UiTheme.softSurface).borderRadius(12)
        Column({ space: 12 * this.fontScale }) {
          this.SectionTitle('切块参数', '用于下一次在线 Embedding 索引构建。')
          this.NumberSetting('片段长度', this.value.chunkChars, 80, 4000, 20,
            (next: number) => this.copy({ chunkChars: next }), ' 字符')
          this.NumberSetting('重叠长度', this.value.chunkOverlap, 0, Math.max(1, this.value.chunkChars - 1), 10,
            (next: number) => this.copy({ chunkOverlap: next }), ' 字符')
        }.width(this.wide() ? '48.5%' : '100%').padding(13 * this.fontScale)
          .backgroundColor(UiTheme.softSurface).borderRadius(12)
      }.width('100%')
      if (this.notice) Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
        .width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
      Button('保存本地算法').height(38 * this.fontScale).fontSize(11 * this.fontScale).width('100%')
        .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).onClick(() => this.save())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    if (this.embedded) {
      Column() { this.Content() }.width('100%').padding(16 * this.fontScale)
        .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
        .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.pageWidth = parseFloat(String(newValue.width))
        })
    } else {
      Scroll() {
        Column() { this.Content() }.width('100%').padding(16 * this.fontScale)
          .backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.softBorder }).borderRadius(16)
          .shadow({ radius: 10, color: UiTheme.cardShadow, offsetY: 3 })
      }.width('100%').height('100%').scrollBar(BarState.On).scrollBarWidth(6)
        .scrollBarColor(UiTheme.secondary).align(Alignment.TopStart)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.pageWidth = parseFloat(String(newValue.width))
        })
    }
  }
}

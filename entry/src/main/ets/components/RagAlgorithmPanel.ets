import { UiTheme } from '../config/UiTheme'
import { RagAlgorithmSettings } from '../models/RagWorkspaceModels'
import { IntegrationService } from '../services/IntegrationService'
import { RagWorkspaceService } from '../services/RagWorkspaceService'

@Component
export struct RagAlgorithmPanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop viewportWidth: number = 900
  onChanged: () => void = () => {}
  @State value: RagAlgorithmSettings = RagWorkspaceService.emptyAlgorithm()
  @State notice: string = ''
  @State pageWidth: number = 900

  aboutToAppear(): void { this.reload() }
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
      localRerank: changes.localRerank ?? this.value.localRerank,
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
  @Builder
  SectionTitle(title: string, detail: string) {
    Column({ space: 2 * this.fontScale }) {
      Text(title).fontSize(13 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
      Text(detail).fontSize(9 * this.fontScale).fontColor(UiTheme.muted)
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
  build() {
    Scroll() {
      Column({ space: 16 * this.fontScale }) {
        Row() {
          Column({ space: 3 * this.fontScale }) {
            Text('本地算法调整').fontSize(18 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
            Text('调整关键词、向量、BM25与本地重排序参数，不改变资料原文。')
              .fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('恢复默认').height(32 * this.fontScale).fontSize(10 * this.fontScale)
            .backgroundColor(UiTheme.raised).fontColor(UiTheme.text).onClick(() => this.value = RagWorkspaceService.emptyAlgorithm())
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          Column({ space: 13 * this.fontScale }) {
            this.SectionTitle('混合检索权重', '关键词与向量分数会按权重比例归一化。')
            this.NumberSetting('关键词权重', this.value.lexicalWeight, 0, 1, 0.05,
              (next: number) => this.copy({ lexicalWeight: next }))
            this.NumberSetting('向量权重', this.value.semanticWeight, 0, 1, 0.05,
              (next: number) => this.copy({ semanticWeight: next }))
            this.NumberSetting('BM25 K1', this.value.bm25K1, 0.1, 5, 0.1,
              (next: number) => this.copy({ bm25K1: next }))
            this.NumberSetting('BM25 B', this.value.bm25B, 0, 1, 0.05,
              (next: number) => this.copy({ bm25B: next }))
          }.width(this.wide() ? '48.5%' : '100%').margin({ bottom: this.wide() ? 0 : 12 * this.fontScale })
            .padding(15 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(10)
          Column({ space: 13 * this.fontScale }) {
            this.SectionTitle('召回与上下文', '控制返回数量、阈值和上下文预算。')
            this.NumberSetting('Top K', this.value.topK, 1, 10, 1,
              (next: number) => this.copy({ topK: next }), ' 条')
            this.NumberSetting('最低分数', this.value.minScore, 0, 1, 0.01,
              (next: number) => this.copy({ minScore: next }))
            this.NumberSetting('单来源上限', this.value.maxPerSource, 1, 10, 1,
              (next: number) => this.copy({ maxPerSource: next }), ' 条')
            this.NumberSetting('上下文预算', this.value.contextChars, 200, 8000, 100,
              (next: number) => this.copy({ contextChars: next }), ' 字符')
          }.width(this.wide() ? '48.5%' : '100%').padding(15 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(10)
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          Column({ space: 12 * this.fontScale }) {
            this.SectionTitle('本地重排序', '按查询词覆盖和精确短语提高候选片段排序。')
            Row() {
              Text('启用本地重排序').fontSize(10 * this.fontScale).fontColor(UiTheme.secondary).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.value.localRerank })
                .onChange((next: boolean) => this.copy({ localRerank: next }))
            }.width('100%')
            this.NumberSetting('重排序权重', this.value.rerankWeight, 0, 1, 0.05,
              (next: number) => this.copy({ rerankWeight: next }))
          }.width(this.wide() ? '48.5%' : '100%').margin({ bottom: this.wide() ? 0 : 12 * this.fontScale })
            .padding(15 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(10)
          Column({ space: 12 * this.fontScale }) {
            this.SectionTitle('切块参数', '用于下一次在线 Embedding 索引构建。')
            this.NumberSetting('片段长度', this.value.chunkChars, 80, 4000, 20,
              (next: number) => this.copy({ chunkChars: next }), ' 字符')
            this.NumberSetting('重叠长度', this.value.chunkOverlap, 0, Math.max(1, this.value.chunkChars - 1), 10,
              (next: number) => this.copy({ chunkOverlap: next }), ' 字符')
          }.width(this.wide() ? '48.5%' : '100%').padding(15 * this.fontScale).backgroundColor(UiTheme.surface)
            .border({ width: 1, color: UiTheme.border }).borderRadius(10)
        }.width('100%')
        if (this.notice) Text(this.notice).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
          .width('100%').padding(10 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
        Button('保存本地算法').height(40 * this.fontScale).fontSize(12 * this.fontScale)
          .backgroundColor(UiTheme.primary).fontColor(UiTheme.onPrimary).onClick(() => this.save())
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 12 * this.fontScale })
    }.width('100%').height('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      .onAreaChange((_oldValue: Area, newValue: Area) => this.pageWidth = parseFloat(String(newValue.width)))
  }
}

import { UiTheme } from '../config/UiTheme'
import { ExecutionRecord, ExecutionTarget } from '../models/ExecutionModels'
import { ExecutionTraceService } from '../services/ExecutionTraceService'

@Component
export struct ExecutionTimeline {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop records: ExecutionRecord[] = []
  @Prop now: number = 0
  @Prop active: boolean = false
  @Prop executionId: string = ''
  onOpenArtifact: (id: string) => void = () => {}

  private status(record: ExecutionRecord): string {
    return record.status === 'running' ? this.active ? '运行中' : '结果未确认' : record.status === 'success' ? '已完成'
      : record.status === 'cancelled' ? '已取消' : record.status === 'interrupted' ? '已中断' : '未成功'
  }
  private duration(record: ExecutionRecord): string {
    const end = record.finishedAt === undefined ? this.active ? this.now : undefined : record.finishedAt
    return ExecutionTraceService.duration(end === undefined ? undefined : Math.max(0, end - record.startedAt))
  }
  private targetKind(target: ExecutionTarget): string {
    return target.kind === 'artifact' ? '会话产物' : target.kind === 'file' ? '文件' : target.kind === 'source' ? '资料'
      : target.kind === 'calendar' ? '日历' : target.kind === 'reminder' ? '提醒' : target.kind === 'memo' ? '备忘录' : target.kind === 'task' ? '定时任务' : '项目'
  }
  build() {
    Column({ space: 10 * this.fontScale }) {
      ForEach(this.records, (record: ExecutionRecord) => {
        Row({ space: 9 * this.fontScale }) {
          Column() {
            if (record.status === 'running' && this.active) { LoadingProgress().width(14 * this.fontScale).height(14 * this.fontScale).color(UiTheme.secondary) }
            else { Text(record.status === 'success' ? '✓' : record.status === 'error' ? '!' : '◌').fontSize(13 * this.fontScale).fontColor(UiTheme.secondary) }
          }.width(18 * this.fontScale).padding({ top: 2 * this.fontScale })
          Column({ space: 5 * this.fontScale }) {
            Row({ space: 8 * this.fontScale }) {
              Text(record.title).fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
              Text(`${this.status(record)} · ${this.duration(record)}`).fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
            }.width('100%')
            Text(record.name).fontSize(10 * this.fontScale).fontFamily('monospace').fontColor(UiTheme.muted).width('100%').copyOption(CopyOptions.InApp)
            if (record.input) { Text(record.input).fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(17 * this.fontScale).width('100%').copyOption(CopyOptions.InApp) }
            Text(record.detail).fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).lineHeight(17 * this.fontScale).width('100%').copyOption(CopyOptions.InApp)
            ForEach(record.targets, (target: ExecutionTarget, index: number) => {
              if (target.kind === 'artifact' && target.id && target.action !== '移除产物') {
                Button(`${target.action} · ${target.label}  ↗`).fontSize(11 * this.fontScale).height(28 * this.fontScale)
                  .padding({ left: 10 * this.fontScale, right: 10 * this.fontScale }).fontColor(UiTheme.text).backgroundColor(UiTheme.surface).borderRadius(6)
                  .constraintSize({ maxWidth: '100%' }).id(`execution-artifact-${this.executionId}-${record.id}-${target.id}`)
                  .hoverEffect(HoverEffect.Highlight).onClick(() => this.onOpenArtifact(target.id!))
              } else {
                Text(`${this.targetKind(target)} · ${target.action} · ${target.label}`).fontSize(10 * this.fontScale).fontColor(UiTheme.secondary)
                  .lineHeight(16 * this.fontScale).width('100%').copyOption(CopyOptions.InApp)
              }
            }, (target: ExecutionTarget, index: number) => `${index}-${target.kind}-${target.id || target.label}`)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Top).padding({ bottom: 9 * this.fontScale })
          .border({ width: { bottom: 1 }, color: UiTheme.border }).id(`execution-${this.executionId}-${record.id}`)
      }, (record: ExecutionRecord) => `${record.id}-${record.status}-${record.finishedAt || 0}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

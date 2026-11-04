import { common } from '@kit.AbilityKit'
import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { AgentTask, AgentTaskDraft, AgentTaskRun } from '../models/AgentTaskModels'
import { AgentTaskStore } from '../services/AgentTaskStore'
import { AgentTaskService } from '../services/AgentTaskService'
import { AgentTaskRuntime } from '../services/AgentTaskRuntime'
import { ScheduleService } from '../services/ScheduleService'
import { MarkdownContent } from './MarkdownContent'
import { MarkdownParser } from '../services/MarkdownParser'
import { SelectionTab } from './SelectionTab'

@Component
export struct AgentTaskPage {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @State tasks: AgentTask[] = []
  @State notice: string = ''
  @State editing: boolean = false
  @State title: string = ''
  @State prompt: string = ''
  @State when: string = ''
  @State mode: string = 'once'
  @State weekdays: string = '1,2,3,4,5'
  @State interval: string = '60'
  @State editId: string = ''
  @State expanded: string = ''
  @State backgroundState: string = ''
  private timer: number = -1
  private alive: boolean = true
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext }
  private store(): AgentTaskStore { return new AgentTaskStore(this.context().filesDir) }
  aboutToAppear(): void { this.alive = true; this.refresh(); this.timer = setInterval(() => this.refresh(), 2500) }
  aboutToDisappear(): void { this.alive = false; clearInterval(this.timer) }
  private refresh(): void {
    if (!this.alive) return
    try { this.tasks = this.store().list(); this.backgroundState = AgentTaskRuntime.backgroundNotice }
    catch (error) { this.notice = (error as Error).message }
  }
  private edit(task?: AgentTask): void {
    this.editId = task?.id || ''; this.title = task?.title || ''; this.prompt = task?.prompt || ''; this.mode = task?.mode || 'once'
    this.when = ScheduleService.localLabel(task && task.nextRunAt > Date.now() ? task.nextRunAt : Date.now() + 3600000)
    this.interval = `${task?.intervalMinutes || 60}`; this.weekdays = task?.weekdays.join(',') || '1,2,3,4,5'; this.setEditing(true)
  }
  private setEditing(value: boolean): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.editing = value)
  }
  private async save(): Promise<void> {
    try {
      const draft: AgentTaskDraft = { title: this.title, prompt: this.prompt, mode: this.mode, firstRunAt: Date.parse(ScheduleService.localInstant(this.when)),
        intervalMinutes: Number(this.interval), weekdays: this.weekdays.split(/[,，、\s]+/).filter((day: string) => day.length > 0).map((day: string) => Number(day)) }
      this.store().save(draft, this.editId || undefined); this.setEditing(false); this.refresh()
      await AgentTaskRuntime.register(this.context())
      if (this.alive) { this.backgroundState = AgentTaskRuntime.backgroundNotice; this.notice = '定时任务已保存，结果会保留在此处。' }
    } catch (error) { if (this.alive) this.notice = (error as Error).message }
  }
  private async run(task: AgentTask): Promise<void> {
    this.notice = '正在执行，结果会保存在任务记录中…'
    try { await AgentTaskRuntime.run(this.context(), task.id, true); if (this.alive) { this.refresh(); this.expanded = task.id; this.notice = '本次执行已结束，请查看实际结果。' } }
    catch (error) { if (this.alive) this.notice = (error as Error).message }
  }
  private async remove(task: AgentTask): Promise<void> {
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '删除定时任务', message: `删除「${task.title}」及其执行记录？`,
        buttons: [{ text: '取消', color: '#777777' }, { text: '删除', color: '#202020' }] })
      if (!this.alive || choice.index !== 1) return
      AgentTaskRuntime.cancel(task.id); this.store().remove(task.id); this.refresh(); AgentTaskRuntime.register(this.context())
    } catch (error) { if (this.alive && (error as Error).message !== 'cancel') this.notice = (error as Error).message }
  }
  private toggle(task: AgentTask): void {
    try { this.store().toggle(task.id); this.refresh(); AgentTaskRuntime.register(this.context()) }
    catch (error) { this.notice = (error as Error).message }
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
  Field(label: string, value: string, id: string, update: (value: string) => void) {
    Text(label).fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
    TextInput({ text: value, placeholder: label }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale }).height(35 * this.fontScale)
      .width('100%').backgroundColor(UiTheme.raised).id(id).focusFeedback().onChange(update)
  }
  @Builder
  Mode(label: string, value: string) {
    SelectionTab({ label: label, selected: this.mode === value, showIndicator: false,
      onSelect: () => {
        this.getUIContext().animateTo({ duration: UiMotion.section, curve: UiMotion.enterCurve },
          () => this.mode = value)
      } })
  }
  build() {
    Column({ space: 12 * this.fontScale }) {
      Row() {
        Column({ space: 5 }) {
          Text('交给 Agent，按计划完成').fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text)
          Text('定时读取已授权日历与资料、整理清单或生成总结，结果保存在任务中。').fontSize(12 * this.fontScale).fontColor(UiTheme.secondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('新建任务').height(34 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.surface)
          .id('agent-task-new').interactive().onClick(() => this.edit())
      }.width('100%')
      Text(this.backgroundState).fontSize(11 * this.fontScale).fontColor(UiTheme.muted).width('100%').id('agent-task-background')
      if (this.notice) { Text(this.notice).fontSize(12 * this.fontScale).fontColor(UiTheme.secondary).width('100%').id('agent-task-notice').transition(UiMotion.fade()) }
      Scroll() {
        Column({ space: 12 * this.fontScale }) {
          if (this.editing) {
            Column({ space: 9 * this.fontScale }) {
              this.Field('任务名称', this.title, 'agent-task-title', (value: string) => this.title = value)
              TextArea({ text: this.prompt, placeholder: '希望 Agent 定时做什么？例如整理明天的日历安排和待办。' }).fontSize(13 * this.fontScale)
                .placeholderFont({ size: 13 * this.fontScale }).width('100%').height(85 * this.fontScale).maxLength(4000).id('agent-task-prompt')
                .focusFeedback().onChange((value: string) => this.prompt = value)
              Row({ space: 8 }) { this.Mode('单次', 'once'); this.Mode('每天', 'daily'); this.Mode('每周', 'weekly'); this.Mode('间隔', 'interval') }
              this.Field('首次执行时间（本地时间，例如2026-10-28 09:00）', this.when, 'agent-task-time', (value: string) => this.when = value)
              if (this.mode === 'weekly') {
                Column({ space: 9 * this.fontScale }) { this.Field('每周几（周一1至周日7，逗号分隔）', this.weekdays, 'agent-task-weekdays', (value: string) => this.weekdays = value) }
                  .width('100%').transition(UiMotion.reveal())
              }
              if (this.mode === 'interval') {
                Column({ space: 9 * this.fontScale }) { this.Field('执行间隔（分钟，至少15分钟）', this.interval, 'agent-task-interval', (value: string) => this.interval = value) }
                  .width('100%').transition(UiMotion.reveal())
              }
              Text('自动任务只读取信息并生成结果；修改日历或其他系统数据仍需你核对。').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
              Row({ space: 10 }) {
                Button('取消').height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text).interactive().onClick(() => this.setEditing(false))
                Button('保存任务').height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.surface)
                  .id('agent-task-save').interactive().onClick(() => this.save())
              }
            }.width('100%').padding(15 * this.fontScale).backgroundColor(UiTheme.surface).borderRadius(12).border({ width: 1, color: UiTheme.border })
              .transition(UiMotion.reveal()).id('agent-task-editor')
          }
          if (!this.tasks.length && !this.editing) {
            Column({ space: 9 }) {
              Stack() {
                Image($r('app.media.ic_clock')).width(28 * this.fontScale).height(28 * this.fontScale)
                  .colorFilter(UiTheme.iconIvory)
              }.width(52 * this.fontScale).height(52 * this.fontScale)
                .backgroundColor(UiTheme.accentStrong).borderRadius(14)
              Text('把重复的整理交给 Agent').fontSize(19 * this.fontScale).fontColor(UiTheme.text)
              Text('例如每天早晨整理日程，或每周汇总资料中的复习重点。').fontSize(13 * this.fontScale).fontColor(UiTheme.secondary)
            }.width('100%').padding(45 * this.fontScale).transition(UiMotion.fade())
          }
          ForEach(this.tasks, (task: AgentTask) => {
            Column({ space: 9 * this.fontScale }) {
              Row() {
                Text(task.title).fontSize(15 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
                if (task.runId) { LoadingProgress().width(15 * this.fontScale).height(15 * this.fontScale).margin({ right: 6 }).color(UiTheme.secondary).transition(UiMotion.fade()) }
                Text(task.runId ? '正在执行' : task.enabled ? '已启用' : task.mode === 'once' && task.runs.length ? '单次已结束' : '已暂停').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary)
              }.width('100%')
              Text(task.prompt).fontSize(13 * this.fontScale).fontColor(UiTheme.secondary).maxLines(3).width('100%')
              Text(`${AgentTaskService.describe(task)}${task.enabled ? ` · 下次 ${ScheduleService.localLabel(task.nextRunAt)}` : ''}`)
                .fontSize(11 * this.fontScale).fontColor(UiTheme.muted).width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                if (task.runId) {
                  Button('停止执行').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 8, bottom: 4 }).interactive().onClick(() => AgentTaskRuntime.cancel(task.id))
                } else {
                  Button('立即运行').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 8, bottom: 4 }).id(`agent-task-run-${task.id}`).interactive().onClick(() => this.run(task))
                  Button(task.enabled ? '暂停' : '启用').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 8, bottom: 4 }).id(`agent-task-toggle-${task.id}`).interactive().onClick(() => this.toggle(task))
                  Button('编辑').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .margin({ right: 8, bottom: 4 }).interactive().onClick(() => this.edit(task))
                }
                Button(this.expanded === task.id ? '收起记录' : `执行记录 ${task.runs.length}`).height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                  .margin({ right: 8, bottom: 4 }).id(`agent-task-results-${task.id}`).interactive().onClick(() =>
                    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.expanded = this.expanded === task.id ? '' : task.id))
                Button('删除').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                  .margin({ right: 8, bottom: 4 }).id(`agent-task-delete-${task.id}`).interactive().onClick(() => this.remove(task))
              }.width('100%')
              if (this.expanded === task.id) {
                Column({ space: 9 * this.fontScale }) {
                if (!task.runs.length) { Text('还没有执行记录').fontSize(12 * this.fontScale).fontColor(UiTheme.muted) }
                ForEach(task.runs, (run: AgentTaskRun) => {
                  Column({ space: 7 }) {
                    Text(`${ScheduleService.localLabel(run.startedAt)} · ${run.status === 'success' ? '已完成' : run.status === 'interrupted' ? '已中断' : '失败'}`)
                      .fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
                    MarkdownContent({ content: MarkdownParser.answer(run.output).body || run.output, textSize: 13 })
                  }.width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.raised).borderRadius(8)
                }, (run: AgentTaskRun) => run.id)
                }.width('100%').alignItems(HorizontalAlign.Start).transition(UiMotion.reveal())
              }
            }.width('100%').padding(16 * this.fontScale).backgroundColor(UiTheme.surface).border({ width: 1, color: UiTheme.border }).borderRadius(12).id(`agent-task-${task.id}`)
              .transition(UiMotion.reveal())
          }, (task: AgentTask) => `${task.id}-${task.updatedAt}-${task.runId}`)
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ right: 12 * this.fontScale, bottom: 8 * this.fontScale })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
        .scrollBarWidth(4).scrollBarColor('#777777')
    }.padding(20 * this.fontScale).width('100%').height('100%').backgroundColor(UiTheme.background)
  }
}

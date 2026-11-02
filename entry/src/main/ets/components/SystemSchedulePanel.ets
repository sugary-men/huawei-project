import { common } from '@kit.AbilityKit'
import { UiTheme } from '../config/UiTheme'
import { UiMotion } from '../config/UiMotion'
import { ScheduleArgs, ScheduleEntry, ScheduleResult } from '../models/ScheduleModels'
import { IntegrationService } from '../services/IntegrationService'
import { ScheduleService } from '../services/ScheduleService'
import { ScheduleOverviewService } from '../services/ScheduleOverviewService'
import { SelectionTab } from './SelectionTab'

@Component
export struct SystemSchedulePanel {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop embedded: boolean = false
  @Prop initialTab: string = 'calendar'
  @State tab: string = 'calendar'
  @State currentTime: string = ''
  @State notice: string = '按需读取系统日历和本应用的提醒、备忘录。你也可以直接在对话里让 Agent 安排。'
  @State entries: ScheduleEntry[] = []
  @State busy: boolean = false
  @State editing: boolean = false
  @State title: string = ''
  @State content: string = ''
  @State start: string = ''
  @State end: string = ''
  @State reminderKind: string = 'alarm'
  @State alarmTime: string = '07:00'
  @State seconds: string = '1500'
  @State selectedId: string = ''
  @State selectedCalendar: number = -1
  @State selectedEvent: number = -1
  private serial: number = 0
  private alive: boolean = true
  onClose: () => void = () => {}

  aboutToAppear(): void {
    this.alive = true
    this.tab = this.initialTab
    IntegrationService.initializeSchedule(this.getUIContext().getHostContext() as common.UIAbilityContext)
    const nextHour = Math.ceil((Date.now() + 3600000) / 60000) * 60000
    this.start = ScheduleService.localLabel(nextHour)
    this.end = ScheduleService.localLabel(nextHour + 3600000)
    this.refreshTime()
    this.refreshEntries()
  }
  aboutToDisappear(): void { this.alive = false; this.serial++ }

  private async refreshTime(): Promise<void> {
    const platform = IntegrationService.schedule
    if (platform === undefined) return
    const result = await ScheduleService.execute({ id: 'panel-time', name: 'get_system_time', arguments: '{}' }, platform,
      () => this.alive, async () => false)
    if (this.alive) this.currentTime = result.ok ? `${ScheduleService.localLabel(result.timestamp || Date.now())} · ${result.timeZone}` : result.message
  }

  private async refreshEntries(): Promise<void> {
    const platform = IntegrationService.schedule
    if (this.busy || platform === undefined) return
    const token = ++this.serial
    const active = (): boolean => this.alive && token === this.serial
    this.busy = true; this.notice = '正在读取已保存内容…'
    const result = await ScheduleOverviewService.list(this.tab, platform, active)
    if (!active()) return
    this.entries = result.entries || []
    this.notice = (this.tab === 'calendar' ? '显示今天起未来31天的日程。' : '') + result.message
    this.busy = false
  }

  private async run(name: string, args: ScheduleArgs): Promise<void> {
    const platform = IntegrationService.schedule
    if (this.busy || platform === undefined) return
    const token = ++this.serial
    const active = (): boolean => this.alive && token === this.serial
    this.busy = true; this.notice = '正在处理…'
    const result: ScheduleResult = await ScheduleService.execute({ id: `panel-${token}`, name: name, arguments: JSON.stringify(args) }, platform,
      active, async (title: string, detail: string): Promise<boolean> => {
        if (!active()) return false
        try {
          const choice = await this.getUIContext().getPromptAction().showDialog({ title: title, message: detail,
            buttons: [{ text: '取消', color: '#777777' }, { text: '确认', color: '#202020' }] })
          return active() && choice.index === 1
        } catch (_error) { return false }
      })
    if (!active()) return
    this.notice = result.message
    const listing = name === 'query_calendar_events' || name === 'list_system_reminders' || (name === 'manage_memo' && args.action === 'list')
    if (listing) this.entries = result.entries || []
    else if (result.ok && result.status !== 'share_opened') {
      this.setEditing(false)
      const refreshed = await ScheduleOverviewService.list(this.tab, platform, active)
      if (!active()) return
      this.entries = refreshed.entries || result.entries || []
      if (!refreshed.ok) this.notice += `\n刷新失败：${refreshed.message}`
    }
    this.busy = false
  }

  private switchTab(tab: string): void {
    if (this.busy) return
    this.tab = tab; this.entries = []; this.editing = false
    this.refreshEntries()
  }
  private edit(entry?: ScheduleEntry): void {
    if (entry?.kind === 'memo' && entry.content === undefined) { this.readMemo(entry); return }
    this.selectedId = entry?.id || ''; this.selectedCalendar = entry?.calendarId === undefined ? -1 : entry.calendarId
    this.selectedEvent = entry?.eventId === undefined ? -1 : entry.eventId
    this.title = entry?.title || ''; this.content = entry?.content || ''
    if (entry?.start) this.start = ScheduleService.localLabel(Date.parse(entry.start))
    if (entry?.end) this.end = ScheduleService.localLabel(Date.parse(entry.end))
    this.setEditing(true)
  }
  private setEditing(value: boolean): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.editing = value)
  }
  private setReminderKind(value: string): void {
    this.getUIContext().animateTo({ duration: UiMotion.section, curve: Curve.EaseOut }, () => this.reminderKind = value)
  }

  private async readMemo(entry: ScheduleEntry): Promise<void> {
    const platform = IntegrationService.schedule
    if (this.busy || platform === undefined) return
    const token = ++this.serial
    this.busy = true
    const result = await ScheduleService.execute({ id: `memo-read-${token}`, name: 'manage_memo',
      arguments: JSON.stringify({ action: 'read', id: entry.id }) }, platform, () => this.alive && token === this.serial, async () => false)
    if (!this.alive || token !== this.serial) return
    if (result.ok && result.entries?.[0]) this.edit(result.entries[0])
    else this.notice = result.message
    this.busy = false
  }
  private calendarForm(): boolean { return this.tab === 'calendar' || this.selectedEvent >= 0 }
  private save(): void {
    try {
      if (this.tab === 'memos') {
        this.run('manage_memo', { action: 'save', id: this.selectedId || undefined, title: this.title, content: this.content }); return
      }
      if (this.calendarForm()) {
        if (this.selectedEvent >= 0) this.run('update_calendar_event', { calendarId: this.selectedCalendar, eventId: this.selectedEvent,
          title: this.title, start: ScheduleService.localInstant(this.start), end: ScheduleService.localInstant(this.end) })
        else this.run('create_calendar_event', { title: this.title, start: ScheduleService.localInstant(this.start), end: ScheduleService.localInstant(this.end), description: this.content, reminderMinutes: [10] })
        return
      }
      const parts = this.alarmTime.split(':')
      const args: ScheduleArgs = { kind: this.reminderKind, title: this.title, content: this.content }
      if (this.reminderKind === 'alarm') { args.hour = Number(parts[0]); args.minute = parts.length === 2 ? Number(parts[1]) : -1 }
      else if (this.reminderKind === 'timer') args.seconds = Number(this.seconds)
      else args.at = ScheduleService.localInstant(this.start)
      this.run('create_system_reminder', args)
    } catch (error) { this.notice = (error as Error).message }
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
    TextInput({ text: value, placeholder: label }).fontSize(13 * this.fontScale).placeholderFont({ size: 13 * this.fontScale })
      .width('100%').height(34 * this.fontScale).padding({ left: 10, right: 10, top: 0, bottom: 0 })
      .backgroundColor(UiTheme.raised).borderRadius(6).id(id).focusFeedback().onChange(update)
  }

  build() {
    Column({ space: 12 * this.fontScale }) {
      if (!this.embedded) { Row() {
        Text('日程与提醒').fontSize(20 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).layoutWeight(1)
        Button('关闭').fontSize(12 * this.fontScale).height(32 * this.fontScale).fontColor(UiTheme.text).backgroundColor(UiTheme.raised)
          .id('system-schedule-close').interactive().onClick(() => this.onClose())
      }.width('100%') }
      Text(this.currentTime).fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).width('100%').id('system-current-time')
        .interactive().onClick(() => this.refreshTime())
      Row({ space: 8 * this.fontScale }) {
        if (!this.embedded) {
          SelectionTab({ label: '日历', selected: this.tab === 'calendar', showIndicator: false,
            itemId: 'system-tab-calendar', disabled: this.busy,
            onSelect: () => this.switchTab('calendar') })
          SelectionTab({ label: '提醒', selected: this.tab === 'reminders', showIndicator: false,
            itemId: 'system-tab-reminders', disabled: this.busy,
            onSelect: () => this.switchTab('reminders') })
          SelectionTab({ label: '备忘录', selected: this.tab === 'memos', showIndicator: false,
            itemId: 'system-tab-memos', disabled: this.busy,
            onSelect: () => this.switchTab('memos') })
        }
        Blank()
        Button(this.busy ? '处理中' : '刷新').fontSize(12 * this.fontScale).height(32 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .id('system-schedule-refresh').enabled(!this.busy).interactive().onClick(() => { this.refreshTime(); this.refreshEntries() })
        Button('新建').fontSize(12 * this.fontScale).height(32 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
          .id('system-schedule-new').enabled(!this.busy).interactive().onClick(() => this.edit())
      }.width('100%')
      Row({ space: 8 * this.fontScale }) {
        if (this.busy) { LoadingProgress().width(16 * this.fontScale).height(16 * this.fontScale).color(UiTheme.secondary).transition(UiMotion.fade()) }
        Text(this.notice).fontSize(12 * this.fontScale).lineHeight(18 * this.fontScale).fontColor(UiTheme.secondary).layoutWeight(1).id('system-schedule-notice')
      }.width('100%')
      Scroll() {
        Column({ space: 10 * this.fontScale }) {
          if (this.editing) {
            Column({ space: 8 * this.fontScale }) {
              this.Field('标题', this.title, 'system-entry-title', (value: string) => this.title = value)
              if (this.calendarForm() || (this.tab === 'reminders' && this.reminderKind === 'calendar')) {
                this.Field('开始时间（本地时间，例如2026-10-28 09:00）', this.start, 'system-entry-start', (value: string) => this.start = value)
                if (this.calendarForm()) this.Field('结束时间（本地时间）', this.end, 'system-entry-end', (value: string) => this.end = value)
              }
              if (this.tab === 'reminders' && !this.calendarForm()) {
                Row({ space: 8 }) {
                  Button(this.reminderKind === 'alarm' ? '✓ 闹钟' : '闹钟').fontSize(11 * this.fontScale).height(30 * this.fontScale)
                    .backgroundColor(UiTheme.surface).fontColor(UiTheme.text).interactive().onClick(() => this.setReminderKind('alarm'))
                  Button(this.reminderKind === 'timer' ? '✓ 倒计时' : '倒计时').fontSize(11 * this.fontScale).height(30 * this.fontScale)
                    .backgroundColor(UiTheme.surface).fontColor(UiTheme.text).interactive().onClick(() => this.setReminderKind('timer'))
                  Button(this.reminderKind === 'calendar' ? '✓ 日期提醒' : '日期提醒').fontSize(11 * this.fontScale).height(30 * this.fontScale)
                    .backgroundColor(UiTheme.surface).fontColor(UiTheme.text).interactive().onClick(() => this.setReminderKind('calendar'))
                }
                if (this.reminderKind === 'alarm') this.Field('下次响铃时刻（设备时间 HH:mm）', this.alarmTime, 'system-alarm-time', (value: string) => this.alarmTime = value)
                else if (this.reminderKind === 'timer') this.Field('倒计时秒数', this.seconds, 'system-timer-seconds', (value: string) => this.seconds = value)
              }
              if (!this.calendarForm() || this.selectedEvent < 0) {
                TextArea({ text: this.content, placeholder: this.tab === 'memos' ? '备忘录正文' : '说明（选填）' }).fontSize(13 * this.fontScale)
                  .placeholderFont({ size: 13 * this.fontScale }).width('100%').height(72 * this.fontScale).maxLength(8000)
                  .backgroundColor(UiTheme.surface).id('system-entry-content').focusFeedback().onChange((value: string) => this.content = value)
              }
              if (this.tab === 'calendar' && this.selectedEvent < 0) { Text('新日程默认提前10分钟提醒。').fontSize(11 * this.fontScale).fontColor(UiTheme.secondary) }
              Row({ space: 10 }) {
                Button('收起').height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.surface).fontColor(UiTheme.text).enabled(!this.busy).interactive().onClick(() => this.setEditing(false))
                Button('核对并保存').height(30 * this.fontScale).fontSize(12 * this.fontScale).backgroundColor(UiTheme.primary).fontColor(UiTheme.surface)
                  .id('system-entry-save').enabled(!this.busy && this.title.trim().length > 0).interactive().onClick(() => this.save())
              }
            }.padding(12 * this.fontScale).width('100%').backgroundColor(UiTheme.raised).borderRadius(8).enabled(!this.busy)
              .transition(UiMotion.reveal()).id('system-schedule-editor')
          }
          ForEach(this.entries, (entry: ScheduleEntry) => {
            Column({ space: 7 * this.fontScale }) {
              Text(entry.title).fontSize(14 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
              Text(entry.detail).fontSize(12 * this.fontScale).lineHeight(19 * this.fontScale).fontColor(UiTheme.secondary).width('100%').copyOption(CopyOptions.InApp)
              Row({ space: 8 }) {
                if (entry.kind !== 'reminder') {
                  Button('修改').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .id(`system-edit-${entry.id}`).interactive().onClick(() => this.edit(entry))
                }
                if (entry.kind === 'memo') {
                  Button('系统分享').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                    .id(`system-share-${entry.id}`).interactive().onClick(() => this.run('manage_memo', { action: 'share', id: entry.id }))
                }
                Button(entry.kind === 'reminder' ? '取消提醒' : '删除').height(28 * this.fontScale).fontSize(11 * this.fontScale).backgroundColor(UiTheme.raised).fontColor(UiTheme.text)
                  .id(`system-delete-${entry.id}`).interactive().onClick(() => {
                    if (entry.kind === 'memo') this.run('manage_memo', { action: 'delete', id: entry.id })
                    else if (entry.kind === 'reminder') this.run('cancel_system_reminder', { reminderId: entry.reminderId })
                    else this.run('delete_calendar_event', { calendarId: entry.calendarId, eventId: entry.eventId })
                  })
              }.enabled(!this.busy)
            }.width('100%').padding(12 * this.fontScale).border({ width: 1, color: UiTheme.border }).borderRadius(8).id(`system-result-${entry.id}`)
              .transition(UiMotion.reveal())
          }, (entry: ScheduleEntry) => `${entry.id}-${entry.detail}`)
          if (!this.busy && !this.editing && this.entries.length === 0) {
            Text(this.tab === 'calendar' ? '当前范围没有可显示的日程。' : this.tab === 'memos' ? '暂无备忘录。' : '暂无可显示的提醒；设置失败的闹钟不会列为已生效。')
              .fontSize(12 * this.fontScale).fontColor(UiTheme.muted).padding(16 * this.fontScale).width('100%').id('system-schedule-empty').transition(UiMotion.fade())
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
    }.padding(22 * this.fontScale).width('100%').height('100%').backgroundColor(UiTheme.surface)
  }
}

export interface AppThemeOption {
  id: string
  name: string
  detail: string
  swatches: string[]
}

interface ThemePalette {
  background: string
  surface: string
  raised: string
  border: string
  text: string
  secondary: string
  muted: string
  primary: string
  onPrimary: string
  focus: string
  shadow: string
  userBubble: string
  agentBubble: string
  choiceSelectedText: string
  choiceUnselectedText: string
  choiceSelectedBackground: string
  choiceUnselectedBackground: string
  choiceSelectedBorder: string
  choiceIndicator: string
  darkSelectionText: string
  darkUnselectedText: string
  darkMutedText: string
  darkSelectionBackground: string
  darkRailSelectionBackground: string
  darkSidebarSection: string
  darkSidebar: string
  darkRail: string
  darkDrawer: string
  darkControl: string
  darkDivider: string
  darkScrollbar: string
  scrim: string
  scrimSoft: string
  darkSelectionChannel: number
  darkUnselectedChannel: number
  softSurface: string
  softSurfaceAlt: string
  softBorder: string
  softText: string
  softMuted: string
  softBlue: string
  softGreen: string
  softSand: string
  accent: string
  accentStrong: string
  accentSoft: string
  accentPale: string
  accentBorder: string
  selection: string
  onAccent: string
  danger: string
  iconAccent: string
  iconMuted: string
  iconOnAccent: string
  chartInk: string
  chartMid: string
  chartLight: string
  chartPale: string
  chartGrid: string
  heatOutside: string
  cardShadow: string
}

const CLASSIC: ThemePalette = {
  background: '#F4F8F9', surface: '#FBFDFD', raised: '#EDF3F4', border: '#DCE7E9',
  text: '#31464D', secondary: '#62777E', muted: '#7A8D93', primary: '#486A78',
  onPrimary: '#F7FCFD', focus: '#6E98A8', shadow: '#161C323C', userBubble: '#E3EFF1',
  agentBubble: '#FBFDFD', choiceSelectedText: '#31464D', choiceUnselectedText: '#71868D',
  choiceSelectedBackground: '#E5EFF2', choiceUnselectedBackground: '#00000000',
  choiceSelectedBorder: '#C9DADF', choiceIndicator: '#486A78', darkSelectionText: '#EEF6F8',
  darkUnselectedText: '#B7C8CE', darkMutedText: '#91AAB2', darkSelectionBackground: '#3D5F69',
  darkRailSelectionBackground: '#3F626D', darkSidebarSection: '#34545E', darkSidebar: '#29444D',
  darkRail: '#2B4650', darkDrawer: '#223B44', darkControl: '#36545E', darkDivider: '#47636C',
  darkScrollbar: '#78939B', scrim: '#3824353D', scrimSoft: '#1424353D',
  darkSelectionChannel: 68, darkUnselectedChannel: 137, softSurface: '#EEF5F6',
  softSurfaceAlt: '#F0F6F4', softBorder: '#DCE8EA', softText: '#31464D', softMuted: '#71878E',
  softBlue: '#91B4C2', softGreen: '#92BAAE', softSand: '#C9B49F', accent: '#4D7380',
  accentStrong: '#3A5D69', accentSoft: '#DCE9ED', accentPale: '#EAF3F5',
  accentBorder: '#C7DCE2', selection: '#D8E6E9', onAccent: '#F7FCFD', danger: '#A45F62',
  iconAccent: '#4B6F7B', iconMuted: '#71878E', iconOnAccent: '#F7FCFD',
  chartInk: '#446C79', chartMid: '#7199A5', chartLight: '#AEC8D0', chartPale: '#D9E8EC',
  chartGrid: '#E2ECEE', heatOutside: '#F1F6F7', cardShadow: '#140E2B34'
}

const MIST: ThemePalette = {
  background: '#F3F6FA', surface: '#FCFDFE', raised: '#EBF1F5', border: '#D8E3EA',
  text: '#354A57', secondary: '#617886', muted: '#7B8F99', primary: '#4F7083',
  onPrimary: '#F8FCFE', focus: '#7594A5', shadow: '#161C2E3A', userBubble: '#E4EEF4',
  agentBubble: '#FCFDFE', choiceSelectedText: '#354A57', choiceUnselectedText: '#728895',
  choiceSelectedBackground: '#E7EFF4', choiceUnselectedBackground: '#00000000',
  choiceSelectedBorder: '#C9DAE4', choiceIndicator: '#4F7083', darkSelectionText: '#EEF5F9',
  darkUnselectedText: '#B9C8D1', darkMutedText: '#94A9B5', darkSelectionBackground: '#426171',
  darkRailSelectionBackground: '#456575', darkSidebarSection: '#3A5664', darkSidebar: '#2F4855',
  darkRail: '#314B58', darkDrawer: '#283F4B', darkControl: '#3B5866', darkDivider: '#4D6874',
  darkScrollbar: '#8199A5', scrim: '#3823313B', scrimSoft: '#1423313B',
  darkSelectionChannel: 72, darkUnselectedChannel: 145, softSurface: '#EDF3F7',
  softSurfaceAlt: '#EFF5F7', softBorder: '#D9E4EB', softText: '#354A57', softMuted: '#728895',
  softBlue: '#95B4C8', softGreen: '#91B9B4', softSand: '#C8B9A8', accent: '#527486',
  accentStrong: '#3E5E6E', accentSoft: '#DDEAF0', accentPale: '#EAF2F6',
  accentBorder: '#C8DBE3', selection: '#D9E7EE', onAccent: '#F8FCFE', danger: '#A15F66',
  iconAccent: '#4D6E80', iconMuted: '#728895', iconOnAccent: '#F8FCFE',
  chartInk: '#486B7B', chartMid: '#7595A5', chartLight: '#B2C7D2', chartPale: '#DCE9EF',
  chartGrid: '#E4EDF2', heatOutside: '#F1F6F8', cardShadow: '#140D2632'
}

const PINE: ThemePalette = {
  background: '#F4F8F6', surface: '#FBFDFC', raised: '#ECF3F0', border: '#D9E6E1',
  text: '#354C46', secondary: '#627A73', muted: '#7D918B', primary: '#4D7268',
  onPrimary: '#F7FCFA', focus: '#75998E', shadow: '#161C3029', userBubble: '#E3F0EB',
  agentBubble: '#FBFDFC', choiceSelectedText: '#354C46', choiceUnselectedText: '#728A83',
  choiceSelectedBackground: '#E6F0EC', choiceUnselectedBackground: '#00000000',
  choiceSelectedBorder: '#CADED7', choiceIndicator: '#4D7268', darkSelectionText: '#EEF8F4',
  darkUnselectedText: '#B7CBC4', darkMutedText: '#93ADA5', darkSelectionBackground: '#42665D',
  darkRailSelectionBackground: '#456A60', darkSidebarSection: '#3A5B52', darkSidebar: '#2F4C45',
  darkRail: '#31504A', darkDrawer: '#28443E', darkControl: '#3A5D54', darkDivider: '#4C6B63',
  darkScrollbar: '#809D95', scrim: '#3823312D', scrimSoft: '#1423312D',
  darkSelectionChannel: 66, darkUnselectedChannel: 139, softSurface: '#EDF5F1',
  softSurfaceAlt: '#F0F6F2', softBorder: '#D9E7E1', softText: '#354C46', softMuted: '#728A83',
  softBlue: '#93B8B2', softGreen: '#91BBAE', softSand: '#C7B8A5', accent: '#52776D',
  accentStrong: '#3B5F56', accentSoft: '#DCECE6', accentPale: '#EAF3EF',
  accentBorder: '#C8DDD5', selection: '#D7E7E1', onAccent: '#F7FCFA', danger: '#9B6262',
  iconAccent: '#4C6F66', iconMuted: '#728A83', iconOnAccent: '#F7FCFA',
  chartInk: '#486E64', chartMid: '#75988E', chartLight: '#AFC9C1', chartPale: '#D9E9E3',
  chartGrid: '#E3ECE8', heatOutside: '#F1F7F4', cardShadow: '#140D2C25'
}

const DUSK: ThemePalette = {
  background: '#F7F5F9', surface: '#FDFCFE', raised: '#F1EEF4', border: '#E4DEE8',
  text: '#4A4250', secondary: '#766B7D', muted: '#8C8192', primary: '#75657F',
  onPrimary: '#FCFAFE', focus: '#9A88A5', shadow: '#161D1620', userBubble: '#EFE9F2',
  agentBubble: '#FDFCFE', choiceSelectedText: '#4A4250', choiceUnselectedText: '#877B8D',
  choiceSelectedBackground: '#EEE8F1', choiceUnselectedBackground: '#00000000',
  choiceSelectedBorder: '#DED4E3', choiceIndicator: '#75657F', darkSelectionText: '#F5F0F7',
  darkUnselectedText: '#CABFD0', darkMutedText: '#A99BAD', darkSelectionBackground: '#66566F',
  darkRailSelectionBackground: '#695972', darkSidebarSection: '#584A60', darkSidebar: '#493D50',
  darkRail: '#4B4052', darkDrawer: '#403547', darkControl: '#5B4D63', darkDivider: '#65576C',
  darkScrollbar: '#9C8EA2', scrim: '#382E2633', scrimSoft: '#142E2633',
  darkSelectionChannel: 80, darkUnselectedChannel: 151, softSurface: '#F3F0F5',
  softSurfaceAlt: '#F4F1F6', softBorder: '#E6DFEA', softText: '#4A4250', softMuted: '#877B8D',
  softBlue: '#A9A7C0', softGreen: '#A4B8AE', softSand: '#C7B4AB', accent: '#75657F',
  accentStrong: '#5E5068', accentSoft: '#EAE3EE', accentPale: '#F1ECF4',
  accentBorder: '#DED2E4', selection: '#E8E0EC', onAccent: '#FCFAFE', danger: '#9D6269',
  iconAccent: '#716176', iconMuted: '#877B8D', iconOnAccent: '#FCFAFE',
  chartInk: '#6B5C73', chartMid: '#96839F', chartLight: '#C4B5CB', chartPale: '#E9E1ED',
  chartGrid: '#EEE7F1', heatOutside: '#F7F3F8', cardShadow: '#140F191D'
}

const MONO: ThemePalette = {
  background: '#F5F5F5', surface: '#FCFCFC', raised: '#EEEEEE', border: '#DADADA',
  text: '#333333', secondary: '#666666', muted: '#8A8A8A', primary: '#555555',
  onPrimary: '#FCFCFC', focus: '#808080', shadow: '#1A000000', userBubble: '#E9E9E9',
  agentBubble: '#FCFCFC', choiceSelectedText: '#333333', choiceUnselectedText: '#888888',
  choiceSelectedBackground: '#E8E8E8', choiceUnselectedBackground: '#00000000',
  choiceSelectedBorder: '#CFCFCF', choiceIndicator: '#555555', darkSelectionText: '#F2F2F2',
  darkUnselectedText: '#C7C7C7', darkMutedText: '#A3A3A3', darkSelectionBackground: '#5A5A5A',
  darkRailSelectionBackground: '#5A5A5A', darkSidebarSection: '#474747', darkSidebar: '#3D3D3D',
  darkRail: '#414141', darkDrawer: '#383838', darkControl: '#4D4D4D', darkDivider: '#606060',
  darkScrollbar: '#969696', scrim: '#3D1F1F1F', scrimSoft: '#171F1F1F',
  darkSelectionChannel: 90, darkUnselectedChannel: 199, softSurface: '#F1F1F1',
  softSurfaceAlt: '#F3F3F3', softBorder: '#DFDFDF', softText: '#333333', softMuted: '#858585',
  softBlue: '#B4B4B4', softGreen: '#B7B7B7', softSand: '#C5C5C5', accent: '#5B5B5B',
  accentStrong: '#444444', accentSoft: '#E6E6E6', accentPale: '#EDEDED',
  accentBorder: '#D5D5D5', selection: '#E2E2E2', onAccent: '#FCFCFC', danger: '#8C6666',
  iconAccent: '#5B5B5B', iconMuted: '#858585', iconOnAccent: '#FCFCFC',
  chartInk: '#555555', chartMid: '#7A7A7A', chartLight: '#ABABAB', chartPale: '#DCDCDC',
  chartGrid: '#E6E6E6', heatOutside: '#F2F2F2', cardShadow: '#1A000000'
}

export class UiTheme {
  static readonly defaultThemeId: string = 'classic'
  static readonly iconIvory: string = '#FFF8E8'
  static readonly iconIvoryMuted: string = '#EEE1C7'
  static readonly iconNavIvory: string = '#FFFFF0'
  private static selectedThemeId: string = UiTheme.defaultThemeId

  static themes(): AppThemeOption[] {
    return [
      { id: 'classic', name: '经典青灰', detail: '当前默认配色', swatches: ['#486A78', '#EAF3F5', '#F4F8F9'] },
      { id: 'mono', name: '黑白灰', detail: '参考仓库的简约中性色', swatches: ['#5B5B5B', '#EDEDED', '#F5F5F5'] },
      { id: 'mist', name: '海盐蓝', detail: '清透冷静的蓝灰色', swatches: ['#4F7083', '#EAF2F6', '#F3F6FA'] },
      { id: 'pine', name: '青岚绿', detail: '柔和自然的青绿色', swatches: ['#4D7268', '#EAF3EF', '#F4F8F6'] },
      { id: 'dusk', name: '雾紫灰', detail: '低饱和的灰紫调', swatches: ['#75657F', '#F1ECF4', '#F7F5F9'] }
    ]
  }

  static normalizeTheme(id?: string): string {
    return UiTheme.themes().some((option: AppThemeOption) => option.id === id) ? id as string : UiTheme.defaultThemeId
  }

  static setTheme(id?: string): string {
    UiTheme.selectedThemeId = UiTheme.normalizeTheme(id)
    return UiTheme.selectedThemeId
  }

  static activeTheme(): string { return UiTheme.selectedThemeId }

  private static palette(): ThemePalette {
    if (UiTheme.selectedThemeId === 'mono') return MONO
    if (UiTheme.selectedThemeId === 'mist') return MIST
    if (UiTheme.selectedThemeId === 'pine') return PINE
    if (UiTheme.selectedThemeId === 'dusk') return DUSK
    return CLASSIC
  }

  static get background(): string { return UiTheme.palette().background }
  static get surface(): string { return UiTheme.palette().surface }
  static get raised(): string { return UiTheme.palette().raised }
  static get border(): string { return UiTheme.palette().border }
  static get text(): string { return UiTheme.palette().text }
  static get secondary(): string { return UiTheme.palette().secondary }
  static get muted(): string { return UiTheme.palette().muted }
  static get primary(): string { return UiTheme.palette().primary }
  static get onPrimary(): string { return UiTheme.palette().onPrimary }
  static get focus(): string { return UiTheme.palette().focus }
  static get shadow(): string { return UiTheme.palette().shadow }
  static get userBubble(): string { return UiTheme.palette().userBubble }
  static get agentBubble(): string { return UiTheme.palette().agentBubble }
  static get choiceSelectedText(): string { return UiTheme.palette().choiceSelectedText }
  static get choiceUnselectedText(): string { return UiTheme.palette().choiceUnselectedText }
  static get choiceSelectedBackground(): string { return UiTheme.palette().choiceSelectedBackground }
  static get choiceUnselectedBackground(): string { return UiTheme.palette().choiceUnselectedBackground }
  static get choiceSelectedBorder(): string { return UiTheme.palette().choiceSelectedBorder }
  static get choiceIndicator(): string { return UiTheme.palette().choiceIndicator }
  static get darkSelectionText(): string { return UiTheme.palette().darkSelectionText }
  static get darkUnselectedText(): string { return UiTheme.palette().darkUnselectedText }
  static get darkMutedText(): string { return UiTheme.palette().darkMutedText }
  static get darkSelectionBackground(): string { return UiTheme.palette().darkSelectionBackground }
  static get darkRailSelectionBackground(): string { return UiTheme.palette().darkRailSelectionBackground }
  static get darkSidebarSection(): string { return UiTheme.palette().darkSidebarSection }
  static get darkSidebar(): string { return UiTheme.palette().darkSidebar }
  static get darkRail(): string { return UiTheme.palette().darkRail }
  static get darkDrawer(): string { return UiTheme.palette().darkDrawer }
  static get darkControl(): string { return UiTheme.palette().darkControl }
  static get darkDivider(): string { return UiTheme.palette().darkDivider }
  static get darkScrollbar(): string { return UiTheme.palette().darkScrollbar }
  static get scrim(): string { return UiTheme.palette().scrim }
  static get scrimSoft(): string { return UiTheme.palette().scrimSoft }
  static get darkSelectionChannel(): number { return UiTheme.palette().darkSelectionChannel }
  static get darkUnselectedChannel(): number { return UiTheme.palette().darkUnselectedChannel }
  static get softSurface(): string { return UiTheme.palette().softSurface }
  static get softSurfaceAlt(): string { return UiTheme.palette().softSurfaceAlt }
  static get softBorder(): string { return UiTheme.palette().softBorder }
  static get softText(): string { return UiTheme.palette().softText }
  static get softMuted(): string { return UiTheme.palette().softMuted }
  static get softBlue(): string { return UiTheme.palette().softBlue }
  static get softGreen(): string { return UiTheme.palette().softGreen }
  static get softSand(): string { return UiTheme.palette().softSand }
  static get accent(): string { return UiTheme.palette().accent }
  static get accentStrong(): string { return UiTheme.palette().accentStrong }
  static get accentSoft(): string { return UiTheme.palette().accentSoft }
  static get accentPale(): string { return UiTheme.palette().accentPale }
  static get accentBorder(): string { return UiTheme.palette().accentBorder }
  static get selection(): string { return UiTheme.palette().selection }
  static get onAccent(): string { return UiTheme.palette().onAccent }
  static get danger(): string { return UiTheme.palette().danger }
  static get iconAccent(): string { return UiTheme.iconIvory }
  static get iconMuted(): string { return UiTheme.iconIvoryMuted }
  static get iconOnAccent(): string { return UiTheme.iconIvory }
  static get chartInk(): string { return UiTheme.palette().chartInk }
  static get chartMid(): string { return UiTheme.palette().chartMid }
  static get chartLight(): string { return UiTheme.palette().chartLight }
  static get chartPale(): string { return UiTheme.palette().chartPale }
  static get chartGrid(): string { return UiTheme.palette().chartGrid }
  static get heatOutside(): string { return UiTheme.palette().heatOutside }
  static get cardShadow(): string { return UiTheme.palette().cardShadow }
}

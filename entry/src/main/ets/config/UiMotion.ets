import { observeReducedMotion } from './ReducedMotionCompat'

// Shared motion tokens. Data operations never wait for an animation.
export class UiMotion {
  private static readonly exitDuration: number = 90
  private static readonly pressDuration: number = 120
  private static readonly fastDuration: number = 160
  private static readonly sectionDuration: number = 180
  private static readonly pageBaseDuration: number = 210
  private static readonly panelDuration: number = 220
  static readonly enterCurve: Curve = Curve.EaseOut
  static readonly moveCurve: Curve = Curve.EaseInOut
  private static reduceMotion: boolean = false
  private static stopObserving: (() => void) | undefined = undefined

  static get exit(): number { return UiMotion.duration(UiMotion.exitDuration) }
  static get press(): number { return UiMotion.duration(UiMotion.pressDuration) }
  static get fast(): number { return UiMotion.duration(UiMotion.fastDuration) }
  static get section(): number { return UiMotion.duration(UiMotion.sectionDuration) }
  static get pageDuration(): number { return UiMotion.duration(UiMotion.pageBaseDuration) }
  static get panel(): number { return UiMotion.duration(UiMotion.panelDuration) }

  static initialize(): void {
    if (UiMotion.stopObserving !== undefined) return
    UiMotion.stopObserving = observeReducedMotion((enabled: boolean): void => {
      UiMotion.reduceMotion = enabled
    })
  }

  static dispose(): void {
    UiMotion.stopObserving?.()
    UiMotion.stopObserving = undefined
    UiMotion.reduceMotion = false
  }
  static reduced(): boolean {
    return UiMotion.reduceMotion
  }

  static duration(value: number): number {
    return UiMotion.reduceMotion ? 0 : value
  }

  static page(): TransitionEffect {
    if (UiMotion.reduceMotion) {
      return TransitionEffect.opacity(0).animation({ duration: 0, curve: Curve.Linear })
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: UiMotion.pageDuration, curve: UiMotion.enterCurve }),
      TransitionEffect.opacity(0).animation({ duration: UiMotion.exit, curve: UiMotion.enterCurve }))
  }

  static reveal(): TransitionEffect {
    if (UiMotion.reduceMotion) {
      return TransitionEffect.opacity(0).animation({ duration: 0, curve: Curve.Linear })
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 5 }))
        .animation({ duration: UiMotion.section, curve: UiMotion.enterCurve }),
      TransitionEffect.opacity(0).animation({ duration: UiMotion.press, curve: UiMotion.enterCurve }))
  }

  static fade(): TransitionEffect {
    return TransitionEffect.opacity(0).animation({
      duration: UiMotion.duration(UiMotion.press),
      curve: UiMotion.enterCurve
    })
  }
}

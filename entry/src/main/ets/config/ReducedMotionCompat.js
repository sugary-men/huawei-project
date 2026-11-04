import accessibility from '@ohos.accessibility'

// API 22 does not declare these optional methods. Keep the SDK boundary in JS
// so an API 22 ArkTS compiler only needs the stable declaration next to this file.
export function observeReducedMotion(onChange) {
  const noop = () => {}
  let enabled = false
  if (typeof accessibility.isAnimationReduceEnabledSync === 'function') {
    try { enabled = accessibility.isAnimationReduceEnabledSync() } catch (_) {}
  }
  onChange(enabled)
  if (typeof accessibility.onAnimationReduceStateChange !== 'function' ||
      typeof accessibility.offAnimationReduceStateChange !== 'function') return noop
  try { accessibility.onAnimationReduceStateChange(onChange) } catch (_) { return noop }
  return () => {
    try { accessibility.offAnimationReduceStateChange(onChange) } catch (_) {}
  }
}

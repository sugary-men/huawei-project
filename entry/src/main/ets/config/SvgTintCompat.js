import deviceInfo from '@ohos.deviceInfo'

// The color overload is absent from API 22 type declarations. Keep it on the
// JS side of the same SDK boundary as the runtime check.
const modifiers = new Map()
export function svgGlyph(color) {
  if (!modifiers.has(color)) {
    let tint = color
    if (!(deviceInfo.sdkApiVersion >= 26)) {
      const rgb = Number.parseInt(color.slice(1), 16)
      // Derive RGB from alpha, avoiding renderer-specific offset units.
      tint = new ColorFilter([0, 0, 0, ((rgb >> 16) & 255) / 255, 0,
        0, 0, 0, ((rgb >> 8) & 255) / 255, 0, 0, 0, 0, (rgb & 255) / 255, 0, 0, 0, 0, 1, 0])
    }
    modifiers.set(color, { applyNormalAttribute(image) {
      if (deviceInfo.sdkApiVersion >= 21 && deviceInfo.sdkApiVersion < 26) image.supportSvg2(true)
      image.colorFilter(tint)
    } })
  }
  return modifiers.get(color)
}

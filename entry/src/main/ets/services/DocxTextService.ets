import { util } from '@kit.ArkTS'
import { zlib } from '@kit.BasicServicesKit'

// Read only word/document.xml from the archive, never extract ZIP paths onto disk.
export class DocxTextService {
  static async extract(buffer: ArrayBuffer): Promise<string> {
    const view = new DataView(buffer)
    let end = buffer.byteLength - 22
    const lower = Math.max(0, end - 65535)
    while (end >= lower && view.getUint32(end, true) !== 0x06054b50) end--
    if (end < lower) throw new Error('DOCX 文件损坏，无法读取。')
    const count = view.getUint16(end + 10, true)
    let offset = view.getUint32(end + 16, true)
    if (count > 4000) throw new Error('DOCX 内容过于复杂，请先转为文本。')
    for (let i = 0; i < count; i++) {
      if (offset + 46 > buffer.byteLength || view.getUint32(offset, true) !== 0x02014b50) break
      const nameLength = view.getUint16(offset + 28, true)
      const extraLength = view.getUint16(offset + 30, true)
      const commentLength = view.getUint16(offset + 32, true)
      const name = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer, offset + 46, nameLength))
      if (name === 'word/document.xml') {
        if ((view.getUint16(offset + 8, true) & 1) !== 0) throw new Error('暂不支持加密 DOCX。')
        const method = view.getUint16(offset + 10, true)
        const compressedSize = view.getUint32(offset + 20, true)
        const size = view.getUint32(offset + 24, true)
        const local = view.getUint32(offset + 42, true)
        if (size > 4 * 1024 * 1024 || local + 30 > buffer.byteLength || view.getUint32(local, true) !== 0x04034b50) {
          throw new Error('DOCX 正文过大或文件结构无法读取。')
        }
        const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true)
        if (start + compressedSize > buffer.byteLength) throw new Error('DOCX 内容不完整。')
        const packed = buffer.slice(start, start + compressedSize)
        let xmlBytes: ArrayBuffer
        if (method === 0) xmlBytes = packed
        else if (method === 8) {
          const zip = await zlib.createZip()
          const stream: zlib.ZStream = { nextIn: packed, availableIn: packed.byteLength,
            nextOut: new ArrayBuffer(size), availableOut: size, totalOut: 0 }
          await zip.inflateInit2(stream, -15)
          try {
            const result = await zip.inflate(stream, zlib.CompressFlushMode.FINISH)
            if (result !== zlib.ReturnStatus.STREAM_END || stream.totalOut !== size || stream.nextOut === undefined) {
              throw new Error('DOCX 正文解压失败。')
            }
            xmlBytes = stream.nextOut
          } finally { await zip.inflateEnd(stream) }
        } else throw new Error('DOCX 压缩格式不受支持。')
        const checksum = await zlib.createChecksum()
        if (await checksum.crc32(0, xmlBytes) !== view.getUint32(offset + 16, true)) throw new Error('DOCX 正文校验失败。')
        return DocxTextService.fromXml(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(xmlBytes)))
      }
      offset += 46 + nameLength + extraLength + commentLength
    }
    throw new Error('未在 DOCX 中找到正文，请确认文件格式。')
  }

  static fromXml(xml: string): string {
    return xml.replace(/<w:(?:tab|br|cr)\b[^>]*\/?\s*>/g, '\n').replace(/<\/w:(?:p|tr)>/g, '\n')
      .replace(/<[^>]+>/g, '').replace(/&#x([0-9a-f]+);/gi, (_match: string, hex: string) => String.fromCodePoint(parseInt(hex, 16)))
      .replace(/&#([0-9]+);/g, (_match: string, value: string) => String.fromCodePoint(parseInt(value, 10)))
      .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
      .replace(/&amp;/g, '&').replace(/\n{3,}/g, '\n\n').trim()
  }
}

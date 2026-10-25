export interface MarkdownRun {
  text: string
  bold: boolean
  italic: boolean
  code: boolean
  strike: boolean
  link: boolean
}

export interface MarkdownRow { cells: string[] }

export interface MarkdownBlock {
  kind: string
  text: string
  level: number
  prefix: string
  language: string
  rows: MarkdownRow[]
}

export interface AnswerParts {
  summary: string
  body: string
  summarizing: boolean
}

// Pure presentation parser: output is rendered with native Text/Span, never HTML.
export class MarkdownParser {
  static answer(content: string): AnswerParts {
    const text = content.trimStart()
    if (text.startsWith('<summary>')) {
      const end = text.indexOf('</summary>')
      return end < 0 ? { summary: text.slice(9).trim(), body: '', summarizing: true }
        : { summary: text.slice(9, end).trim(), body: text.slice(end + 10).trim(), summarizing: false }
    }
    // Accept older saved answers, which put the summary under a Markdown heading.
    const heading = /^(#{1,6})[ \t]+(?:思路摘要|思考摘要)[：: \t]*\r?\n/.exec(text)
    if (heading !== null) {
      const rest = text.slice(heading[0].length)
      const boundary = /\n(?:[ \t]*(?:---+|\*\*\*+)[ \t]*(?:\r?\n|$)|#{1,6}[ \t]+)/.exec(rest)
      if (boundary === null) return { summary: rest.trim(), body: '', summarizing: true }
      const tail = rest.slice(boundary.index + 1).replace(/^[ \t]*(?:---+|\*\*\*+)[ \t]*(?:\r?\n|$)/, '')
      return { summary: rest.slice(0, boundary.index).trim(), body: tail.trim(), summarizing: false }
    }
    // Hide an incomplete opening tag while streaming it character by character.
    if ('<summary>'.startsWith(text) && text.startsWith('<')) return { summary: '', body: '', summarizing: true }
    return { summary: '', body: content, summarizing: false }
  }

  private static block(kind: string, text: string = ''): MarkdownBlock {
    return { kind: kind, text: text, level: 0, prefix: '', language: '', rows: [] }
  }

  private static divider(text: string): boolean {
    return /^\s{0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$/.test(text)
  }

  static cells(line: string): string[] {
    let text = line.trim()
    if (text.startsWith('|')) text = text.slice(1)
    if (text.endsWith('|') && !text.endsWith('\\|')) text = text.slice(0, -1)
    const result: string[] = []
    let cell = ''
    let code = false
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '\\' && text[i + 1] === '|') { cell += '|'; i++; continue }
      if (text[i] === '`') code = !code
      if (text[i] === '|' && !code) { result.push(cell.trim()); cell = '' } else cell += text[i]
    }
    result.push(cell.trim())
    return result
  }

  private static tableSeparator(line: string): boolean {
    const cells = MarkdownParser.cells(line)
    return cells.length >= 2 && cells.every((cell: string) => /^:?-{3,}:?$/.test(cell))
  }

  private static startsBlock(lines: string[], index: number): boolean {
    const text = lines[index]
    return text.trim().length === 0 || /^\s{0,3}(?:#{1,6}\s|```|~~~|>)/.test(text) ||
      /^\s*(?:[-+*]|\d+[.)])\s+/.test(text) || MarkdownParser.divider(text) ||
      (index + 1 < lines.length && MarkdownParser.tableSeparator(lines[index + 1]))
  }

  static parse(content: string): MarkdownBlock[] {
    const lines = content.replace(/\r\n?/g, '\n').split('\n')
    const blocks: MarkdownBlock[] = []
    let i = 0
    while (i < lines.length) {
      const line = lines[i]
      if (!line.trim()) { i++; continue }
      const fence = /^\s{0,3}(`{3,}|~{3,})(.*)$/.exec(line)
      if (fence !== null) {
        const block = MarkdownParser.block('code')
        block.language = fence[2].trim()
        const body: string[] = []
        i++
        while (i < lines.length && !(lines[i].trim().startsWith(fence[1]) &&
          lines[i].trim().replace(new RegExp(fence[1][0], 'g'), '').length === 0)) body.push(lines[i++])
        if (i < lines.length) i++
        block.text = body.join('\n')
        blocks.push(block)
        continue
      }
      if (i + 1 < lines.length && line.includes('|') && MarkdownParser.tableSeparator(lines[i + 1])) {
        const block = MarkdownParser.block('table')
        block.rows.push({ cells: MarkdownParser.cells(line) })
        const columns = block.rows[0].cells.length
        i += 2
        while (i < lines.length && lines[i].trim() && lines[i].includes('|')) {
          const cells = MarkdownParser.cells(lines[i++]).slice(0, columns)
          while (cells.length < columns) cells.push('')
          block.rows.push({ cells: cells })
        }
        blocks.push(block)
        continue
      }
      const heading = /^\s{0,3}(#{1,6})\s+(.+?)(?:\s+#+)?\s*$/.exec(line)
      if (heading !== null) {
        const block = MarkdownParser.block('heading', heading[2])
        block.level = heading[1].length
        blocks.push(block); i++; continue
      }
      if (i + 1 < lines.length && /^\s*(?:={3,}|-{3,})\s*$/.test(lines[i + 1])) {
        const block = MarkdownParser.block('heading', line)
        block.level = lines[i + 1].trim().startsWith('=') ? 1 : 2
        blocks.push(block); i += 2; continue
      }
      if (MarkdownParser.divider(line)) { blocks.push(MarkdownParser.block('divider')); i++; continue }
      const list = /^(\s*)([-+*]|\d+[.)])\s+(.*)$/.exec(line)
      if (list !== null) {
        const task = /^\[([ xX])\]\s+(.*)$/.exec(list[3])
        const block = MarkdownParser.block('list', task === null ? list[3] : task[2])
        block.level = Math.min(4, Math.floor(list[1].length / 2))
        block.prefix = task !== null ? (task[1] === ' ' ? '☐' : '☑') : /^\d/.test(list[2]) ? list[2] : '•'
        blocks.push(block); i++; continue
      }
      if (/^\s{0,3}>/.test(line)) {
        const body: string[] = []
        while (i < lines.length && /^\s{0,3}>/.test(lines[i])) body.push(lines[i++].replace(/^\s{0,3}>\s?/, ''))
        blocks.push(MarkdownParser.block('quote', body.join('\n')))
        continue
      }
      const body: string[] = [line]
      i++
      while (i < lines.length && !MarkdownParser.startsBlock(lines, i)) body.push(lines[i++])
      blocks.push(MarkdownParser.block('paragraph', body.join('\n')))
    }
    return blocks
  }

  static inline(text: string, bold: boolean = false, italic: boolean = false,
    strike: boolean = false, depth: number = 0): MarkdownRun[] {
    const runs: MarkdownRun[] = []
    let plain = ''
    const flush = (): void => {
      if (plain) runs.push({ text: plain, bold: bold, italic: italic, code: false, strike: strike, link: false })
      plain = ''
    }
    let i = 0
    while (i < text.length) {
      if (text[i] === '\\' && i + 1 < text.length && /[\\`*{}_\[\]()#+.!|>~-]/.test(text[i + 1])) {
        plain += text[i + 1]; i += 2; continue
      }
      if (text[i] === '`') {
        let length = 1
        while (text[i + length] === '`') length++
        const marker = '`'.repeat(length)
        const end = text.indexOf(marker, i + length)
        if (end >= 0) {
          flush()
          runs.push({ text: text.slice(i + length, end).replace(/\n/g, ' '), bold: bold,
            italic: false, code: true, strike: strike, link: false })
          i = end + length; continue
        }
      }
      const link = /^!?\[([^\]]+)\]\(([^\s)]+)(?:\s+"[^"]*")?\)/.exec(text.slice(i))
      if (link !== null) {
        flush()
        const image = text[i] === '!'
        runs.push({ text: image ? `图片：${link[1]}` : `${link[1]}（${link[2]}）`, bold: bold,
          italic: italic, code: false, strike: strike, link: !image })
        i += link[0].length; continue
      }
      const pair = text.slice(i, i + 2)
      const marker = pair === '**' || pair === '__' || pair === '~~' ? pair
        : text[i] === '*' || text[i] === '_' ? text[i] : ''
      if (marker && depth < 8 && !(marker === '_' && i > 0 && /[a-zA-Z0-9]/.test(text[i - 1]))) {
        const end = text.indexOf(marker, i + marker.length)
        if (end > i + marker.length) {
          flush()
          runs.push(...MarkdownParser.inline(text.slice(i + marker.length, end),
            marker.length === 2 && marker !== '~~' ? true : bold,
            marker.length === 1 ? true : italic, marker === '~~' ? true : strike, depth + 1))
          i = end + marker.length; continue
        }
      }
      plain += text[i++]
    }
    flush()
    return runs
  }
}

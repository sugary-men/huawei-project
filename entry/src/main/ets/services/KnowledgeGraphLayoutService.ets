import {
  KnowledgeGraphEdge,
  KnowledgeGraphLayout,
  KnowledgeGraphNode
} from '../models/KnowledgeGraphModels'
import { KnowledgeChunk } from '../models/RagModels'

interface RelatedNode {
  index: number
  score: number
}

export class KnowledgeGraphLayoutService {
  static build(baseId: string, baseName: string, chunks: KnowledgeChunk[],
    width: number, height: number): KnowledgeGraphLayout {
    const safeWidth = Math.max(240, width)
    const safeHeight = Math.max(300, height)
    const centerX = safeWidth / 2
    const centerY = safeHeight / 2
    const nodes: KnowledgeGraphNode[] = []
    const edges: KnowledgeGraphEdge[] = []
    const root: KnowledgeGraphNode = {
      id: `base:${baseId}`,
      kind: 'base',
      baseId: baseId,
      sourceId: '',
      chunkId: '',
      title: baseName || '当前知识库',
      detail: `${chunks.length} 个知识节点`,
      x: centerX - 76,
      y: centerY - 23,
      width: 152,
      height: 46
    }
    nodes.push(root)
    const goldenAngle = 2.399963229728653
    const radiusLimit = Math.max(86, Math.min(safeWidth, safeHeight) * 0.34)
    chunks.forEach((chunk: KnowledgeChunk, index: number) => {
      const ratio = chunks.length <= 1 ? 0 : Math.sqrt((index + 1) / chunks.length)
      const radius = 68 + ratio * radiusLimit
      const angle = index * goldenAngle - Math.PI / 2
      const node: KnowledgeGraphNode = {
        id: `chunk:${baseId}:${chunk.id}`,
        kind: 'chunk',
        baseId: baseId,
        sourceId: chunk.sourceId,
        chunkId: chunk.id,
        title: chunk.title || chunk.location || '知识片段',
        detail: `${chunk.location || '片段'} · ${KnowledgeGraphLayoutService.modalityLabel(chunk.modality || 'text')}`,
        x: centerX + Math.cos(angle) * radius - 68,
        y: centerY + Math.sin(angle) * radius - 21,
        width: 136,
        height: 42
      }
      nodes.push(node)
      edges.push({
        id: `root:${node.id}`,
        from: root.id,
        to: node.id,
        kind: 'branch',
        weight: 0.45
      })
    })

    const relationLimit = chunks.length > 80 ? 1 : 2
    for (let left = 0; left < chunks.length; left++) {
      const related: RelatedNode[] = []
      for (let right = left + 1; right < chunks.length; right++) {
        const score = KnowledgeGraphLayoutService.relationScore(chunks[left], chunks[right])
        if (score >= 0.32) related.push({ index: right, score: score })
      }
      related.sort((a: RelatedNode, b: RelatedNode): number => b.score - a.score)
      related.slice(0, relationLimit).forEach((item: RelatedNode) => {
        edges.push({
          id: `semantic:${chunks[left].id}:${chunks[item.index].id}`,
          from: nodes[left + 1].id,
          to: nodes[item.index + 1].id,
          kind: 'semantic',
          weight: item.score
        })
      })
    }
    KnowledgeGraphLayoutService.relax(nodes, safeWidth, safeHeight, chunks.length > 120 ? 4 : 10)
    return { nodes: nodes, edges: edges }
  }

  static avoidOverlap(node: KnowledgeGraphNode, nodes: KnowledgeGraphNode[],
    width: number, height: number): void {
    nodes.forEach((other: KnowledgeGraphNode) => {
      if (other.id === node.id) return
      const overlapX = (node.width + other.width) / 2 + 10 -
        Math.abs(node.x + node.width / 2 - other.x - other.width / 2)
      const overlapY = (node.height + other.height) / 2 + 8 -
        Math.abs(node.y + node.height / 2 - other.y - other.height / 2)
      if (overlapX <= 0 || overlapY <= 0) return
      if (overlapX < overlapY) {
        const direction = node.x + node.width / 2 < other.x + other.width / 2 ? -1 : 1
        node.x += direction * Math.min(18, overlapX * 0.55)
      } else {
        const direction = node.y + node.height / 2 < other.y + other.height / 2 ? -1 : 1
        node.y += direction * Math.min(18, overlapY * 0.55)
      }
    })
    node.x = Math.max(14, Math.min(Math.max(14, width - node.width - 14), node.x))
    node.y = Math.max(14, Math.min(Math.max(14, height - node.height - 14), node.y))
  }

  private static relax(nodes: KnowledgeGraphNode[], width: number, height: number,
    iterations: number): void {
    for (let iteration = 0; iteration < iterations; iteration++) {
      for (let left = 0; left < nodes.length; left++) {
        for (let right = left + 1; right < nodes.length; right++) {
          const a = nodes[left]
          const b = nodes[right]
          const overlapX = (a.width + b.width) / 2 + 10 -
            Math.abs(a.x + a.width / 2 - b.x - b.width / 2)
          const overlapY = (a.height + b.height) / 2 + 8 -
            Math.abs(a.y + a.height / 2 - b.y - b.height / 2)
          if (overlapX <= 0 || overlapY <= 0) continue
          const aFixed = a.kind === 'base'
          const bFixed = b.kind === 'base'
          const movement = aFixed || bFixed ? 1 : 0.5
          if (overlapX < overlapY) {
            const direction = a.x + a.width / 2 < b.x + b.width / 2 ? -1 : 1
            if (!aFixed) a.x += direction * overlapX * movement
            if (!bFixed) b.x -= direction * overlapX * movement
          } else {
            const direction = a.y + a.height / 2 < b.y + b.height / 2 ? -1 : 1
            if (!aFixed) a.y += direction * overlapY * movement
            if (!bFixed) b.y -= direction * overlapY * movement
          }
        }
      }
      nodes.forEach((node: KnowledgeGraphNode) => {
        if (node.kind === 'base') return
        node.x = Math.max(14, Math.min(width - node.width - 14, node.x))
        node.y = Math.max(14, Math.min(height - node.height - 14, node.y))
      })
    }
  }

  private static relationScore(a: KnowledgeChunk, b: KnowledgeChunk): number {
    let semantic = 0
    if (a.vectorModel === b.vectorModel && a.vector.length > 0 && a.vector.length === b.vector.length) {
      let dot = 0
      let aa = 0
      let bb = 0
      for (let index = 0; index < a.vector.length; index++) {
        dot += a.vector[index] * b.vector[index]
        aa += a.vector[index] * a.vector[index]
        bb += b.vector[index] * b.vector[index]
      }
      semantic = aa > 0 && bb > 0 ? Math.max(0, Math.min(1, dot / Math.sqrt(aa * bb))) : 0
    }
    const textA = `${a.title}${a.content}`.slice(0, 240)
    const textB = `${b.title}${b.content}`.slice(0, 240)
    let shared = 0
    for (let index = 0; index < textA.length; index++) {
      if (textB.includes(textA.charAt(index))) shared++
    }
    const lexical = shared / Math.max(1, Math.min(textA.length, textB.length))
    const sameSource = a.sourceId === b.sourceId ? 0.08 : 0
    return Math.min(1, semantic * 0.76 + lexical * 0.24 + sameSource)
  }

  private static modalityLabel(value: string): string {
    if (value === 'image') return '图片'
    if (value === 'table') return '表格'
    if (value === 'audio') return '音频'
    if (value === 'video') return '视频'
    return '文本'
  }
}

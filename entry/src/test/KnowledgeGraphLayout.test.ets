import { describe, expect, it } from '@ohos/hypium'
import { KnowledgeGraphNode } from '../main/ets/models/KnowledgeGraphModels'
import { KnowledgeChunk } from '../main/ets/models/RagModels'
import { KnowledgeGraphLayoutService } from '../main/ets/services/KnowledgeGraphLayoutService'

function chunks(count: number): KnowledgeChunk[] {
  const result: KnowledgeChunk[] = []
  for (let index = 0; index < count; index++) {
    const vector: number[] = []
    for (let dimension = 0; dimension < 8; dimension++) {
      vector.push(Math.sin(index * 0.17 + dimension * 0.31))
    }
    result.push({
      id: `chunk-${index}`,
      sourceId: `source-${index % 10}`,
      title: `课程资料 ${index % 10}`,
      location: `片段 ${index + 1}`,
      course: `课程 ${index % 6}`,
      content: `知识片段 ${index}，包含检索、索引和关系图测试数据。`,
      vector: vector,
      vectorModel: 'test-vector',
      modality: 'text'
    })
  }
  return result
}

export default function knowledgeGraphLayoutTest() {
  describe('KnowledgeGraphLayout', () => {
    it('buildsStableLayoutFor120Nodes', 0, () => {
      const layout = KnowledgeGraphLayoutService.build('base-test', '测试知识库',
        chunks(120), 900, 560)
      expect(layout.nodes.length).assertEqual(121)
      expect(layout.edges.length >= 120).assertTrue()
      expect(layout.nodes[0].x).assertEqual(374)
      expect(layout.nodes[0].y).assertEqual(257)
      layout.nodes.forEach((node: KnowledgeGraphNode) => {
        expect(Number.isFinite(node.x)).assertTrue()
        expect(Number.isFinite(node.y)).assertTrue()
        expect(node.x >= 0).assertTrue()
        expect(node.y >= 0).assertTrue()
      })
    })

    it('movesDraggedNodeOutOfOverlap', 0, () => {
      const layout = KnowledgeGraphLayoutService.build('base-test', '测试知识库',
        chunks(3), 720, 480)
      const first = layout.nodes[1]
      const second = layout.nodes[2]
      second.x = first.x
      second.y = first.y
      const beforeX = second.x
      const beforeY = second.y
      KnowledgeGraphLayoutService.avoidOverlap(second, layout.nodes, 720, 480)
      expect(second.x !== beforeX || second.y !== beforeY).assertTrue()
    })
  })
}

import { KnowledgeGraphNode } from '../models/KnowledgeGraphModels'

export interface KnowledgeGraphNodeFrame {
  left: number
  top: number
  width: number
  height: number
  centerX: number
  centerY: number
}

export class KnowledgeGraphGeometry {
  static frame(node: KnowledgeGraphNode, scale: number,
    offsetX: number, offsetY: number): KnowledgeGraphNodeFrame {
    const width = node.width * scale
    const height = node.height * scale
    return {
      left: node.x * scale + offsetX,
      top: node.y * scale + offsetY,
      width: width,
      height: height,
      centerX: (node.x + node.width / 2) * scale + offsetX,
      centerY: (node.y + node.height / 2) * scale + offsetY
    }
  }
}

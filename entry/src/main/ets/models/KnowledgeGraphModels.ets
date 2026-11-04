export interface KnowledgeGraphNode {
  id: string
  kind: string
  baseId: string
  sourceId: string
  chunkId: string
  title: string
  detail: string
  x: number
  y: number
  width: number
  height: number
}

export interface KnowledgeGraphEdge {
  id: string
  from: string
  to: string
  kind: string
  weight: number
}

export interface KnowledgeGraphLayout {
  nodes: KnowledgeGraphNode[]
  edges: KnowledgeGraphEdge[]
}

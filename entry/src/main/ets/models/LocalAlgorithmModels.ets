export interface LocalModelEntry {
  id: string
  name: string
  path: string
  size: number
  format: string
  enabled: boolean
  addedAt: number
}

export interface LocalAlgorithmEntry {
  id: string
  name: string
  description: string
  builtIn: boolean
  enabled: boolean
  createdAt: number
}

export interface LocalAlgorithmArchive {
  version: number
  models: LocalModelEntry[]
  algorithms: LocalAlgorithmEntry[]
}

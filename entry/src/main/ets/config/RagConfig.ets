import { RetrievalOptions } from '../models/RagModels'

export class RagConfig {
  static defaults(): RetrievalOptions {
    return { course: '', topK: 4, minScore: 0.20, maxPerSource: 2, contextChars: 2400 }
  }
}

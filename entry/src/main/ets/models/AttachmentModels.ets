export interface ChatAttachment {
  id: string
  name: string
  kind: string
  mimeType: string
  path: string
  size: number
  text: string
  truncated: boolean
}

export interface ModelImageUrl { url: string }
export interface ModelContentPart {
  type: string
  text?: string
  image_url?: ModelImageUrl
}

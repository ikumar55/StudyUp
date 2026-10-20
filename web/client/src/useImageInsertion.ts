import { useState } from 'react'
import type { ClipboardEvent, DragEvent, RefObject } from 'react'
import { api, errorMessage } from './api.ts'
import { imageFiles, imageSnippet, prepareImage } from './images.ts'
import { useToasts } from './toasts.tsx'

/**
 * Lets a card field take images: paste a screenshot (⌘V), drop image files, or pick them.
 * Each image is uploaded, and a reference is inserted on its own line where the cursor was.
 */
export function useImageInsertion(
  field: RefObject<HTMLTextAreaElement | null>,
  setText: (update: (text: string) => string) => void,
) {
  const toasts = useToasts()
  const [uploading, setUploading] = useState(0)

  /** The cursor position when the image arrived, so typing during the upload doesn't move it. */
  const selection = () => ({
    start: field.current?.selectionStart ?? Number.MAX_SAFE_INTEGER,
    end: field.current?.selectionEnd ?? Number.MAX_SAFE_INTEGER,
  })

  const insert = async (files: File[], at: { start: number; end: number }) => {
    setUploading((count) => count + files.length)
    const snippets: string[] = []
    for (const file of files) {
      try {
        const { id } = await api.uploadImage(await prepareImage(file))
        snippets.push(imageSnippet(id))
      } catch (error) {
        toasts.error(errorMessage(error))
      } finally {
        setUploading((count) => count - 1)
      }
    }
    if (snippets.length === 0) return
    setText((text) => {
      const before = text.slice(0, at.start)
      const after = text.slice(at.end)
      const lead = before && !before.endsWith('\n') ? '\n' : ''
      const trail = after && !after.startsWith('\n') ? '\n' : ''
      return before + lead + snippets.join('\n') + trail + after
    })
  }

  return {
    uploading: uploading > 0,

    /** Handles a paste that carries images. Returns false for text pastes, which go on as normal. */
    onPaste(event: ClipboardEvent<HTMLTextAreaElement>): boolean {
      const files = imageFiles(event.clipboardData)
      if (files.length === 0) return false
      event.preventDefault()
      void insert(files, selection())
      return true
    },

    onDragOver(event: DragEvent<HTMLTextAreaElement>) {
      if ([...event.dataTransfer.items].some((item) => item.kind === 'file')) event.preventDefault()
    },

    onDrop(event: DragEvent<HTMLTextAreaElement>) {
      const files = imageFiles(event.dataTransfer)
      if (files.length === 0) return
      event.preventDefault()
      void insert(files, selection())
    },

    /** Opens the file picker. */
    pick() {
      const at = selection()
      const input = document.createElement('input')
      input.type = 'file'
      input.accept = 'image/png,image/jpeg,image/webp,image/gif,image/heic'
      input.multiple = true
      input.onchange = () => {
        const files = [...(input.files ?? [])]
        if (files.length > 0) void insert(files, at)
      }
      input.click()
    },
  }
}

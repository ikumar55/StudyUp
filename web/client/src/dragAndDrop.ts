// Drag-and-drop of cards and folders onto folders in the sidebar.
// The dragged item is kept here because dataTransfer contents can't be read during dragover.

import type { DragEvent } from 'react'

export interface DragItem {
  kind: 'card' | 'folder'
  id: string
}

let current: DragItem | null = null

const mimeType = 'application/x-studyup-item'

export function startDrag(event: DragEvent, item: DragItem, label: string): void {
  current = item
  event.dataTransfer.setData(mimeType, JSON.stringify(item))
  event.dataTransfer.setData('text/plain', label)
  event.dataTransfer.effectAllowed = 'move'
}

export function endDrag(): void {
  current = null
}

export function draggedItem(): DragItem | null {
  return current
}

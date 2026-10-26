/** A change to a text field: replace `from..<to` with `insert`, then select `selectStart..<selectEnd`. */
export interface TextEdit {
  from: number
  to: number
  insert: string
  selectStart: number
  selectEnd: number
}

/**
 * ⌘B: wraps the selection in `**`, or unwraps it if it's already bold. With nothing selected, inserts
 * `****` with the cursor in the middle. Spaces at the edges of the selection stay outside the markers,
 * since Markdown doesn't treat `**word **` as bold.
 */
export function toggleBold(value: string, start: number, end: number): TextEdit {
  const selected = value.slice(start, end)
  if (start >= 2 && value.slice(start - 2, start) === '**' && value.slice(end, end + 2) === '**') {
    return { from: start - 2, to: end + 2, insert: selected, selectStart: start - 2, selectEnd: end - 2 }
  }
  if (selected.length >= 4 && selected.startsWith('**') && selected.endsWith('**')) {
    return { from: start, to: end, insert: selected.slice(2, -2), selectStart: start, selectEnd: end - 4 }
  }
  const inner = selected.trim()
  if (!inner) {
    return { from: end, to: end, insert: '****', selectStart: end + 2, selectEnd: end + 2 }
  }
  const from = start + (selected.length - selected.trimStart().length)
  return { from, to: from + inner.length, insert: `**${inner}**`, selectStart: from + 2, selectEnd: from + 2 + inner.length }
}

/** Applies an edit so it lands in the browser's undo history (⌘Z) and React's onChange sees it. */
export function applyEdit(element: HTMLTextAreaElement, edit: TextEdit): void {
  element.setSelectionRange(edit.from, edit.to)
  // Deprecated but still the only way to keep native undo; fall back if a browser drops it.
  if (!document.execCommand('insertText', false, edit.insert)) {
    element.setRangeText(edit.insert)
    element.dispatchEvent(new Event('input', { bubbles: true }))
  }
  element.setSelectionRange(edit.selectStart, edit.selectEnd)
}

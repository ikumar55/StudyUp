import { useEffect, useMemo, useRef, useState } from 'react'
import type { KeyboardEvent } from 'react'
import { flattenTree, pathLabel } from '../libraryIndex.ts'
import type { LibraryIndex } from '../libraryIndex.ts'
import { Dialog } from './Dialog.tsx'
import { FolderIcon } from './Icons.tsx'

interface Props {
  title: string
  index: LibraryIndex
  /** Where the item is now; shown but not selectable. */
  currentId: string | null
  /** Folders that can't be picked (a folder and its descendants, when moving a folder). */
  excluded?: ReadonlySet<string>
  /** Offer "Top level" as a destination (for folders). */
  allowTopLevel?: boolean
  onPick: (folderId: string | null) => void
  onClose: () => void
}

interface Row {
  id: string | null
  label: string
  detail?: string
  depth: number
  disabled: boolean
}

/** Picks a destination folder. Type to filter, arrows to choose, Return to move. */
export function MoveDialog({ title, index, currentId, excluded, allowTopLevel, onPick, onClose }: Props) {
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const list = useRef<HTMLUListElement>(null)

  const rows = useMemo<Row[]>(() => {
    const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean)
    const list: Row[] = []
    if (allowTopLevel && terms.length === 0) {
      list.push({ id: null, label: 'Top level', depth: 0, disabled: currentId === null })
    }
    for (const { folder, depth } of flattenTree(index)) {
      const disabled = folder.id === currentId || (excluded?.has(folder.id) ?? false)
      if (terms.length === 0) {
        list.push({ id: folder.id, label: folder.name, depth, disabled })
        continue
      }
      const path = pathLabel(index, folder.id)
      const haystack = path.toLowerCase()
      if (terms.every((term) => haystack.includes(term))) {
        list.push({ id: folder.id, label: folder.name, detail: path, depth: 0, disabled })
      }
    }
    return list
  }, [index, query, currentId, excluded, allowTopLevel])

  const enabled = rows.filter((row) => !row.disabled)
  const activeRow = enabled[Math.min(active, enabled.length - 1)]

  useEffect(() => {
    list.current?.querySelector('.is-active')?.scrollIntoView({ block: 'nearest' })
  }, [activeRow])

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      const step = event.key === 'ArrowDown' ? 1 : -1
      setActive((current) => Math.max(0, Math.min(enabled.length - 1, current + step)))
    } else if (event.key === 'Enter' && activeRow) {
      event.preventDefault()
      onPick(activeRow.id)
    }
  }

  return (
    <Dialog title={title} onClose={onClose} className="dialog-picker">
      <input
        className="text-input"
        type="search"
        placeholder="Filter topics…"
        value={query}
        onChange={(event) => {
          setQuery(event.target.value)
          setActive(0)
        }}
        onKeyDown={onKeyDown}
        data-autofocus
        aria-label="Filter topics"
      />
      <ul ref={list} className="picker-list" role="listbox" aria-label="Destination">
        {rows.length === 0 && <li className="picker-empty">No topics match “{query}”.</li>}
        {rows.map((row) => {
          const isActive = row === activeRow
          return (
            <li key={row.id ?? 'root'} role="option" aria-selected={isActive} aria-disabled={row.disabled}>
              <button
                type="button"
                className={`picker-row${isActive ? ' is-active' : ''}`}
                style={{ paddingLeft: 10 + row.depth * 16 }}
                disabled={row.disabled}
                tabIndex={-1}
                onMouseEnter={() => {
                  const at = enabled.indexOf(row)
                  if (at !== -1) setActive(at)
                }}
                onClick={() => onPick(row.id)}
              >
                <FolderIcon className="picker-icon" />
                <span className="picker-label">{row.label}</span>
                {row.detail && row.detail !== row.label && <span className="picker-detail">{row.detail}</span>}
                {row.id === currentId && <span className="picker-detail">Current</span>}
              </button>
            </li>
          )
        })}
      </ul>
      <p className="dialog-hint">↑↓ to choose · Return to move · Esc to cancel</p>
    </Dialog>
  )
}

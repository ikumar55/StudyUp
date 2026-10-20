import { memo, useEffect, useRef, useState } from 'react'
import type { DragEvent, KeyboardEvent, MouseEvent } from 'react'
import type { FolderRecord } from '../../../shared/protocol.ts'
import { draggedItem, endDrag, startDrag } from '../dragAndDrop.ts'
import { modKey } from '../format.ts'
import { descendantIds } from '../libraryIndex.ts'
import type { LibraryIndex } from '../libraryIndex.ts'
import type { FolderActions, FolderEdit, Selection } from '../types.ts'
import { FolderNameInput } from './FolderNameInput.tsx'
import { ChevronIcon, EditIcon, FolderIcon, MoreIcon, MoveIcon, PlusIcon, TrashIcon } from './Icons.tsx'
import { Menu } from './Menu.tsx'

interface Props {
  index: LibraryIndex
  selected: Selection
  collapsed: ReadonlySet<string>
  onToggle: (id: string, expanded: boolean) => void
  edit: FolderEdit | null
  actions: FolderActions
}

const indentStep = 14
const rowPadding = 8

/** The nested topic list. Arrow keys move and expand, Return renames, ⌘⌫ deletes. */
export function FolderTree({ index, selected, collapsed, onToggle, edit, actions }: Props) {
  const [menu, setMenu] = useState<{ folder: FolderRecord; at: { x: number; y: number } } | null>(null)
  const tree = useRef<HTMLUListElement>(null)

  const openMenu = (folder: FolderRecord, at: { x: number; y: number }) => setMenu({ folder, at })
  // The one row reachable with Tab: the selected folder, or the first one.
  const tabStop = typeof selected === 'string' && index.folders.has(selected)
    ? selected
    : (index.children.get(null)?.[0]?.id ?? null)

  const onKeyDown = (event: KeyboardEvent<HTMLUListElement>) => {
    const target = event.target as HTMLElement
    const id = target.dataset.folderId
    if (!id || target.getAttribute('role') !== 'treeitem') return
    const folder = index.folders.get(id)
    if (!folder) return
    const rows = [...(tree.current?.querySelectorAll<HTMLElement>('[role="treeitem"]') ?? [])]
    const position = rows.indexOf(target)
    const focusRow = (row: HTMLElement | undefined) => {
      if (!row) return
      row.focus()
      if (row.dataset.folderId) actions.select(row.dataset.folderId)
    }
    const hasChildren = (index.children.get(id)?.length ?? 0) > 0
    const isExpanded = hasChildren && !collapsed.has(id)

    switch (event.key) {
      case 'ArrowDown':
        focusRow(rows[position + 1])
        break
      case 'ArrowUp':
        focusRow(rows[position - 1])
        break
      case 'Home':
        focusRow(rows[0])
        break
      case 'End':
        focusRow(rows[rows.length - 1])
        break
      case 'ArrowRight':
        if (hasChildren && !isExpanded) onToggle(id, true)
        else if (isExpanded) focusRow(rows[position + 1])
        break
      case 'ArrowLeft':
        if (isExpanded) onToggle(id, false)
        else if (folder.parentId) focusRow(rows.find((row) => row.dataset.folderId === folder.parentId))
        break
      case 'Enter':
        actions.startRename(id)
        break
      case 'Backspace':
      case 'Delete':
        if (!event.metaKey && !event.ctrlKey) return
        actions.requestDelete(id)
        break
      case 'ContextMenu':
      case 'F10': {
        if (event.key === 'F10' && !event.shiftKey) return
        const rect = target.getBoundingClientRect()
        openMenu(folder, { x: rect.left + 24, y: rect.bottom })
        break
      }
      default:
        return
    }
    event.preventDefault()
  }

  return (
    <>
      <ul ref={tree} className="tree" role="tree" aria-label="Topics" onKeyDown={onKeyDown}>
        <FolderChildren
          parentId={null}
          depth={0}
          index={index}
          selected={selected}
          collapsed={collapsed}
          onToggle={onToggle}
          edit={edit}
          actions={actions}
          openMenu={openMenu}
          tabStop={tabStop}
        />
      </ul>
      {menu && (
        <Menu
          label={`${menu.folder.name} actions`}
          at={menu.at}
          onClose={() => setMenu(null)}
          items={[
            { label: 'New subtopic', icon: <PlusIcon />, onSelect: () => actions.startCreate(menu.folder.id) },
            { label: 'Rename', icon: <EditIcon />, hint: '↩', onSelect: () => actions.startRename(menu.folder.id) },
            { label: 'Move to…', icon: <MoveIcon />, onSelect: () => actions.requestMove(menu.folder.id) },
            'separator',
            {
              label: 'Delete…',
              icon: <TrashIcon />,
              hint: `${modKey}⌫`,
              danger: true,
              onSelect: () => actions.requestDelete(menu.folder.id),
            },
          ]}
        />
      )}
    </>
  )
}

interface ChildrenProps extends Omit<Props, 'index'> {
  index: LibraryIndex
  parentId: string | null
  depth: number
  openMenu: (folder: FolderRecord, at: { x: number; y: number }) => void
  tabStop: string | null
}

function FolderChildren(props: ChildrenProps) {
  const { parentId, depth, index, edit } = props
  const children = index.children.get(parentId) ?? []
  const creatingHere = edit?.mode === 'create' && edit.parentId === parentId
  return (
    <>
      {children.map((folder) => (
        <FolderNode key={folder.id} {...props} folder={folder} />
      ))}
      {creatingHere && (
        <li role="none" className="tree-input-row">
          <FolderNameInput
            initialName=""
            placeholder={parentId === null ? 'New topic name' : 'New subtopic name'}
            style={{ marginLeft: rowPadding + depth * indentStep + 18 }}
            onCommit={(name) => props.actions.commitCreate(parentId, name)}
            onCancel={props.actions.cancelEdit}
          />
        </li>
      )}
    </>
  )
}

const FolderNode = memo(function FolderNode(props: ChildrenProps & { folder: FolderRecord }) {
  const { folder, depth, index, selected, collapsed, onToggle, edit, actions, openMenu, tabStop } = props
  const [dropState, setDropState] = useState<'none' | 'valid'>('none')
  const expandTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const childCount = index.children.get(folder.id)?.length ?? 0
  const creatingChild = edit?.mode === 'create' && edit.parentId === folder.id
  const hasChildren = childCount > 0 || creatingChild
  const expanded = hasChildren && (!collapsed.has(folder.id) || creatingChild)
  const isSelected = selected === folder.id
  const renaming = edit?.mode === 'rename' && edit.id === folder.id
  const total = index.totalCounts.get(folder.id) ?? 0

  useEffect(() => () => {
    if (expandTimer.current) clearTimeout(expandTimer.current)
  }, [])

  const canDrop = () => {
    const item = draggedItem()
    if (!item) return false
    if (item.kind === 'card') return true
    return !descendantIds(index, item.id).has(folder.id) && index.folders.get(item.id)?.parentId !== folder.id
  }

  const onDragOver = (event: DragEvent) => {
    if (!canDrop()) return
    event.preventDefault()
    event.dataTransfer.dropEffect = 'move'
    if (dropState !== 'valid') setDropState('valid')
    // Hovering a collapsed folder while dragging opens it.
    if (hasChildren && !expanded && !expandTimer.current) {
      expandTimer.current = setTimeout(() => onToggle(folder.id, true), 700)
    }
  }

  const clearDrop = () => {
    setDropState('none')
    if (expandTimer.current) clearTimeout(expandTimer.current)
    expandTimer.current = null
  }

  const onDrop = (event: DragEvent) => {
    event.preventDefault()
    clearDrop()
    const item = draggedItem()
    endDrag()
    if (!item || !canDropItem(item)) return
    if (item.kind === 'card') actions.moveCard(item.id, folder.id)
    else actions.moveFolder(item.id, folder.id)
  }

  const canDropItem = (item: { kind: string; id: string }) =>
    item.kind === 'card' || !descendantIds(index, item.id).has(folder.id)

  const onContextMenu = (event: MouseEvent) => {
    event.preventDefault()
    actions.select(folder.id)
    openMenu(folder, { x: event.clientX, y: event.clientY })
  }

  return (
    <li role="none">
      <div
        role="treeitem"
        aria-level={depth + 1}
        aria-selected={isSelected}
        aria-expanded={hasChildren ? expanded : undefined}
        tabIndex={folder.id === tabStop ? 0 : -1}
        data-folder-id={folder.id}
        className={`tree-row${isSelected ? ' is-selected' : ''}${dropState === 'valid' ? ' is-drop-target' : ''}`}
        style={{ paddingLeft: rowPadding + depth * indentStep }}
        draggable={!renaming}
        onClick={() => actions.select(folder.id)}
        onDoubleClick={() => actions.startRename(folder.id)}
        onContextMenu={onContextMenu}
        onDragStart={(event) => startDrag(event, { kind: 'folder', id: folder.id }, folder.name)}
        onDragEnd={endDrag}
        onDragOver={onDragOver}
        onDragLeave={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget as Node | null)) clearDrop()
        }}
        onDrop={onDrop}
      >
        <button
          type="button"
          tabIndex={-1}
          className={`tree-chevron${expanded ? ' is-expanded' : ''}${hasChildren ? '' : ' is-hidden'}`}
          aria-label={expanded ? 'Collapse' : 'Expand'}
          onClick={(event) => {
            event.stopPropagation()
            onToggle(folder.id, !expanded)
          }}
        >
          <ChevronIcon width={12} height={12} />
        </button>
        <FolderIcon className="tree-icon" />
        {renaming ? (
          <FolderNameInput
            initialName={folder.name}
            placeholder="Topic name"
            onCommit={(name) => actions.commitRename(folder.id, name)}
            onCancel={actions.cancelEdit}
          />
        ) : (
          <span className="tree-name" title={folder.name}>{folder.name}</span>
        )}
        {!renaming && (
          <>
            <span className="tree-count" aria-label={`${total} cards`}>{total > 0 ? total.toLocaleString() : ''}</span>
            <button
              type="button"
              tabIndex={-1}
              className="tree-more"
              aria-label={`${folder.name} actions`}
              onClick={(event) => {
                event.stopPropagation()
                const rect = event.currentTarget.getBoundingClientRect()
                openMenu(folder, { x: rect.left, y: rect.bottom + 4 })
              }}
            >
              <MoreIcon />
            </button>
          </>
        )}
      </div>
      {expanded && (
        <ul role="group">
          <FolderChildren {...props} parentId={folder.id} depth={depth + 1} />
        </ul>
      )}
    </li>
  )
})

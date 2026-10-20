import { useState } from 'react'
import type { KeyboardEvent, Ref } from 'react'
import type { ServerStatus } from '../../../shared/protocol.ts'
import { api } from '../api.ts'
import { useNow } from '../clock.tsx'
import { draggedItem, endDrag } from '../dragAndDrop.ts'
import { modKey, timeAgo } from '../format.ts'
import type { LibraryIndex } from '../libraryIndex.ts'
import { unfiled } from '../types.ts'
import type { FolderActions, FolderEdit, Selection } from '../types.ts'
import { FolderTree } from './FolderTree.tsx'
import { DownloadIcon, FolderIcon, KeyboardIcon, PhoneIcon, PlusIcon, SearchIcon } from './Icons.tsx'

interface Props {
  index: LibraryIndex
  status: ServerStatus | null
  offline: boolean
  selected: Selection
  collapsed: ReadonlySet<string>
  onToggle: (id: string, expanded: boolean) => void
  edit: FolderEdit | null
  actions: FolderActions
  query: string
  onQueryChange: (query: string) => void
  onSearchKeyDown: (event: KeyboardEvent<HTMLInputElement>) => void
  searchRef: Ref<HTMLInputElement>
  onOpenPhone: () => void
  onOpenShortcuts: () => void
}

export function Sidebar(props: Props) {
  const { index, selected, actions, query } = props
  const [rootDrop, setRootDrop] = useState(false)
  const topLevel = index.children.get(null) ?? []
  const unfiledCount = index.cardsByFolder.get(null)?.length ?? 0

  // Dropping a folder on the "Topics" heading moves it to the top level.
  const canDropAtRoot = () => {
    const item = draggedItem()
    return item?.kind === 'folder' && index.folders.get(item.id)?.parentId !== null
  }

  return (
    <aside className="sidebar">
      <div className="sidebar-top">
        <div className="brand">
          <img src="/icon.svg" alt="" width={20} height={20} />
          <span>StudyUp</span>
        </div>
        <label className="search-box">
          <SearchIcon className="search-icon" />
          <input
            ref={props.searchRef}
            type="search"
            placeholder="Search cards"
            value={query}
            onChange={(event) => props.onQueryChange(event.target.value)}
            onKeyDown={props.onSearchKeyDown}
            aria-label="Search all cards"
            aria-controls="search-results"
          />
          {!query && <kbd className="search-shortcut">{modKey}K</kbd>}
        </label>
      </div>

      <div
        className={`sidebar-heading${rootDrop ? ' is-drop-target' : ''}`}
        onDragOver={(event) => {
          if (!canDropAtRoot()) return
          event.preventDefault()
          setRootDrop(true)
        }}
        onDragLeave={() => setRootDrop(false)}
        onDrop={(event) => {
          event.preventDefault()
          setRootDrop(false)
          const item = draggedItem()
          endDrag()
          if (item?.kind === 'folder') actions.moveFolder(item.id, null)
        }}
      >
        <span>Topics</span>
        <button
          type="button"
          className="icon-button"
          title="New topic"
          aria-label="New topic"
          onClick={() => actions.startCreate(null)}
        >
          <PlusIcon />
        </button>
      </div>

      <nav className="sidebar-scroll" aria-label="Topics">
        <FolderTree
          index={index}
          selected={selected}
          collapsed={props.collapsed}
          onToggle={props.onToggle}
          edit={props.edit}
          actions={actions}
        />
        {topLevel.length === 0 && props.edit?.mode !== 'create' && (
          <button type="button" className="sidebar-empty" onClick={() => actions.startCreate(null)}>
            <PlusIcon /> Create your first topic
          </button>
        )}
        {unfiledCount > 0 && (
          <button
            type="button"
            className={`tree-row tree-row-flat${selected === unfiled ? ' is-selected' : ''}`}
            onClick={() => actions.select(unfiled)}
          >
            <FolderIcon className="tree-icon" />
            <span className="tree-name">Unfiled</span>
            <span className="tree-count">{unfiledCount}</span>
          </button>
        )}
      </nav>

      <footer className="sidebar-footer">
        <PhoneButton status={props.status} offline={props.offline} onClick={props.onOpenPhone} />
        <div className="sidebar-footer-row">
          <a className="footer-link" href={api.backupURL} download title="Download a JSON backup of all topics, cards, and review history">
            <DownloadIcon /> Download backup
          </a>
          <button
            type="button"
            className="icon-button"
            title="Keyboard shortcuts (?)"
            aria-label="Keyboard shortcuts"
            onClick={props.onOpenShortcuts}
          >
            <KeyboardIcon />
          </button>
        </div>
      </footer>
    </aside>
  )
}

function PhoneButton({ status, offline, onClick }: { status: ServerStatus | null; offline: boolean; onClick: () => void }) {
  const now = useNow()
  const devices = status?.devices ?? []
  const lastSync = Math.max(0, ...devices.map((device) => device.lastSyncAt ?? 0))

  let title = 'Pair an iPhone'
  let detail = 'Study these cards on your phone'
  if (offline) {
    title = 'Server not reachable'
    detail = 'Start it with npm start'
  } else if (devices.length > 0) {
    title = devices.length === 1 ? devices[0].name : `${devices.length} iPhones`
    detail = lastSync > 0 ? `Synced ${timeAgo(lastSync, now)}` : 'Paired · not synced yet'
  }

  return (
    <button type="button" className="phone-button" onClick={onClick}>
      <span className={`phone-dot${offline ? ' is-offline' : devices.length > 0 ? ' is-paired' : ''}`} aria-hidden="true">
        <PhoneIcon />
      </span>
      <span className="phone-text">
        <span className="phone-title">{title}</span>
        <span className="phone-detail">{detail}</span>
      </span>
    </button>
  )
}

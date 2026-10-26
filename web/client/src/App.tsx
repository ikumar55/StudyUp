import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { KeyboardEvent as ReactKeyboardEvent } from 'react'
import { CardList } from './components/CardList.tsx'
import { ConfirmDialog } from './components/Dialog.tsx'
import { FolderView } from './components/FolderView.tsx'
import { MoveDialog } from './components/MoveDialog.tsx'
import { PhoneDialog } from './components/PhoneDialog.tsx'
import { SearchResults } from './components/SearchResults.tsx'
import { ShortcutsDialog } from './components/ShortcutsDialog.tsx'
import { Sidebar } from './components/Sidebar.tsx'
import { WelcomeView } from './components/WelcomeView.tsx'
import { hasModifier, plural } from './format.ts'
import { buildIndex, descendantIds, folderPath } from './libraryIndex.ts'
import { searchCards } from './search.ts'
import type { SearchResult } from './search.ts'
import { loadValue, saveValue } from './storage.ts'
import { unfiled } from './types.ts'
import type { FolderEdit, Selection } from './types.ts'
import { useActions } from './useActions.ts'
import { useLibrary } from './useLibrary.ts'

type OpenDialog =
  | { kind: 'phone' }
  | { kind: 'shortcuts' }
  | { kind: 'moveCard'; id: string }
  | { kind: 'moveFolder'; id: string }
  | { kind: 'deleteFolder'; id: string }

const noCards: ReadonlySet<string> = new Set()

export function App() {
  const lib = useLibrary()
  const [pendingDeletes, setPendingDeletes] = useState<Set<string>>(() => new Set())
  const index = useMemo(
    () => (lib.library ? buildIndex(lib.library, pendingDeletes.size > 0 ? pendingDeletes : noCards) : null),
    [lib.library, pendingDeletes],
  )

  const [selected, setSelected] = useState<Selection>(() => loadValue<Selection>('selected', null))
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set(loadValue<string[]>('collapsed', [])))
  const [includeSubfolders, setIncludeSubfolders] = useState(() => loadValue('includeSubfolders', false))
  const [edit, setEdit] = useState<FolderEdit | null>(null)
  const [dialog, setDialog] = useState<OpenDialog | null>(null)
  const [query, setQuery] = useState('')
  const [activeResult, setActiveResult] = useState(0)
  const [highlight, setHighlight] = useState<string | null>(null)
  const questionRef = useRef<HTMLTextAreaElement>(null)
  const searchRef = useRef<HTMLInputElement>(null)

  useEffect(() => saveValue('selected', selected), [selected])
  useEffect(() => saveValue('collapsed', [...collapsed]), [collapsed])
  useEffect(() => saveValue('includeSubfolders', includeSubfolders), [includeSubfolders])

  const expand = useCallback((id: string) => {
    setCollapsed((current) => {
      if (!current.has(id)) return current
      const next = new Set(current)
      next.delete(id)
      return next
    })
  }, [])

  const onToggle = useCallback((id: string, expanded: boolean) => {
    setCollapsed((current) => {
      const next = new Set(current)
      if (expanded) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const indexRef = useRef(index)
  indexRef.current = index

  const select = useCallback((id: Selection) => {
    setSelected(id)
    setQuery('')
    // Open the folders above it so it's visible in the sidebar.
    const current = indexRef.current
    if (current && typeof id === 'string' && id !== unfiled) {
      for (const ancestor of folderPath(current, id).slice(0, -1)) expand(ancestor.id)
    }
  }, [expand])

  // Keep the selection valid as folders come and go (including deletes from the phone).
  useEffect(() => {
    if (!index) return
    const valid = selected === unfiled
      ? (index.cardsByFolder.get(null)?.length ?? 0) > 0
      : selected !== null && index.folders.has(selected)
    if (!valid) setSelected(index.children.get(null)?.[0]?.id ?? null)
  }, [index, selected])

  // A highlighted search result fades after a moment.
  useEffect(() => {
    if (!highlight) return
    const timer = setTimeout(() => setHighlight(null), 2500)
    return () => clearTimeout(timer)
  }, [highlight])

  const actions = useActions({
    lib,
    index,
    selected,
    select,
    setEdit,
    expand,
    setPendingDeletes,
    openMoveFolder: (id) => setDialog({ kind: 'moveFolder', id }),
    openDeleteFolder: (id) => setDialog({ kind: 'deleteFolder', id }),
    openMoveCard: (id) => setDialog({ kind: 'moveCard', id }),
    focusQuestion: () => questionRef.current?.focus(),
  })

  const selectedFolder = index && typeof selected === 'string' ? index.folders.get(selected) : undefined

  // MARK: Search

  const searching = query.trim().length > 0
  const search = useMemo(
    () => (index && searching ? searchCards(index.allCards, query) : { results: [], total: 0 }),
    [index, query, searching],
  )

  const openResult = (result: SearchResult) => {
    select(result.card.folderId && index?.folders.has(result.card.folderId) ? result.card.folderId : unfiled)
    setHighlight(result.card.id)
  }

  const onSearchKeyDown = (event: ReactKeyboardEvent<HTMLInputElement>) => {
    const count = search.results.length
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      if (count === 0) return
      event.preventDefault()
      const step = event.key === 'ArrowDown' ? 1 : -1
      setActiveResult((current) => (current + step + count) % count)
    } else if (event.key === 'Enter') {
      const result = search.results[Math.min(activeResult, count - 1)]
      if (result) {
        event.preventDefault()
        openResult(result)
        event.currentTarget.blur()
      }
    } else if (event.key === 'Escape') {
      event.preventDefault()
      if (query) setQuery('')
      else event.currentTarget.blur()
    }
  }

  // MARK: Global shortcuts

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return
      if (event.key.toLowerCase() === 'k' && hasModifier(event) && !event.shiftKey && !event.altKey) {
        event.preventDefault()
        searchRef.current?.focus()
        searchRef.current?.select()
        return
      }
      if (dialog || document.querySelector('dialog[open]')) return
      const target = event.target as HTMLElement
      const typing = target.closest('input, textarea, select, [contenteditable="true"]') !== null
      if (typing || event.metaKey || event.ctrlKey || event.altKey) return

      if (event.key === '?') {
        event.preventDefault()
        setDialog({ kind: 'shortcuts' })
      } else if (event.key === 'n' && selectedFolder && !searching) {
        event.preventDefault()
        questionRef.current?.focus()
      } else if (event.key === 'Escape' && searching) {
        setQuery('')
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [dialog, selectedFolder, searching])

  // MARK: Rendering

  const closeDialog = () => setDialog(null)

  let main
  if (!index) {
    main = lib.loadError ? (
      <div className="empty-state">
        <p className="empty-title">Can’t reach the StudyUp server</p>
        <p className="empty-text">{lib.loadError}</p>
        <p className="empty-text">Start it from the <code>web</code> folder with <code>npm start</code>; this page reconnects on its own.</p>
        <button type="button" className="button" onClick={lib.refresh}>Try again</button>
      </div>
    ) : (
      <div className="loading" aria-busy="true">
        <div className="skeleton skeleton-title" />
        <div className="skeleton skeleton-form" />
        <div className="skeleton skeleton-card" />
        <div className="skeleton skeleton-card" />
      </div>
    )
  } else if (searching) {
    main = (
      <SearchResults
        index={index}
        query={query}
        results={search.results}
        total={search.total}
        active={Math.min(activeResult, Math.max(0, search.results.length - 1))}
        onActiveChange={setActiveResult}
        onOpen={openResult}
      />
    )
  } else if (selectedFolder) {
    main = (
      <FolderView
        index={index}
        folder={selectedFolder}
        folderActions={actions.folder}
        cardActions={actions.card}
        onAddCards={actions.addCards}
        questionRef={questionRef}
        includeSubfolders={includeSubfolders}
        onIncludeSubfoldersChange={setIncludeSubfolders}
        highlightId={highlight}
      />
    )
  } else if (selected === unfiled) {
    main = (
      <div className="folder-view">
        <header className="folder-header">
          <h1 className="folder-title">Unfiled</h1>
          <p className="folder-meta">Cards whose topic was deleted on another device. Move them into a topic to keep them organized.</p>
        </header>
        <CardList cards={index.cardsByFolder.get(null) ?? []} actions={actions.card} highlightId={highlight} empty={null} />
      </div>
    )
  } else {
    main = (
      <WelcomeView
        hasPhone={(lib.status?.devices.length ?? 0) > 0}
        onNewTopic={() => actions.folder.startCreate(null)}
        onPair={() => setDialog({ kind: 'phone' })}
      />
    )
  }

  return (
    <div className="app">
      {index ? (
        <Sidebar
          index={index}
          status={lib.status}
          offline={lib.offline}
          selected={selected}
          collapsed={collapsed}
          onToggle={onToggle}
          edit={edit}
          actions={actions.folder}
          query={query}
          onQueryChange={(value) => {
            setQuery(value)
            setActiveResult(0)
          }}
          onSearchKeyDown={onSearchKeyDown}
          searchRef={searchRef}
          onOpenPhone={() => setDialog({ kind: 'phone' })}
          onOpenShortcuts={() => setDialog({ kind: 'shortcuts' })}
        />
      ) : (
        <aside className="sidebar sidebar-loading" />
      )}

      <main className="main">
        {lib.offline && index && (
          <div className="banner" role="alert">
            Lost connection to the StudyUp server. Changes can’t be saved until it’s running again.
          </div>
        )}
        <div className="main-content">{main}</div>
      </main>

      {dialog?.kind === 'phone' && <PhoneDialog status={lib.status} onRefresh={lib.refresh} onClose={closeDialog} />}
      {dialog?.kind === 'shortcuts' && <ShortcutsDialog onClose={closeDialog} />}
      {index && dialog?.kind === 'moveCard' && (
        <MoveDialog
          title="Move card to…"
          index={index}
          currentId={index.allCards.find((card) => card.id === dialog.id)?.folderId ?? null}
          onPick={(folderId) => {
            closeDialog()
            if (folderId) actions.folder.moveCard(dialog.id, folderId)
          }}
          onClose={closeDialog}
        />
      )}
      {index && dialog?.kind === 'moveFolder' && (
        <MoveDialog
          title={`Move “${index.folders.get(dialog.id)?.name ?? 'topic'}” to…`}
          index={index}
          currentId={index.folders.get(dialog.id)?.parentId ?? null}
          excluded={descendantIds(index, dialog.id)}
          allowTopLevel
          onPick={(parentId) => {
            closeDialog()
            actions.folder.moveFolder(dialog.id, parentId)
          }}
          onClose={closeDialog}
        />
      )}
      {index && dialog?.kind === 'deleteFolder' && (() => {
        const folder = index.folders.get(dialog.id)
        if (!folder) return null
        const subfolders = descendantIds(index, folder.id).size - 1
        const cards = index.totalCounts.get(folder.id) ?? 0
        const contents = [
          subfolders > 0 ? plural(subfolders, 'subtopic') : null,
          cards > 0 ? plural(cards, 'card') : null,
        ].filter(Boolean)
        return (
          <ConfirmDialog
            title={`Delete “${folder.name}”?`}
            destructive
            confirmLabel={cards > 0 ? `Delete ${plural(cards, 'card')}` : 'Delete topic'}
            message={
              <>
                <p>
                  {contents.length > 0
                    ? <>This deletes <strong>{contents.join(' and ')}</strong> inside it, along with their study progress.</>
                    : 'This topic is empty.'}
                </p>
                {contents.length > 0 && <p className="confirm-detail">The delete syncs to your iPhone and can’t be undone. Download a backup first if you might want them back.</p>}
              </>
            }
            onCancel={closeDialog}
            onConfirm={() => {
              closeDialog()
              void actions.deleteFolder(folder.id)
            }}
          />
        )
      })()}
    </div>
  )
}

import { useMemo, useState } from 'react'
import type { RefObject } from 'react'
import type { FolderRecord } from '../../../shared/protocol.ts'
import { useNow } from '../clock.tsx'
import { isDue, modKey, plural } from '../format.ts'
import { cardsIn, folderPath } from '../libraryIndex.ts'
import type { LibraryIndex } from '../libraryIndex.ts'
import type { CardActions, FolderActions } from '../types.ts'
import { Breadcrumb } from './Breadcrumb.tsx'
import { CardList } from './CardList.tsx'
import { EditIcon, FolderIcon, MoreIcon, MoveIcon, PlusIcon, TrashIcon } from './Icons.tsx'
import { Menu } from './Menu.tsx'
import { QuickAdd } from './QuickAdd.tsx'

interface Props {
  index: LibraryIndex
  folder: FolderRecord
  folderActions: FolderActions
  cardActions: CardActions
  onAddCard: (folderId: string, front: string, back: string) => Promise<boolean>
  onBulkAdd: (text?: string) => void
  questionRef: RefObject<HTMLTextAreaElement | null>
  includeSubfolders: boolean
  onIncludeSubfoldersChange: (value: boolean) => void
  highlightId: string | null
}

export function FolderView(props: Props) {
  const { index, folder, folderActions, includeSubfolders } = props
  const [menuAt, setMenuAt] = useState<{ x: number; y: number } | null>(null)
  const now = useNow()

  const path = folderPath(index, folder.id)
  const subfolders = index.children.get(folder.id) ?? []
  const showSubfolderCards = includeSubfolders && subfolders.length > 0
  const cards = useMemo(() => cardsIn(index, folder.id, showSubfolderCards), [index, folder.id, showSubfolderCards])
  const directCount = index.cardsByFolder.get(folder.id)?.length ?? 0
  const total = index.totalCounts.get(folder.id) ?? 0
  const dueCount = cards.filter((card) => isDue(card.progress, now)).length
  const newCount = cards.filter((card) => !card.progress || card.progress.state === 0).length

  const folderLabel = showSubfolderCards
    ? (card: { folderId: string | null }) => {
        if (card.folderId === folder.id || card.folderId === null) return undefined
        return folderPath(index, card.folderId).slice(path.length).map((f) => f.name).join(' › ')
      }
    : undefined

  return (
    <div className="folder-view">
      <header className="folder-header">
        <Breadcrumb path={path} onSelect={folderActions.select} />
        <div className="folder-title-row">
          <h1 className="folder-title" onDoubleClick={() => folderActions.startRename(folder.id)}>{folder.name}</h1>
          <button
            type="button"
            className="icon-button"
            aria-label="Topic actions"
            onClick={(event) => {
              const rect = event.currentTarget.getBoundingClientRect()
              setMenuAt({ x: rect.left, y: rect.bottom + 4 })
            }}
          >
            <MoreIcon />
          </button>
        </div>
        <p className="folder-meta">
          {plural(cards.length, 'card')}
          {dueCount > 0 && <> · <span className="meta-due">{dueCount} due</span></>}
          {newCount > 0 && newCount < cards.length && <> · {newCount} new</>}
          {!showSubfolderCards && total > directCount && <> · {plural(total - directCount, 'more card')} in subtopics</>}
        </p>
        {subfolders.length > 0 && (
          <div className="subfolders">
            {subfolders.map((child) => (
              <button key={child.id} type="button" className="chip" onClick={() => folderActions.select(child.id)}>
                <FolderIcon /> {child.name}
                <span className="chip-count">{index.totalCounts.get(child.id) ?? 0}</span>
              </button>
            ))}
            <label className="toggle subfolder-toggle">
              <input
                type="checkbox"
                checked={includeSubfolders}
                onChange={(event) => props.onIncludeSubfoldersChange(event.target.checked)}
              />
              Show cards from subtopics
            </label>
          </div>
        )}
      </header>

      <QuickAdd
        folderName={folder.name}
        onAdd={(front, back) => props.onAddCard(folder.id, front, back)}
        onBulkAdd={props.onBulkAdd}
        questionRef={props.questionRef}
      />

      <CardList
        cards={cards}
        actions={props.cardActions}
        folderLabel={folderLabel}
        highlightId={props.highlightId}
        empty={
          <div className="empty-state empty-state-inline">
            <p className="empty-title">No cards in {folder.name} yet</p>
            <p className="empty-text">
              Type a question and answer above and press <kbd>{modKey}↩</kbd>, or paste your notes
              with{' '}
              <button type="button" className="link-button" onClick={() => props.onBulkAdd()}>Bulk add</button>.
            </p>
            {total > directCount && !showSubfolderCards && (
              <button type="button" className="button" onClick={() => props.onIncludeSubfoldersChange(true)}>
                Show the {plural(total - directCount, 'card')} in its subtopics
              </button>
            )}
          </div>
        }
      />

      {menuAt && (
        <Menu
          label={`${folder.name} actions`}
          at={menuAt}
          onClose={() => setMenuAt(null)}
          items={[
            { label: 'New subtopic', icon: <PlusIcon />, onSelect: () => folderActions.startCreate(folder.id) },
            { label: 'Rename', icon: <EditIcon />, onSelect: () => folderActions.startRename(folder.id) },
            { label: 'Move to…', icon: <MoveIcon />, onSelect: () => folderActions.requestMove(folder.id) },
            'separator',
            { label: 'Delete…', icon: <TrashIcon />, danger: true, onSelect: () => folderActions.requestDelete(folder.id) },
          ]}
        />
      )}
    </div>
  )
}

import { memo, useEffect, useRef, useState } from 'react'
import type { KeyboardEvent, MouseEvent } from 'react'
import type { CardRecord } from '../../../shared/protocol.ts'
import { endDrag, startDrag } from '../dragAndDrop.ts'
import { hasModifier, modKey, plainText } from '../format.ts'
import type { CardActions } from '../types.ts'
import { useImageInsertion } from '../useImageInsertion.ts'
import { AutoTextarea } from './AutoTextarea.tsx'
import { ConfirmDialog } from './Dialog.tsx'
import { EditIcon, GripIcon, MoreIcon, MoveIcon, RefreshIcon, TrashIcon } from './Icons.tsx'
import { Menu } from './Menu.tsx'
import { Markdown } from './Markdown.tsx'
import { StatusBadge } from './StatusBadge.tsx'

interface Props {
  card: CardRecord
  actions: CardActions
  /** Shown when the card is listed outside its own folder (subtopics included). */
  folderLabel?: string
  highlighted?: boolean
}

/** One card. Click (or Return) to edit in place; ⌘↩ saves and Esc cancels. ⌫ deletes, M moves. */
export const CardItem = memo(function CardItem({ card, actions, folderLabel, highlighted }: Props) {
  const [editing, setEditing] = useState<null | 'front' | 'back'>(null)
  const [menuAt, setMenuAt] = useState<{ x: number; y: number } | null>(null)
  const [confirmingReset, setConfirmingReset] = useState(false)
  const studied = card.progress !== null && card.progress.state !== 0

  return (
    <article
      id={`card-${card.id}`}
      className={`card${editing ? ' is-editing' : ''}${highlighted ? ' is-highlighted' : ''}`}
      tabIndex={editing ? -1 : 0}
      aria-label={plainText(card.front).slice(0, 120)}
      onKeyDown={editing ? undefined : (event) => onCardKeyDown(event, card, actions, setEditing)}
    >
      {editing ? (
        <CardEditor card={card} focus={editing} actions={actions} onDone={() => setEditing(null)} />
      ) : (
        <>
          <div className="card-main" onClick={(event) => onCardClick(event, setEditing)}>
            {folderLabel && <div className="card-folder">{folderLabel}</div>}
            <Markdown className="card-front" text={card.front} />
            <div className="card-divider" />
            <Markdown className="card-back" text={card.back} />
          </div>
          <div className="card-side">
            <StatusBadge progress={card.progress} />
            <div className="card-actions">
              <span
                className="icon-button card-grip"
                draggable
                title="Drag onto a topic to move"
                onDragStart={(event) => {
                  startDrag(event, { kind: 'card', id: card.id }, plainText(card.front))
                  const element = event.currentTarget.closest('.card')
                  if (element) event.dataTransfer.setDragImage(element, 20, 20)
                }}
                onDragEnd={endDrag}
              >
                <GripIcon />
              </span>
              <button type="button" className="icon-button" title="Edit (Return)" aria-label="Edit card" onClick={() => setEditing('front')}>
                <EditIcon />
              </button>
              <button type="button" className="icon-button" title="Move to… (M)" aria-label="Move card" onClick={() => actions.requestMove(card.id)}>
                <MoveIcon />
              </button>
              <button type="button" className="icon-button icon-button-danger" title="Delete (⌫)" aria-label="Delete card" onClick={() => actions.remove(card.id)}>
                <TrashIcon />
              </button>
              <button
                type="button"
                className="icon-button"
                title="More"
                aria-label="More card actions"
                aria-haspopup="menu"
                onClick={(event) => {
                  const box = event.currentTarget.getBoundingClientRect()
                  setMenuAt({ x: box.left, y: box.bottom + 4 })
                }}
              >
                <MoreIcon />
              </button>
            </div>
          </div>
          {menuAt && (
            <Menu
              label="Card actions"
              at={menuAt}
              onClose={() => setMenuAt(null)}
              items={studied
                ? [
                    { label: 'Review today', icon: <RefreshIcon />, onSelect: () => actions.reviewToday(card.id) },
                    { label: 'Reset progress…', icon: <RefreshIcon />, danger: true, onSelect: () => setConfirmingReset(true) },
                  ]
                : [{ label: 'Not studied yet: it’s already a new card', onSelect: () => {} }]}
            />
          )}
          {confirmingReset && (
            <ConfirmDialog
              title="Reset this card’s progress?"
              message="It will come back as a new card, as if you’d never studied it. Its review history is kept."
              confirmLabel="Reset Progress"
              destructive
              onConfirm={() => {
                setConfirmingReset(false)
                actions.resetProgress(card.id)
              }}
              onCancel={() => setConfirmingReset(false)}
            />
          )}
        </>
      )}
    </article>
  )
})

function onCardClick(event: MouseEvent<HTMLElement>, setEditing: (field: 'front' | 'back') => void) {
  const target = event.target as HTMLElement
  // Let links work and don't interrupt selecting text to copy it.
  if (target.closest('a')) return
  if (window.getSelection()?.toString()) return
  setEditing(target.closest('.card-back') ? 'back' : 'front')
}

function onCardKeyDown(
  event: KeyboardEvent<HTMLElement>,
  card: CardRecord,
  actions: CardActions,
  setEditing: (field: 'front' | 'back') => void,
) {
  if (event.target !== event.currentTarget || event.metaKey || event.ctrlKey || event.altKey) return
  const focusSibling = (step: 1 | -1) => {
    const cards = [...document.querySelectorAll<HTMLElement>('.card[tabindex="0"]')]
    cards[cards.indexOf(event.currentTarget) + step]?.focus()
  }
  switch (event.key) {
    case 'Enter':
      setEditing('front')
      break
    case 'Backspace':
    case 'Delete':
      focusSibling(1)
      actions.remove(card.id)
      break
    case 'm':
    case 'M':
      actions.requestMove(card.id)
      break
    case 'ArrowDown':
    case 'j':
      focusSibling(1)
      break
    case 'ArrowUp':
    case 'k':
      focusSibling(-1)
      break
    default:
      return
  }
  event.preventDefault()
}

interface EditorProps {
  card: CardRecord
  focus: 'front' | 'back'
  actions: CardActions
  onDone: () => void
}

/** The inline editor. Its draft is local, so library refreshes from the phone never overwrite it. */
function CardEditor({ card, focus, actions, onDone }: EditorProps) {
  const [front, setFront] = useState(card.front)
  const [back, setBack] = useState(card.back)
  const [saving, setSaving] = useState(false)
  const [confirmingDiscard, setConfirmingDiscard] = useState(false)
  const frontRef = useRef<HTMLTextAreaElement>(null)
  const backRef = useRef<HTMLTextAreaElement>(null)
  const frontImages = useImageInsertion(frontRef, setFront)
  const backImages = useImageInsertion(backRef, setBack)
  const uploading = frontImages.uploading || backImages.uploading

  useEffect(() => {
    const field = focus === 'back' ? backRef.current : frontRef.current
    field?.focus()
    field?.setSelectionRange(field.value.length, field.value.length)
  }, [focus])

  const close = () => {
    onDone()
    // Return focus to the card so keyboard navigation continues from here.
    requestAnimationFrame(() => document.getElementById(`card-${card.id}`)?.focus())
  }

  const hasChanges = front.trim() !== card.front || back.trim() !== card.back

  /** Esc and Cancel ask before throwing away an edit, as the iPhone does. */
  const cancel = () => (hasChanges ? setConfirmingDiscard(true) : close())

  const save = async () => {
    if (saving || uploading) return
    if (!hasChanges) return close()
    if (!front.trim() || !back.trim()) {
      ;(front.trim() ? backRef : frontRef).current?.focus()
      return
    }
    setSaving(true)
    const ok = await actions.save(card.id, front, back)
    setSaving(false)
    if (ok) close()
  }

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'Enter' && hasModifier(event)) {
      event.preventDefault()
      void save()
    } else if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      cancel()
    }
  }

  return (
    <>
      <div className="card-editor" onKeyDown={onKeyDown}>
        <label className="field-label" htmlFor={`edit-front-${card.id}`}>Question</label>
        <AutoTextarea
          id={`edit-front-${card.id}`}
          ref={frontRef}
          className="field-input"
          rows={1}
          value={front}
          onChange={(event) => setFront(event.target.value)}
          onPaste={frontImages.onPaste}
          onDragOver={frontImages.onDragOver}
          onDrop={frontImages.onDrop}
        />
        <label className="field-label" htmlFor={`edit-back-${card.id}`}>Answer</label>
        <AutoTextarea
          id={`edit-back-${card.id}`}
          ref={backRef}
          className="field-input"
          rows={2}
          value={back}
          onChange={(event) => setBack(event.target.value)}
          onPaste={backImages.onPaste}
          onDragOver={backImages.onDragOver}
          onDrop={backImages.onDrop}
        />
        <div className="card-editor-footer">
          <span className="quick-hint">
            {uploading ? 'Uploading image…' : <><kbd>{modKey}↩</kbd> save · <kbd>Esc</kbd> cancel · paste images with <kbd>{modKey}V</kbd></>}
          </span>
          <button type="button" className="button" onClick={cancel}>Cancel</button>
          <button type="button" className="button button-primary" disabled={saving || uploading} onClick={() => void save()}>
            Save
          </button>
        </div>
      </div>
      {/* Outside the editor, so its keys (Esc, ⌘↩) don't reach the editor's handler. */}
      {confirmingDiscard && (
        <ConfirmDialog
          title="Discard your changes?"
          message="Your edits to this card haven’t been saved."
          confirmLabel="Discard"
          cancelLabel="Keep Editing"
          destructive
          onConfirm={close}
          onCancel={() => setConfirmingDiscard(false)}
        />
      )}
    </>
  )
}

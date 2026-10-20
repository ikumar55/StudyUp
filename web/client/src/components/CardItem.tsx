import { memo, useEffect, useRef, useState } from 'react'
import type { KeyboardEvent, MouseEvent } from 'react'
import type { CardRecord } from '../../../shared/protocol.ts'
import { endDrag, startDrag } from '../dragAndDrop.ts'
import { hasModifier, modKey, plainText } from '../format.ts'
import type { CardActions } from '../types.ts'
import { AutoTextarea } from './AutoTextarea.tsx'
import { EditIcon, GripIcon, MoveIcon, TrashIcon } from './Icons.tsx'
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
            </div>
          </div>
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
  const frontRef = useRef<HTMLTextAreaElement>(null)
  const backRef = useRef<HTMLTextAreaElement>(null)

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

  const save = async () => {
    if (saving) return
    if (front.trim() === card.front && back.trim() === card.back) return close()
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
      close()
    }
  }

  return (
    <div className="card-editor" onKeyDown={onKeyDown}>
      <label className="field-label" htmlFor={`edit-front-${card.id}`}>Question</label>
      <AutoTextarea
        id={`edit-front-${card.id}`}
        ref={frontRef}
        className="field-input"
        rows={1}
        value={front}
        onChange={(event) => setFront(event.target.value)}
      />
      <label className="field-label" htmlFor={`edit-back-${card.id}`}>Answer</label>
      <AutoTextarea
        id={`edit-back-${card.id}`}
        ref={backRef}
        className="field-input"
        rows={2}
        value={back}
        onChange={(event) => setBack(event.target.value)}
      />
      <div className="card-editor-footer">
        <span className="quick-hint"><kbd>{modKey}↩</kbd> save · <kbd>Esc</kbd> cancel</span>
        <button type="button" className="button" onClick={close}>Cancel</button>
        <button type="button" className="button button-primary" disabled={saving} onClick={() => void save()}>
          Save
        </button>
      </div>
    </div>
  )
}

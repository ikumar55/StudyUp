import { useEffect, useRef, useState } from 'react'
import type { KeyboardEvent, RefObject } from 'react'
import { expandCloze, hasCloze } from '../cloze.ts'
import { hasModifier, modKey } from '../format.ts'
import { loadValue, saveValue } from '../storage.ts'
import { useImageInsertion } from '../useImageInsertion.ts'
import { AutoTextarea } from './AutoTextarea.tsx'
import { CheckIcon, ImageIcon } from './Icons.tsx'
import { Markdown } from './Markdown.tsx'

interface Draft {
  front: string
  back: string
}

interface Props {
  folderName: string
  /** Adds the card(s); resolves to false if the server refused them. A cloze question makes several. */
  onAdd: (cards: { front: string; back: string }[]) => Promise<boolean>
  questionRef: RefObject<HTMLTextAreaElement | null>
}

const emptyDraft: Draft = { front: '', back: '' }

/**
 * The card entry form. ⌘↩ adds the card, clears both fields, and returns to Question, so cards can be
 * typed one after another without the mouse. The draft survives reloads and switching topics.
 */
export function QuickAdd({ folderName, onAdd, questionRef }: Props) {
  const [draft, setDraft] = useState<Draft>(() => loadValue('draft', emptyDraft))
  const [preview, setPreview] = useState(() => loadValue('preview', false))
  const [added, setAdded] = useState<{ count: number; folder: string } | null>(null)
  const [hint, setHint] = useState<string | null>(null)
  const answerRef = useRef<HTMLTextAreaElement>(null)
  const draftRef = useRef(draft)
  draftRef.current = draft
  // Screenshots usually illustrate the answer, so the Image button targets it unless Question was used last.
  const [lastField, setLastField] = useState<keyof Draft>('back')
  const frontImages = useImageInsertion(questionRef, (edit) => setDraft((d) => ({ ...d, front: edit(d.front) })))
  const backImages = useImageInsertion(answerRef, (edit) => setDraft((d) => ({ ...d, back: edit(d.back) })))
  const uploading = frontImages.uploading || backImages.uploading
  const clozeCards = hasCloze(draft.front) ? expandCloze(draft.front.trim(), draft.back) : null

  useEffect(() => saveValue('draft', draft.front || draft.back ? draft : undefined), [draft])
  useEffect(() => saveValue('preview', preview), [preview])

  // The confirmation fades on its own.
  useEffect(() => {
    if (!added) return
    const timer = setTimeout(() => setAdded(null), 2400)
    return () => clearTimeout(timer)
  }, [added])

  useEffect(() => {
    if (!hint) return
    const timer = setTimeout(() => setHint(null), 2400)
    return () => clearTimeout(timer)
  }, [hint])

  const submit = async () => {
    const front = draft.front.trim()
    const back = draft.back.trim()
    if (!front) {
      setHint('Write a question first.')
      questionRef.current?.focus()
      return
    }
    const cloze = hasCloze(front)
    if (!back && !cloze) {
      // ⌘↩ in Question with no answer yet just moves on to Answer.
      answerRef.current?.focus()
      return
    }
    if (uploading) {
      setHint('Wait for the image to finish uploading.')
      return
    }
    // Clear right away so the next card can be typed while this one saves.
    setDraft(emptyDraft)
    setHint(null)
    questionRef.current?.focus()
    const cards = cloze ? expandCloze(front, back) : [{ front, back }]
    const ok = await onAdd(cards)
    if (ok) {
      setAdded((current) => ({ count: (current?.folder === folderName ? current.count : 0) + cards.length, folder: folderName }))
    } else if (!draftRef.current.front && !draftRef.current.back) {
      // Put the text back so nothing is lost.
      setDraft({ front, back })
    }
  }

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && hasModifier(event)) {
      event.preventDefault()
      void submit()
    }
  }

  const update = (field: keyof Draft) => (event: { target: { value: string } }) =>
    setDraft((current) => ({ ...current, [field]: event.target.value }))

  return (
    <section className="quick-add" aria-label="Add a card">
      <div className="field">
        <label htmlFor="quick-front" className="field-label">Question</label>
        <AutoTextarea
          id="quick-front"
          ref={questionRef}
          className="field-input"
          rows={1}
          placeholder="What does the TLB cache?"
          value={draft.front}
          onChange={update('front')}
          onKeyDown={onKeyDown}
          onFocus={() => setLastField('front')}
          onPaste={frontImages.onPaste}
          onDragOver={frontImages.onDragOver}
          onDrop={frontImages.onDrop}
        />
      </div>
      <div className="field">
        <label htmlFor="quick-back" className="field-label">Answer</label>
        <AutoTextarea
          id="quick-back"
          ref={answerRef}
          className="field-input"
          rows={2}
          placeholder="Recent virtual-to-physical page translations."
          value={draft.back}
          onChange={update('back')}
          onKeyDown={onKeyDown}
          onFocus={() => setLastField('back')}
          onPaste={backImages.onPaste}
          onDragOver={backImages.onDragOver}
          onDrop={backImages.onDrop}
        />
      </div>

      {preview && clozeCards && clozeCards.map((card, i) => (
        <div key={i} className="quick-preview" aria-label={`Preview of cloze card ${i + 1}`}>
          <Markdown className="card-front" text={card.front} />
          <div className="card-divider" />
          <Markdown className="card-back" text={card.back} />
        </div>
      ))}
      {preview && !clozeCards && (draft.front.trim() || draft.back.trim()) && (
        <div className="quick-preview" aria-label="Preview">
          <Markdown className="card-front" text={draft.front || ' '} />
          <div className="card-divider" />
          <Markdown className="card-back" text={draft.back || ' '} />
        </div>
      )}

      <div className="quick-footer">
        <div className="quick-status" aria-live="polite">
          {hint ? (
            <span className="quick-hint-warning">{hint}</span>
          ) : uploading ? (
            <span className="quick-hint">Uploading image…</span>
          ) : clozeCards ? (
            <span className="quick-hint">
              Cloze: makes {clozeCards.length} {clozeCards.length === 1 ? 'card' : 'cards'}. Answer is optional (an extra note).
            </span>
          ) : added ? (
            <span key={added.count} className="quick-added">
              <CheckIcon /> {added.count > 1 ? `${added.count} cards added` : 'Card added'} to {added.folder}
            </span>
          ) : (
            <span className="quick-hint">
              <kbd>{modKey}↩</kbd> add · <kbd>Tab</kbd> next field · paste images · $math$
            </span>
          )}
        </div>
        <label className="toggle">
          <input type="checkbox" checked={preview} onChange={(event) => setPreview(event.target.checked)} />
          Preview
        </label>
        <button
          type="button"
          className="button button-quiet"
          title={`Add an image to the ${lastField === 'front' ? 'question' : 'answer'}`}
          onClick={() => (lastField === 'front' ? frontImages : backImages).pick()}
        >
          <ImageIcon /> Image…
        </button>
        <button type="button" className="button button-primary" onClick={() => void submit()}>
          Add card
        </button>
      </div>
    </section>
  )
}

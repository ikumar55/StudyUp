import { useEffect, useRef, useState } from 'react'
import type { ClipboardEvent, KeyboardEvent, RefObject } from 'react'
import { parseBulk } from '../bulkParse.ts'
import { hasModifier, modKey } from '../format.ts'
import { loadValue, saveValue } from '../storage.ts'
import { useImageInsertion } from '../useImageInsertion.ts'
import { AutoTextarea } from './AutoTextarea.tsx'
import { CheckIcon, ImageIcon, ImportIcon } from './Icons.tsx'
import { Markdown } from './Markdown.tsx'

interface Draft {
  front: string
  back: string
}

interface Props {
  folderName: string
  /** Adds the card; resolves to false if the server refused it. */
  onAdd: (front: string, back: string) => Promise<boolean>
  onBulkAdd: (text?: string) => void
  questionRef: RefObject<HTMLTextAreaElement | null>
}

const emptyDraft: Draft = { front: '', back: '' }

/**
 * The card entry form. ⌘↩ adds the card, clears both fields, and returns to Question, so cards can be
 * typed one after another without the mouse. The draft survives reloads and switching topics.
 */
export function QuickAdd({ folderName, onAdd, onBulkAdd, questionRef }: Props) {
  const [draft, setDraft] = useState<Draft>(() => loadValue('draft', emptyDraft))
  const [preview, setPreview] = useState(() => loadValue('preview', false))
  const [added, setAdded] = useState<{ count: number; folder: string } | null>(null)
  const [hint, setHint] = useState<string | null>(null)
  const [pasteOffer, setPasteOffer] = useState<{ text: string; count: number; before: Draft } | null>(null)
  const answerRef = useRef<HTMLTextAreaElement>(null)
  const draftRef = useRef(draft)
  draftRef.current = draft
  // Screenshots usually illustrate the answer, so the Image button targets it unless Question was used last.
  const [lastField, setLastField] = useState<keyof Draft>('back')
  const frontImages = useImageInsertion(questionRef, (edit) => setDraft((d) => ({ ...d, front: edit(d.front) })))
  const backImages = useImageInsertion(answerRef, (edit) => setDraft((d) => ({ ...d, back: edit(d.back) })))
  const uploading = frontImages.uploading || backImages.uploading

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
    if (!back) {
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
    setPasteOffer(null)
    setHint(null)
    questionRef.current?.focus()
    const ok = await onAdd(front, back)
    if (ok) {
      setAdded((current) => ({ count: (current?.folder === folderName ? current.count : 0) + 1, folder: folderName }))
    } else if (!draftRef.current.front && !draftRef.current.back) {
      // Put the text back so nothing is lost.
      setDraft({ front, back })
    }
  }

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && hasModifier(event)) {
      event.preventDefault()
      void submit()
    } else if (event.key === 'Escape' && pasteOffer) {
      setPasteOffer(null)
    }
  }

  // Pasting notes with several cards offers to import them all at once.
  const onPaste = (event: ClipboardEvent<HTMLTextAreaElement>) => {
    const text = event.clipboardData.getData('text/plain')
    if (!text.includes('\n')) return
    const { format, cards, skipped } = parseBulk(text)
    // Pasted code (e.g. C++ with "::") shouldn't look like cards: require mostly-clean matches,
    // and for "::" lines, the spaced form.
    const spacedColons = text.split('\n').filter((line) => /\s::\s/.test(line)).length
    if (cards.length < 2 || skipped.length > cards.length / 4) return
    if (format === 'colons' && spacedColons < cards.length) return
    setPasteOffer({ text, count: cards.length, before: draft })
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
          onPaste={(event) => frontImages.onPaste(event) || onPaste(event)}
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
          onPaste={(event) => backImages.onPaste(event) || onPaste(event)}
          onDragOver={backImages.onDragOver}
          onDrop={backImages.onDrop}
        />
      </div>

      {pasteOffer && (
        <div className="paste-offer" role="status">
          <ImportIcon />
          <span>That looks like {pasteOffer.count} cards.</span>
          <button
            type="button"
            className="button button-small button-primary"
            onClick={() => {
              setDraft(pasteOffer.before)
              onBulkAdd(pasteOffer.text)
              setPasteOffer(null)
            }}
          >
            Import {pasteOffer.count} cards…
          </button>
          <button type="button" className="button button-small button-quiet" onClick={() => setPasteOffer(null)}>
            Keep as one card
          </button>
        </div>
      )}

      {preview && (draft.front.trim() || draft.back.trim()) && (
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
          ) : added ? (
            <span key={added.count} className="quick-added">
              <CheckIcon /> {added.count > 1 ? `${added.count} cards added` : 'Card added'} to {added.folder}
            </span>
          ) : (
            <span className="quick-hint">
              <kbd>{modKey}↩</kbd> add card · <kbd>Tab</kbd> next field · paste screenshots with <kbd>{modKey}V</kbd>
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
        <button type="button" className="button button-quiet" onClick={() => onBulkAdd()}>
          <ImportIcon /> Bulk add…
        </button>
        <button type="button" className="button button-primary" onClick={() => void submit()}>
          Add card
        </button>
      </div>
    </section>
  )
}

import { useDeferredValue, useMemo, useState } from 'react'
import type { KeyboardEvent } from 'react'
import { formatNames, parseBulk } from '../bulkParse.ts'
import { flattenTree } from '../libraryIndex.ts'
import type { BulkFormat } from '../bulkParse.ts'
import { hasModifier, modKey, plural } from '../format.ts'
import type { LibraryIndex } from '../libraryIndex.ts'
import { Dialog } from './Dialog.tsx'
import { FolderSelect } from './FolderSelect.tsx'
import { Markdown } from './Markdown.tsx'

interface Props {
  index: LibraryIndex
  initialText: string
  defaultFolderId: string
  /** Resolves to false if the import failed (the dialog stays open). */
  onImport: (folderId: string, cards: { front: string; back: string }[]) => Promise<boolean>
  onClose: () => void
}

const placeholder = `Paste notes in any of these formats:

Q: What does the TLB cache?
A: Recent virtual-to-physical
page translations.

What is a context switch? :: Saving one thread's state and loading another's

Gradient descent<TAB>Step against the gradient`

/** Shown when the preview would be very long; the import itself includes every card. */
const previewLimit = 200

export function BulkImportDialog({ index, initialText, defaultFolderId, onImport, onClose }: Props) {
  const [text, setText] = useState(initialText)
  const [formatChoice, setFormatChoice] = useState<BulkFormat | 'auto'>('auto')
  const [chosenFolderId, setFolderId] = useState(defaultFolderId)
  // If the chosen topic is deleted meanwhile (e.g. from the phone), fall back to the first one.
  const folderId = index.folders.has(chosenFolderId) ? chosenFolderId : (flattenTree(index)[0]?.folder.id ?? '')
  const [importing, setImporting] = useState(false)

  const deferredText = useDeferredValue(text)
  const parse = (value: string) => (formatChoice === 'auto' ? parseBulk(value) : parseBulk(value, formatChoice))
  const result = useMemo(() => parse(deferredText), [deferredText, formatChoice])
  const count = result.cards.length

  const submit = async () => {
    // Parse the latest text, in case the deferred preview hasn't caught up.
    const cards = parse(text).cards
    if (cards.length === 0 || importing || !index.folders.has(folderId)) return
    setImporting(true)
    const ok = await onImport(folderId, cards.map(({ front, back }) => ({ front, back })))
    setImporting(false)
    if (ok) onClose()
  }

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'Enter' && hasModifier(event)) {
      event.preventDefault()
      void submit()
    }
  }

  return (
    <Dialog title="Bulk add cards" onClose={onClose} className="dialog-wide">
      <div className="bulk" onKeyDown={onKeyDown}>
        <div className="bulk-input">
          <textarea
            className="bulk-textarea"
            value={text}
            placeholder={placeholder}
            spellCheck={false}
            onChange={(event) => setText(event.target.value)}
            onKeyDown={(event) => {
              // Allow typing a real tab for tab-separated lines.
              if (event.key === 'Tab' && !event.shiftKey && formatChoice === 'tab') {
                event.preventDefault()
                const target = event.currentTarget
                const { selectionStart, selectionEnd } = target
                setText(text.slice(0, selectionStart) + '\t' + text.slice(selectionEnd))
                requestAnimationFrame(() => target.setSelectionRange(selectionStart + 1, selectionStart + 1))
              }
            }}
            aria-label="Notes to turn into cards"
            data-autofocus
          />
          <div className="bulk-format">
            <label htmlFor="bulk-format">Format</label>
            <select
              id="bulk-format"
              className="select select-small"
              value={formatChoice}
              onChange={(event) => setFormatChoice(event.target.value as BulkFormat | 'auto')}
            >
              <option value="auto">
                Detect automatically{formatChoice === 'auto' && result.format ? ` (${formatNames[result.format]})` : ''}
              </option>
              {(Object.keys(formatNames) as BulkFormat[]).map((format) => (
                <option key={format} value={format}>{formatNames[format]}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="bulk-preview" aria-live="polite">
          <div className="bulk-preview-header">
            <strong>{plural(count, 'card')}</strong>
            {result.skipped.length > 0 && (
              <span className="bulk-skipped-count">{plural(result.skipped.length, 'line')} skipped</span>
            )}
          </div>
          {count === 0 && result.skipped.length === 0 && (
            <p className="bulk-empty">
              {text.trim() ? 'No cards found. Use “Q:” and “A:” lines, “question :: answer”, or tab-separated lines.' : 'The cards you paste will appear here.'}
            </p>
          )}
          {result.skipped.length > 0 && (
            <ul className="bulk-skipped">
              {result.skipped.slice(0, 20).map((line) => (
                <li key={line.line}>
                  <span className="bulk-line">Line {line.line}</span> {line.reason}: <q>{line.text.slice(0, 80)}</q>
                </li>
              ))}
            </ul>
          )}
          <ol className="bulk-cards">
            {result.cards.slice(0, previewLimit).map((card, i) => (
              <li key={`${card.line}-${i}`} className="bulk-card">
                <span className="bulk-card-number">{i + 1}</span>
                <div className="bulk-card-body">
                  <Markdown className="card-front" text={card.front} />
                  <div className="card-divider" />
                  <Markdown className="card-back" text={card.back} />
                </div>
              </li>
            ))}
          </ol>
          {count > previewLimit && <p className="bulk-empty">…and {count - previewLimit} more</p>}
        </div>
      </div>

      <footer className="dialog-footer">
        <label className="bulk-target" htmlFor="bulk-folder">
          Add to
          <FolderSelect id="bulk-folder" index={index} value={folderId} onChange={setFolderId} />
        </label>
        <span className="dialog-footer-spacer" />
        <span className="quick-hint"><kbd>{modKey}↩</kbd> import</span>
        <button type="button" className="button" onClick={onClose}>Cancel</button>
        <button type="button" className="button button-primary" disabled={count === 0 || importing || !folderId} onClick={() => void submit()}>
          {importing ? 'Importing…' : count === 0 ? 'Import' : `Import ${plural(count, 'card')}`}
        </button>
      </footer>
    </Dialog>
  )
}

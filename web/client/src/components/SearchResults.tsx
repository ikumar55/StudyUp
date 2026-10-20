import { useEffect, useRef } from 'react'
import { pathLabel } from '../libraryIndex.ts'
import type { LibraryIndex } from '../libraryIndex.ts'
import { highlightParts, searchTerms, snippet } from '../search.ts'
import type { SearchResult } from '../search.ts'
import { StatusBadge } from './StatusBadge.tsx'

interface Props {
  index: LibraryIndex
  query: string
  results: SearchResult[]
  total: number
  active: number
  onActiveChange: (index: number) => void
  onOpen: (result: SearchResult) => void
}

/** Matches across every topic. ↑↓ in the search box choose, Return opens, Esc clears. */
export function SearchResults({ index, query, results, total, active, onActiveChange, onOpen }: Props) {
  const terms = searchTerms(query)
  const list = useRef<HTMLUListElement>(null)

  useEffect(() => {
    list.current?.querySelector('.is-active')?.scrollIntoView({ block: 'nearest' })
  }, [active])

  return (
    <div className="search-view">
      <header className="folder-header">
        <h1 className="folder-title">Search</h1>
        <p className="folder-meta">
          {total === 0
            ? `No cards match “${query.trim()}”`
            : `${total.toLocaleString()} ${total === 1 ? 'card matches' : 'cards match'} “${query.trim()}”`}
          {total > results.length && ` · showing the first ${results.length}`}
        </p>
      </header>
      {total === 0 ? (
        <div className="empty-state empty-state-inline">
          <p className="empty-text">Search looks in every card’s question and answer. Try fewer or different words.</p>
        </div>
      ) : (
        <ul ref={list} id="search-results" className="search-results" role="listbox" aria-label="Search results">
          {results.map((result, position) => (
            <li key={result.card.id} role="option" aria-selected={position === active}>
              <button
                type="button"
                className={`search-result${position === active ? ' is-active' : ''}`}
                onMouseEnter={() => onActiveChange(position)}
                onClick={() => onOpen(result)}
              >
                <span className="search-path">{pathLabel(index, result.card.folderId)}</span>
                <span className="search-front"><Highlighted text={snippet(result.front, terms)} terms={terms} /></span>
                <span className="search-back"><Highlighted text={snippet(result.back, terms)} terms={terms} /></span>
                <StatusBadge progress={result.card.progress} />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function Highlighted({ text, terms }: { text: string; terms: string[] }) {
  return (
    <>
      {highlightParts(text, terms).map((part, i) => (part.match ? <mark key={i}>{part.text}</mark> : part.text))}
    </>
  )
}

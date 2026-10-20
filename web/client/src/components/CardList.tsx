import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import type { CardRecord } from '../../../shared/protocol.ts'
import type { CardActions } from '../types.ts'
import { CardItem } from './CardItem.tsx'

interface Props {
  cards: CardRecord[]
  actions: CardActions
  /** A label for cards that live in a subfolder, or undefined for cards in this folder. */
  folderLabel?: (card: CardRecord) => string | undefined
  /** A card to scroll to and flash (after jumping from search). */
  highlightId: string | null
  empty: ReactNode
}

/** Cards render in pages so a folder with hundreds of cards stays quick. */
const pageSize = 150

export function CardList({ cards, actions, folderLabel, highlightId, empty }: Props) {
  const [limit, setLimit] = useState(pageSize)

  // Make sure a card being jumped to is rendered.
  const highlightIndex = highlightId ? cards.findIndex((card) => card.id === highlightId) : -1
  const shown = Math.max(limit, highlightIndex + 1)

  useEffect(() => {
    if (!highlightId) return
    const element = document.getElementById(`card-${highlightId}`)
    element?.scrollIntoView({ block: 'center', behavior: 'smooth' })
    element?.focus({ preventScroll: true })
  }, [highlightId])

  if (cards.length === 0) return <>{empty}</>

  return (
    <div className="card-list">
      {cards.slice(0, shown).map((card) => (
        <CardItem
          key={card.id}
          card={card}
          actions={actions}
          folderLabel={folderLabel?.(card)}
          highlighted={card.id === highlightId}
        />
      ))}
      {cards.length > shown && (
        <button type="button" className="button show-more" onClick={() => setLimit((current) => current + pageSize)}>
          Show {Math.min(pageSize, cards.length - shown)} more of {cards.length - shown}
        </button>
      )}
    </div>
  )
}

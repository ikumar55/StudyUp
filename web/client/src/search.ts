import type { CardRecord } from '../../shared/protocol.ts'
import { plainText } from './format.ts'

export interface SearchResult {
  card: CardRecord
  front: string
  back: string
}

/** Lowercased words; a card matches when every word appears in its question or answer. */
export function searchTerms(query: string): string[] {
  return query.toLowerCase().split(/\s+/).filter(Boolean)
}

export function searchCards(cards: CardRecord[], query: string, limit = 200): { results: SearchResult[]; total: number } {
  const terms = searchTerms(query)
  if (terms.length === 0) return { results: [], total: 0 }
  const results: SearchResult[] = []
  let total = 0
  for (const card of cards) {
    const haystack = `${card.front}\n${card.back}`.toLowerCase()
    if (!terms.every((term) => haystack.includes(term))) continue
    total += 1
    if (results.length < limit) results.push({ card, front: plainText(card.front), back: plainText(card.back) })
  }
  return { results, total }
}

/** Splits text into plain and matching parts for highlighting. */
export function highlightParts(text: string, terms: string[]): { text: string; match: boolean }[] {
  if (terms.length === 0) return [{ text, match: false }]
  const escaped = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
  const pattern = new RegExp(`(${escaped.join('|')})`, 'gi')
  return text.split(pattern).filter(Boolean).map((part) => ({
    text: part,
    match: terms.includes(part.toLowerCase()),
  }))
}

/** A window of text around the first match, so long answers still show why they matched. */
export function snippet(text: string, terms: string[], length = 180): string {
  if (text.length <= length) return text
  const lower = text.toLowerCase()
  const first = Math.min(...terms.map((term) => lower.indexOf(term)).filter((at) => at >= 0), Infinity)
  if (!Number.isFinite(first) || first < length / 2) return `${text.slice(0, length).trimEnd()}…`
  const start = Math.max(0, first - Math.floor(length / 3))
  return `…${text.slice(start, start + length).trim()}…`
}

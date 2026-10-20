import type { Progress } from '../../shared/protocol.ts'

const minute = 60_000
const hour = 60 * minute
const day = 24 * hour

export type StatusTone = 'new' | 'learning' | 'due' | 'scheduled'

export interface CardStatus {
  label: string
  tone: StatusTone
  /** Longer description for a tooltip. */
  detail: string
}

/** The study status shown on a card, from the progress the iPhone reports. */
export function cardStatus(progress: Progress | null, now: number): CardStatus {
  if (!progress || progress.state === 0) {
    return { label: 'New', tone: 'new', detail: 'Not studied yet' }
  }
  const history = reviewHistory(progress)
  if (progress.state === 1 || progress.state === 3) {
    const label = progress.state === 3 ? 'Relearning' : 'Learning'
    return { label: 'Learning', tone: 'learning', detail: `${label} · ${history}` }
  }
  if (progress.due <= now) {
    return { label: 'Due now', tone: 'due', detail: `Due since ${formatDateTime(progress.due)} · ${history}` }
  }
  return {
    label: `Due in ${shortDuration(progress.due - now)}`,
    tone: 'scheduled',
    detail: `Next review ${formatDateTime(progress.due)} · ${history}`,
  }
}

export function isDue(progress: Progress | null, now: number): boolean {
  return progress !== null && progress.state !== 0 && progress.due <= now
}

function reviewHistory(progress: Progress): string {
  const reviews = `${progress.reps} review${progress.reps === 1 ? '' : 's'}`
  if (progress.lapses === 0) return reviews
  return `${reviews}, ${progress.lapses} lapse${progress.lapses === 1 ? '' : 's'}`
}

/** "25m", "5h", "3d", "2mo", "1y". */
export function shortDuration(ms: number): string {
  if (ms < hour) return `${Math.max(1, Math.round(ms / minute))}m`
  if (ms < day) return `${Math.round(ms / hour)}h`
  if (ms < 30 * day) return `${Math.round(ms / day)}d`
  if (ms < 365 * day) return `${Math.round(ms / (30 * day))}mo`
  return `${Math.round(ms / (365 * day))}y`
}

/** "just now", "2 min ago", "3 hr ago", "yesterday", "4 days ago", or a date. */
export function timeAgo(time: number, now: number): string {
  const elapsed = Math.max(0, now - time)
  if (elapsed < 45_000) return 'just now'
  if (elapsed < hour) return `${Math.max(1, Math.round(elapsed / minute))} min ago`
  if (elapsed < day) {
    const hours = Math.round(elapsed / hour)
    return `${hours} hr ago`
  }
  if (elapsed < 2 * day) return 'yesterday'
  if (elapsed < 7 * day) return `${Math.floor(elapsed / day)} days ago`
  return `on ${formatDate(time)}`
}

export function formatDate(time: number): string {
  return new Date(time).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
}

export function formatDateTime(time: number): string {
  return new Date(time).toLocaleString(undefined, {
    weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  })
}

/** "9:42" for a countdown. */
export function countdown(ms: number): string {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000))
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}:${String(seconds).padStart(2, '0')}`
}

export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${count.toLocaleString()} ${count === 1 ? singular : pluralForm}`
}

export const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent)

/** The platform's command key, for shortcut hints. */
export const modKey = isMac ? '⌘' : 'Ctrl+'

/** True for ⌘ on a Mac and Ctrl elsewhere. */
export function hasModifier(event: { metaKey: boolean; ctrlKey: boolean }): boolean {
  return isMac ? event.metaKey : event.ctrlKey
}

/** Markdown reduced to plain text, for search snippets. */
export function plainText(markdown: string): string {
  return markdown
    .replace(/```[^\n]*\n?/g, '')
    .replace(/`([^`]*)`/g, '$1')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/(\*\*|__)(.*?)\1/g, '$2')
    .replace(/(^|\s)[*_](\S[^*_]*?)[*_](?=\s|$|[.,;:!?])/g, '$1$2')
    .replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+/gm, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * * Cards are short notes, so a single Return should start a new line rather than
 * being folded into the paragraph as standard Markdown does. Code blocks are left alone.
 */
export function keepLineBreaks(text: string): string {
  return text
    .split(/(^(?:```|~~~)[^\n]*\n[\s\S]*?(?:^(?:```|~~~)\s*$|(?![\s\S])))/m)
    .map((part, i) => (i % 2 === 1 ? part : part.replace(/([^\n])\n(?=[^\n])/g, '$1  \n')))
    .join('')
}

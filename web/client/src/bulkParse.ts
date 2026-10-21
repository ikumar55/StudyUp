// Turns pasted notes into cards. Pure, so it can be tested with `node --test`.
//
// Supported formats (detected automatically):
//   qa      Blocks of "Q: ..." / "A: ..." lines. Questions and answers can span lines;
//           an answer runs until the next "Q:". Also accepts "Question:"/"Answer:",
//           a leading list marker ("- Q:"), and bold labels ("**Q:**").
//   colons  One card per line: "question :: answer".
//   tab     One card per line: "question<TAB>answer" (e.g. a spreadsheet or Anki export).
//   cloze   One sentence per line with {{blanks}}; each blank becomes a card (see cloze.ts).
//
// In every format, a question with {{blanks}} needs no answer and expands into one card per blank.

import { expandCloze, hasCloze } from './cloze.ts'

export type BulkFormat = 'qa' | 'colons' | 'tab' | 'cloze'

export interface ParsedCard {
  front: string
  back: string
  /** 1-based line where the card starts. */
  line: number
}

export interface SkippedLine {
  line: number
  text: string
  reason: string
}

export interface BulkParseResult {
  format: BulkFormat | null
  cards: ParsedCard[]
  skipped: SkippedLine[]
}

export const formatNames: Record<BulkFormat, string> = {
  qa: 'Q: / A: blocks',
  colons: 'question :: answer',
  tab: 'Tab-separated',
  cloze: 'Cloze sentences ({{…}})',
}

const questionLabel = /^\s*(?:[-*+]\s+)?(\*\*|__)?(?:q|question)(?:\1)?\s*[:：]\s*(?:\1)?\s?/i
const answerLabel = /^\s*(?:[-*+]\s+)?(\*\*|__)?(?:a|answer)(?:\1)?\s*[:：]\s*(?:\1)?\s?/i
const fence = /^\s*(```|~~~)/
/** A "::" with space on at least one side is preferred, so "What does std::move do? :: ..." splits correctly. */
const spacedColons = /\s::|::\s/

export function parseBulk(text: string, format: BulkFormat | null = detectFormat(text)): BulkParseResult {
  const lines = text.replace(/\r\n?/g, '\n').split('\n')
  const parsed = (() => {
    switch (format) {
      case 'qa': return parseQA(lines)
      case 'colons': return parseLines(lines, splitColons, 'No “::” on this line')
      case 'tab': return parseLines(lines, splitTab, 'No tab on this line')
      case 'cloze': return parseLines(lines, (line) => (hasCloze(line) ? [line.trim(), ''] : null), 'No {{blank}} on this line')
      default: return null
    }
  })()
  if (!parsed) return { format: null, cards: [], skipped: [] }
  return { format, cards: parsed.cards.flatMap(expandBlanks), skipped: parsed.skipped }
}

/** A card whose question has {{blanks}} becomes one card per blank. */
function expandBlanks(card: ParsedCard): ParsedCard[] {
  if (!hasCloze(card.front)) return [card]
  return expandCloze(card.front, card.back).map((expanded) => ({ ...expanded, line: card.line }))
}

/** Q:/A: labels are explicit, so they win whenever both appear; otherwise the format with more matching lines. */
export function detectFormat(text: string): BulkFormat | null {
  const lines = text.replace(/\r\n?/g, '\n').split('\n')
  let questions = 0
  let answers = 0
  let colons = 0
  let tabs = 0
  let clozes = 0
  for (const line of lines) {
    if (questionLabel.test(line)) questions += 1
    else if (answerLabel.test(line)) answers += 1
    if (splitColons(line)) colons += 1
    if (splitTab(line)) tabs += 1
    if (hasCloze(line)) clozes += 1
  }
  if (questions > 0 && (answers > 0 || clozes > 0)) return 'qa'
  if (colons === 0 && tabs === 0) return clozes > 0 ? 'cloze' : null
  return colons >= tabs ? 'colons' : 'tab'
}

function parseQA(lines: string[]): { cards: ParsedCard[]; skipped: SkippedLine[] } {
  const cards: ParsedCard[] = []
  const skipped: SkippedLine[] = []
  let current: { line: number; front: string[]; back: string[]; inAnswer: boolean } | null = null
  let inFence = false

  const finish = () => {
    if (!current) return
    const front = joinLines(current.front)
    const back = joinLines(current.back)
    if (front && (back || hasCloze(front))) {
      cards.push({ front, back, line: current.line })
    } else {
      skipped.push({
        line: current.line,
        text: front || back,
        reason: front ? 'Question has no answer' : 'Answer has no question',
      })
    }
    current = null
  }

  lines.forEach((line, index) => {
    const lineNumber = index + 1
    if (!inFence) {
      const question = questionLabel.exec(line)
      if (question) {
        finish()
        current = { line: lineNumber, front: [line.slice(question[0].length)], back: [], inAnswer: false }
        return
      }
      const answer = answerLabel.exec(line)
      if (answer && current && !current.inAnswer) {
        current.inAnswer = true
        current.back.push(line.slice(answer[0].length))
        return
      }
    }
    if (fence.test(line)) inFence = !inFence

    if (current) {
      ;(current.inAnswer ? current.back : current.front).push(line)
    } else if (line.trim()) {
      skipped.push({ line: lineNumber, text: line.trim(), reason: 'Not part of a Q:/A: block' })
    }
  })
  finish()
  return { cards, skipped }
}

function parseLines(
  lines: string[],
  split: (line: string) => [string, string] | null,
  missingReason: string,
): { cards: ParsedCard[]; skipped: SkippedLine[] } {
  const cards: ParsedCard[] = []
  const skipped: SkippedLine[] = []
  lines.forEach((line, index) => {
    const lineNumber = index + 1
    if (!line.trim() || isAnkiHeader(line)) return
    const parts = split(line)
    if (!parts) {
      skipped.push({ line: lineNumber, text: line.trim(), reason: missingReason })
      return
    }
    const [front, back] = parts
    if (!front) skipped.push({ line: lineNumber, text: line.trim(), reason: 'Missing question' })
    else if (!back && !hasCloze(front)) skipped.push({ line: lineNumber, text: line.trim(), reason: 'Missing answer' })
    else cards.push({ front, back, line: lineNumber })
  })
  return { cards, skipped }
}

function splitColons(line: string): [string, string] | null {
  const spaced = spacedColons.exec(line)
  const at = spaced ? line.indexOf('::', spaced.index) : line.indexOf('::')
  if (at === -1) return null
  return [line.slice(0, at).trim(), line.slice(at + 2).trim()]
}

function splitTab(line: string): [string, string] | null {
  const at = line.indexOf('\t')
  if (at === -1) return null
  return [line.slice(0, at).trim(), line.slice(at + 1).trim()]
}

/** Anki text exports start with lines like "#separator:tab". */
function isAnkiHeader(line: string): boolean {
  return /^#[a-z ]+:/i.test(line)
}

/** Joins lines, dropping blank lines at the start and end but keeping indentation (for code). */
function joinLines(lines: string[]): string {
  let start = 0
  let end = lines.length
  while (start < end && !lines[start].trim()) start += 1
  while (end > start && !lines[end - 1].trim()) end -= 1
  return lines.slice(start, end).map((line) => line.trimEnd()).join('\n').trim()
}

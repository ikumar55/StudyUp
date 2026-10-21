// Cloze (fill-in-the-blank) cards. Pure, so it can be tested with `node --test`.
// The iPhone has the same rules in StudyUp/Content/Cloze.swift.
//
//   A {{page fault}} occurs when a page isn't in {{physical memory}}.   → two cards, one per blank
//   {{c1::TCP}} is reliable; {{c1::UDP}} is not; {{c2::QUIC}} …         → blanks sharing a number hide together
//   The {{TLB::a cache}} holds translations.                             → "[a cache]" is shown as a hint
//
// Each card's front hides its blank(s) as **[…]**; its back is the whole sentence with the answer in
// bold, so the answer is seen in context. Anything typed as the answer is added below as an extra note.

const CLOZE = /\{\{(?:c(\d+)::)?(.+?)(?:::(.+?))?\}\}/g

interface Deletion {
  start: number
  end: number
  group: string
  answer: string
  hint: string | undefined
}

export function hasCloze(text: string): boolean {
  return deletions(text).length > 0
}

/** The cards a cloze question makes, in order of first appearance. Empty if there are no blanks. */
export function expandCloze(question: string, extra = ''): { front: string; back: string }[] {
  const found = deletions(question)
  const groups = [...new Set(found.map((d) => d.group))]
  const note = extra.trim()
  return groups.map((group) => {
    const render = (hidden: (d: Deletion) => string) => {
      let text = ''
      let last = 0
      for (const deletion of found) {
        text += question.slice(last, deletion.start)
        text += deletion.group === group ? hidden(deletion) : deletion.answer
        last = deletion.end
      }
      return (text + question.slice(last)).trim()
    }
    const front = render((d) => `**[${d.hint ?? '…'}]**`)
    const back = render((d) => `**${d.answer}**`)
    return { front, back: note ? `${back}\n\n${note}` : back }
  })
}

function deletions(text: string): Deletion[] {
  let unnumbered = 0
  return [...text.matchAll(CLOZE)].map((match) => ({
    start: match.index,
    end: match.index + match[0].length,
    // Unnumbered blanks each get their own card.
    group: match[1] ? `c${match[1]}` : `blank${unnumbered++}`,
    answer: match[2].trim(),
    hint: match[3]?.trim(),
  }))
}

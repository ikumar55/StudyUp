import assert from 'node:assert/strict'
import { test } from 'node:test'
import { expandCloze, hasCloze } from './cloze.ts'

test('each blank becomes its own card, with the answer shown in context on the back', () => {
  assert.deepEqual(expandCloze('A {{page fault}} occurs when a page isn’t in {{physical memory}}.'), [
    {
      front: 'A **[…]** occurs when a page isn’t in physical memory.',
      back: 'A **page fault** occurs when a page isn’t in physical memory.',
    },
    {
      front: 'A page fault occurs when a page isn’t in **[…]**.',
      back: 'A page fault occurs when a page isn’t in **physical memory**.',
    },
  ])
})

test('numbered blanks sharing a number hide together', () => {
  const cards = expandCloze('{{c1::TCP}} and {{c1::SCTP}} are reliable; {{c2::UDP}} is not.')
  assert.equal(cards.length, 2)
  assert.equal(cards[0].front, '**[…]** and **[…]** are reliable; UDP is not.')
  assert.equal(cards[1].front, 'TCP and SCTP are reliable; **[…]** is not.')
})

test('hints show in the blank, and the typed answer becomes an extra note', () => {
  const [card] = expandCloze('The {{TLB::a cache}} holds recent translations.', 'Flushed on a context switch.')
  assert.equal(card.front, 'The **[a cache]** holds recent translations.')
  assert.equal(card.back, 'The **TLB** holds recent translations.\n\nFlushed on a context switch.')
})

test('text without blanks is not a cloze', () => {
  assert.equal(hasCloze('What is a {page} fault?'), false)
  assert.deepEqual(expandCloze('No blanks here'), [])
  assert.equal(hasCloze('A {{blank}} here'), true)
})

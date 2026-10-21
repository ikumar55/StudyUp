import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import type { Progress } from '../../shared/protocol.ts'
import { cardStatus, displayMath, dueText, keepLineBreaks, plainText, shortDuration, timeAgo } from './format.ts'

const day = 86_400_000
const progress = (state: number, due: number): Progress => ({
  state, due, stability: 1, difficulty: 5, step: 0, reps: 3, lapses: 0, lastReview: null, updatedAt: 0,
})

describe('cardStatus', () => {
  const now = 1_000 * day
  test('labels each state', () => {
    assert.equal(cardStatus(null, now).label, 'New')
    assert.equal(cardStatus(progress(1, now + day), now).label, 'Learning')
    assert.equal(cardStatus(progress(3, now - day), now).label, 'Learning')
    assert.equal(cardStatus(progress(2, now), now).label, 'Due now')
    const noon = new Date(2027, 0, 15, 12).getTime()
    assert.equal(cardStatus(progress(2, noon + 3 * day), noon).label, 'Due in 3 days')
    assert.equal(cardStatus(progress(2, noon + 2 * 3_600_000), noon).label, 'Due later today')
  })
})

test('shortDuration', () => {
  assert.deepEqual([60_000, 25 * 60_000, 5 * 3_600_000, 3 * day, 65 * day, 800 * day].map(shortDuration),
    ['1m', '25m', '5h', '3d', '2mo', '2y'])
})

test('timeAgo', () => {
  const now = 1_000 * day
  assert.equal(timeAgo(now - 10_000, now), 'just now')
  assert.equal(timeAgo(now - 2 * 60_000, now), '2 min ago')
  assert.equal(timeAgo(now - 3 * 3_600_000, now), '3 hr ago')
  assert.equal(timeAgo(now - 30 * 3_600_000, now), 'yesterday')
  assert.equal(timeAgo(now - 4 * day, now), '4 days ago')
})

test('keepLineBreaks turns single newlines into hard breaks, except in code', () => {
  assert.equal(keepLineBreaks('one\ntwo\n\nthree'), 'one  \ntwo\n\nthree')
  assert.equal(keepLineBreaks('a\nb\n```\nx\ny\n```\nc\nd'), 'a  \nb\n```\nx\ny\n```\nc  \nd')
  assert.equal(keepLineBreaks('```\nunclosed\ncode'), '```\nunclosed\ncode')
})

test('keepLineBreaks leaves multi-line math blocks alone', () => {
  assert.equal(
    keepLineBreaks('Softmax:\n$$\n\\sigma(z)_i =\n\\frac{e^{z_i}}{\\sum_j e^{z_j}}\n$$\ndone\nhere'),
    'Softmax:\n$$\n\\sigma(z)_i =\n\\frac{e^{z_i}}{\\sum_j e^{z_j}}\n$$\ndone  \nhere',
  )
})

test('plainText strips common Markdown', () => {
  assert.equal(plainText('What does **`fork()`** return?'), 'What does fork() return?')
  assert.equal(plainText('- [link](http://x) and _em_'), 'link and em')
})

test('displayMath makes a line holding only $$…$$ a block formula', () => {
  assert.equal(displayMath('Softmax:\n$$\\sigma(z)$$\nok'), 'Softmax:\n$$\n\\sigma(z)\n$$\nok')
  // Inline $$ inside a sentence, and multi-line blocks, are left as they are.
  assert.equal(displayMath('so $$x$$ here'), 'so $$x$$ here')
  assert.equal(displayMath('$$\nx\n$$'), '$$\nx\n$$')
})

test('dueText says when a card comes back in plain words', () => {
  const noon = new Date(2027, 0, 15, 12).getTime()
  const later = (days: number) => noon + days * day
  assert.deepEqual(
    [later(0.2), later(1), later(4), later(16), later(75), later(365), later(550)].map((due) => dueText(due, noon)),
    ['later today', 'tomorrow', 'in 4 days', 'in 2 weeks', 'in 2 months', 'in 1 year', 'in 1.5 years'],
  )
})

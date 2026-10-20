import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import { detectFormat, parseBulk } from './bulkParse.ts'

const fronts = (text: string) => parseBulk(text).cards.map((card) => [card.front, card.back])

describe('Q:/A: blocks', () => {
  test('parses simple pairs', () => {
    const text = 'Q: What is a TLB?\nA: A cache of page-table entries.\n\nQ: What is a page fault?\nA: An access to an unmapped page.'
    assert.equal(detectFormat(text), 'qa')
    assert.deepEqual(fronts(text), [
      ['What is a TLB?', 'A cache of page-table entries.'],
      ['What is a page fault?', 'An access to an unmapped page.'],
    ])
  })

  test('keeps multi-line answers until the next Q:', () => {
    const text = 'Q: Name the process states\nA: - Running\n- Ready\n\n- Blocked\nQ: Next\nA: Card'
    const result = parseBulk(text)
    assert.equal(result.cards.length, 2)
    assert.equal(result.cards[0].back, '- Running\n- Ready\n\n- Blocked')
    assert.equal(result.cards[1].line, 6)
  })

  test('allows multi-line questions and code blocks', () => {
    const text = [
      'Q: What does this print?',
      '```c',
      'printf("Q: %d", 1);',
      '```',
      'A: Q: 1',
    ].join('\n')
    assert.deepEqual(fronts(text), [['What does this print?\n```c\nprintf("Q: %d", 1);\n```', 'Q: 1']])
  })

  test('accepts labels with list markers, bold, and full words, case-insensitively', () => {
    const text = '- **Q:** Big-O of binary search?\n- **A:** O(log n)\nquestion: Unit of entropy?\nanswer: bits'
    assert.deepEqual(fronts(text), [
      ['Big-O of binary search?', 'O(log n)'],
      ['Unit of entropy?', 'bits'],
    ])
  })

  test('reports questions without answers and stray text', () => {
    const result = parseBulk('Intro line\nQ: Lonely question\nQ: Real\nA: Answer')
    assert.equal(result.cards.length, 1)
    assert.deepEqual(result.skipped.map((s) => [s.line, s.reason]), [
      [1, 'Not part of a Q:/A: block'],
      [2, 'Question has no answer'],
    ])
  })

  test('handles Windows line endings', () => {
    assert.deepEqual(fronts('Q: One\r\nA: Two\r\n'), [['One', 'Two']])
  })
})

describe('question :: answer lines', () => {
  test('parses one card per line', () => {
    const text = 'What is a mutex? :: A lock for mutual exclusion\nDefine overfitting::Fitting noise in the training data\n'
    assert.equal(detectFormat(text), 'colons')
    assert.deepEqual(fronts(text), [
      ['What is a mutex?', 'A lock for mutual exclusion'],
      ['Define overfitting', 'Fitting noise in the training data'],
    ])
  })

  test('does not split C++ scope operators', () => {
    assert.deepEqual(fronts('What does std::move do? :: Casts to an rvalue reference'), [
      ['What does std::move do?', 'Casts to an rvalue reference'],
    ])
  })

  test('skips lines without a separator or with an empty side', () => {
    const result = parseBulk('A :: B\njust a note\nNo answer ::\n')
    assert.equal(result.cards.length, 1)
    assert.deepEqual(result.skipped.map((s) => s.reason), ['No “::” on this line', 'Missing answer'])
  })
})

describe('tab-separated lines', () => {
  test('parses spreadsheet rows and skips Anki headers', () => {
    const text = '#separator:tab\n#html:false\nGradient descent\tIteratively step against the gradient\nReLU\tmax(0, x)'
    assert.equal(detectFormat(text), 'tab')
    assert.deepEqual(fronts(text), [
      ['Gradient descent', 'Iteratively step against the gradient'],
      ['ReLU', 'max(0, x)'],
    ])
  })

  test('keeps extra columns in the answer', () => {
    assert.deepEqual(fronts('Front\tBack\tmore'), [['Front', 'Back\tmore']])
  })
})

describe('detection', () => {
  test('returns null for plain text', () => {
    assert.equal(detectFormat('Just some notes\nwith no cards'), null)
    assert.deepEqual(parseBulk(''), { format: null, cards: [], skipped: [] })
  })

  test('prefers Q:/A: when answers contain ::', () => {
    assert.equal(detectFormat('Q: Scope operator?\nA: In C++ it is written a :: b'), 'qa')
  })

  test('uses the majority format', () => {
    assert.equal(detectFormat('a :: b\nc :: d\ne\tf'), 'colons')
  })

  test('an explicit format overrides detection', () => {
    assert.equal(parseBulk('a :: b', 'tab').cards.length, 0)
  })
})

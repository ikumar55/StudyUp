import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import { toggleBold } from './textEdits.ts'
import type { TextEdit } from './textEdits.ts'

/** Applies an edit to plain text and marks the resulting selection with [ ]. */
function apply(value: string, edit: TextEdit): string {
  const text = value.slice(0, edit.from) + edit.insert + value.slice(edit.to)
  return `${text.slice(0, edit.selectStart)}[${text.slice(edit.selectStart, edit.selectEnd)}]${text.slice(edit.selectEnd)}`
}

/** Runs toggleBold on text whose selection is marked with [ ]. */
function bold(marked: string): string {
  const start = marked.indexOf('[')
  const end = marked.indexOf(']') - 1
  const value = marked.replace('[', '').replace(']', '')
  return apply(value, toggleBold(value, start, end))
}

describe('toggleBold', () => {
  test('wraps the selection and keeps it selected', () => {
    assert.equal(bold('The [TLB] caches translations'), 'The **[TLB]** caches translations')
  })

  test('unwraps a selection inside the markers', () => {
    assert.equal(bold('The **[TLB]** caches'), 'The [TLB] caches')
  })

  test('unwraps a selection that includes the markers', () => {
    assert.equal(bold('The [**TLB**] caches'), 'The [TLB] caches')
  })

  test('leaves spaces at the edges outside the markers', () => {
    assert.equal(bold('The[ TLB ]caches'), 'The **[TLB]** caches')
  })

  test('with nothing selected, inserts markers with the cursor between them', () => {
    assert.equal(bold('The []'), 'The **[]**')
  })

  test('at the very start of the text', () => {
    assert.equal(bold('[TLB] caches'), '**[TLB]** caches')
  })
})

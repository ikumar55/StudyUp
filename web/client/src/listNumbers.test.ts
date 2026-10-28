import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import type { ListItem, Root } from 'mdast'
import remarkParse from 'remark-parse'
import { unified } from 'unified'
import { prepareMarkdown } from './format.ts'
import { remarkTypedListNumbers } from './listNumbers.ts'

/** The number each list item will show, as the editor renders `text`. */
function numbers(text: string): unknown[] {
  const processor = unified().use(remarkParse).use(remarkTypedListNumbers)
  const source = prepareMarkdown(text)
  const tree = processor.runSync(processor.parse(source), source) as Root
  const items: ListItem[] = []
  const walk = (node: Root | Root['children'][number]) => {
    if (node.type === 'listItem') items.push(node)
    if ('children' in node) node.children.forEach(walk)
  }
  walk(tree)
  return items.map((item) => item.data?.hProperties?.value)
}

describe('remarkTypedListNumbers', () => {
  test('keeps the numbers typed instead of counting', () => {
    assert.deepEqual(numbers('1) Type ls. 2) The shell reads it.\n3) fork and exec\n4) ls reads the directory'), ['1', '3', '4'])
  })

  test('works with dots and a list that starts later', () => {
    assert.deepEqual(numbers('3. three\n4. four\n9. nine'), ['3', '4', '9'])
  })

  test('leaves bullet lists alone', () => {
    assert.deepEqual(numbers('- one\n- two'), [undefined, undefined])
  })
})

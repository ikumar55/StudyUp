import type { Nodes, Root } from 'mdast'
import type { VFile } from 'vfile'

/** A remark plugin: numbered list items keep the number typed ("1) … 3) …" shows 1, 3), instead of
 *  Markdown counting 1, 2, 3. The iPhone shows the text as typed, so both read the same. */
export function remarkTypedListNumbers() {
  return (tree: Root, file: VFile) => {
    const source = String(file)
    const walk = (node: Nodes) => {
      if (node.type === 'list' && node.ordered) {
        for (const item of node.children) {
          const offset = item.position?.start.offset
          const number = offset === undefined ? undefined : /^\s*(\d+)[.)]/.exec(source.slice(offset))?.[1]
          if (number !== undefined) {
            item.data = { ...item.data, hProperties: { ...item.data?.hProperties, value: String(Number(number)) } }
          }
        }
      }
      if ('children' in node) node.children.forEach(walk)
    }
    walk(tree)
  }
}

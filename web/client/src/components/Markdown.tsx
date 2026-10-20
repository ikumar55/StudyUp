import { memo } from 'react'
import ReactMarkdown from 'react-markdown'
import type { Components } from 'react-markdown'
import { keepLineBreaks } from '../format.ts'

// react-markdown never renders raw HTML and strips unsafe URLs, so card text can't inject markup.
const components: Components = {
  a: ({ node: _node, ...props }) => <a {...props} target="_blank" rel="noreferrer noopener" />,
}

/** Card text rendered as Markdown: inline formatting, lists, and code blocks. */
export const Markdown = memo(function Markdown({ text, className }: { text: string; className?: string }) {
  return (
    <div className={className ? `markdown ${className}` : 'markdown'}>
      <ReactMarkdown components={components}>{keepLineBreaks(text)}</ReactMarkdown>
    </div>
  )
})


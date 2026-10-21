import { memo, useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import ReactMarkdown, { defaultUrlTransform } from 'react-markdown'
import type { Components } from 'react-markdown'
import rehypeHighlight from 'rehype-highlight'
import rehypeKatex from 'rehype-katex'
import remarkMath from 'remark-math'
import 'katex/dist/katex.min.css'
import { prepareMarkdown } from '../format.ts'
import { imageURL } from '../images.ts'

// react-markdown never renders raw HTML and strips unsafe URLs, so card text can't inject markup.
// `image:<id>` references are the one custom scheme allowed; they resolve to the server's image store.
const urlTransform = (url: string) => imageURL(url) ?? defaultUrlTransform(url)

// $inline$ and $$display$$ LaTeX, rendered by KaTeX. Bad LaTeX shows in red instead of failing the card.
// Code blocks that name their language (```c) get syntax colors; others stay plain.
const remarkPlugins = [remarkMath]
const rehypePlugins: Parameters<typeof ReactMarkdown>[0]['rehypePlugins'] = [
  [rehypeKatex, { throwOnError: false, strict: 'ignore' }],
  [rehypeHighlight, { detect: false }],
]

const components: Components = {
  a: ({ node: _node, ...props }) => <a {...props} target="_blank" rel="noreferrer noopener" />,
  img: ({ src, alt }) => (typeof src === 'string' && src ? <CardImage src={src} alt={alt ?? ''} /> : null),
}

/** Card text rendered as Markdown: inline formatting, lists, code blocks, math, and images. */
export const Markdown = memo(function Markdown({ text, className }: { text: string; className?: string }) {
  return (
    <div className={className ? `markdown ${className}` : 'markdown'}>
      <ReactMarkdown
        components={components}
        urlTransform={urlTransform}
        remarkPlugins={remarkPlugins}
        rehypePlugins={rehypePlugins}
      >
        {prepareMarkdown(text)}
      </ReactMarkdown>
    </div>
  )
})

/** An image in a card. Click to view it full size; click again or press Esc to close. */
function CardImage({ src, alt }: { src: string; alt: string }) {
  const [zoomed, setZoomed] = useState(false)

  useEffect(() => {
    if (!zoomed) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation()
        setZoomed(false)
      }
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [zoomed])

  return (
    <>
      <button
        type="button"
        className="card-image"
        title="View full size"
        onClick={(event) => {
          // Don't also open the card editor.
          event.stopPropagation()
          setZoomed(true)
        }}
      >
        <img src={src} alt={alt} loading="lazy" />
      </button>
      {zoomed && createPortal(
        <div className="image-lightbox" role="dialog" aria-label="Image" onClick={() => setZoomed(false)}>
          <img src={src} alt={alt} />
        </div>,
        document.body,
      )}
    </>
  )
}

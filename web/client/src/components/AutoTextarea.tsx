import { useCallback, useLayoutEffect, useRef } from 'react'
import type { Ref, TextareaHTMLAttributes } from 'react'

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  value: string
  ref?: Ref<HTMLTextAreaElement>
}

/** A textarea that grows with its content. */
export function AutoTextarea({ ref, value, rows = 2, ...props }: Props) {
  const inner = useRef<HTMLTextAreaElement | null>(null)

  const setRef = useCallback((element: HTMLTextAreaElement | null) => {
    inner.current = element
    if (typeof ref === 'function') ref(element)
    else if (ref) ref.current = element
  }, [ref])

  useLayoutEffect(() => {
    const element = inner.current
    if (!element) return
    element.style.height = 'auto'
    element.style.height = `${element.scrollHeight + 2}px`
  }, [value])

  return <textarea ref={setRef} value={value} rows={rows} {...props} />
}

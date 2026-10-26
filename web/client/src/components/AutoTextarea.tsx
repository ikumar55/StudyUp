import { useCallback, useLayoutEffect, useRef } from 'react'
import type { KeyboardEvent, Ref, TextareaHTMLAttributes } from 'react'
import { hasModifier } from '../format.ts'
import { applyEdit, toggleBold } from '../textEdits.ts'

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  value: string
  ref?: Ref<HTMLTextAreaElement>
}

/** A textarea that grows with its content. ⌘B makes the selection bold. */
export function AutoTextarea({ ref, value, rows = 2, onKeyDown, ...props }: Props) {
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

  const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key.toLowerCase() === 'b' && hasModifier(event) && !event.shiftKey && !event.altKey) {
      event.preventDefault()
      const element = event.currentTarget
      applyEdit(element, toggleBold(element.value, element.selectionStart, element.selectionEnd))
      return
    }
    onKeyDown?.(event)
  }

  return <textarea ref={setRef} value={value} rows={rows} onKeyDown={handleKeyDown} {...props} />
}

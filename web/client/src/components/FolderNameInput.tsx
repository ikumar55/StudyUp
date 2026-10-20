import { useEffect, useRef, useState } from 'react'
import type { CSSProperties } from 'react'

interface Props {
  initialName: string
  placeholder: string
  /** Resolves to false to keep the field open (e.g. the server refused the name). */
  onCommit: (name: string) => Promise<boolean>
  onCancel: () => void
  style?: CSSProperties
}

/** An inline name field: Return saves, Esc cancels, clicking away saves if something was typed. */
export function FolderNameInput({ initialName, placeholder, onCommit, onCancel, style }: Props) {
  const [name, setName] = useState(initialName)
  const [saving, setSaving] = useState(false)
  const ref = useRef<HTMLInputElement>(null)
  const done = useRef(false)
  const busy = useRef(false)

  useEffect(() => {
    ref.current?.focus()
    ref.current?.select()
  }, [])

  const commit = async () => {
    if (done.current || busy.current) return
    const trimmed = name.trim()
    if (!trimmed || trimmed === initialName) {
      done.current = true
      onCancel()
      return
    }
    busy.current = true
    setSaving(true)
    const ok = await onCommit(trimmed)
    busy.current = false
    if (ok) {
      done.current = true
    } else {
      setSaving(false)
      requestAnimationFrame(() => ref.current?.focus())
    }
  }

  return (
    <input
      ref={ref}
      className="tree-input"
      style={style}
      value={name}
      placeholder={placeholder}
      readOnly={saving}
      aria-label={placeholder}
      onChange={(event) => setName(event.target.value)}
      onKeyDown={(event) => {
        event.stopPropagation()
        if (event.key === 'Enter') {
          event.preventDefault()
          void commit()
        } else if (event.key === 'Escape') {
          event.preventDefault()
          done.current = true
          onCancel()
        }
      }}
      onBlur={() => void commit()}
    />
  )
}

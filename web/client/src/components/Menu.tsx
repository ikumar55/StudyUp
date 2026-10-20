import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import type { KeyboardEvent, ReactNode } from 'react'

export interface MenuItem {
  label: string
  icon?: ReactNode
  hint?: string
  danger?: boolean
  onSelect: () => void
}

interface Props {
  /** Viewport coordinates of the menu's top-left corner. */
  at: { x: number; y: number }
  items: (MenuItem | 'separator')[]
  onClose: () => void
  label: string
}

/** A small popup menu: arrow keys move, Return picks, Esc or a click elsewhere closes. */
export function Menu({ at, items, onClose, label }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const opener = useRef(document.activeElement as HTMLElement | null)
  const [position, setPosition] = useState(at)
  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose

  // Keep the menu on screen.
  useLayoutEffect(() => {
    const menu = ref.current
    if (!menu) return
    const { width, height } = menu.getBoundingClientRect()
    setPosition({
      x: Math.max(8, Math.min(at.x, window.innerWidth - width - 8)),
      y: Math.max(8, at.y + height > window.innerHeight - 8 ? at.y - height : at.y),
    })
  }, [at])

  useEffect(() => {
    ref.current?.querySelector<HTMLElement>('[role="menuitem"]')?.focus()
    const onPointerDown = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) onCloseRef.current()
    }
    const onBlur = () => onCloseRef.current()
    document.addEventListener('pointerdown', onPointerDown, true)
    window.addEventListener('blur', onBlur)
    window.addEventListener('resize', onBlur)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true)
      window.removeEventListener('blur', onBlur)
      window.removeEventListener('resize', onBlur)
    }
  }, [])

  const onKeyDown = (event: KeyboardEvent) => {
    const buttons = [...(ref.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? [])]
    const index = buttons.indexOf(document.activeElement as HTMLElement)
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      const step = event.key === 'ArrowDown' ? 1 : -1
      buttons[(index + step + buttons.length) % buttons.length]?.focus()
    } else if (event.key === 'Escape' || event.key === 'Tab') {
      event.preventDefault()
      event.stopPropagation()
      onClose()
      opener.current?.focus()
    }
  }

  return createPortal(
    <div
      ref={ref}
      className="menu"
      role="menu"
      aria-label={label}
      style={{ left: position.x, top: position.y }}
      onKeyDown={onKeyDown}
    >
      {items.map((item, index) =>
        item === 'separator' ? (
          <div key={index} className="menu-separator" role="separator" />
        ) : (
          <button
            key={item.label}
            type="button"
            role="menuitem"
            className={item.danger ? 'menu-item menu-item-danger' : 'menu-item'}
            onClick={() => {
              onClose()
              item.onSelect()
            }}
          >
            <span className="menu-icon">{item.icon}</span>
            <span className="menu-label">{item.label}</span>
            {item.hint && <span className="menu-hint">{item.hint}</span>}
          </button>
        ),
      )}
    </div>,
    document.body,
  )
}

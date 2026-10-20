import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'

export interface ToastOptions {
  message: string
  kind?: 'info' | 'success' | 'error'
  /** A button such as "Undo". */
  action?: { label: string; run: () => void }
  /** Milliseconds before it disappears. */
  duration?: number
  /** Runs when the toast goes away without its action being used. */
  onExpire?: () => void
}

interface Toast extends ToastOptions {
  id: number
}

interface ToastAPI {
  show: (options: ToastOptions) => void
  error: (message: string) => void
}

const ToastContext = createContext<ToastAPI | null>(null)

export function useToasts(): ToastAPI {
  const api = useContext(ToastContext)
  if (!api) throw new Error('useToasts must be used inside <ToastProvider>')
  return api
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const current = useRef<Toast[]>([])
  const nextId = useRef(1)

  const replace = useCallback((next: Toast[]) => {
    current.current = next
    setToasts(next)
  }, [])

  const dismiss = useCallback((id: number, expired: boolean) => {
    const toast = current.current.find((t) => t.id === id)
    if (!toast) return
    replace(current.current.filter((t) => t.id !== id))
    if (expired) toast.onExpire?.()
  }, [replace])

  const show = useCallback((options: ToastOptions) => {
    const id = nextId.current++
    // Keep at most a few on screen; the oldest ones expire first.
    const overflow = current.current.slice(0, Math.max(0, current.current.length - 3))
    replace([...current.current.slice(overflow.length), { ...options, id }])
    for (const toast of overflow) toast.onExpire?.()
  }, [replace])

  const error = useCallback((message: string) => show({ message, kind: 'error', duration: 6000 }), [show])

  // Toasts live in the top layer as a popover, re-shown on each change so they stay above any open dialog.
  const container = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const element = container.current
    if (!element || typeof element.showPopover !== 'function') return
    try {
      if (element.matches(':popover-open')) element.hidePopover()
      if (toasts.length > 0) element.showPopover()
    } catch {
      // Popovers unsupported; the toasts still show, just below dialogs.
    }
  }, [toasts])
  const api = useMemo(() => ({ show, error }), [show, error])

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div ref={container} className="toasts" popover="manual" role="status" aria-live="polite">
        {toasts.map((toast) => (
          <ToastView key={toast.id} toast={toast} onDismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  )
}

function ToastView({ toast, onDismiss }: { toast: Toast; onDismiss: (id: number, expired: boolean) => void }) {
  const [paused, setPaused] = useState(false)

  useEffect(() => {
    if (paused) return
    const timer = setTimeout(() => onDismiss(toast.id, true), toast.duration ?? 4000)
    return () => clearTimeout(timer)
  }, [paused, toast, onDismiss])

  return (
    <div
      className={`toast toast-${toast.kind ?? 'info'}`}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
    >
      <span className="toast-message">{toast.message}</span>
      {toast.action && (
        <button
          type="button"
          className="toast-action"
          onClick={() => {
            toast.action!.run()
            onDismiss(toast.id, false)
          }}
        >
          {toast.action.label}
        </button>
      )}
      <button type="button" className="toast-close" aria-label="Dismiss" onClick={() => onDismiss(toast.id, true)}>
        ×
      </button>
    </div>
  )
}

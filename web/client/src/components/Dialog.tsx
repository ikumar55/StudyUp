import { useEffect, useRef } from 'react'
import type { ReactNode } from 'react'
import { CloseIcon } from './Icons.tsx'

interface Props {
  title: string
  onClose: () => void
  children: ReactNode
  /** Extra class for sizing, e.g. "dialog-wide". */
  className?: string
}

/** A modal built on <dialog>: focus stays inside, Esc or a backdrop click closes, the page behind is inert. */
export function Dialog({ title, onClose, children, className }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose

  useEffect(() => {
    const dialog = ref.current
    if (!dialog) return
    const previous = document.activeElement as HTMLElement | null
    dialog.showModal()
    // Elements marked data-autofocus get focus; otherwise the browser picks the first control.
    dialog.querySelector<HTMLElement>('[data-autofocus]')?.focus()
    return () => {
      dialog.close()
      previous?.focus?.()
    }
  }, [])

  return (
    <dialog
      ref={ref}
      className={className ? `dialog ${className}` : 'dialog'}
      aria-label={title}
      onCancel={(event) => {
        event.preventDefault()
        onCloseRef.current()
      }}
      onMouseDown={(event) => {
        // A click on the backdrop (the dialog element itself, outside its content) closes it.
        if (event.target === ref.current) onCloseRef.current()
      }}
    >
      <div className="dialog-body">
        <header className="dialog-header">
          <h2>{title}</h2>
          <button type="button" className="icon-button" aria-label="Close" onClick={() => onCloseRef.current()}>
            <CloseIcon />
          </button>
        </header>
        {children}
      </div>
    </dialog>
  )
}

interface ConfirmProps {
  title: string
  message: ReactNode
  confirmLabel: string
  /** The safe choice; "Cancel" unless given. */
  cancelLabel?: string
  destructive?: boolean
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({ title, message, confirmLabel, cancelLabel = 'Cancel', destructive, onConfirm, onCancel }: ConfirmProps) {
  return (
    <Dialog title={title} onClose={onCancel} className="dialog-narrow">
      <div className="confirm-message">{message}</div>
      <footer className="dialog-footer">
        {/* For destructive actions the safe choice gets focus, so a stray Return doesn't delete. */}
        <button type="button" className="button" onClick={onCancel} data-autofocus={destructive ? true : undefined}>
          {cancelLabel}
        </button>
        <button
          type="button"
          className={destructive ? 'button button-danger' : 'button button-primary'}
          onClick={onConfirm}
          data-autofocus={destructive ? undefined : true}
        >
          {confirmLabel}
        </button>
      </footer>
    </Dialog>
  )
}

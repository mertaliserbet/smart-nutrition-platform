import { useId, useLayoutEffect, useRef } from 'react'
import type { ReactNode } from 'react'
import { createPortal } from 'react-dom'
import './confirmationDialog.css'

export function ConfirmationDialog({ title, children, confirmLabel, cancelLabel = 'Vazgeç', destructive = false, onConfirm, onCancel }: {
  title: string; children: ReactNode; confirmLabel: string; cancelLabel?: string; destructive?: boolean; onConfirm: () => void; onCancel: () => void
}) {
  const container = useRef<HTMLDivElement>(null)
  const id = useId()
  useLayoutEffect(() => {
    const previous = document.activeElement as HTMLElement | null
    const root = document.getElementById('root')
    const wasInert = root?.inert ?? false
    const overflow = document.body.style.overflow
    if (root) root.inert = true
    document.body.style.overflow = 'hidden'
    container.current?.querySelector<HTMLButtonElement>('button')?.focus()
    return () => {
      if (root) root.inert = wasInert
      document.body.style.overflow = overflow
      if (previous?.isConnected) previous.focus()
    }
  }, [])
  return createPortal(<div className="confirmation-backdrop"><div ref={container} className="card confirmation-dialog" role="alertdialog" aria-modal="true" aria-labelledby={`${id}-title`} aria-describedby={`${id}-body`}
    onKeyDown={event => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); onCancel() }
      if (event.key === 'Tab') {
        const buttons = container.current?.querySelectorAll<HTMLButtonElement>('button')
        if (buttons?.length && ((event.shiftKey && document.activeElement === buttons[0]) || (!event.shiftKey && document.activeElement === buttons[buttons.length - 1]))) {
          event.preventDefault(); (event.shiftKey ? buttons[buttons.length - 1] : buttons[0])?.focus()
        }
      }
    }}><h3 id={`${id}-title`}>{title}</h3><div id={`${id}-body`}>{children}</div><div className="confirmation-actions">
      <button type="button" className="button button-secondary" onClick={onCancel}>{cancelLabel}</button>
      <button type="button" className={`button ${destructive ? 'button-danger' : 'button-primary'}`} onClick={onConfirm}>{confirmLabel}</button>
    </div></div></div>, document.body)
}

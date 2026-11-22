import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'

export function PlanConfirmation({ title, children, confirmLabel, onConfirm, onCancel }: {
  title: string; children: React.ReactNode; confirmLabel: string; onConfirm: () => void; onCancel: () => void
}) {
  const container = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null
    container.current?.querySelector<HTMLButtonElement>('button')?.focus()
    return () => { if (previous?.isConnected) previous.focus() }
  }, [])
  return createPortal(<div className="plan-modal-backdrop"><div ref={container} className="card plan-modal" role="alertdialog" aria-modal="true" aria-labelledby="plan-confirm-title" aria-describedby="plan-confirm-body"
    onKeyDown={event => {
      if (event.key === 'Escape') { event.preventDefault(); onCancel() }
      if (event.key === 'Tab') {
        const buttons = container.current?.querySelectorAll('button')
        if (buttons?.length && ((event.shiftKey && document.activeElement === buttons[0]) || (!event.shiftKey && document.activeElement === buttons[buttons.length - 1]))) {
          event.preventDefault(); (event.shiftKey ? buttons[buttons.length - 1] : buttons[0])?.focus()
        }
      }
    }}><h3 id="plan-confirm-title">{title}</h3><div id="plan-confirm-body">{children}</div><div className="expert-pagination">
      <button className="button button-secondary" onClick={onCancel}>Düzenlemeye dön</button>
      <button className="button button-primary" onClick={onConfirm}>{confirmLabel}</button>
    </div></div></div>, document.body)
}

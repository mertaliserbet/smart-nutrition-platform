import { useEffect, useId, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Icon } from '../../core/components/Icon'
import './workspace.css'

export function WorkspaceProfileMenu({ displayName, email, children, showName = false }: {
  displayName: string; email?: string; children: ReactNode; showName?: boolean
}) {
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const button = useRef<HTMLButtonElement>(null)
  const id = useId()
  const initials = displayName.trim().split(/\s+/).slice(0, 2)
    .map(part => Array.from(part)[0]).join('').toLocaleUpperCase('tr-TR')

  useEffect(() => {
    if (!open) return
    function outside(event: PointerEvent) {
      if (event.target instanceof Node && !root.current?.contains(event.target)) setOpen(false)
    }
    document.addEventListener('pointerdown', outside)
    return () => document.removeEventListener('pointerdown', outside)
  }, [open])

  return <div ref={root} className={`workspace-profile${showName ? ' sidebar-profile' : ''}`} onBlur={event => {
    if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false)
  }} onKeyDown={event => {
    if (event.key === 'Escape' && open) { setOpen(false); button.current?.focus() }
  }}>
    <button ref={button} type="button" className="workspace-avatar" aria-label="Profil menüsü" aria-expanded={open}
      aria-controls={open ? id : undefined} onClick={() => setOpen(value => !value)}><span className="profile-initials" aria-hidden="true">{initials}</span>{showName && <><span className="profile-name">{displayName}</span><Icon name="chevron" /></>}</button>
    {open && <div id={id} className="workspace-profile-panel">
      <div className="workspace-profile-identity"><strong>{displayName}</strong>{email && <span>{email}</span>}</div>
      {children}
    </div>}
  </div>
}

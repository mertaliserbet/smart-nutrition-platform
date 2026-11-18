import { createContext, useContext, useEffect, useId, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Icon } from '../components/Icon'

type ThemeMode = 'system' | 'light' | 'dark'
const themeLabels: Record<ThemeMode, string> = { system: 'Sistem teması', light: 'Açık tema', dark: 'Koyu tema' }
const ThemeContext = createContext<{ mode: ThemeMode; setMode: (mode: ThemeMode) => void } | null>(null)

export function ThemeProvider({ children }: { children: ReactNode }) {
  // Session-only preference until the shared persistence decision is approved.
  const [mode, setMode] = useState<ThemeMode>('system')
  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    const applyTheme = () => {
      document.documentElement.dataset.theme = mode === 'system' ? (media.matches ? 'dark' : 'light') : mode
    }
    applyTheme()
    media.addEventListener('change', applyTheme)
    return () => media.removeEventListener('change', applyTheme)
  }, [mode])
  return <ThemeContext.Provider value={{ mode, setMode }}>{children}</ThemeContext.Provider>
}

export function ThemeControl() {
  const theme = useContext(ThemeContext)
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const trigger = useRef<HTMLButtonElement>(null)
  const menu = useRef<HTMLDivElement>(null)
  const menuId = useId()

  useEffect(() => {
    if (!open) return
    menu.current?.querySelector<HTMLButtonElement>('[aria-checked="true"]')?.focus()
    function closeOutside(event: PointerEvent) {
      if (event.target instanceof Node && !root.current?.contains(event.target)) setOpen(false)
    }
    document.addEventListener('pointerdown', closeOutside)
    return () => document.removeEventListener('pointerdown', closeOutside)
  }, [open])

  if (!theme) throw new Error('ThemeControl requires ThemeProvider')
  const label = themeLabels[theme.mode]
  function closeMenu() {
    trigger.current?.focus()
    setOpen(false)
  }

  return (
    <div className="theme-control" ref={root} onBlur={event => {
      if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false)
    }} onKeyDown={event => {
      if (open && event.key === 'Escape') {
        event.preventDefault()
        event.stopPropagation()
        closeMenu()
      }
    }}>
      <button type="button" ref={trigger} className="theme-trigger" aria-label={`Görünüm: ${label}`}
        aria-haspopup="menu" aria-expanded={open} aria-controls={open ? menuId : undefined}
        onClick={() => setOpen(value => !value)} onKeyDown={event => {
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault()
            setOpen(true)
          }
        }}>
        <Icon name="sun" /><span>{label}</span><span className="theme-chevron" aria-hidden="true" />
      </button>
      {open && <div ref={menu} id={menuId} className="theme-menu" role="menu" aria-label="Tema seçenekleri" onKeyDown={event => {
        const options = Array.from(event.currentTarget.querySelectorAll('button'))
        const current = options.indexOf(document.activeElement as HTMLButtonElement)
        const next = event.key === 'ArrowDown' ? (current + 1) % options.length
          : event.key === 'ArrowUp' ? (current + options.length - 1) % options.length
          : event.key === 'Home' ? 0 : event.key === 'End' ? options.length - 1 : undefined
        if (next !== undefined) {
          event.preventDefault()
          options[next]?.focus()
        }
      }}>
        {Object.entries(themeLabels).map(([mode, text]) => <button type="button" key={mode} role="menuitemradio"
          aria-checked={theme.mode === mode} tabIndex={-1} onClick={() => { theme.setMode(mode as ThemeMode); closeMenu() }}>
          {text}{theme.mode === mode && <Icon name="check" />}
        </button>)}
      </div>}
    </div>
  )
}

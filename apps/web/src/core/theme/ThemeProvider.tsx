import { createContext, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { Icon } from '../components/Icon'

type ThemeMode = 'system' | 'light' | 'dark'
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
  if (!theme) throw new Error('ThemeControl requires ThemeProvider')
  return (
    <label className="theme-control">
      <Icon name="sun" /><span className="sr-only">Görünüm</span>
      <select value={theme.mode} onChange={(event) => theme.setMode(event.target.value as ThemeMode)}>
        <option value="system">Sistem teması</option><option value="light">Açık tema</option><option value="dark">Koyu tema</option>
      </select>
    </label>
  )
}

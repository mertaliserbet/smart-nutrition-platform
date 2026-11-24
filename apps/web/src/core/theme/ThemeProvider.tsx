import { useLayoutEffect } from 'react'
import type { ReactNode } from 'react'

// Limely has one fixed presentation, independent of the operating system theme.
export function ThemeProvider({ children }: { children: ReactNode }) {
  useLayoutEffect(() => { document.documentElement.dataset.theme = 'light' }, [])
  return children
}

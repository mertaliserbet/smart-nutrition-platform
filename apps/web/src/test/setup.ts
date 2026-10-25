import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, beforeEach, vi } from 'vitest'

let media: MediaQueryList

export function setSystemTheme(isDark: boolean) {
  Object.defineProperty(media, 'matches', { value: isDark, configurable: true })
  media.dispatchEvent(new Event('change'))
}

beforeEach(() => {
  media = new EventTarget() as MediaQueryList
  Object.defineProperty(media, 'matches', { value: false, configurable: true })
  Object.defineProperty(media, 'media', { value: '(prefers-color-scheme: dark)' })
  vi.stubGlobal('matchMedia', vi.fn(() => media))
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
  vi.unstubAllEnvs()
  document.documentElement.removeAttribute('data-theme')
})

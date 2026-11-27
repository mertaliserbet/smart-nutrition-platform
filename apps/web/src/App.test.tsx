import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from './App'
import { setSystemTheme } from './test/setup'

function renderApp(path = '/giris') {
  const user = userEvent.setup()
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return user
}

describe.each([
  { environment: 'development', dev: true },
  { environment: 'production', dev: false },
])('navigation in $environment', ({ dev }) => {
  it.each(['/onizleme', '/onizleme/danisanlar', '/onizleme/danisanlar/10000000-0000-4000-8000-000000000001?kayit=tahliller', '/onizleme/baglanti-istekleri'])('rejects the removed preview URL %s without requesting data', (path) => {
    vi.stubEnv('DEV', dev)
    const request = vi.spyOn(globalThis, 'fetch')
    renderApp(path)
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Bu sayfa bulunamadı.')
    expect(screen.getByRole('link', { name: 'Giriş ekranına dön' })).toHaveAttribute('href', '/giris')
    expect(screen.queryByRole('navigation', { name: 'Diyetisyen paneli' })).not.toBeInTheDocument()
    expect(request).not.toHaveBeenCalled()
  })

  it.each(['/giris', '/diyetisyenler-icin'])('exposes no panel preview entry on %s', (path) => {
    vi.stubEnv('DEV', dev)
    renderApp(path)
    expect(screen.queryByRole('link', { name: 'Panel tasarımını incele' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Paneli incele' })).not.toBeInTheDocument()
    expect(screen.getAllByRole('link').some(link => link.getAttribute('href')?.startsWith('/onizleme'))).toBe(false)
  })
})

it('provides a safe destination for unknown routes', () => {
  renderApp('/unknown')
  expect(screen.getByRole('link', { name: 'Giriş ekranına dön' })).toHaveAttribute('href', '/giris')
})

describe('appearance', () => {
  it('keeps the reference appearance when the operating system changes and exposes no theme switch', async () => {
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderApp('/giris')
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
    act(() => setSystemTheme(true))
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
    expect(screen.queryByRole('button', { name: /^Görünüm/ })).not.toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Şifremi unuttum' }))
    act(() => setSystemTheme(false))
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
    expect(screen.queryByRole('menu', { name: 'Tema seçenekleri' })).not.toBeInTheDocument()
    expect(storage).not.toHaveBeenCalled()
  })
})

import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from './App'
import { setSystemTheme } from './test/setup'

function renderApp(path = '/onizleme') {
  const user = userEvent.setup()
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return user
}

describe('workspace preview and navigation', () => {
  it('keeps unknown metrics distinct from zero and makes no data requests', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderApp()
    expect(screen.getAllByLabelText('Veri henüz alınmadı')).toHaveLength(4)
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Danışanlarımı görüntüle' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Danışanlarım' })).toHaveFocus()
    expect(screen.getByRole('searchbox', { name: 'Danışan ara' })).toBeEnabled()
    await user.click(screen.getByRole('link', { name: 'Bağlantı isteklerini incele' }))
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Bağlantı istekleri')
    expect(request).not.toHaveBeenCalled()
  })

  it('closes the mobile menu with Escape and returns focus to its trigger', async () => {
    const user = renderApp()
    const trigger = screen.getByRole('button', { name: 'Menüyü aç' })
    await user.click(trigger)
    expect(trigger).toHaveAttribute('aria-expanded', 'true')
    await user.keyboard('{Escape}')
    expect(trigger).toHaveAttribute('aria-expanded', 'false')
    expect(trigger).toHaveFocus()
  })

  it('replaces the preview header login link with an avatar menu without reading an account', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderApp()
    const avatar = screen.getByRole('button', { name: 'Profil menüsü' })
    expect(screen.queryByRole('link', { name: 'Giriş ekranı' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Giriş yap' })).not.toBeInTheDocument()
    await user.click(avatar)
    expect(avatar).toHaveAttribute('aria-expanded', 'true')
    await user.tab()
    expect(screen.getByRole('link', { name: 'Giriş yap' })).toHaveFocus()
    await user.keyboard('{Escape}')
    expect(avatar).toHaveFocus()
    expect(avatar).toHaveAttribute('aria-expanded', 'false')
    await user.click(avatar)
    await user.click(screen.getByRole('link', { name: 'Giriş yap' }))
    expect(screen.getByRole('heading', { name: 'Tekrar hoş geldiniz.' })).toBeVisible()
    expect(request).not.toHaveBeenCalled()
  })

  it('blocks direct preview URLs and removes the preview link in a production environment', () => {
    vi.stubEnv('DEV', false)
    renderApp('/onizleme/danisanlar')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Bu sayfa bulunamadı.')
    expect(screen.queryByRole('navigation', { name: 'Diyetisyen paneli' })).not.toBeInTheDocument()
  })

  it('never exposes panel preview access on the production login screen', () => {
    vi.stubEnv('DEV', false)
    renderApp('/giris')
    expect(screen.queryByRole('link', { name: 'Panel tasarımını incele' })).not.toBeInTheDocument()
  })

  it('provides a safe destination for unknown routes', () => {
    renderApp('/unknown')
    expect(screen.getByRole('link', { name: 'Giriş ekranına dön' })).toHaveAttribute('href', '/giris')
  })
})

describe('appearance', () => {
  it('follows system changes and keeps an explicit choice across navigation without storage', async () => {
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderApp('/giris')
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
    act(() => setSystemTheme(true))
    expect(document.documentElement).toHaveAttribute('data-theme', 'dark')
    const trigger = () => screen.getByRole('button', { name: /^Görünüm/ })
    await user.click(trigger())
    expect(screen.getByRole('menuitemradio', { name: 'Sistem teması', checked: true })).toHaveFocus()
    await user.keyboard('{ArrowDown}{Enter}')
    expect(trigger()).toHaveFocus()
    expect(screen.queryByRole('menu', { name: 'Tema seçenekleri' })).not.toBeInTheDocument()
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
    act(() => setSystemTheme(true))
    expect(document.documentElement).toHaveAttribute('data-theme', 'light')
    await user.click(screen.getByRole('link', { name: 'Şifremi unuttum' }))
    expect(trigger()).toHaveAccessibleName('Görünüm: Açık tema')
    await user.click(trigger())
    await user.keyboard('{Escape}')
    expect(trigger()).toHaveFocus()
    expect(trigger()).toHaveAttribute('aria-expanded', 'false')
    await user.click(trigger())
    await user.click(screen.getByRole('menuitemradio', { name: 'Sistem teması' }))
    expect(document.documentElement).toHaveAttribute('data-theme', 'dark')
    expect(storage).not.toHaveBeenCalled()
  })
})

import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { AuthForm } from './AuthPage'

function renderApp(path = '/giris') {
  const user = userEvent.setup()
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return user
}

describe('authentication presentation boundary', () => {
  it('shows direct links to the application and admin login', async () => {
    const user = renderApp()
    const application = screen.getByRole('link', { name: 'Diyetisyen başvurusu yap' })
    const admin = screen.getByRole('link', { name: 'Yönetici girişi' })
    expect(application).toBeVisible()
    expect(application).toHaveAttribute('href', '/uzman-basvurusu')
    expect(admin).toBeVisible()
    expect(admin).toHaveAttribute('href', '/yonetici-giris')
    expect(screen.queryByRole('link', { name: 'Danışan hesabı oluştur', hidden: true })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'E-postamı doğrula', hidden: true })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Hesabımı aç', hidden: true })).not.toBeInTheDocument()
    await user.click(admin)
    expect(screen.getByRole('heading', { name: 'Yönetici girişi' })).toHaveFocus()
  })

  it('labels invalid fields and focuses the first error', async () => {
    const user = renderApp()
    await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
    expect(screen.getByLabelText('E-posta adresi')).toHaveFocus()
    expect(screen.getByLabelText('E-posta adresi')).toHaveAccessibleDescription('E-posta adresinizi girin.')
    await user.type(screen.getByLabelText('E-posta adresi'), 'invalid')
    await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
    expect(screen.getByText('Geçerli bir e-posta adresi girin.')).toBeVisible()
    await user.clear(screen.getByLabelText('E-posta adresi'))
    await user.type(screen.getByLabelText('E-posta adresi'), 'demo@example.com')
    await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveFocus()
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveAccessibleDescription('Şifrenizi girin.')
  })

  it('toggles password visibility without changing whitespace', async () => {
    const user = renderApp()
    const password = screen.getByLabelText('Şifre', { exact: true })
    await user.type(password, ' demo secret ')
    expect(password).toHaveAttribute('type', 'password')
    await user.click(screen.getByRole('button', { name: 'Şifreyi göster' }))
    expect(password).toHaveAttribute('type', 'text')
    expect(password).toHaveValue(' demo secret ')
    await user.click(screen.getByRole('button', { name: 'Şifreyi gizle' }))
    expect(password).toHaveAttribute('type', 'password')
  })

  it('clears credentials and reports a failed real login without storing anything', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(Response.json({ requestToken: 'synthetic-csrf' }))
      .mockResolvedValueOnce(new Response(null, { status: 401 }))
    const store = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderApp()
    await user.type(screen.getByLabelText('E-posta adresi'), 'demo@example.com')
    await user.type(screen.getByLabelText('Şifre', { exact: true }), 'a')
    await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Giriş bilgileri doğrulanamadı')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Tekrar hoş geldin')
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
    expect(request).toHaveBeenCalledTimes(2)
    expect(request).toHaveBeenLastCalledWith('/api/v1/auth/web-session', expect.objectContaining({
      method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf', 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'demo@example.com', password: 'a' }),
    }))
    expect(store).not.toHaveBeenCalled()
  })

  it('clears credentials when switching pages', async () => {
    const user = renderApp()
    await user.type(screen.getByLabelText('E-posta adresi'), 'demo@example.com')
    await user.type(screen.getByLabelText('Şifre', { exact: true }), 'demo secret')
    await user.click(screen.getByRole('link', { name: 'Şifremi unuttum' }))
    expect(screen.getByRole('heading', { level: 1 })).toHaveFocus()
    expect(screen.getByLabelText('E-posta adresi')).toHaveValue('')
    await user.click(screen.getByRole('link', { name: 'Giriş ekranına dön' }))
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
  })

  it('uses the real reset request without revealing account existence or promising delivery', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(null, { status: 202 }))
    const user = renderApp('/sifremi-unuttum')
    await user.type(screen.getByLabelText('E-posta adresi'), 'demo@example.com')
    await user.click(screen.getByRole('button', { name: 'Sıfırlama bağlantısı iste' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Uygun bir hesap varsa')
    expect(request).toHaveBeenCalledWith('/api/v1/auth/password-reset-requests', expect.objectContaining({
      method: 'POST', credentials: 'omit', body: JSON.stringify({ email: 'demo@example.com' }),
    }))
  })

  it('announces errors and blocks interaction while a presentation loading state is supplied', () => {
    render(<MemoryRouter><AuthForm mode="login" isLoading errorMessage="İşlem tamamlanamadı." /></MemoryRouter>)
    expect(screen.getByRole('alert')).toHaveTextContent('İşlem tamamlanamadı.')
    expect(screen.getByRole('form')).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByLabelText('E-posta adresi')).toBeDisabled()
    expect(screen.getByRole('button', { name: 'İşlem sürüyor…' })).toBeDisabled()
  })
})

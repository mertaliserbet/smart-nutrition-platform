import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const syntheticId = 'd6dc3345-c7a5-4900-a9a4-b2d7d49fa386'

function renderPage(path = '/kayit') {
  const user = userEvent.setup()
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return user
}

function fillForm(password = ' synthetic secret ') {
  fireEvent.change(screen.getByLabelText('Ad ve soyad'), { target: { value: ' Sentetik Danışan ' } })
  fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: ' synthetic@example.test ' } })
  fireEvent.change(screen.getByLabelText('Şifre', { exact: true }), { target: { value: password } })
}

describe('client registration', () => {
  it('is reachable from login in production, without choosing a privileged role or making automatic requests', async () => {
    vi.stubEnv('DEV', false)
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderPage('/giris')
    await user.click(screen.getByRole('link', { name: 'Danışan hesabı oluştur' }))
    expect(screen.getByRole('heading', { level: 1, name: 'Danışan hesabı oluşturun.' })).toHaveFocus()
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveAttribute('autocomplete', 'new-password')
    expect(screen.queryByRole('combobox', { name: /rol/i })).not.toBeInTheDocument()
    expect(request).not.toHaveBeenCalled()
  })

  it('validates required fields and focuses the first invalid field before sending', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderPage()
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(screen.getByLabelText('Ad ve soyad')).toHaveFocus()
    expect(screen.getByLabelText('Ad ve soyad')).toHaveAccessibleDescription('Adınızı ve soyadınızı girin.')
    fireEvent.change(screen.getByLabelText('Ad ve soyad'), { target: { value: 'Sentetik' } })
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(screen.getByLabelText('E-posta adresi')).toHaveFocus()
    fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: 'synthetic@example.test' } })
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveFocus()
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveAccessibleDescription(/8–128 karakter olmalı/)
    expect(request).not.toHaveBeenCalled()
  })

  it.each(['a'.repeat(7), '😀'.repeat(7), 'a'.repeat(129), '😀'.repeat(129)])('rejects a password outside the Unicode length range', async (password) => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderPage()
    fillForm(password)
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(screen.getByText('Şifreniz 8–128 karakter olmalı.')).toBeVisible()
    expect(request).not.toHaveBeenCalled()
  })

  it.each([' synthetic secret ', '😀'.repeat(8), '😀'.repeat(128), ' '.repeat(8)])('preserves valid passwords and sends only the approved anonymous request', async (password) => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ id: syntheticId }, { status: 201 }))
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderPage()
    fillForm(password)
    await user.click(screen.getByRole('button', { name: 'Şifreyi göster' }))
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue(password)
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(request).toHaveBeenCalledExactlyOnceWith('/api/v1/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ displayName: 'Sentetik Danışan', email: 'synthetic@example.test', password }),
      credentials: 'omit', cache: 'no-store', redirect: 'error', signal: expect.any(AbortSignal),
    })
    expect(await screen.findByRole('status')).toHaveTextContent('Hesabınız oluşturuldu. Giriş yapmadan önce e-postanızı doğrulayın.')
    expect(screen.queryByRole('form')).not.toBeInTheDocument()
    expect(document.body).not.toHaveTextContent(syntheticId)
    expect(storage).not.toHaveBeenCalled()
    await user.click(screen.getByRole('link', { name: 'E-postamı doğrula' }))
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('E-postanızı doğrulayın.')
    expect(screen.getByLabelText('E-posta adresi')).toHaveValue('')
    expect(request).toHaveBeenCalledTimes(1)
  })

  it.each([
    [400, 'Kayıt bilgilerini kontrol'], [409, 'Bu e-posta adresiyle kayıt tamamlanamadı'],
    [422, 'Şifre kayıt kurallarını karşılamıyor'], [429, 'Çok fazla istek'], [500, 'Kayıt tamamlanamadı'],
    [200, 'Kayıt tamamlanamadı'], [202, 'Kayıt tamamlanamadı'],
  ])('handles status %i without exposing server details or claiming success', async (status, message) => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ error: { message: 'sensitive-server-detail' } }, { status: Number(status) }))
    const user = renderPage()
    fillForm()
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(String(message))
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveAttribute('type', 'password')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(document.body).not.toHaveTextContent('sensitive-server-detail')
    expect(screen.getByRole('button', { name: 'Hesap oluştur' })).toBeEnabled()
  })

  it.each([{}, { id: 'invalid' }, { id: syntheticId, accessToken: 'sensitive' }, null])('does not confirm malformed or expanded success bodies', async (body) => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json(body, { status: 201 }))
    const user = renderPage()
    fillForm()
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Kayıt sonucu doğrulanamadı.')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('explains an uncertain network outcome without automatic retries', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('sensitive-network-detail'))
    const user = renderPage()
    fillForm()
    await user.click(screen.getByRole('button', { name: 'Hesap oluştur' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Kayıt sonucu doğrulanamadı.')
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
    expect(document.body).not.toHaveTextContent('sensitive-network-detail')
    expect(request).toHaveBeenCalledTimes(1)
  })

  it('blocks duplicate submits, clears the password immediately and ignores late responses after leaving', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => new Promise((resolve) => { finish = resolve }))
    const user = renderPage()
    fillForm()
    const form = screen.getByRole('form', { name: 'Danışan kayıt formu' })
    fireEvent.submit(form)
    fireEvent.submit(form)
    expect(request).toHaveBeenCalledTimes(1)
    expect(form).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
    expect(screen.getByLabelText('Ad ve soyad')).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Hesap oluşturuluyor…' })).toBeDisabled()
    const signal = request.mock.calls[0]?.[1]?.signal
    await user.click(screen.getByRole('link', { name: 'Giriş ekranına dön' }))
    expect(signal?.aborted).toBe(true)
    await act(async () => finish(Response.json({ id: syntheticId }, { status: 201 })))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Danışan hesabı oluştur' }))
    expect(screen.getByLabelText('Ad ve soyad')).toHaveValue('')
    expect(screen.getByLabelText('E-posta adresi')).toHaveValue('')
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
  })
})

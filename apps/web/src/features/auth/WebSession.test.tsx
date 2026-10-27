import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const userAccount = { id: '17e6d4ad-128a-4b08-9f7c-4be6e9aa10b2', displayName: 'Sentetik Danışan',
  email: 'synthetic@example.test', role: 'client', isEmailVerified: true }
const csrf = () => Response.json({ requestToken: 'synthetic-csrf' })
const account = () => Response.json(userAccount)

function page(path = '/giris') {
  const user = userEvent.setup()
  const result = render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return { user, ...result }
}

function enterCredentials() {
  fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: ' synthetic@example.test ' } })
  fireEvent.change(screen.getByLabelText('Şifre', { exact: true }), { target: { value: ' synthetic password 🔒 ' } })
}

describe('web cookie session', () => {
  it('logs in using CSRF and restores the account without tokens in JS storage or navigation', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const { user } = page()
    enterCredentials()
    await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
    expect(await screen.findByText('Sentetik Danışan')).toBeVisible()
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Hesabım')
    expect(screen.queryByRole('navigation', { name: 'Diyetisyen paneli' })).not.toBeInTheDocument()
    expect(request.mock.calls.map(call => call[0])).toEqual([
      '/api/v1/auth/csrf', '/api/v1/auth/web-session', '/api/v1/auth/csrf', '/api/v1/auth/me',
    ])
    expect(request.mock.calls[1]?.[1]).toMatchObject({ method: 'POST', credentials: 'same-origin',
      body: JSON.stringify({ email: 'synthetic@example.test', password: ' synthetic password 🔒 ' }),
      headers: { 'X-CSRF-TOKEN': 'synthetic-csrf', 'Content-Type': 'application/json' } })
    for (const [, options] of request.mock.calls) {
      expect(options).toMatchObject({ credentials: 'same-origin', cache: 'no-store', redirect: 'error' })
      expect(options?.headers).not.toHaveProperty('Authorization')
    }
    expect(storage).not.toHaveBeenCalled()
  })

  it('restores a nullable display name and never treats a dietitian role as panel authorization', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(Response.json({ ...userAccount, displayName: null, role: 'dietitian' }))
    page('/hesabim')
    expect(await screen.findByText('Belirtilmemiş')).toBeVisible()
    expect(screen.getByText('Diyetisyen', { exact: true })).toBeVisible()
    expect(screen.queryByRole('navigation', { name: 'Diyetisyen paneli' })).not.toBeInTheDocument()
  })

  it('clears the visible account immediately and treats only 204 as confirmed logout', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockImplementationOnce(() => new Promise<Response>(resolve => { finish = resolve }))
    const { user } = page('/hesabim')
    await screen.findByText(userAccount.email)
    await user.click(screen.getByRole('button', { name: 'Çıkış yap' }))
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('İşlem sürüyor')
    expect(request).toHaveBeenLastCalledWith('/api/v1/auth/web-session', expect.objectContaining({
      method: 'DELETE', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf' },
    }))
    await act(async () => finish(new Response(null, { status: 204 })))
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Tekrar hoş geldiniz.')
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
  })

  it('keeps an unconfirmed logout visible and retries only after an explicit click and context read', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockRejectedValueOnce(new Error('private transport detail'))
      .mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account()).mockResolvedValueOnce(new Response(null, { status: 204 }))
    const { user } = page('/hesabim')
    await screen.findByText(userAccount.email)
    await user.click(screen.getByRole('button', { name: 'Çıkış yap' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Çıkış sunucuda doğrulanamadı; tekrar deneyin.')
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(3)
    expect(document.body).not.toHaveTextContent('private transport detail')
    await user.click(screen.getByRole('button', { name: 'Çıkışı tekrar dene' }))
    expect(await screen.findByRole('heading', { name: 'Tekrar hoş geldiniz.' })).toBeVisible()
    expect(request).toHaveBeenCalledTimes(6)
  })

  it('does not log out a different account that appeared in another tab after a failed attempt', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockResolvedValueOnce(new Response(null, { status: 500 })).mockResolvedValueOnce(csrf())
      .mockResolvedValueOnce(Response.json({ ...userAccount, id: 'b2f53ff0-c37d-4831-80b2-af27755ca19f', email: 'other@example.test' }))
    const { user } = page('/hesabim')
    await screen.findByText(userAccount.email)
    await user.click(screen.getByRole('button', { name: 'Çıkış yap' }))
    await user.click(await screen.findByRole('button', { name: 'Çıkışı tekrar dene' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Oturum bağlamı değişti')
    expect(request.mock.calls.filter(call => call[1]?.method === 'DELETE')).toHaveLength(1)
    expect(document.body).not.toHaveTextContent('other@example.test')
  })

  it('drops stale CSRF without automatically retrying a failed mutation', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockResolvedValueOnce(new Response(null, { status: 400 }))
    const { user } = page('/hesabim')
    await screen.findByText(userAccount.email)
    await user.click(screen.getByRole('button', { name: 'Çıkış yap' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Oturum bağlamı değişti')
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(3)
  })

  it('returns to login on a server 401 without displaying a stale account', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(new Response(null, { status: 401 }))
    page('/hesabim')
    expect(await screen.findByRole('heading', { name: 'Tekrar hoş geldiniz.' })).toBeVisible()
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
  })

  it.each([{ ...userAccount, role: 'admin' }, { ...userAccount, accessToken: 'forbidden' }, { ...userAccount, isEmailVerified: false }])(
    'rejects an unexpected account response', async invalid => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(Response.json(invalid))
      page('/hesabim')
      expect(await screen.findByRole('alert')).toHaveTextContent('Hesap bilgileri doğrulanamadı')
      expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
    })

  it('blocks duplicate login submissions and aborts on navigation so a late response cannot sign the UI in', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf())
      .mockImplementationOnce(() => new Promise<Response>(resolve => { finish = resolve }))
    const { user } = page()
    enterCredentials()
    await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
    expect(screen.getByRole('button', { name: 'İşlem sürüyor…' })).toBeDisabled()
    expect(screen.getByLabelText('Şifre', { exact: true })).toHaveValue('')
    fireEvent.submit(screen.getByRole('form'))
    expect(request).toHaveBeenCalledTimes(2)
    const signal = request.mock.calls[1]?.[1]?.signal
    await user.click(screen.getByRole('link', { name: 'Şifremi unuttum' }))
    expect(signal?.aborted).toBe(true)
    await act(async () => finish(account()))
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Şifrenizi mi unuttunuz?')
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
  })

  it('aborts account restoration when leaving and ignores late data', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf())
      .mockImplementationOnce(() => new Promise<Response>(resolve => { finish = resolve }))
    const { user } = page('/hesabim')
    await waitFor(() => expect(request).toHaveBeenCalledTimes(2))
    const signal = request.mock.calls[1]?.[1]?.signal
    await user.click(screen.getByRole('link', { name: 'Giriş ekranına git' }))
    expect(signal?.aborted).toBe(true)
    await act(async () => finish(account()))
    expect(screen.queryByText(userAccount.email)).not.toBeInTheDocument()
  })
})

import { StrictMode, useEffect } from 'react'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { BrowserRouter, MemoryRouter, useLocation, useNavigate } from 'react-router-dom'
import type { Location, NavigateFunction } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { passwordResetNotice, requestPasswordReset, resetPassword, resetPasswordError } from './passwordResetApi'

const token = 'A'.repeat(43), nextToken = 'B'.repeat(43), password = ' Yeni parola 🔑 '
const link = (value = token) => `/sifremi-unuttum#token=${value}`
function open(path = '/sifremi-unuttum', strict = false) {
  let location: Location, navigate: NavigateFunction
  function Probe() {
    const current = useLocation(), go = useNavigate()
    useEffect(() => { location = current; navigate = go }, [current, go])
    return null
  }
  const content = <MemoryRouter initialEntries={['/giris', path]} initialIndex={1}><App /><Probe /></MemoryRouter>
  const view = render(strict ? <StrictMode>{content}</StrictMode> : content)
  return { ...view, location: () => location!, navigate: (path: string | number) => {
    if (typeof path === 'number') navigate!(path); else navigate!(path)
  } }
}
function fill(value = password, repeat = value) {
  fireEvent.change(screen.getByLabelText('Yeni şifre', { exact: true }), { target: { value } })
  fireEvent.change(screen.getByLabelText('Yeni şifre tekrarı'), { target: { value: repeat } })
}
function submit() { fireEvent.submit(screen.getByRole('form', { name: 'Yeni şifre formu' })) }

describe('canonical password reset API', () => {
  it('sends only canonical fields, unmodified credentials and no ambient identity/referrer', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(null, { status: 202 })).mockResolvedValueOnce(new Response(null, { status: 204 }))
    const signal = new AbortController().signal
    await requestPasswordReset({ email: ' synthetic@example.test ' }, signal)
    await resetPassword({ token, password }, signal)
    expect(request.mock.calls.map(([path]) => path)).toEqual(['/api/v1/auth/password-reset-requests', '/api/v1/auth/reset-password'])
    for (const [, options] of request.mock.calls) expect(options).toMatchObject({ method: 'POST', credentials: 'omit', signal,
      cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', headers: { 'Content-Type': 'application/json' } })
    expect(request.mock.calls[0]![1]!.body).toBe(JSON.stringify({ email: ' synthetic@example.test ' }))
    expect(JSON.parse(String(request.mock.calls[1]![1]!.body))).toEqual({ token, password })
  })
  it.each([200, 400, 403, 422, 429, 500])('does not treat unexpected reset-request HTTP %s as success or reflect response text', async status => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(`private ${token}`, { status }))
    try { await requestPasswordReset({ email: 'synthetic@example.test' }, new AbortController().signal); throw new Error('Unexpected success') }
    catch (error) { expect(String(error).includes(token)).toBe(false); expect(error).toMatchObject({ status }) }
  })
  it('counts Unicode scalar values with the shipped 8–128 policy and preserves whitespace', () => {
    expect(resetPasswordError('😀'.repeat(8))).toBeUndefined()
    expect(resetPasswordError('😀'.repeat(128))).toBeUndefined()
    expect(resetPasswordError(' '.repeat(8))).toBeUndefined()
    expect(resetPasswordError('😀'.repeat(7))).toContain('8–128')
    expect(resetPasswordError('😀'.repeat(129))).toContain('8–128')
    expect(resetPasswordError('abcdefg\ud800')).toContain('Unicode')
  })
})

describe('requesting a real reset link', () => {
  it('uses the same safe success message for any accepted address without account disclosure', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 202 }))
    open()
    for (const email of ['existing@example.test', 'missing@example.test']) {
      fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: email } })
      fireEvent.submit(screen.getByRole('form'))
      expect(await screen.findByRole('status')).toHaveTextContent(passwordResetNotice)
    }
    expect(request).toHaveBeenCalledTimes(2)
  })
  it('validates email and synchronously blocks duplicate submissions while pending', async () => {
    let finish: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => new Promise(resolve => { finish = resolve }))
    open(); fireEvent.submit(screen.getByRole('form'))
    expect(screen.getByLabelText('E-posta adresi')).toHaveFocus(); expect(request).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: 'synthetic@example.test' } })
    fireEvent.submit(screen.getByRole('form')); fireEvent.submit(screen.getByRole('form'))
    expect(request).toHaveBeenCalledTimes(1); expect(screen.getByLabelText('E-posta adresi')).toBeDisabled()
    await act(async () => finish!(new Response(null, { status: 202 })))
    expect(screen.getByRole('status')).toHaveTextContent(passwordResetNotice)
  })
  it.each([400, 429, 500, 0])('distinguishes request HTTP %s/network errors from accepted email delivery', async status => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => { if (!status) throw new TypeError('synthetic offline'); return new Response(null, { status }) })
    open(); fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: 'synthetic@example.test' } }); fireEvent.submit(screen.getByRole('form'))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 429 ? 'Çok fazla' : status === 0 ? 'sonucu doğrulanamadı' : status === 400 ? 'Bilgiler doğrulanamadı' : 'sunucuda tamamlanamadı')
    expect(screen.queryByText(passwordResetNotice)).not.toBeInTheDocument()
  })
})

describe('email-link password form', () => {
  it('captures a token once, scrubs the URL and works under React StrictMode without persistence', () => {
    const store = vi.spyOn(Storage.prototype, 'setItem'), request = vi.spyOn(globalThis, 'fetch')
    const page = open(link(), true)
    expect(screen.getByRole('form', { name: 'Yeni şifre formu' })).toBeInTheDocument()
    expect(page.location().hash).toBe(''); expect(page.location().search).toBe(''); expect(page.location().state).toBeNull()
    expect(document.body.innerHTML.includes(token)).toBe(false)
    expect(store).not.toHaveBeenCalled(); expect(request).not.toHaveBeenCalled()
  })
  it('scrubs the actual browser URL and history state before submitting any request', () => {
    const previous = window.location.href
    window.history.replaceState(null, '', link())
    try {
      render(<BrowserRouter><App /></BrowserRouter>)
      expect(window.location.hash).toBe(''); expect(window.location.search).toBe('')
      expect(JSON.stringify(window.history.state).includes(token)).toBe(false)
      expect(screen.getByLabelText('Yeni şifre', { exact: true })).toHaveAttribute('autoComplete', 'new-password')
    } finally { window.history.replaceState(null, '', previous) }
  })
  it.each(['#token=', '#token=short', `#token=${token}&token=${token}`, `?token=${token}`, '#unknown=private'])('clears invalid/missing %s secret input and offers a fresh link without HTTP', suffix => {
    const request = vi.spyOn(globalThis, 'fetch'), page = open('/sifremi-unuttum' + suffix)
    expect(screen.getByRole('alert')).toHaveTextContent('eksik, geçersiz')
    expect(screen.queryByRole('form', { name: 'Yeni şifre formu' })).not.toBeInTheDocument()
    expect(page.location().hash).toBe(''); expect(page.location().search).toBe('')
    expect(request).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('link', { name: 'Yeni sıfırlama bağlantısı iste' }))
    expect(screen.getByLabelText('E-posta adresi')).toBeInTheDocument()
  })
  it('explains how to reopen the email when the clean page is refreshed', () => {
    const first = open(link()); first.unmount(); open('/sifremi-unuttum')
    expect(screen.getByText(/sayfayı yenilediyseniz/)).toBeInTheDocument()
    expect(screen.queryByLabelText('Yeni şifre', { exact: true })).not.toBeInTheDocument()
  })
  it('focuses validation errors and does not silently trim or normalize either password', () => {
    const request = vi.spyOn(globalThis, 'fetch'); open(link()); fill('short'); submit()
    expect(screen.getByLabelText('Yeni şifre', { exact: true })).toHaveFocus()
    fill(password, password.trim()); submit()
    expect(screen.getByLabelText('Yeni şifre tekrarı')).toHaveFocus()
    expect(screen.getByRole('alert')).toHaveTextContent('Şifreler aynı olmalı.')
    expect(request).not.toHaveBeenCalled()
  })
  it('sends the exact password once, clears secrets, replaces navigation and never auto-logs-in', async () => {
    let finish: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => new Promise(resolve => { finish = resolve }))
    const store = vi.spyOn(Storage.prototype, 'setItem'), page = open(link()); fill(); submit(); submit()
    expect(request).toHaveBeenCalledTimes(1)
    expect(screen.getByLabelText('Yeni şifre', { exact: true })).toHaveValue('')
    expect(screen.getByLabelText('Yeni şifre tekrarı')).toBeDisabled()
    expect(JSON.parse(String(request.mock.calls[0]![1]!.body))).toEqual({ token, password })
    await act(async () => finish!(new Response(null, { status: 204 })))
    expect(await screen.findByRole('heading', { name: 'Tekrar hoş geldiniz.' })).toBeInTheDocument()
    expect(page.location().pathname).toBe('/giris'); expect(page.location().state).toEqual({ passwordResetComplete: true })
    expect(screen.getByRole('status')).toHaveTextContent('MFA doğrulaması devam eder')
    expect(request).toHaveBeenCalledTimes(1); expect(store).not.toHaveBeenCalled()
    act(() => page.navigate(-1)); expect(screen.queryByRole('form', { name: 'Yeni şifre formu' })).not.toBeInTheDocument()
  })
  it('shows the shared invalid/expired/used-token message for 422 and never reflects server secrets', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(`private ${token} ${password}`, { status: 422 }))
    open(link()); fill(); submit()
    expect(await screen.findByRole('alert')).toHaveTextContent('süresi dolmuş veya kullanılmış')
    expect(document.body.innerHTML.includes(token)).toBe(false); expect(document.body.innerHTML.includes(password)).toBe(false)
    expect(screen.getByRole('link', { name: 'Yeni sıfırlama bağlantısı iste' })).toBeInTheDocument()
  })
  it.each([400, 429, 500, 0])('handles reset error %s without claiming success and permits a deliberate retry', async status => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => { if (!status) throw new TypeError('private network error'); return new Response('private', { status }) })
    open(link()); fill(); submit()
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 429 ? 'Çok fazla' : status === 0 ? 'sonucu doğrulanamadı' : status === 400 ? 'Bilgiler doğrulanamadı' : 'sunucuda tamamlanamadı')
    expect(screen.getByRole('button', { name: 'Şifreyi yenile' })).toBeEnabled()
    expect(screen.getByLabelText('Yeni şifre', { exact: true })).toHaveValue('')
  })
  it('aborts the previous token operation and ignores its late success after a new link arrives', async () => {
    let finish: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => new Promise(resolve => { finish = resolve }))
    const page = open(link()); fill(); submit()
    const signal = request.mock.calls[0]![1]!.signal!
    act(() => page.navigate(link(nextToken)))
    expect(signal.aborted).toBe(true)
    await act(async () => finish!(new Response(null, { status: 204 })))
    expect(page.location().pathname).toBe('/sifremi-unuttum')
    expect(screen.getByLabelText('Yeni şifre', { exact: true })).toHaveValue('')
    expect(screen.queryByText(/Şifreniz yenilendi/)).not.toBeInTheDocument()
  })
})

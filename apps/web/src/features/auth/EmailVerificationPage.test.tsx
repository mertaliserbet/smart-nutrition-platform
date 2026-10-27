import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const syntheticToken = 'A'.repeat(43)

function renderPage(path = '/eposta-dogrulama') {
  const user = userEvent.setup()
  render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return user
}

function enterToken(value = syntheticToken) {
  fireEvent.change(screen.getByLabelText('Doğrulama kodu'), { target: { value } })
}

describe('email verification', () => {
  it('is reachable from login and never consumes a code automatically from the URL', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderPage('/giris')
    await user.click(screen.getByRole('link', { name: 'E-postamı doğrula' }))
    expect(screen.getByRole('heading', { level: 1 })).toHaveFocus()
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
    expect(request).not.toHaveBeenCalled()
  })

  it('ignores URL token fields and validates malformed input without a request', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderPage(`/eposta-dogrulama?token=${syntheticToken}`)
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
    await user.click(screen.getByRole('button', { name: 'E-postamı doğrula' }))
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveFocus()
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveAccessibleDescription(/43 karakterlik/)
    enterToken('wrong')
    await user.click(screen.getByRole('button', { name: 'E-postamı doğrula' }))
    expect(request).not.toHaveBeenCalled()
  })

  it('uses the canonical token body and only 204 completes verification without a session', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 204 }))
    const storage = vi.spyOn(Storage.prototype, 'setItem')
    const user = renderPage()
    enterToken(` ${syntheticToken}\n`)
    await user.click(screen.getByRole('button', { name: 'E-postamı doğrula' }))
    expect(request).toHaveBeenCalledExactlyOnceWith('/api/v1/auth/verify-email', expect.objectContaining({
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: syntheticToken }),
      credentials: 'omit', cache: 'no-store', redirect: 'error', signal: expect.any(AbortSignal),
    }))
    expect(await screen.findByRole('status')).toHaveTextContent('E-posta adresiniz doğrulandı. Oturum açılmadı.')
    expect(screen.queryByLabelText('Doğrulama kodu')).not.toBeInTheDocument()
    expect(screen.queryByRole('form')).not.toBeInTheDocument()
    expect(storage).not.toHaveBeenCalled()
    await user.click(screen.getByRole('link', { name: 'Giriş ekranına dön' }))
    await user.click(screen.getByRole('link', { name: 'E-postamı doğrula' }))
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
    expect(request).toHaveBeenCalledTimes(1)
  })

  it('shows the same safe 422 error and clears the submitted token without echoing server data', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      error: { code: 'validation_failed', message: syntheticToken }, requestId: 'synthetic',
    }), { status: 422 }))
    const user = renderPage()
    enterToken()
    await user.click(screen.getByRole('button', { name: 'E-postamı doğrula' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Kod geçersiz veya süresi dolmuş.')
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
    expect(document.body).not.toHaveTextContent(syntheticToken)
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it.each([200, 202, 400, 429, 500])('does not report success for unexpected verify status %s', async (status) => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status }))
    const user = renderPage()
    enterToken()
    await user.click(screen.getByRole('button', { name: 'E-postamı doğrula' }))
    const alert = await screen.findByRole('alert')
    expect(alert).toBeVisible()
    if (status === 429) expect(alert).toHaveTextContent('Çok fazla istek')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
  })

  it('blocks repeat and competing requests while pending, then aborts when leaving', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => new Promise((resolve) => { finish = resolve }))
    const user = renderPage()
    enterToken()
    fireEvent.submit(screen.getByRole('form', { name: 'E-posta doğrulama formu' }))
    fireEvent.submit(screen.getByRole('form', { name: 'E-posta doğrulama formu' }))
    fireEvent.submit(screen.getByRole('form', { name: 'Doğrulama kodunu yeniden isteme formu' }))
    expect(request).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('form', { name: 'E-posta doğrulama formu' })).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByLabelText('Doğrulama kodu')).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Yeni kod iste' })).toBeDisabled()
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
    const signal = request.mock.calls[0]?.[1]?.signal
    await user.click(screen.getByRole('link', { name: 'Giriş ekranına dön' }))
    expect(signal?.aborted).toBe(true)
    await act(async () => finish(new Response(null, { status: 204 })))
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Tekrar hoş geldiniz.')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })
})

describe('resend verification', () => {
  it('validates the email before requesting a code', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    const user = renderPage()
    await user.click(screen.getByRole('button', { name: 'Yeni kod iste' }))
    expect(screen.getByLabelText('E-posta adresi')).toHaveFocus()
    expect(screen.getByLabelText('E-posta adresi')).toHaveAccessibleDescription('Geçerli bir e-posta adresi girin.')
    expect(request).not.toHaveBeenCalled()
  })

  it('treats 202 as a generic acceptance, preserves account privacy and clears any old code', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 202 }))
    const user = renderPage()
    enterToken()
    fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: ' synthetic@example.test ' } })
    await user.click(screen.getByRole('button', { name: 'Yeni kod iste' }))
    expect(request).toHaveBeenCalledExactlyOnceWith('/api/v1/auth/resend-verification', expect.objectContaining({
      body: JSON.stringify({ email: 'synthetic@example.test' }), credentials: 'omit', cache: 'no-store',
    }))
    expect(await screen.findByRole('status')).toHaveTextContent('Hesap doğrulama için uygunsa kod gönderimi işleme alınır.')
    expect(screen.getByRole('status')).not.toHaveTextContent('gönderildi')
    expect(screen.getByLabelText('Doğrulama kodu')).toHaveValue('')
    expect(screen.getByRole('button', { name: 'E-postamı doğrula' })).toBeEnabled()
  })

  it.each([204, 429, 500])('does not claim a resend was accepted for HTTP %s', async (status) => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status }))
    const user = renderPage()
    await user.type(screen.getByLabelText('E-posta adresi'), 'synthetic@example.test')
    await user.click(screen.getByRole('button', { name: 'Yeni kod iste' }))
    expect(await screen.findByRole('alert')).toBeVisible()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('allows retry after a network failure without displaying transport details', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
      .mockRejectedValueOnce(new Error('synthetic private transport detail'))
      .mockResolvedValueOnce(new Response(null, { status: 202 }))
    const user = renderPage()
    await user.type(screen.getByLabelText('E-posta adresi'), 'synthetic@example.test')
    await user.click(screen.getByRole('button', { name: 'Yeni kod iste' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Sunucuya ulaşılamadı.')
    expect(document.body).not.toHaveTextContent('synthetic private transport detail')
    await user.click(screen.getByRole('button', { name: 'Yeni kod iste' }))
    expect(await screen.findByRole('status')).toHaveTextContent('işleme alınır')
    expect(request).toHaveBeenCalledTimes(2)
  })
})

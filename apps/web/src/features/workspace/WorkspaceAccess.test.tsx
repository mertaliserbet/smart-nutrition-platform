import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const userId = '17e6d4ad-128a-4b08-9f7c-4be6e9aa10b2'
const expertId = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const userAccount = (role = 'client') => ({ id: userId, displayName: 'Sentetik Hesap', email: 'synthetic@example.test', role, isEmailVerified: true })
const profile = (isVerified = true) => ({ id: expertId, displayName: 'Sentetik Uzman', isVerified })
const empty = () => Response.json({ items: [], totalCount: 0 })

function page(path = '/giris') {
  const result = render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return { ...result, user: userEvent.setup() }
}
function api(role = 'client', verified = true) {
  return vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
    const path = String(input)
    if (path === '/api/v1/auth/csrf') return Response.json({ requestToken: 'synthetic-csrf' })
    if (path === '/api/v1/auth/web-session' || path === '/api/v1/auth/me') return Response.json(userAccount(role))
    if (path === '/api/v1/dietitians/me') return Response.json(profile(verified))
    if (path.startsWith('/api/v1/dietitian/clients?') || path.startsWith('/api/v1/dietitian-relationships?')) return empty()
    throw new Error(`Unexpected test request: ${path}`)
  })
}
async function signIn(user: ReturnType<typeof userEvent.setup>) {
  fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: 'synthetic@example.test' } })
  fireEvent.change(screen.getByLabelText('Şifre', { exact: true }), { target: { value: 'synthetic password' } })
  await user.click(screen.getByRole('button', { name: 'Giriş yap' }))
}

describe('workspace entry and session recovery', () => {
  it.each(['client', 'dietitian'])('takes an approved %s profile from login into the live dashboard', async role => {
    const request = api(role)
    const { user } = page()
    await signIn(user)
    expect(await screen.findByRole('heading', { level: 1, name: 'Genel bakış' })).toBeVisible()
    await screen.findByText('İlk danışanınızla bağlantı kurun')
    expect(document.title).toBe('Genel bakış · Smart Nutrition')
    expect(screen.getByRole('heading', { level: 1, name: 'Genel bakış' })).toHaveFocus()
    const metrics = within(screen.getByRole('region', { name: 'Çalışma alanı özeti' }))
    expect(metrics.getAllByText('0', { exact: true })).toHaveLength(2)
    expect(request.mock.calls.filter(([path]) => path === '/api/v1/dietitians/me')).toHaveLength(2)
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1)
    for (const [path, options] of request.mock.calls) {
      if (String(path).includes('/dietitian/') || String(path).includes('/dietitian-relationships')) {
        expect(options?.headers).toMatchObject({ 'X-Profile-Context': 'dietitian' })
      }
    }
    expect(screen.queryByText('Önizleme senaryosu')).not.toBeInTheDocument()
    expect(screen.queryByText('Yeni öğün kayıtları')).not.toBeInTheDocument()
  })

  it.each(['client', 'dietitian'])('takes a pending %s profile to status without requesting client resources', async role => {
    const request = api(role, false)
    const { user } = page(); await signIn(user)
    expect(await screen.findByText('Başvurunuz Admin incelemesini bekliyor.')).toBeVisible()
    expect(request.mock.calls.some(([path]) => String(path).includes('/dietitian/clients'))).toBe(false)
  })

  it('keeps a signed-in client account usable when the profile check fails and offers a fresh entry', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ requestToken: 'csrf' }))
      .mockResolvedValueOnce(Response.json(userAccount())).mockRejectedValueOnce(new Error('network'))
      .mockResolvedValueOnce(Response.json({ requestToken: 'csrf' })).mockResolvedValueOnce(Response.json(userAccount()))
    const { user } = page(); await signIn(user)
    expect(await screen.findByText('synthetic@example.test')).toBeVisible()
    expect(screen.getByRole('status')).toHaveTextContent('Giriş yapıldı; diyetisyen erişimi şu anda doğrulanamadı')
    expect(screen.getByRole('link', { name: 'Çalışma alanımı aç' })).toHaveAttribute('href', '/calisma-alani')
    expect(screen.getByRole('button', { name: 'Çıkış yap' })).toBeEnabled()
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1)
  })

  it('rechecks approval after navigation and blocks data if approval was lost after login', async () => {
    const request = api()
    const original = request.getMockImplementation()!
    let checks = 0
    request.mockImplementation((input, options) => {
      if (String(input) === '/api/v1/dietitians/me') return Promise.resolve(Response.json(profile(++checks === 1)))
      return original(input, options)
    })
    const { user } = page(); await signIn(user)
    expect(await screen.findByText('Başvurunuz Admin incelemesini bekliyor.')).toBeVisible()
    expect(request.mock.calls.some(([path]) => String(path).includes('/dietitian/clients'))).toBe(false)
  })

  it('aborts profile resolution on leaving login and ignores its late approval', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ requestToken: 'csrf' }))
      .mockResolvedValueOnce(Response.json(userAccount())).mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const { user } = page(); await signIn(user)
    await waitFor(() => expect(request).toHaveBeenCalledTimes(3))
    const signal = request.mock.calls[2]?.[1]?.signal
    await user.click(screen.getByRole('link', { name: 'Şifremi unuttum' }))
    expect(signal?.aborted).toBe(true)
    await act(async () => finish(Response.json(profile())))
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Şifrenizi mi unuttunuz?')
    expect(screen.queryByRole('navigation', { name: 'Diyetisyen çalışma alanı' })).not.toBeInTheDocument()
  })

  it('hides dashboard counts and names on refresh failure instead of retaining private data or displaying zero', async () => {
    const request = api()
    const original = request.getMockImplementation()!
    let reads = 0
    request.mockImplementation((input, options) => {
      if (String(input).startsWith('/api/v1/dietitian/clients?')) return Promise.resolve(++reads === 1
        ? Response.json({ items: [{ id: clientId, displayName: 'Sentetik Danışan' }], totalCount: 12 })
        : new Response(null, { status: 500 }))
      return original(input, options)
    })
    const { user } = page('/calisma-alani')
    await screen.findByText('Sentetik Danışan')
    await user.click(screen.getByRole('button', { name: 'Özeti yenile' }))
    await screen.findByRole('alert')
    expect(screen.queryByText('Sentetik Danışan')).not.toBeInTheDocument()
    const metrics = within(screen.getByRole('region', { name: 'Çalışma alanı özeti' }))
    expect(metrics.getAllByText('—')).toHaveLength(2)
    expect(metrics.queryByText('0', { exact: true })).not.toBeInTheDocument()
  })

  it('closes the live mobile menu on Escape and on route selection', async () => {
    api()
    const { user } = page('/calisma-alani')
    await screen.findByText('İlk danışanınızla bağlantı kurun')
    const menu = screen.getByRole('button', { name: 'Menüyü aç' })
    await user.click(menu); expect(menu).toHaveAttribute('aria-expanded', 'true')
    await user.keyboard('{Escape}'); expect(menu).toHaveAttribute('aria-expanded', 'false'); expect(menu).toHaveFocus()
    await user.click(menu)
    await user.click(within(screen.getByRole('navigation', { name: 'Diyetisyen çalışma alanı' })).getByRole('link', { name: 'Bağlantılar ve davet' }))
    expect(menu).toHaveAttribute('aria-expanded', 'false')
    expect(await screen.findByRole('heading', { level: 1, name: 'Bağlantılar ve davet' })).toBeVisible()
  })
})

describe('administrator workspace', () => {
  it('reads approved applications with the existing filter and provides no approval mutation for them', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ requestToken: 'csrf' }))
      .mockResolvedValueOnce(Response.json(userAccount('admin'))).mockResolvedValueOnce(empty())
      .mockResolvedValueOnce(Response.json({ requestToken: 'csrf' })).mockResolvedValueOnce(Response.json(userAccount('admin')))
      .mockResolvedValueOnce(Response.json({ items: [{ ...profile(), licenseInfo: 'Sentetik mesleki kayıt' }], totalCount: 1 }))
    const { user } = page('/yonetim')
    await screen.findByText('İnceleme bekleyen başvuru bulunmuyor.')
    await user.selectOptions(screen.getByRole('combobox', { name: 'Başvuru durumu' }), 'true')
    expect(await screen.findByText('Sentetik mesleki kayıt')).toBeVisible()
    expect(request.mock.calls[5]?.[0]).toBe('/api/v1/admin/dietitians?isVerified=true&page=1&pageSize=10')
    expect(screen.queryByRole('button', { name: /uzman onayı ver/ })).not.toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Yönetici paneli' })).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Danışanlarım' })).not.toBeInTheDocument()
  })

  it('returns a directly opened administrator account to administrator login after confirmed logout', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ requestToken: 'csrf' }))
      .mockResolvedValueOnce(Response.json(userAccount('admin'))).mockResolvedValueOnce(new Response(null, { status: 204 }))
    const { user } = page('/hesabim')
    await screen.findByText('synthetic@example.test')
    await user.click(screen.getByRole('button', { name: 'Çıkış yap' }))
    expect(await screen.findByRole('heading', { level: 1, name: 'Yönetici girişi' })).toBeVisible()
    expect(request.mock.calls[2]?.[1]?.method).toBe('DELETE')
  })
})

import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const expert = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const client = '17514097-4a19-4376-819e-045fe3180aae'
const relationship = 'c428ae15-f14c-4685-a272-69a81225c9df'
const account = (role = 'dietitian') => Response.json({ id: '8a0829e9-fbdd-486a-bc1d-128701513c04', displayName: 'Sentetik Uzman', email: 'expert@example.test', role, isEmailVerified: true })
const status = (isVerified = true) => Response.json({ id: expert, displayName: 'Sentetik Uzman', isVerified })
const list = () => Response.json({ items: [{ id: client, displayName: 'Sentetik Danışan' }], totalCount: 1 })
const relation = (state = 'pending') => ({ id: relationship, clientId: client, dietitianId: expert, status: state, requestedAt: '2026-10-29T09:00:00Z', respondedAt: state === 'pending' ? null : '2026-10-29T09:30:00Z', endedAt: state === 'ended' ? '2026-10-29T10:00:00Z' : null })
function setup(path = '/calisma-alani/danisanlar') {
  const rendered = render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return { ...rendered, user: userEvent.setup() }
}
function gated() {
  return vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ requestToken: 'synthetic-csrf' })).mockResolvedValueOnce(account()).mockResolvedValueOnce(status())
}

describe('authenticated dietitian workspace', () => {
  it('loads actual minimal client data after account and expert checks, without preview data', async () => {
    const request = gated().mockResolvedValueOnce(list())
    setup()
    expect(await screen.findByRole('link', { name: 'Sentetik Danışan için danışan detayını aç' })).toBeVisible()
    expect(request.mock.calls[3]?.[0]).toContain('/api/v1/dietitian/clients?')
    expect(request.mock.calls[3]?.[1]).toMatchObject({ method: 'GET', credentials: 'same-origin', cache: 'no-store' })
    expect(screen.queryByText('Önizleme senaryosu')).not.toBeInTheDocument()
    expect(screen.queryByText('Kalori')).not.toBeInTheDocument()
  })

  it('blocks the resource request for an unverified expert and shows the application status', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ requestToken: 'csrf' })).mockResolvedValueOnce(account()).mockResolvedValueOnce(status(false))
      .mockResolvedValueOnce(account()).mockResolvedValueOnce(status(false))
    setup()
    expect(await screen.findByText('Başvurunuz Admin incelemesini bekliyor.')).toBeVisible()
    expect(request.mock.calls.some(([path]) => String(path).includes('/dietitian/clients'))).toBe(false)
  })

  it('reads client details only from the requested dashboard and rejects another client id', async () => {
    const request = gated().mockResolvedValueOnce(Response.json({ clientId: client, displayName: 'Sentetik Danışan' }))
    setup(`/calisma-alani/danisanlar/${client}`)
    expect(await screen.findByRole('heading', { level: 2, name: 'Sentetik Danışan' })).toBeVisible()
    expect(request.mock.calls[3]?.[0]).toBe(`/api/v1/dietitian/clients/${client}/dashboard`)
    expect(screen.queryByText('Tahliller')).not.toBeInTheDocument()
  })

  it('clears an earlier client list immediately during refresh and redirects on a new 401', async () => {
    const request = gated().mockResolvedValueOnce(list()).mockResolvedValueOnce(new Response(null, { status: 401 }))
    const { user } = setup()
    await screen.findByText('Sentetik Danışan')
    await user.click(screen.getByRole('button', { name: 'Listeyi yenile' }))
    expect(await screen.findByRole('heading', { name: 'Tekrar hoş geldiniz.' })).toBeVisible()
    expect(screen.queryByText('Sentetik Danışan')).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(5)
  })

  it('submits server search parameters while clearing the old page', async () => {
    const request = gated().mockResolvedValueOnce(list()).mockResolvedValueOnce(Response.json({ items: [], totalCount: 0 }))
    const { user } = setup()
    await screen.findByText('Sentetik Danışan')
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: ' Aranan ' } })
    await user.click(screen.getByRole('button', { name: 'Ara' }))
    expect(await screen.findByText('0 danışan')).toBeVisible()
    const url = new URL(request.mock.calls[4]?.[0] as string, 'https://localhost')
    expect(url.searchParams.get('query')).toBe('Aranan')
    expect(url.searchParams.get('page')).toBe('1')
  })

  it('creates a single-use invitation with CSRF only after explicit submission', async () => {
    const request = gated().mockResolvedValueOnce(Response.json({ items: [], totalCount: 0 }))
      .mockResolvedValueOnce(Response.json({ invitationCode: 'ABCDEFGH234567AB', expiresAt: '2026-10-30T09:00:00Z' }))
    const { user } = setup('/calisma-alani/baglantilar')
    await screen.findByText('Bu durumda bağlantı bulunmuyor.')
    expect(request).toHaveBeenCalledTimes(4)
    await user.click(screen.getByRole('button', { name: 'Davet kodu oluştur' }))
    expect(await screen.findByText('ABCDEFGH234567AB')).toBeVisible()
    expect(request.mock.calls[4]?.[0]).toBe('/api/v1/dietitians/me/invitation-code')
    expect(request.mock.calls[4]?.[1]).toMatchObject({ method: 'POST', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf' } })
    expect(request.mock.calls[4]?.[1]?.body).toBeUndefined()
  })

  it('accepts only the selected relationship and refreshes the list after confirmed success', async () => {
    const request = gated().mockResolvedValueOnce(Response.json({ items: [relation()], totalCount: 1 })).mockResolvedValueOnce(Response.json(relation('active')))
      .mockResolvedValueOnce(Response.json({ items: [], totalCount: 0 }))
    const { user } = setup('/calisma-alani/baglantilar')
    await user.click(await screen.findByRole('button', { name: 'Kabul et' }))
    expect(await screen.findByText('Bağlantı kabul edildi.')).toBeVisible()
    expect(request.mock.calls[4]?.[0]).toBe(`/api/v1/dietitian-relationships/${relationship}/accept`)
    expect(request.mock.calls.filter(([path, options]) => String(path).includes('/accept') && options?.method === 'POST')).toHaveLength(1)
  })

  it('drops connection data on stale CSRF without retrying the write', async () => {
    const request = gated().mockResolvedValueOnce(Response.json({ items: [relation()], totalCount: 1 })).mockResolvedValueOnce(new Response(null, { status: 400 }))
    const { user } = setup('/calisma-alani/baglantilar')
    await user.click(await screen.findByRole('button', { name: 'Kabul et' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Oturum bağlamı')
    expect(screen.queryByText(`Danışan kimliği: ${client}`)).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(5)
  })

  it('rejects a foreign dietitian response before showing relationship data', async () => {
    gated().mockResolvedValueOnce(Response.json({ items: [{ ...relation(), dietitianId: client }], totalCount: 1 }))
    setup('/calisma-alani/baglantilar')
    expect(await screen.findByRole('alert')).toHaveTextContent('Sunucu yanıtı doğrulanamadı')
    expect(screen.queryByRole('button', { name: 'Kabul et' })).not.toBeInTheDocument()
  })

  it('aborts pending private reads when the workspace is unmounted', async () => {
    let finish!: (response: Response) => void
    const request = gated().mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const { unmount } = setup()
    await screen.findByText('Danışanlar okunuyor…')
    const signal = request.mock.calls[3]?.[1]?.signal
    unmount(); expect(signal?.aborted).toBe(true)
    await act(async () => finish(list()))
    expect(screen.queryByText('Sentetik Danışan')).not.toBeInTheDocument()
  })
})

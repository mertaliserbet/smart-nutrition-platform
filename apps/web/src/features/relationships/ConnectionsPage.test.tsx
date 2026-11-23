import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { ConnectionsPage } from './ConnectionsPage'

const clientId = '11111111-1111-4111-8111-111111111111'
const dietitianId = '22222222-2222-4222-8222-222222222222'
const code = 'ABCDEFGH234567AB'
function setup(expiresAt = new Date(Date.now() + 60_000).toISOString(), value = code) {
  const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_, options) => options?.method === 'POST'
    ? Response.json({ invitationCode: value, expiresAt })
    : Response.json({ items: [{ id: '33333333-3333-4333-8333-333333333333', clientId, dietitianId, status: 'pending', requestedAt: '2026-11-20T09:00:00Z', respondedAt: null, endedAt: null }], totalCount: 1 }))
  const view = render(<MemoryRouter><WorkspaceContext.Provider value={{ token: 'synthetic', dietitianId, onFailure: () => false }}><ConnectionsPage /></WorkspaceContext.Provider></MemoryRouter>)
  return { ...view, request }
}
describe('connection identity and invitation clipboard', () => {
  it('cancels ending with Escape, traps keyboard focus and sends only the explicitly confirmed relationship', async () => {
    const user = userEvent.setup()
    const relationshipId = '33333333-3333-4333-8333-333333333333'
    const active = { id: relationshipId, clientId, dietitianId, status: 'active', requestedAt: '2026-11-20T09:00:00Z', respondedAt: '2026-11-20T10:00:00Z', endedAt: null }
    let ended = false
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async (path, options) => {
      if (options?.method === 'POST') { return new Promise<Response>(resolve => { finish = resolve }) }
      const empty = ended || String(path).includes('status=pending')
      return Response.json({ items: empty ? [] : [active], totalCount: empty ? 0 : 1 })
    })
    render(<MemoryRouter><WorkspaceContext.Provider value={{ token: 'synthetic', dietitianId, onFailure: () => false }}><ConnectionsPage /></WorkspaceContext.Provider></MemoryRouter>)
    await screen.findByText('Bu durumda bağlantı bulunmuyor.')
    await user.selectOptions(screen.getByRole('combobox', { name: 'Durum' }), 'active')
    const end = await screen.findByRole('button', { name: 'Bağlantıyı sonlandır' })
    await user.click(end)
    expect(screen.getByRole('alertdialog')).toHaveTextContent('aktif atanmış programınız arşivlenecek')
    expect(screen.getByRole('alertdialog')).toHaveTextContent('açık görevleriniz iptal edilecek')
    expect(screen.getByRole('button', { name: 'Vazgeç' })).toHaveFocus()
    await user.tab({ shift: true })
    expect(screen.getByRole('button', { name: 'Onayla ve sonlandır' })).toHaveFocus()
    await user.tab()
    expect(screen.getByRole('button', { name: 'Vazgeç' })).toHaveFocus()
    await user.keyboard('{Escape}')
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    expect(end).toHaveFocus()
    expect(request.mock.calls.some(([, options]) => options?.method === 'POST')).toBe(false)
    await user.click(end)
    await user.click(screen.getByRole('button', { name: 'Onayla ve sonlandır' }))
    fireEvent.click(end)
    const writes = request.mock.calls.filter(([, options]) => options?.method === 'POST')
    expect(writes).toHaveLength(1)
    expect(writes[0]?.[0]).toBe(`/api/v1/dietitian-relationships/${relationshipId}/end`)
    expect(writes[0]?.[1]).toMatchObject({ credentials: 'same-origin', headers: { 'X-CSRF-TOKEN': 'synthetic', 'X-Profile-Context': 'dietitian' } })
    expect(screen.queryByText('Bağlantı sonlandırıldı.')).not.toBeInTheDocument()
    ended = true
    await act(async () => finish(Response.json({ ...active, status: 'ended', endedAt: '2026-11-23T10:00:00Z' })))
    expect(await screen.findByText('Bağlantı sonlandırıldı.')).toBeVisible()
    expect(await screen.findByText('Bu durumda bağlantı bulunmuyor.')).toBeVisible()
  })
  it('shows the honest missing name and request time without UUIDs or active-client lookups', async () => {
    const { request } = setup()
    expect(await screen.findByRole('heading', { name: 'Danışan adı mevcut değil' })).toBeVisible()
    expect(screen.getByText(/Talep:/).querySelector('time')).toHaveAttribute('dateTime', '2026-11-20T09:00:00Z')
    expect(document.body.textContent).not.toContain(clientId)
    expect(request).toHaveBeenCalledTimes(1)
    expect(String(request.mock.calls[0]![0])).toContain('/dietitian-relationships?')
    expect(screen.queryByRole('button', { name: 'Kodu kopyala' })).not.toBeInTheDocument()
  })
  it('announces success only after the clipboard promise completes and ignores double clicks', async () => {
    let finish!: () => void
    const writeText = vi.fn(() => new Promise<void>(resolve => { finish = resolve }))
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    setup(); await waitFor(() => expect(screen.getByRole('button', { name: 'Davet kodu oluştur' })).toBeEnabled()); fireEvent.click(screen.getByRole('button', { name: 'Davet kodu oluştur' }))
    const copy = await screen.findByRole('button', { name: 'Kodu kopyala' })
    await waitFor(() => expect(copy).toBeEnabled())
    fireEvent.click(copy); fireEvent.click(copy)
    expect(writeText).toHaveBeenCalledExactlyOnceWith(code)
    expect(screen.queryByText('Davet kodu kopyalandı.')).not.toBeInTheDocument()
    await act(async () => finish())
    expect(screen.getByText('Davet kodu kopyalandı.')).toHaveAttribute('role', 'status')
  })
  it.each(['denied', 'unavailable'])('provides accessible feedback when clipboard is %s', async state => {
    const writeText = vi.fn().mockRejectedValue(new Error('Synthetic denial'))
    vi.stubGlobal('navigator', state === 'denied' ? { clipboard: { writeText } } : {})
    setup(); await waitFor(() => expect(screen.getByRole('button', { name: 'Davet kodu oluştur' })).toBeEnabled()); fireEvent.click(screen.getByRole('button', { name: 'Davet kodu oluştur' }))
    const copy = await screen.findByRole('button', { name: 'Kodu kopyala' })
    await waitFor(() => expect(copy).toBeEnabled())
    fireEvent.click(copy)
    expect(await screen.findByRole('alert')).toHaveTextContent('Kod kopyalanamadı')
    expect(screen.queryByText('Davet kodu kopyalandı.')).not.toBeInTheDocument()
  })
  it('does not copy expired or malformed codes', async () => {
    const writeText = vi.fn(); vi.stubGlobal('navigator', { clipboard: { writeText } })
    const view = setup(new Date(Date.now() - 1).toISOString())
    await waitFor(() => expect(screen.getByRole('button', { name: 'Davet kodu oluştur' })).toBeEnabled()); fireEvent.click(screen.getByRole('button', { name: 'Davet kodu oluştur' }))
    const copy = await screen.findByRole('button', { name: 'Kodu kopyala' })
    expect(copy).toBeDisabled(); fireEvent.click(copy); expect(writeText).not.toHaveBeenCalled()
    view.unmount(); setup(new Date(Date.now() + 60_000).toISOString(), 'invalid')
    await waitFor(() => expect(screen.getByRole('button', { name: 'Davet kodu oluştur' })).toBeEnabled()); fireEvent.click(screen.getByRole('button', { name: 'Davet kodu oluştur' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Sunucu yanıtı doğrulanamadı')
    expect(screen.queryByRole('button', { name: 'Kodu kopyala' })).not.toBeInTheDocument()
    expect(writeText).not.toHaveBeenCalled()
  })
})

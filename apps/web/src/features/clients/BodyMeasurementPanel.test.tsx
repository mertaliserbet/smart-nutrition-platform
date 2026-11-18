import { act, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { BodyMeasurementPanel } from './BodyMeasurementPanel'
import { getBodyMeasurements } from './bodyMeasurementApi'

const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const otherId = '8a0829e9-fbdd-486a-bc1d-128701513c04'
const expertId = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const record = (client = clientId) => ({ id: 'c428ae15-f14c-4685-a272-69a81225c9df', clientId: client,
  measuredAt: '2026-11-18T09:00:00.123456Z', source: 'manual', weightKg: 73.123456789,
  waistCm: null, hipCm: 98.125, chestCm: 91.25, bodyFatPercent: 0, note: 'Sentetik ölçüm notu' })
const result = (client = clientId, totalCount = 1) => Response.json({ items: [record(client)], totalCount })
const empty = () => Response.json({ items: [], totalCount: 0 })
const session = { token: 'synthetic-csrf', dietitianId: expertId, onFailure: vi.fn(() => false) }
function panel(client = clientId, context = session) {
  return <WorkspaceContext.Provider value={context}><BodyMeasurementPanel clientId={client} /></WorkspaceContext.Provider>
}

describe('dietitian measurement API', () => {
  it('uses the existing GET with explicit paging, offset instants and cookie expert context', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result())
    const signal = new AbortController().signal
    const range = { from: '2026-11-18T00:00:00+03:00', to: '2026-11-19T00:00:00+03:00' }
    const page = await getBodyMeasurements(clientId, 1, range, signal)
    expect(page.items[0]).toEqual(record())
    const url = new URL(String(request.mock.calls[0]?.[0]), 'https://localhost')
    expect(url.pathname).toBe(`/api/v1/dietitian/clients/${clientId}/body-measurements`)
    expect(Object.fromEntries(url.searchParams)).toEqual({ page: '1', pageSize: '10', ...range })
    expect(request.mock.calls[0]?.[1]).toEqual({ method: 'GET', credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal, headers: { 'X-Profile-Context': 'dietitian' } })
  })

  it.each(['foreign', 'missingHip', 'missingNote', 'string', 'negative', 'zeroWeight', 'fatRange', 'allNull', 'duplicate', 'count', 'time', 'json'])('rejects malformed or foreign %s data', async scenario => {
    const row = record()
    if (scenario === 'foreign') row.clientId = otherId
    if (scenario === 'missingHip') Reflect.deleteProperty(row, 'hipCm')
    if (scenario === 'missingNote') Reflect.deleteProperty(row, 'note')
    if (scenario === 'string') Reflect.set(row, 'weightKg', '73')
    if (scenario === 'negative') row.hipCm = -1
    if (scenario === 'zeroWeight') row.weightKg = 0
    if (scenario === 'fatRange') row.bodyFatPercent = 101
    if (scenario === 'allNull') for (const key of ['weightKg', 'waistCm', 'hipCm', 'chestCm', 'bodyFatPercent']) Reflect.set(row, key, null)
    if (scenario === 'time') row.measuredAt = '2026-11-18T09:00:00'
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(scenario === 'json' ? new Response('{')
      : Response.json({ items: scenario === 'duplicate' ? [row, row] : [row], totalCount: scenario === 'count' ? 0 : 2 }))
    await expect(getBodyMeasurements(clientId, 1, {}, new AbortController().signal)).rejects.toMatchObject({ status: 500 })
  })
})

describe('real measurement panel', () => {
  it('displays full decimal values, unknown values and genuine zero with source, time and note', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result())
    render(panel())
    expect(await screen.findByText('73,123456789 kg')).toBeVisible()
    expect(screen.getByText('98,125 cm')).toBeVisible()
    expect(screen.getByText('91,25 cm')).toBeVisible()
    expect(screen.getByText('0 %')).toBeVisible()
    expect(screen.getByText('Bilinmiyor')).toBeVisible()
    expect(screen.getByText('Sentetik ölçüm notu')).toBeVisible()
    expect(screen.getByText('Manuel kayıt')).toBeVisible()
    expect(screen.getByRole('article').querySelector('time')).toHaveAttribute('datetime', record().measuredAt)
    expect(screen.queryByRole('button', { name: /düzenle|sil|kaydet/i })).not.toBeInTheDocument()
  })

  it('pages on the server and hides stale rows/counts while reading', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result(clientId, 11)).mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const user = userEvent.setup(); render(panel()); await screen.findByText('73,123456789 kg')
    await user.click(screen.getByRole('button', { name: 'Sonraki ölçüm sayfası' }))
    expect(screen.queryByText('73,123456789 kg')).not.toBeInTheDocument()
    expect(screen.queryByText('11 ölçüm · Sayfa 1')).not.toBeInTheDocument()
    expect(screen.getByText('Ölçümler okunuyor…')).toBeVisible()
    expect(String(request.mock.calls[1]?.[0])).toContain('page=2&pageSize=10')
    await act(async () => finish(result(clientId, 11)))
    expect(await screen.findByText('11 ölçüm · Sayfa 2')).toBeVisible()
  })

  it('sends UTC filters, rejects invalid intervals, resets paging and clears inputs', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result(clientId, 11)).mockResolvedValueOnce(result(clientId, 11)).mockResolvedValueOnce(empty()).mockResolvedValueOnce(empty())
    const user = userEvent.setup(); render(panel()); await screen.findByText('73,123456789 kg')
    await user.click(screen.getByRole('button', { name: 'Sonraki ölçüm sayfası' })); await screen.findByText('11 ölçüm · Sayfa 2')
    fireEvent.change(screen.getByLabelText('Ölçüm başlangıcı'), { target: { value: '2026-11-18T09:00' } })
    fireEvent.change(screen.getByLabelText('Ölçüm bitişi'), { target: { value: '2026-11-18T08:00' } })
    await user.click(screen.getByRole('button', { name: 'Ölçümleri filtrele' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Ölçüm bitişi başlangıçtan sonra olmalı')
    expect(request).toHaveBeenCalledTimes(2)
    fireEvent.change(screen.getByLabelText('Ölçüm bitişi'), { target: { value: '2026-11-18T10:00' } })
    await user.click(screen.getByRole('button', { name: 'Ölçümleri filtrele' }))
    expect(await screen.findByText('Bu aralıkta ölçüm kaydı yok')).toBeVisible()
    expect(Object.fromEntries(new URL(String(request.mock.calls[2]?.[0]), 'https://localhost').searchParams)).toEqual({ page: '1', pageSize: '10', from: '2026-11-18T09:00:00.000Z', to: '2026-11-18T10:00:00.000Z' })
    await user.click(screen.getByRole('button', { name: 'Ölçüm filtresini temizle' }))
    expect(await screen.findByText('Henüz ölçüm kaydı yok')).toBeVisible()
    expect(screen.getByLabelText('Ölçüm başlangıcı')).toHaveValue('')
    expect(String(request.mock.calls[3]?.[0])).not.toContain('from=')
  })

  it.each([403, 404, 500])('clears health data on status %s without converting denial/failure to an empty diary', async status => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockResolvedValueOnce(new Response(null, { status })).mockResolvedValueOnce(empty())
    const user = userEvent.setup(); render(panel()); await screen.findByText('73,123456789 kg')
    await user.click(screen.getByRole('button', { name: 'Ölçümleri yenile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 403 ? 'Ölçüm paylaşımı kapalı' : status === 404 ? 'aktif bağlantınız sona erdi' : 'Ölçümler okunamadı')
    expect(screen.queryByText('73,123456789 kg')).not.toBeInTheDocument()
    expect(screen.queryByText('1 ölçüm · Sayfa 1')).not.toBeInTheDocument()
    expect(screen.queryByText('Henüz ölçüm kaydı yok')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Ölçümleri yenile' }))
    expect(await screen.findByText('Henüz ölçüm kaydı yok')).toBeVisible()
  })

  it('rechecks on focus and distinguishes network failure from no measurements', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockRejectedValueOnce(new TypeError('Synthetic offline'))
    render(panel()); await screen.findByText('73,123456789 kg')
    act(() => window.dispatchEvent(new Event('focus')))
    expect(screen.queryByText('73,123456789 kg')).not.toBeInTheDocument()
    expect(await screen.findByRole('alert')).toHaveTextContent('sunucuya ulaşılamadı')
    expect(screen.queryByText('0 ölçüm')).not.toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(2)
  })

  it('aborts late reads after client, session and unmount changes', async () => {
    let late!: (response: Response) => void
    let unmounted!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() => new Promise(resolve => { late = resolve })).mockResolvedValueOnce(empty())
      .mockImplementationOnce(() => new Promise(resolve => { unmounted = resolve }))
    const view = render(panel()); view.rerender(panel(otherId)); await screen.findByText('Henüz ölçüm kaydı yok')
    expect(request.mock.calls[0]?.[1]?.signal?.aborted).toBe(true)
    await act(async () => late(result()))
    expect(screen.queryByText('73,123456789 kg')).not.toBeInTheDocument()
    view.rerender(panel(otherId, { ...session, token: 'new-session-csrf' }))
    expect(screen.queryByText('Henüz ölçüm kaydı yok')).not.toBeInTheDocument()
    view.unmount(); expect(request.mock.calls[2]?.[1]?.signal?.aborted).toBe(true)
    await act(async () => unmounted(result(otherId)))
  })

  it.each([true, false])('keeps sharing independent in actual client details (measurements allowed: %s)', async allowed => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
      const path = String(input)
      if (path.endsWith('/csrf')) return Response.json({ requestToken: 'synthetic-csrf' })
      if (path.endsWith('/auth/me')) return Response.json({ id: otherId, displayName: 'Sentetik uzman', email: 'expert@example.test', role: 'client', isEmailVerified: true })
      if (path.endsWith('/dietitians/me')) return Response.json({ id: expertId, displayName: 'Sentetik uzman', isVerified: true })
      if (path.endsWith('/dashboard')) return Response.json({ clientId, displayName: 'Sentetik danışan' })
      if (path.includes('/body-measurements?')) return allowed ? result() : new Response(null, { status: 403 })
      if (path.includes('/nutrition-plans?')) return allowed ? new Response(null, { status: 403 }) : empty()
      if (path.includes('/meal-logs?')) return new Response(null, { status: 403 })
      throw new Error('Unexpected test request')
    })
    render(<MemoryRouter initialEntries={[`/calisma-alani/danisanlar/${clientId}`]}><App /></MemoryRouter>)
    const section = await screen.findByRole('region', { name: 'Vücut ölçümleri' })
    if (allowed) {
      expect(await within(section).findByText('73,123456789 kg')).toBeVisible()
      expect(await screen.findByText('Programlara erişim veya düzenleme izniniz bulunmuyor.')).toBeVisible()
    } else {
      expect(await within(section).findByRole('alert')).toHaveTextContent('Ölçüm paylaşımı kapalı')
      expect(await screen.findByRole('button', { name: 'Yeni program oluştur' })).toBeVisible()
    }
    expect(screen.getByRole('heading', { name: 'Sentetik danışan' })).toBeVisible()
  })
})

import { act, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { BodyMeasurementPanel } from './BodyMeasurementPanel'
import { BodyMeasurementCharts } from './BodyMeasurementCharts'
import { getBodyMeasurementHistory, getBodyMeasurements } from './bodyMeasurementApi'

const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const otherId = '8a0829e9-fbdd-486a-bc1d-128701513c04'
const expertId = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const record = (client = clientId) => ({ id: 'c428ae15-f14c-4685-a272-69a81225c9df', clientId: client,
  measuredAt: '2026-11-18T09:00:00.123456Z', source: 'manual' as const, weightKg: 73.123456789,
  waistCm: null, hipCm: 98.125, chestCm: 91.25, bodyFatPercent: 0, note: 'Sentetik ölçüm notu' })
const result = (client = clientId, totalCount = 1) => Response.json({ items: [record(client)], totalCount })
const empty = () => Response.json({ items: [], totalCount: 0 })
function historyResponse(input: RequestInfo | URL) {
  const url = new URL(String(input), 'https://localhost')
  if (url.searchParams.get('sortOrder') !== 'asc') return undefined
  const page = Number(url.searchParams.get('page'))
  const rows = Array.from({ length: 11 }, (_, index) => ({ ...record(),
    id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
    measuredAt: `2026-11-${String(index + 1).padStart(2, '0')}T09:00:00Z`,
  }))
  return Response.json({ items: rows.slice((page - 1) * 10, page * 10), totalCount: 11 })
}
const session = { token: 'synthetic-csrf', dietitianId: expertId, onFailure: vi.fn(() => false) }
function panel(client = clientId, context = session) {
  return <WorkspaceContext.Provider value={context}><BodyMeasurementPanel clientId={client} /></WorkspaceContext.Provider>
}

describe('dietitian measurement API', () => {
  it('loads every chart page chronologically with the same date filter and expert cookies', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async input => historyResponse(input)!)
    const range = { from: '2026-11-01T00:00:00Z', to: '2026-11-19T00:00:00Z' }
    const rows = await getBodyMeasurementHistory(clientId, range, new AbortController().signal, 11)
    expect(rows).toHaveLength(11)
    expect(new Set(rows.map(row => row.id)).size).toBe(11)
    expect(request.mock.calls.map(([input]) => Object.fromEntries(new URL(String(input), 'https://localhost').searchParams)))
      .toEqual([1, 2].map(page => ({ page: String(page), pageSize: '10', sortOrder: 'asc', ...range })))
    expect(request.mock.calls.every(([, options]) => options?.credentials === 'same-origin' &&
      (options.headers as Record<string, string>)['X-Profile-Context'] === 'dietitian')).toBe(true)
  })

  it.each(['count', 'empty', 'duplicate', 'foreign'])('rejects inconsistent chart history: %s', async scenario => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
      const value = await historyResponse(input)!.json()
      if (String(input).includes('page=2')) {
        if (scenario === 'count') value.totalCount = 10
        if (scenario === 'empty') value.items = []
        if (scenario === 'duplicate') value.items[0].id = '00000000-0000-4000-8000-000000000000'
        if (scenario === 'foreign') value.items[0].clientId = otherId
      }
      return Response.json(value)
    })
    await expect(getBodyMeasurementHistory(clientId, {}, new AbortController().signal, 11)).rejects.toMatchObject({ status: 500 })
  })

  it('cancels chart pagination before sending the next request', async () => {
    const controller = new AbortController()
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
      const response = historyResponse(input)!
      controller.abort()
      return response
    })
    await expect(getBodyMeasurementHistory(clientId, {}, controller.signal, 11)).rejects.toMatchObject({ name: 'AbortError' })
    expect(request).toHaveBeenCalledTimes(1)
  })

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
  it('removes the entire diary when a chart page loses permission', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
      const url = new URL(String(input), 'https://localhost')
      if (!url.searchParams.has('sortOrder')) return result(clientId, 11)
      if (url.searchParams.get('page') === '2') return new Response(null, { status: 403 })
      return historyResponse(input)!
    })
    render(panel())
    expect(await screen.findByRole('alert')).toHaveTextContent('Ölçüm paylaşımı kapalı')
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    expect(screen.queryByText('Henüz ölçüm kaydı yok')).not.toBeInTheDocument()
  })

  it('clears charts while hidden and rechecks permission on return', async () => {
    const visible = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockResolvedValueOnce(new Response(null, { status: 403 }))
    render(panel()); await screen.findByText('73,123456789 kg')
    expect(screen.getByRole('img', { name: 'Kilo gelişimi (kg): 1 kayıt' })).toBeVisible()
    visible.mockReturnValue('hidden')
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(1)
    visible.mockReturnValue('visible')
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    expect(await screen.findByRole('alert')).toHaveTextContent('Ölçüm paylaşımı kapalı')
    expect(request).toHaveBeenCalledTimes(2)
  })

  it('rechecks an open panel periodically and removes revoked data', async () => {
    vi.useFakeTimers()
    try {
      const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockResolvedValueOnce(new Response(null, { status: 403 }))
      await act(async () => { render(panel()) })
      expect(screen.getByRole('img', { name: 'Kilo gelişimi (kg): 1 kayıt' })).toBeVisible()
      await act(async () => { await vi.advanceTimersByTimeAsync(30_000) })
      expect(screen.getByRole('alert')).toHaveTextContent('Ölçüm paylaşımı kapalı')
      expect(screen.queryByRole('img')).not.toBeInTheDocument()
      expect(screen.queryByRole('article')).not.toBeInTheDocument()
      expect(request).toHaveBeenCalledTimes(2)
    } finally { vi.useRealTimers() }
  })

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
    let listReads = 0
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(input => {
      const history = historyResponse(input)
      if (history) return Promise.resolve(history)
      return ++listReads === 1 ? Promise.resolve(result(clientId, 11)) : new Promise(resolve => { finish = resolve })
    })
    const user = userEvent.setup(); render(panel()); await screen.findByText('73,123456789 kg')
    expect(screen.getByRole('img', { name: 'Kilo gelişimi (kg): 11 kayıt' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Sonraki ölçüm sayfası' }))
    expect(screen.queryByText('73,123456789 kg')).not.toBeInTheDocument()
    expect(screen.queryByText('11 ölçüm · Sayfa 1')).not.toBeInTheDocument()
    expect(screen.getByText('Ölçümler okunuyor…')).toBeVisible()
    expect(request.mock.calls.some(([url]) => String(url).includes('page=2&pageSize=10') && !String(url).includes('sortOrder'))).toBe(true)
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    await act(async () => finish(result(clientId, 11)))
    expect(await screen.findByText('11 ölçüm · Sayfa 2')).toBeVisible()
  })

  it('sends UTC filters, rejects invalid intervals, resets paging and clears inputs', async () => {
    let listReads = 0
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async input => historyResponse(input) ?? (++listReads <= 2 ? result(clientId, 11) : empty()))
    const user = userEvent.setup(); render(panel()); await screen.findByText('73,123456789 kg')
    await user.click(screen.getByRole('button', { name: 'Sonraki ölçüm sayfası' })); await screen.findByText('11 ölçüm · Sayfa 2')
    fireEvent.change(screen.getByLabelText('Ölçüm başlangıcı'), { target: { value: '2026-11-18T09:00' } })
    fireEvent.change(screen.getByLabelText('Ölçüm bitişi'), { target: { value: '2026-11-18T08:00' } })
    await user.click(screen.getByRole('button', { name: 'Ölçümleri filtrele' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Ölçüm bitişi başlangıçtan sonra olmalı')
    expect(listReads).toBe(2)
    fireEvent.change(screen.getByLabelText('Ölçüm bitişi'), { target: { value: '2026-11-18T10:00' } })
    await user.click(screen.getByRole('button', { name: 'Ölçümleri filtrele' }))
    expect(await screen.findByText('Bu aralıkta ölçüm kaydı yok')).toBeVisible()
    const listCalls = () => request.mock.calls.filter(([url]) => !String(url).includes('sortOrder'))
    expect(Object.fromEntries(new URL(String(listCalls()[2]?.[0]), 'https://localhost').searchParams)).toEqual({ page: '1', pageSize: '10', from: '2026-11-18T09:00:00.000Z', to: '2026-11-18T10:00:00.000Z' })
    await user.click(screen.getByRole('button', { name: 'Ölçüm filtresini temizle' }))
    expect(await screen.findByText('Henüz ölçüm kaydı yok')).toBeVisible()
    expect(screen.getByLabelText('Ölçüm başlangıcı')).toHaveValue('')
    expect(String(listCalls()[3]?.[0])).not.toContain('from=')
  })

  it.each([403, 404, 500])('clears health data on status %s without converting denial/failure to an empty diary', async status => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockResolvedValueOnce(new Response(null, { status })).mockResolvedValueOnce(empty())
    const user = userEvent.setup(); render(panel()); await screen.findByText('73,123456789 kg')
    await user.click(screen.getByRole('button', { name: 'Ölçümleri yenile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 403 ? 'Ölçüm paylaşımı kapalı' : status === 404 ? 'aktif bağlantınız sona erdi' : 'Ölçümler okunamadı')
    expect(screen.queryByText('73,123456789 kg')).not.toBeInTheDocument()
    expect(screen.queryByText('1 ölçüm · Sayfa 1')).not.toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
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

describe('measurement trend plots', () => {
  it('uses chronological date spacing and never invents null points', () => {
    render(<BodyMeasurementCharts records={[
      { ...record(), id: 'last', measuredAt: '2026-11-11T09:00:00Z', weightKg: 70 },
      { ...record(), id: 'missing', measuredAt: '2026-11-02T09:00:00Z', weightKg: null },
      { ...record(), id: 'middle', measuredAt: '2026-11-03T09:00:00Z', weightKg: 75 },
      { ...record(), id: 'first', measuredAt: '2026-11-01T09:00:00Z', weightKg: 80 },
    ]} />)
    const chart = screen.getByRole('img', { name: 'Kilo gelişimi (kg): 3 kayıt' })
    expect([...chart.querySelectorAll('circle')].map(point => point.getAttribute('cx'))).toEqual(['72', '151.2', '468'])
    expect(chart.querySelector('polyline')).toHaveAttribute('points', '72,44 151.2,116 468,188')
    expect(within(chart).getByText('01.11.2026')).toBeVisible()
    expect(within(chart).getByText('11.11.2026')).toBeVisible()
  })

  it('shows a genuine zero fat point and explicit empty fields without fake lines', () => {
    render(<BodyMeasurementCharts records={[{ ...record(), weightKg: null, waistCm: null, hipCm: null, chestCm: null, bodyFatPercent: 0 }]} />)
    expect(screen.getAllByText('Bu alan için ölçüm kaydı yok.')).toHaveLength(4)
    expect(screen.getAllByRole('img')).toHaveLength(1)
    const chart = screen.getByRole('img', { name: 'Vücut yağ oranı gelişimi (%): 1 kayıt' })
    expect(chart.querySelectorAll('circle')).toHaveLength(1)
    expect(chart.querySelector('polyline')).not.toBeInTheDocument()
    expect(screen.getByText('Tek ölçüm kaydı; henüz değişim çizgisi yok.')).toBeVisible()
  })
})

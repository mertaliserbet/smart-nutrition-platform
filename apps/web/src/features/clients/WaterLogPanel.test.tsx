import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { WaterLogPanel } from './WaterLogPanel'
import { WaterLogList } from './ClientRecordViews'
import { getWaterDailyTotal, getWaterHistory, getWaterLogs, localDateInput, localDayRange, waterHistoryRange } from './waterLogApi'

const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const otherId = '8a0829e9-fbdd-486a-bc1d-128701513c04'
const recordId = 'c428ae15-f14c-4685-a272-69a81225c9df'
const session = { token: 'synthetic-csrf', dietitianId: '5b74318b-678d-4bf2-9b82-6a0b3d381376', onFailure: vi.fn(() => false) }
const row = (client = clientId, day = '2026-11-10') => ({ id: recordId, clientId: client, amountMl: 375.125,
  consumedAt: new Date(Date.parse(localDayRange(day).from) + 3600000).toISOString(), source: 'manual' })
function responseFor(input: RequestInfo | URL, empty = false, amount = 375.125) {
  const url = new URL(String(input), 'https://localhost'), from = url.searchParams.get('from')!, to = url.searchParams.get('to')!
  const total = { from: new Date(from).toISOString(), to: new Date(to).toISOString(), totalAmountMl: empty ? 0 : amount }
  if (url.pathname.endsWith('/daily-total')) return Response.json(total)
  if (url.pathname.endsWith('/daily-history')) {
    const days = (Date.parse(to.slice(0, 10)) - Date.parse(from.slice(0, 10))) / 86400000
    const items = Array.from({ length: days }, (_, index) => {
      const date = new Date(`${from.slice(0, 10)}T12:00:00`); date.setDate(date.getDate() + index)
      const range = localDayRange(localDateInput(date))
      return { from: new Date(range.from).toISOString(), to: new Date(range.to).toISOString(), totalAmountMl: empty ? 0 : index === 0 ? amount : 0 }
    })
    return Response.json({ items, totalCount: days })
  }
  return Response.json({ items: empty ? [] : [row(url.pathname.includes(otherId) ? otherId : clientId, from.slice(0, 10))], totalCount: empty ? 0 : 1 })
}
function panel(client = clientId, context = session) {
  return <WorkspaceContext.Provider value={context}><WaterLogPanel clientId={client} /></WorkspaceContext.Provider>
}
function requestMock(empty = false) { return vi.spyOn(globalThis, 'fetch').mockImplementation(async input => responseFor(input, empty)) }

describe('water API DTOs', () => {
  it('uses canonical cookie GET paths and explicit-offset day bounds without requesting goals or permissions', async () => {
    const request = requestMock(), signal = new AbortController().signal, range = localDayRange('2026-11-10')
    expect((await getWaterLogs(clientId, 1, range, signal)).items).toEqual([row()])
    expect((await getWaterDailyTotal(clientId, range, signal)).totalAmountMl).toBe(375.125)
    const history = await getWaterHistory(clientId, waterHistoryRange('2026-11-08', '2026-11-10'), signal)
    expect(history).toHaveLength(3)
    expect(request.mock.calls.every(([url, options]) => String(url).includes(`/dietitian/clients/${clientId}/water-logs`) &&
      options?.method === 'GET' && options.credentials === 'same-origin' && options.cache === 'no-store' &&
      (options.headers as Record<string, string>)['X-Profile-Context'] === 'dietitian' && options.signal === signal)).toBe(true)
    const historyQuery = new URL(String(request.mock.calls[2]![0]), 'https://localhost').searchParams
    expect(historyQuery.get('timeZone')).toBe(Intl.DateTimeFormat().resolvedOptions().timeZone)
    expect(historyQuery.get('pageSize')).toBe('31')
    expect(new URL(String(request.mock.calls[0]![0]), 'https://localhost').searchParams.get('from')).toBe(range.from)
  })

  it.each(['foreign', 'zero', 'negative', 'string', 'time', 'outside', 'source', 'duplicate', 'count', 'extra', 'json'])('rejects invalid %s list data', async scenario => {
    const record = row()
    if (scenario === 'foreign') record.clientId = otherId
    if (scenario === 'zero') record.amountMl = 0
    if (scenario === 'negative') record.amountMl = -5
    if (scenario === 'string') Reflect.set(record, 'amountMl', '375')
    if (scenario === 'time') record.consumedAt = '2026-11-10T01:00:00'
    if (scenario === 'outside') record.consumedAt = '2025-11-10T01:00:00Z'
    if (scenario === 'source') record.source = 'unknown'
    if (scenario === 'extra') Reflect.set(record, 'dailyWaterTargetMl', 2000)
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(scenario === 'json' ? new Response('{') :
      Response.json({ items: scenario === 'duplicate' ? [record, record] : [record], totalCount: scenario === 'count' ? 0 : 2 }))
    await expect(getWaterLogs(clientId, 1, localDayRange('2026-11-10'), new AbortController().signal)).rejects.toMatchObject({ status: 500 })
  })

  it.each(['negative', 'wrongDay', 'string', 'extra', 'missing'])('rejects invalid %s daily totals', async scenario => {
    const range = localDayRange('2026-11-10'), value = { ...range, totalAmountMl: 375 }
    if (scenario === 'negative') value.totalAmountMl = -1
    if (scenario === 'wrongDay') value.from = '2026-11-09T00:00:00Z'
    if (scenario === 'string') Reflect.set(value, 'totalAmountMl', '375')
    if (scenario === 'extra') Reflect.set(value, 'dailyWaterTargetMl', 2000)
    if (scenario === 'missing') Reflect.deleteProperty(value, 'totalAmountMl')
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json(value))
    await expect(getWaterDailyTotal(clientId, range, new AbortController().signal)).rejects.toMatchObject({ status: 500 })
  })

  it.each(['missingDay', 'count', 'duplicate', 'wrongEnd'])('rejects %s history instead of showing an incomplete graph', async scenario => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
      const value = await responseFor(input).json()
      if (scenario === 'missingDay') value.items.pop()
      if (scenario === 'count') value.totalCount = 4
      if (scenario === 'duplicate') value.items[1] = value.items[0]
      if (scenario === 'wrongEnd') value.items[2].to = '2026-11-20T00:00:00Z'
      return Response.json(value)
    })
    await expect(getWaterHistory(clientId, waterHistoryRange('2026-11-08', '2026-11-10'), new AbortController().signal)).rejects.toMatchObject({ status: 500 })
  })

  it('validates a bounded inclusive calendar range and rejects aborted reads without sending HTTP', async () => {
    expect(waterHistoryRange('2026-11-10', '2026-11-10').days).toBe(1)
    expect(() => waterHistoryRange('2026-11-10', '2026-12-11')).toThrow('31 gün')
    expect(() => waterHistoryRange('2026-11-11', '2026-11-10')).toThrow('31 gün')
    const request = requestMock(), controller = new AbortController(); controller.abort()
    await expect(getWaterLogs(clientId, 1, localDayRange('2026-11-10'), controller.signal)).rejects.toMatchObject({ name: 'AbortError' })
    expect(request).not.toHaveBeenCalled()
  })
})

describe('water tracking in the real workspace', () => {
  it('orders the existing water list by actual microsecond instants rather than timestamp text', () => {
    const base = row(), newer = { ...row(), source: 'manual' as const, id: otherId, consumedAt: '2026-11-10T10:00:00.000001Z', amountMl: 500 }
    render(<WaterLogList clientId={clientId} records={[{ ...base, source: 'manual', consumedAt: '2026-11-10T13:00:00+03:00' }, newer]} />)
    const records = screen.getAllByRole('listitem')
    expect(records[0]).toHaveTextContent('500 mL'); expect(records[1]).toHaveTextContent('375,125 mL')
  })

  it('renders the exact amount, timestamp/source, daily total and accessible complete history', async () => {
    requestMock(); render(panel())
    const total = await screen.findByRole('status', { name: 'Seçilen günün su toplamı' })
    expect(total).toHaveTextContent('375,125 mL')
    expect(screen.getByRole('list', { name: 'Su kayıtları' })).toHaveTextContent('Manuel kayıt')
    expect(screen.getByRole('list', { name: 'Su kayıtları' }).querySelector('time')?.dateTime).toBeTruthy()
    expect(within(screen.getByRole('table', { name: 'Su tüketiminin günlük geçmişi' })).getAllByRole('row')).toHaveLength(8)
    expect(screen.getByRole('img', { name: 'Günlük su toplamı grafiği: 7 gün' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /izin|kaydet|sil/i })).not.toBeInTheDocument()
  })

  it('distinguishes an authorized empty day from a connection or permission error', async () => {
    requestMock(true); render(panel())
    expect(await screen.findByRole('status', { name: 'Seçilen günün su toplamı' })).toHaveTextContent('0 mL')
    expect(screen.getByText('Seçilen günde su kaydı yok')).toBeInTheDocument()
  })

  it.each([403, 404, 500, 422, 0])('shows %s errors without displaying a zero total or cached history', async status => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => { if (status === 0) throw new TypeError('synthetic offline'); return new Response(null, { status }) })
    render(panel()); const error = await screen.findByRole('alert')
    expect(error).toHaveTextContent(status === 403 ? 'mobil uygulamadaki' : status === 404 ? 'bağlantınız sona erdi' : status === 0 ? 'sunucuya ulaşılamadı' : status === 422 ? 'hesaplanamadı' : 'okunamadı')
    expect(screen.queryByRole('status', { name: 'Seçilen günün su toplamı' })).not.toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('removes all data when any component request reports permission withdrawal', async () => {
    const request = requestMock(); render(panel()); await screen.findByRole('table')
    request.mockImplementation(async input => String(input).includes('daily-history') ? new Response(null, { status: 403 }) : responseFor(input))
    fireEvent.click(screen.getByRole('button', { name: 'Su takibini yenile' }))
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(await screen.findByRole('alert')).toHaveTextContent('Su paylaşımı kapalı')
    expect(screen.queryByRole('list', { name: 'Su kayıtları' })).not.toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
  })

  it('hides old day results immediately and ignores a late response from the previous date', async () => {
    const requests: { input: RequestInfo | URL; resolve: (response: Response) => void; signal?: AbortSignal | null }[] = []
    vi.spyOn(globalThis, 'fetch').mockImplementation((input, options) => new Promise(resolve => requests.push({ input, resolve, signal: options?.signal })))
    render(panel()); expect(requests).toHaveLength(3)
    fireEvent.change(screen.getByLabelText('Su günü'), { target: { value: '2026-11-10' } })
    expect(requests).toHaveLength(6); expect(requests[0]!.signal?.aborted).toBe(true)
    await act(async () => { requests.slice(3).forEach(r => r.resolve(responseFor(r.input, false, 500))) })
    expect(await screen.findByRole('status', { name: 'Seçilen günün su toplamı' })).toHaveTextContent('500 mL')
    await act(async () => { requests.slice(0, 3).forEach(r => r.resolve(responseFor(r.input, false, 999))) })
    expect(screen.getByRole('status', { name: 'Seçilen günün su toplamı' })).not.toHaveTextContent('999')
  })

  it('switches client and session without retaining old private results', async () => {
    const request = requestMock(); const view = render(panel()); await screen.findByRole('table')
    request.mockImplementation(async () => new Response(null, { status: 404 }))
    view.rerender(panel(otherId)); expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(await screen.findByRole('alert')).toHaveTextContent('bağlantınız sona erdi')
    request.mockImplementation(async input => responseFor(input))
    view.rerender(panel(clientId, { ...session, token: 'synthetic-new-session' })); expect(screen.queryByRole('table')).not.toBeInTheDocument()
    await screen.findByRole('table')
  })

  it('ignores a late response belonging to the previous client', async () => {
    const old: { input: RequestInfo | URL; resolve: (response: Response) => void }[] = []
    vi.spyOn(globalThis, 'fetch').mockImplementation((input) => String(input).includes(clientId)
      ? new Promise(resolve => old.push({ input, resolve })) : Promise.resolve(responseFor(input, false, 500)))
    const view = render(panel()); expect(old).toHaveLength(3)
    view.rerender(panel(otherId))
    expect(await screen.findByRole('status', { name: 'Seçilen günün su toplamı' })).toHaveTextContent('500 mL')
    await act(async () => { old.forEach(r => r.resolve(responseFor(r.input, false, 999))) })
    expect(screen.getByRole('status', { name: 'Seçilen günün su toplamı' })).not.toHaveTextContent('999')
  })

  it('clears data on range edits, validates inputs and changes the server history window', async () => {
    const request = requestMock(); render(panel()); await screen.findByRole('table')
    fireEvent.change(screen.getByLabelText('Su geçmişi başlangıcı'), { target: { value: '' } })
    expect(screen.queryByRole('table')).not.toBeInTheDocument(); await screen.findByRole('alert')
    fireEvent.change(screen.getByLabelText('Su geçmişi bitişi'), { target: { value: '2026-11-10' } })
    fireEvent.change(screen.getByLabelText('Su geçmişi başlangıcı'), { target: { value: '2026-11-08' } })
    expect(await screen.findByRole('img', { name: 'Günlük su toplamı grafiği: 3 gün' })).toBeInTheDocument()
    expect(String(request.mock.calls.at(-1)![0])).toContain('daily-history')
  })

  it('does not retain rows while hidden and checks access on return', async () => {
    const visible = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
    const request = requestMock(); render(panel()); await screen.findByRole('table'); const count = request.mock.calls.length
    visible.mockReturnValue('hidden'); act(() => document.dispatchEvent(new Event('visibilitychange')))
    expect(screen.queryByRole('table')).not.toBeInTheDocument(); expect(request).toHaveBeenCalledTimes(count)
    request.mockImplementation(async () => new Response(null, { status: 403 })); visible.mockReturnValue('visible')
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    expect(await screen.findByRole('alert')).toHaveTextContent('Su paylaşımı kapalı')
  })

  it('periodically revalidates visible water access', async () => {
    vi.useFakeTimers()
    try {
      const request = requestMock(); render(panel()); await act(async () => {})
      expect(screen.getByRole('table')).toBeInTheDocument()
      request.mockImplementation(async () => new Response(null, { status: 403 }))
      await act(async () => { await vi.advanceTimersByTimeAsync(30_000) })
      expect(screen.getByRole('alert')).toHaveTextContent('Su paylaşımı kapalı')
      expect(screen.queryByRole('table')).not.toBeInTheDocument()
    } finally { vi.useRealTimers() }
  })
})

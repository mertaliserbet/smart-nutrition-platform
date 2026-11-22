import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'
import { WebSessionError } from '../auth/webSessionApi'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { MealLogPanel } from './MealLogPanel'
import { getMealLogs } from './mealLogApi'

const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const otherId = '8a0829e9-fbdd-486a-bc1d-128701513c04'
const expertId = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const mealId = 'c428ae15-f14c-4685-a272-69a81225c9df'
const itemId = 'ab43db0b-8cb1-47aa-93d0-583c9cb956aa'
const record = (owner = clientId, name = 'Sentetik gerçek API öğünü') => ({
  id: mealId, clientId: owner, consumedAt: '2026-11-18T09:00:00.123456Z', createdAt: '2026-11-18T10:00:00Z',
  mealType: 'breakfast', source: 'manual', note: 'Sentetik öğün notu', foodAnalysisId: null,
  items: [{ id: itemId, mealLogId: mealId, foodItemId: null, recipeId: null, displayName: name, quantityGrams: 123.125,
    caloriesKcal: null, proteinGrams: 12.345, carbsGrams: 0, fatGrams: 2, isEstimated: true }],
})
const result = (owner = clientId, name?: string, totalCount = 1) => Response.json({ items: [record(owner, name)], totalCount })
const session = { token: 'synthetic-csrf', dietitianId: expertId, onFailure: vi.fn(() => false) }
function panel(id = clientId, context = session) {
  return <WorkspaceContext.Provider value={context}><MealLogPanel clientId={id} /></WorkspaceContext.Provider>
}

describe('real dietitian meal API', () => {
  it('uses the canonical paged GET with the HTTPS cookie context and offset instants', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result())
    const signal = new AbortController().signal
    const data = await getMealLogs(clientId, 1, { from: '2026-11-18T00:00:00Z', to: '2026-11-19T00:00:00Z' }, signal)
    expect(data.items[0]?.items[0]?.caloriesKcal).toBeNull()
    expect(data.items[0]?.items[0]?.carbsGrams).toBe(0)
    const [path, options] = request.mock.calls[0]!
    const url = new URL(String(path), 'https://localhost')
    expect(url.pathname).toBe(`/api/v1/dietitian/clients/${clientId}/meal-logs`)
    expect(Object.fromEntries(url.searchParams)).toEqual({ page: '1', pageSize: '10', from: '2026-11-18T00:00:00Z', to: '2026-11-19T00:00:00Z' })
    expect(options).toEqual({ method: 'GET', credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal, headers: { 'X-Profile-Context': 'dietitian' } })
  })

  it.each([401, 403, 404, 500])('preserves status %s without retrying or returning fake records', async status => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status }))
    await expect(getMealLogs(clientId, 1, {}, new AbortController().signal)).rejects.toMatchObject({ status })
    expect(request).toHaveBeenCalledTimes(1)
  })

  it.each(['client', 'itemOwner', 'duplicate', 'missingNutrient', 'negative', 'count', 'invalidJson'])('rejects invalid or foreign %s responses', async scenario => {
    const row = record()
    if (scenario === 'client') row.clientId = otherId
    if (scenario === 'itemOwner') row.items[0]!.mealLogId = otherId
    if (scenario === 'duplicate') row.items.push(row.items[0]!)
    if (scenario === 'missingNutrient') Reflect.deleteProperty(row.items[0]!, 'caloriesKcal')
    if (scenario === 'negative') row.items[0]!.proteinGrams = -1
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(scenario === 'invalidJson' ? new Response('{')
      : Response.json({ items: [row], totalCount: scenario === 'count' ? 0 : 1 }))
    await expect(getMealLogs(clientId, 1, {}, new AbortController().signal)).rejects.toBeInstanceOf(WebSessionError)
  })
})

describe('real meal panel', () => {
  it('shows full detail, unknown nutrients, real zero and estimates without edit controls', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result())
    render(panel())
    expect(await screen.findByText('Sentetik gerçek API öğünü')).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Kahvaltı' })).toBeVisible()
    expect(screen.getByText('123,125 g')).toBeVisible()
    expect(screen.getByText('12,345 g')).toBeVisible()
    expect(screen.getByText('0 g')).toBeVisible()
    expect(screen.getByText('Bilinmiyor')).toBeVisible()
    expect(screen.getByText('Tahmini')).toBeVisible()
    expect(screen.getByText('Sentetik öğün notu')).toBeVisible()
    expect(screen.queryByRole('button', { name: /düzenle|sil/i })).not.toBeInTheDocument()
  })

  it('hides previous rows and counts while paging and uses server pagination exactly once', async () => {
    let finish!: (value: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result(clientId, 'Birinci sayfa öğünü', 11))
      .mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const user = userEvent.setup(); render(panel())
    await screen.findByText('Birinci sayfa öğünü')
    await user.click(screen.getByRole('button', { name: 'Sonraki öğün sayfası' }))
    expect(screen.queryByText('Birinci sayfa öğünü')).not.toBeInTheDocument()
    expect(screen.queryByText('11 öğün · Sayfa 1')).not.toBeInTheDocument()
    expect(screen.getByText('Öğünler okunuyor…')).toBeVisible()
    await act(async () => { finish(result(clientId, 'İkinci sayfa öğünü', 11)) })
    expect(await screen.findByText('İkinci sayfa öğünü')).toBeVisible()
    expect(screen.getByText('11 öğün · Sayfa 2')).toBeVisible()
    expect(String(request.mock.calls[1]?.[0])).toContain('page=2&pageSize=10')
  })

  it('submits local calendar [from,to) filters, validates ranges and clears filters', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => Promise.resolve(result()))
    const user = userEvent.setup(); render(panel()); await screen.findByText('Sentetik gerçek API öğünü')
    await user.click(screen.getByRole('button', { name: 'Özel aralık' }))
    fireEvent.change(screen.getByLabelText('Başlangıç'), { target: { value: '2026-11-18' } })
    fireEvent.change(screen.getByLabelText('Bitiş'), { target: { value: '2026-11-18' } })
    await user.click(screen.getByRole('button', { name: 'Filtrele' }))
    await waitFor(() => expect(request).toHaveBeenCalledTimes(2))
    const url = new URL(String(request.mock.calls[1]?.[0]), 'https://localhost')
    expect(url.searchParams.get('from')).toBe(new Date('2026-11-18T00:00:00').toISOString())
    expect(url.searchParams.get('to')).toBe(new Date('2026-11-19T00:00:00').toISOString())
    expect(screen.getByText(/Tarihler ve kayıt saatleri cihazınızın/)).toBeVisible()
    fireEvent.change(screen.getByLabelText('Bitiş'), { target: { value: '2026-11-17' } })
    await user.click(screen.getByRole('button', { name: 'Filtrele' }))
    expect(await screen.findByText('Geçerli bir başlangıç ve bitiş günü seçin; bitiş başlangıçtan önce olamaz.')).toBeVisible()
    expect(request).toHaveBeenCalledTimes(2)
    await user.click(screen.getByRole('button', { name: 'Filtreyi temizle' }))
    await waitFor(() => expect(request).toHaveBeenCalledTimes(3))
    expect(String(request.mock.calls[2]?.[0])).not.toContain('from=')
    await user.click(screen.getByRole('button', { name: 'Özel aralık' }))
    expect(screen.getByLabelText('Başlangıç')).toHaveValue('')
  })

  it('rejects an empty custom calendar range without sending a request', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(result())
    render(panel()); await screen.findByText('Sentetik gerçek API öğünü')
    const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Özel aralık' })); await user.click(screen.getByRole('button', { name: 'Filtrele' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Geçerli bir başlangıç ve bitiş günü seçin')
    expect(request).toHaveBeenCalledTimes(1)
  })
  it('aborts a superseded preset, retries the selected range and permits clicking the same preset again', async () => {
    let finish!: (response: Response) => void
    const empty = () => Response.json({ items: [], totalCount: 0 })
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result())
      .mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
      .mockResolvedValueOnce(new Response(null, { status: 500 })).mockResolvedValueOnce(empty()).mockResolvedValueOnce(empty())
    render(panel()); await screen.findByText('Sentetik gerçek API öğünü'); const user = userEvent.setup()
    await user.click(screen.getByRole('button', { name: 'Bugün' })); await user.click(screen.getByRole('button', { name: 'Dün' }))
    expect(request.mock.calls[1]![1]!.signal!.aborted).toBe(true)
    expect(await screen.findByRole('alert')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Öğünleri yenile' })); await screen.findByText('Bu aralıkta öğün kaydı yok')
    expect(request.mock.calls[3]![0]).toBe(request.mock.calls[2]![0])
    await act(async () => finish(result()))
    expect(screen.queryByText('Sentetik gerçek API öğünü')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Dün' })); await waitFor(() => expect(request).toHaveBeenCalledTimes(5))
    expect(request.mock.calls[4]![0]).toBe(request.mock.calls[3]![0])
  })

  it.each([403, 404])('removes cached meals and counts on access loss (%s) and permits explicit retry', async status => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockResolvedValueOnce(new Response(null, { status }))
      .mockResolvedValueOnce(Response.json({ items: [], totalCount: 0 }))
    const user = userEvent.setup(); render(panel()); await screen.findByText('Sentetik gerçek API öğünü')
    await user.click(screen.getByRole('button', { name: 'Öğünleri yenile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 403 ? 'Öğün paylaşımı kapalı' : 'aktif bağlantınız sona erdi')
    expect(screen.queryByText('Sentetik gerçek API öğünü')).not.toBeInTheDocument()
    expect(screen.queryByText('1 öğün · Sayfa 1')).not.toBeInTheDocument()
    expect(screen.queryByText('Henüz öğün kaydı yok')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Öğünleri yenile' }))
    expect(await screen.findByText('Henüz öğün kaydı yok')).toBeVisible()
    expect(request).toHaveBeenCalledTimes(3)
  })

  it('separates loading, empty and network failure and clears stale data on focus', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result()).mockRejectedValueOnce(new TypeError('Synthetic offline'))
      .mockResolvedValueOnce(Response.json({ items: [], totalCount: 0 }))
    const user = userEvent.setup(); render(panel()); await screen.findByText('Sentetik gerçek API öğünü')
    act(() => window.dispatchEvent(new Event('focus')))
    expect(screen.queryByText('Sentetik gerçek API öğünü')).not.toBeInTheDocument()
    expect(await screen.findByRole('alert')).toHaveTextContent('sunucuya ulaşılamadı')
    expect(screen.queryByText('0 öğün')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Öğünleri yenile' }))
    expect(await screen.findByText('Henüz öğün kaydı yok')).toBeVisible()
  })

  it('aborts old client requests and ignores late results after client or account changes', async () => {
    let late!: (value: Response) => void
    let switched!: (value: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(result())
      .mockImplementationOnce(() => new Promise(resolve => { late = resolve }))
      .mockResolvedValueOnce(result(otherId, 'İkinci danışanın öğünü'))
      .mockImplementationOnce(() => new Promise(resolve => { switched = resolve }))
    const user = userEvent.setup(); const view = render(panel()); await screen.findByText('Sentetik gerçek API öğünü')
    await user.click(screen.getByRole('button', { name: 'Öğünleri yenile' }))
    view.rerender(panel(otherId))
    expect(screen.queryByText('Sentetik gerçek API öğünü')).not.toBeInTheDocument()
    expect(await screen.findByText('İkinci danışanın öğünü')).toBeVisible()
    expect(request.mock.calls[1]?.[1]?.signal?.aborted).toBe(true)
    await act(async () => { late(result()) })
    expect(screen.queryByText('Sentetik gerçek API öğünü')).not.toBeInTheDocument()
    view.rerender(panel(otherId, { ...session, dietitianId: otherId }))
    expect(screen.queryByText('İkinci danışanın öğünü')).not.toBeInTheDocument()
    await act(async () => { switched(Response.json({ items: [], totalCount: 0 })) })
    expect(await screen.findByText('Henüz öğün kaydı yok')).toBeVisible()
    view.unmount()
  })

  it('is integrated into actual client details and does not block separately permitted programs', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => {
      const url = String(path)
      if (url.endsWith('/csrf')) return Response.json({ requestToken: 'synthetic-csrf' })
      if (url.endsWith('/auth/me')) return Response.json({ id: otherId, displayName: 'Sentetik Uzman', email: 'expert@example.test', role: 'dietitian', isEmailVerified: true })
      if (url.endsWith('/dietitians/me')) return Response.json({ id: expertId, displayName: 'Sentetik Uzman', isVerified: true })
      if (url.endsWith('/dashboard')) return Response.json({ clientId, displayName: 'Sentetik Danışan' })
      if (url.includes('/meal-logs?')) return new Response(null, { status: 403 })
      if (url.includes('/body-measurements?')) return new Response(null, { status: 403 })
      if (url.includes('/nutrition-plans?')) return Response.json({ items: [], totalCount: 0 })
      throw new Error('Unexpected request')
    })
    render(<MemoryRouter initialEntries={[`/calisma-alani/danisanlar/${clientId}?bolum=ogunler`]}><App /></MemoryRouter>)
    expect(await screen.findByRole('heading', { name: 'Öğün günlüğü' })).toBeVisible()
    expect(await screen.findByText(/Öğün paylaşımı kapalı/)).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Sentetik Danışan' })).toBeVisible()
    await userEvent.setup().click(screen.getByRole('link', { name: 'Program' }))
    expect(await screen.findByRole('button', { name: 'Yeni program oluştur' })).toBeVisible()
  })
})

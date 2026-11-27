import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { ReportsOverview } from '../workspace/ReportsOverview'
import { NutritionPlanPrint } from './NutritionPlanPrint'
import { NutritionPlanPanel } from './NutritionPlanPanel'
import type { NutritionPlanResponse } from './nutritionPlanApi'

const clientId = '10000000-0000-4000-8000-000000000001'
const dietitianId = '20000000-0000-4000-8000-000000000001'
const id = (index: number) => '30000000-0000-4000-8000-' + String(index).padStart(12, '0')
const versionId = (index: number) => '40000000-0000-4000-8000-' + String(index).padStart(12, '0')
function plan(index = 1, status: NutritionPlanResponse['status'] = 'active'): NutritionPlanResponse {
  return { id: id(index), clientId, dietitianId, title: 'Sentetik program ' + index, status, versionId: versionId(index), versionNumber: 2,
    startDate: '2026-11-01', endDate: null, dailyCaloriesTargetKcal: null, dailyWaterTargetMl: 2000, createdAt: '2026-11-01T09:00:00Z',
    items: [{ id: '50000000-0000-4000-8000-000000000001', nutritionPlanId: id(index), dayOfWeek: null, mealType: 'breakfast',
      description: 'Sentetik ortak öneri ' + index, recommendedQuantity: '½ kase', sortOrder: 0, recipeId: null, alternativeGroupId: null }] }
}
function version(row: NutritionPlanResponse) {
  return { id: row.versionId, nutritionPlanId: row.id, versionNumber: row.versionNumber, createdAt: row.createdAt,
    snapshot: { title: row.title, startDate: row.startDate, endDate: row.endDate, dailyCaloriesTargetKcal: row.dailyCaloriesTargetKcal,
      dailyWaterTargetMl: row.dailyWaterTargetMl, items: row.items } }
}
function mockApi(plans: NutritionPlanResponse[] = [plan()]) {
  return vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
    const url = new URL(String(input), window.location.origin)
    if (url.pathname === '/api/v1/nutrition-plans') {
      const offset = (Number(url.searchParams.get('page')) - 1) * 10
      return Response.json({ items: plans.slice(offset, offset + 10), totalCount: plans.length })
    }
    const row = plans.find(item => url.pathname === '/api/v1/nutrition-plans/' + item.id || url.pathname === '/api/v1/nutrition-plans/' + item.id + '/versions/' + item.versionId)
    if (row) return Response.json(url.pathname.includes('/versions/') ? version(row) : row)
    throw new Error('Unexpected test request: ' + url.pathname)
  })
}
const session = { token: 'synthetic-csrf', dietitianId, dietitianName: 'Sentetik Diyetisyen', onFailure: vi.fn(() => false) }
function page(program = plan()) {
  const onBack = vi.fn()
  const tree = (value: NutritionPlanResponse) => <WorkspaceContext.Provider value={session}>
    <NutritionPlanPrint clientId={value.clientId} clientName={value.clientId === clientId ? 'Örnek İpek' : 'Örnek Çağla'} program={value} onBack={onBack} />
  </WorkspaceContext.Provider>
  const rendered = render(tree(program))
  return { ...rendered, user: userEvent.setup(), onBack, changeProgram: (value: NutritionPlanResponse) => rendered.rerender(tree(value)) }
}
const printButton = () => screen.getByRole('button', { name: 'Yazdır / PDF' })
const documentView = () => screen.queryByRole('article', { name: 'Yazdırılabilir beslenme programı' })
const originalFonts = Object.getOwnPropertyDescriptor(document, 'fonts')
const originalDecode = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'decode')

beforeEach(() => {
  Object.defineProperty(document, 'fonts', { configurable: true, value: { load: vi.fn(async () => [{}]), ready: Promise.resolve() } })
  Object.defineProperty(HTMLImageElement.prototype, 'decode', { configurable: true, value: vi.fn(async () => undefined) })
  vi.spyOn(HTMLImageElement.prototype, 'naturalWidth', 'get').mockReturnValue(202)
  vi.spyOn(window, 'print').mockImplementation(() => undefined)
  session.onFailure.mockClear()
})
afterEach(() => {
  vi.restoreAllMocks()
  if (originalFonts) Object.defineProperty(document, 'fonts', originalFonts)
  else Reflect.deleteProperty(document, 'fonts')
  if (originalDecode) Object.defineProperty(HTMLImageElement.prototype, 'decode', originalDecode)
  else Reflect.deleteProperty(HTMLImageElement.prototype, 'decode')
})

describe('printable nutrition programs', () => {
  it('opens exactly the supplied program without a second program picker or list request', async () => {
    const rows = Array.from({ length: 11 }, (_, index) => plan(index + 1, index === 10 ? 'active' : 'archived'))
    const request = mockApi(rows)
    page(rows[10]!)
    expect(printButton()).toBeDisabled()
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(screen.queryByRole('combobox', { name: 'Beslenme programı' })).not.toBeInTheDocument()
    expect(request.mock.calls.some(([url]) => String(url).includes('?clientId='))).toBe(false)
    expect(documentView()).toHaveTextContent('Sentetik program 11')
  })

  it('waits for logo and fonts, pins content, and rechecks access before calling print', async () => {
    const row = plan()
    const request = mockApi([row])
    let loaded!: () => void
    vi.mocked(HTMLImageElement.prototype.decode).mockReturnValue(new Promise<void>(resolve => { loaded = resolve }))
    const { user, onBack } = page()
    await screen.findByRole('article')
    expect(printButton()).toBeDisabled()
    await waitFor(() => expect(loaded).toBeDefined())
    await act(async () => loaded())
    await waitFor(() => expect(printButton()).toBeEnabled())
    const document = within(documentView()!)
    expect(document.getAllByText('Sentetik ortak öneri 1')).toHaveLength(1)
    expect(document.getByRole('heading', { name: 'Her gün' })).toBeVisible()
    expect(document.queryByRole('heading', { name: 'Pazartesi' })).not.toBeInTheDocument()
    expect(document.getByText('Miktar: ½ kase')).toBeVisible()
    expect(document.getAllByText('Belirtilmemiş')).toHaveLength(2)
    expect(document.getByText(/İçerik sürümü 2/)).toBeVisible()
    await user.click(printButton())
    await waitFor(() => expect(window.print).toHaveBeenCalledTimes(1))
    expect(request.mock.calls.filter(([url]) => String(url).endsWith('/versions/' + row.versionId))).toHaveLength(2)
    expect(request.mock.calls.every(([, init]) => !init?.method || init.method === 'GET')).toBe(true)
    await user.click(screen.getByRole('button', { name: 'Programlara dön' }))
    expect(onBack).toHaveBeenCalledOnce()
  })

  it('keeps the listed version pinned even when the program has a newer current version', async () => {
    const row = plan()
    const request = mockApi([row])
    const original = request.getMockImplementation()!
    request.mockImplementation((input, init) => String(input) === '/api/v1/nutrition-plans/' + row.id
      ? Promise.resolve(Response.json({ ...row, title: 'Daha yeni içerik', versionNumber: 3, versionId: versionId(99) })) : original(input, init))
    page()
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(documentView()).toHaveTextContent('Sentetik program 1')
    expect(documentView()).toHaveTextContent('İçerik sürümü 2')
    expect(documentView()).not.toHaveTextContent('Daha yeni içerik')
    expect(request.mock.calls.some(([url]) => String(url).endsWith('/versions/' + versionId(99)))).toBe(false)
  })

  it('does not offer printing when the program list is empty', async () => {
    mockApi([])
    render(<WorkspaceContext.Provider value={session}><NutritionPlanPanel clientId={clientId} showPrintAction /></WorkspaceContext.Provider>)
    await screen.findByText('Bu danışanın kayıtlı beslenme programı bulunmuyor.')
    expect(screen.queryByRole('button', { name: /programını yazdır/ })).not.toBeInTheDocument()
    expect(documentView()).not.toBeInTheDocument()
  })

  it('groups alternatives explicitly and retains day and meal order without duplicating shared suggestions', async () => {
    const row = plan()
    row.items.push(...[2, 1].map((index) => ({ ...row.items[0]!, id: '50000000-0000-4000-8000-' + String(index + 1).padStart(12, '0'),
      dayOfWeek: 1, sortOrder: index, description: 'Alternatif öneri ' + index, recommendedQuantity: null,
      alternativeGroupId: '60000000-0000-4000-8000-000000000001' })))
    mockApi([row]); page(row)
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(within(documentView()!).getAllByRole('heading', { level: 2 }).map(node => node.textContent)).toEqual(['Sentetik program 1', 'Her gün', 'Pazartesi'])
    expect(screen.getAllByText('Alternatifler · Birini seçin')).toHaveLength(1)
    expect(documentView()!.querySelectorAll('.nutrition-print-alternatives li')).toHaveLength(2)
    expect(documentView()!.querySelector('.nutrition-print-alternatives li')).toHaveTextContent('Alternatif öneri 1')
    expect(screen.getAllByText('Sentetik ortak öneri 1')).toHaveLength(1)
  })

  it.each([403, 404])('shows access failure %s locally, clears the document and can retry', async status => {
    const request = mockApi()
    request.mockResolvedValueOnce(new Response(null, { status }))
    const { user } = page()
    await screen.findByRole('alert')
    expect(documentView()).not.toBeInTheDocument()
    expect(printButton()).toBeDisabled()
    expect(session.onFailure).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Belgeyi yeniden yükle' }))
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(documentView()).toBeVisible()
    expect(request).toHaveBeenCalledTimes(3)
  })

  it('hides the previous document immediately while another program loads and ignores its late response', async () => {
    const first = plan(), second = plan(2, 'draft')
    const request = mockApi([first, second])
    const original = request.getMockImplementation()!
    let resolveFirst!: (value: Response) => void
    request.mockImplementation((input, init) => String(input).endsWith('/versions/' + first.versionId)
      ? new Promise<Response>(resolve => { resolveFirst = resolve }) : original(input, init))
    const { changeProgram } = page()
    await waitFor(() => expect(resolveFirst).toBeDefined())
    changeProgram(second)
    expect(documentView()).not.toBeInTheDocument()
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(documentView()).toHaveTextContent(second.title)
    await act(async () => resolveFirst(Response.json(version(first))))
    expect(documentView()).not.toHaveTextContent(first.title)
    expect(documentView()).toHaveTextContent(second.title)
  })

  it('clears all previous client data on a client change while its program is still pending', async () => {
    const nextClient = '10000000-0000-4000-8000-000000000002'
    const second = { ...plan(2), clientId: nextClient }
    const request = mockApi([plan(), second])
    const original = request.getMockImplementation()!
    let finish!: (response: Response) => void
    request.mockImplementation((input, init) => String(input) === '/api/v1/nutrition-plans/' + second.id
      ? new Promise<Response>(resolve => { finish = resolve }) : original(input, init))
    const { changeProgram } = page()
    await waitFor(() => expect(printButton()).toBeEnabled())
    changeProgram(second)
    expect(documentView()).not.toBeInTheDocument()
    expect(screen.queryByText('Örnek İpek')).not.toBeInTheDocument()
    expect(printButton()).toBeDisabled()
    await act(async () => finish(Response.json(second)))
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(documentView()).toHaveTextContent('Örnek Çağla')
  })

  it('removes the document if permission is revoked immediately before printing', async () => {
    const request = mockApi()
    const { user } = page()
    await waitFor(() => expect(printButton()).toBeEnabled())
    request.mockResolvedValueOnce(new Response(null, { status: 403 }))
    await user.click(printButton())
    await screen.findByRole('alert')
    expect(documentView()).not.toBeInTheDocument()
    expect(printButton()).toBeDisabled()
    expect(window.print).not.toHaveBeenCalled()
  })

  it('handles a failed logo, retries, and does not allow printing with missing assets', async () => {
    mockApi()
    vi.mocked(HTMLImageElement.prototype.decode).mockRejectedValue(new Error('Synthetic logo failure'))
    const { user } = page()
    expect(await screen.findByRole('alert')).toHaveTextContent('logosu yüklenemedi')
    expect(printButton()).toBeDisabled()
    vi.mocked(HTMLImageElement.prototype.decode).mockResolvedValue()
    await user.click(screen.getByRole('button', { name: 'Belgeyi yeniden yükle' }))
    await waitFor(() => expect(printButton()).toBeEnabled())
  })

  it('retries server errors and rejects a version that does not match the selected metadata', async () => {
    const request = mockApi()
    request.mockResolvedValueOnce(new Response(null, { status: 500 }))
    const { user } = page()
    await screen.findByRole('alert')
    expect(documentView()).not.toBeInTheDocument()
    const original = request.getMockImplementation()!
    request.mockImplementation((input, init) => String(input).includes('/versions/')
      ? Promise.resolve(Response.json({ ...version(plan()), versionNumber: 3 })) : original(input, init))
    await user.click(screen.getByRole('button', { name: 'Belgeyi yeniden yükle' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('İçerik sürümü doğrulanamadı')
    expect(documentView()).not.toBeInTheDocument()
    expect(printButton()).toBeDisabled()
  })

  it('prints the chosen card on a later program page and restores that page and button focus', async () => {
    const rows = Array.from({ length: 11 }, (_, index) => plan(index + 1, index === 0 ? 'active' : 'draft'))
    mockApi(rows)
    const user = userEvent.setup()
    render(<WorkspaceContext.Provider value={session}><NutritionPlanPanel clientId={clientId} clientName="Örnek İpek" compact showPrintAction /></WorkspaceContext.Provider>)
    await screen.findByRole('heading', { name: 'Sentetik program 1' })
    await user.click(screen.getByRole('button', { name: 'Sonraki programlar sayfası' }))
    const trigger = await screen.findByRole('button', { name: 'Sentetik program 11 programını yazdır' })
    await user.click(trigger)
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(documentView()).toHaveTextContent('Sentetik program 11')
    expect(within(documentView()!).queryByRole('heading', { name: 'Sentetik program 1' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Programlara dön' }))
    expect(documentView()).not.toBeInTheDocument()
    expect(screen.getByText('Sayfa 2')).toBeVisible()
    expect(trigger).toHaveFocus()
  })

  it('keeps an unsaved editor draft while viewing a saved program and returning', async () => {
    mockApi()
    const user = userEvent.setup()
    render(<WorkspaceContext.Provider value={session}><NutritionPlanPanel clientId={clientId} clientName="Örnek İpek" showPrintAction /></WorkspaceContext.Provider>)
    await user.click(await screen.findByRole('button', { name: 'Programı düzenle' }))
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Kaydedilmemiş taslak başlığı' } })
    await user.click(screen.getByRole('button', { name: 'Sentetik program 1 programını yazdır' }))
    await waitFor(() => expect(printButton()).toBeEnabled())
    expect(documentView()).toHaveTextContent('Sentetik program 1')
    expect(documentView()).not.toHaveTextContent('Kaydedilmemiş taslak başlığı')
    await user.click(screen.getByRole('button', { name: 'Programlara dön' }))
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Kaydedilmemiş taslak başlığı')
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
  })

  it('keeps reports and CSV usable without any print entry', async () => {
    const request = mockApi()
    const original = request.getMockImplementation()!
    request.mockImplementation((input, init) => String(input).includes('/dietitian/clients/')
      ? Promise.resolve(Response.json({ items: [], totalCount: 0 })) : original(input, init))
    render(<MemoryRouter><WorkspaceContext.Provider value={session}><ReportsOverview clientId={clientId} clientName="Örnek İpek" totalClients={1} /></WorkspaceContext.Provider></MemoryRouter>)
    const start = screen.getByLabelText(/28 günlük dönem başlangıcı/, { selector: 'input' })
    fireEvent.change(start, { target: { value: '2026-11-01' } })
    await waitFor(() => expect(screen.getByRole('button', { name: 'CSV indir' })).toBeEnabled())
    expect(screen.queryByRole('button', { name: /Yazdır|PDF/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/PDF olarak kaydet/)).not.toBeInTheDocument()
    expect(screen.getByLabelText(/28 günlük dönem başlangıcı/, { selector: 'input' })).toHaveValue('2026-11-01')
    expect(screen.getByRole('img', { name: 'Seçilen danışanın haftalara göre öğün sayıları' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'CSV indir' })).toBeEnabled()
  })
})

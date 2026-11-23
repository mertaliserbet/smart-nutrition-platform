import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Link, Route, Routes } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { NutritionPlanPanel } from './NutritionPlanPanel'
import { NutritionPlanEditor } from './NutritionPlanEditor'
import { copyItems, draftContent, planDraft, reusablePlanDraft } from './planDraft'
import type { NutritionPlanResponse, PlanContentRequest } from './nutritionPlanApi'

const client = '11111111-1111-4111-8111-111111111111', expert = '22222222-2222-4222-8222-222222222222'
const sourceClient = '33333333-3333-4333-8333-333333333333', planId = '44444444-4444-4444-8444-444444444444'
const group = '55555555-5555-4555-8555-555555555555'
const session = { token: 'synthetic', dietitianId: expert, onFailure: vi.fn(() => false) }
const plan = (changes: Partial<NutritionPlanResponse> = {}): NutritionPlanResponse => ({
  id: planId, clientId: client, dietitianId: expert, title: 'Kaynak başlığı', startDate: '2026-11-18', endDate: '2026-11-30',
  dailyCaloriesTargetKcal: 1900, dailyWaterTargetMl: 2100, status: 'draft', createdAt: '2026-11-18T10:00:00Z',
  versionId: '66666666-6666-4666-8666-666666666666', versionNumber: 1,
  items: [0, 1].map(i => ({ id: `77777777-7777-4777-8777-77777777777${i}`, nutritionPlanId: planId, dayOfWeek: 1,
    mealType: 'breakfast', description: `Sentetik seçenek ${i + 1}`, recommendedQuantity: '1 porsiyon', sortOrder: i, recipeId: null, alternativeGroupId: group })), ...changes,
})
const list = (items = [plan()], totalCount = items.length) => Response.json({ items, totalCount })
function setup(clientId = client, context = session) {
  const view = render(<WorkspaceContext.Provider value={context}><NutritionPlanPanel clientId={clientId} clientName="Hedef Sentetik Ada" /></WorkspaceContext.Provider>)
  return { ...view, user: userEvent.setup() }
}
async function changeTitle(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole('button', { name: 'Programı düzenle' }))
  fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Değişen taslak' } })
}

describe('program draft protection', () => {
  it('does not warn for a clean or reverted draft, but cancel requires a deliberate discard for actual edits', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => list())
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Programı düzenle' }))
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'geçici' } })
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Kaynak başlığı' } })
    await user.click(screen.getByRole('button', { name: 'Vazgeç' }))
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    await changeTitle(user)
    await user.click(screen.getByRole('button', { name: 'Vazgeç' }))
    expect(screen.getByRole('alertdialog')).toHaveTextContent('Kaydedilmemiş değişiklikler')
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' }))
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Değişen taslak')
    await user.click(screen.getByRole('button', { name: 'Vazgeç' }))
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri sil' }))
    expect(screen.queryByLabelText('Program başlığı')).not.toBeInTheDocument()
  })
  it('preserves editing across refresh, history, paging and a failed save', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async (path, options) => {
      if (options?.method === 'PATCH') return new Response(null, { status: 500 })
      if (String(path).includes('/versions?')) return Response.json({ items: [], totalCount: 0 })
      return list([plan()], 11)
    })
    const { user } = setup(); await changeTitle(user)
    await user.click(screen.getByRole('button', { name: 'Programları yeniden kontrol et' }))
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Değişen taslak')
    await user.click(await screen.findByRole('button', { name: 'Sürüm geçmişini aç' }))
    expect(await screen.findByRole('region', { name: 'Program sürüm geçmişi' })).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Sonraki programlar sayfası' }))
    await screen.findByRole('button', { name: 'Önceki programlar sayfası' })
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Değişen taslak')
    await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('doğrulanamadı')
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Değişen taslak')
    expect(request.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1)
  })
  it('guards switching programs and resets beforeunload protection after successful save', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (_path, options) => options?.method === 'PATCH'
      ? Response.json(plan({ title: 'Değişen taslak', versionNumber: 2 })) : list())
    const { user } = setup(); await changeTitle(user)
    const event = new Event('beforeunload', { cancelable: true }); window.dispatchEvent(event); expect(event.defaultPrevented).toBe(true)
    await user.click(screen.getByRole('button', { name: 'Yeni program oluştur' })); expect(screen.getByRole('alertdialog')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' }))
    await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    await screen.findByText('Yeni program sürümü kaydedildi.')
    const clean = new Event('beforeunload', { cancelable: true }); window.dispatchEvent(clean); expect(clean.defaultPrevented).toBe(false)
  })
  it('guards leaving the client but lets section links retain the editor', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => list())
    render(<MemoryRouter initialEntries={['/client']}><WorkspaceContext.Provider value={session}><Routes><Route path="/client" element={<><Link to="?bolum=ozet">Bölüm</Link><Link to="/list">Liste</Link><NutritionPlanPanel clientId={client} /></>} /><Route path="/list" element={<h1>Liste ekranı</h1>} /></Routes></WorkspaceContext.Provider></MemoryRouter>)
    const user = userEvent.setup(); await changeTitle(user)
    await user.click(screen.getByRole('link', { name: 'Bölüm' })); expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Liste' })); expect(screen.getByRole('alertdialog')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' })); expect(screen.getByLabelText('Program başlığı')).toHaveValue('Değişen taslak')
    await user.click(screen.getByRole('link', { name: 'Liste' })); await user.click(screen.getByRole('button', { name: 'Değişiklikleri sil' }))
    expect(screen.getByRole('heading', { name: 'Liste ekranı' })).toBeVisible()
  })
  it.each(['permission', 'client', 'session'])('removes private drafts on %s change', async scenario => {
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => list())
    const { user, rerender } = setup(); await changeTitle(user)
    if (scenario === 'permission') { request.mockResolvedValue(new Response(null, { status: 403 })); act(() => window.dispatchEvent(new Event('focus'))) }
    else rerender(<WorkspaceContext.Provider value={scenario === 'session' ? { ...session, token: 'other' } : session}><NutritionPlanPanel clientId={scenario === 'client' ? sourceClient : client} /></WorkspaceContext.Provider>)
    await waitFor(() => expect(screen.queryByDisplayValue('Değişen taslak')).not.toBeInTheDocument())
  })
  it('confirms archive by program name and does not activate another program', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async (_path, options) => options?.method === 'POST' ? Response.json(plan({ status: 'archived' })) : list())
    const { user } = setup(); await user.click(await screen.findByRole('button', { name: 'Programı arşivle' }))
    expect(screen.getByRole('alertdialog')).toHaveTextContent('Kaynak başlığı'); expect(request).toHaveBeenCalledTimes(1)
    await user.click(screen.getByRole('button', { name: 'Onayla ve arşivle' })); await screen.findByText('Beslenme programı arşivlendi.')
    expect(request.mock.calls.some(([path]) => String(path).endsWith('/activate'))).toBe(false)
  })
})

describe('weekly plan editing', () => {
  it('copies all daily alternatives using independent row/group identities and preserves the source order', async () => {
    const save = vi.fn(async (_value: PlanContentRequest) => {})
    render(<NutritionPlanEditor initial={plan()} busy={false} onSave={save} onCancel={() => {}} />)
    const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Pazartesi' }))
    await user.selectOptions(screen.getByLabelText('Hedef gün'), '2'); await user.click(screen.getByRole('button', { name: 'Günü kopyala' }))
    expect(screen.getByRole('button', { name: 'Salı' })).toHaveAttribute('aria-pressed', 'true')
    await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    const items = save.mock.calls[0]![0].items
    expect(items.map(row => row.dayOfWeek)).toEqual([1, 1, 2, 2]); expect(items.map(row => row.sortOrder)).toEqual([0, 1, 2, 3])
    expect(items[0]!.alternativeGroupId).toBe(items[1]!.alternativeGroupId)
    expect(items[2]!.alternativeGroupId).toBe(items[3]!.alternativeGroupId)
    expect(items[2]!.alternativeGroupId).not.toBe(group)
    expect(items.every(row => !('id' in row) && !('nutritionPlanId' in row))).toBe(true)
  })
  it('requires confirmation to replace a populated day', async () => {
    const original = plan(), seed = planDraft(original)
    seed.items.push(...copyItems(seed.items, '2'))
    render(<NutritionPlanEditor initial={original} seed={seed} busy={false} onSave={async () => {}} onCancel={() => {}} />)
    const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Pazartesi' })); await user.selectOptions(screen.getByLabelText('Hedef gün'), '2')
    await user.click(screen.getByRole('button', { name: 'Günü kopyala' })); expect(screen.getByRole('alertdialog')).toHaveTextContent('Salı')
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' })); expect(screen.getByRole('button', { name: 'Pazartesi' })).toHaveAttribute('aria-pressed', 'true')
    await user.click(screen.getByRole('button', { name: 'Günü kopyala' })); await user.click(screen.getByRole('button', { name: 'Hedef günü değiştir' }))
    expect(screen.getByRole('button', { name: 'Salı' })).toHaveAttribute('aria-pressed', 'true')
  })
  it('refuses copying beyond the 100-item limit and keeps every existing recommendation', async () => {
    const initial = plan()
    initial.items.push(...Array.from({ length: 98 }, (_, i) => ({ ...initial.items[0]!, id: crypto.randomUUID(), dayOfWeek: 2, sortOrder: i + 2, alternativeGroupId: null })))
    const save = vi.fn(async (_value: PlanContentRequest) => {})
    render(<NutritionPlanEditor initial={initial} busy={false} onSave={save} onCancel={() => {}} />)
    const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Pazartesi' }))
    await user.selectOptions(screen.getByLabelText('Hedef gün'), '3'); await user.click(screen.getByRole('button', { name: 'Günü kopyala' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('100 öğün önerisi sınırını aşıyor')
    expect(screen.getByRole('button', { name: 'Öğün önerisi ekle' })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    expect(save.mock.calls[0]![0].items).toHaveLength(100)
    expect(save.mock.calls[0]![0].items.some(row => row.dayOfWeek === 3)).toBe(false)
  })
  it('opens the first invalid day/card and focuses its field without dropping other days', async () => {
    const initial = plan(); initial.items[0]!.description = ''
    const save = vi.fn(async (_value: PlanContentRequest) => {})
    render(<NutritionPlanEditor initial={initial} busy={false} onSave={save} onCancel={() => {}} />)
    const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    expect(screen.getByRole('button', { name: 'Pazartesi' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByLabelText('Öğün 1 açıklaması')).toHaveFocus(); expect(screen.getByLabelText('Öğün 1 açıklaması')).toBeVisible()
    expect(screen.getByLabelText('Öğün 1 açıklaması')).toHaveAttribute('aria-invalid', 'true'); expect(save).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('Öğün 1 açıklaması'), { target: { value: 'Düzeltilmiş' } })
    await user.click(screen.getByRole('button', { name: 'Her gün' })); await user.click(screen.getByRole('button', { name: 'Pazartesi' }))
    expect(screen.getByLabelText('Öğün 1 açıklaması')).toHaveValue('Düzeltilmiş')
  })
})

describe('copying only authorized own program structure', () => {
  function copySetup(options: { denied?: boolean; foreign?: boolean; personal?: boolean } = {}) {
    const source = plan({ clientId: sourceClient })
    let deny = options.denied ?? false
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async (path, init) => {
      const url = String(path)
      if (url.includes('/dietitian/clients?')) return Response.json({ items: [{ id: sourceClient, displayName: 'Kaynak Sentetik Deniz' }], totalCount: 11 })
      if (url === `/api/v1/nutrition-plans/${planId}`) return deny ? new Response(null, { status: 403 }) : Response.json(options.foreign || options.personal ? { ...source, dietitianId: options.personal ? null : group } : source)
      if (init?.method === 'POST') return Response.json(plan(), { status: 201 })
      if (url.includes(`clientId=${sourceClient}`)) return list([source, plan({ ...source, id: '88888888-8888-4888-8888-888888888888', dietitianId: null, title: 'Kişisel', items: source.items.map(row => ({ ...row, nutritionPlanId: '88888888-8888-4888-8888-888888888888' })) })])
      return list([])
    })
    return { ...setup(), request, source, deny: () => { deny = true } }
  }
  async function choose(user: ReturnType<typeof userEvent.setup>) {
    await user.click(await screen.findByRole('button', { name: 'Kendi programımdan kopyala' }))
    await user.click(await screen.findByRole('button', { name: 'Kaynak Sentetik Deniz' }))
    expect(await screen.findByRole('button', { name: 'Kaynak başlığı programını kopyala' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Kişisel programını kopyala' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Kaynak başlığı programını kopyala' }))
  }
  it('uses paged client/program lists, copies reusable fields only, POSTs an independent target draft and never writes the source or activates', async () => {
    const { user, request } = copySetup(); await choose(user)
    expect(screen.queryByRole('button', { name: 'Kişisel programını kopyala' })).not.toBeInTheDocument()
    expect(screen.getByText('Hedef danışan: Hedef Sentetik Ada')).toBeVisible()
    expect(screen.getByText(/Serbest metin kişiye özel bilgi içerebilir/)).toBeVisible()
    expect(screen.getByLabelText('Program başlığı')).toHaveValue(''); expect(screen.getByLabelText('Başlangıç tarihi')).toHaveValue('')
    expect(screen.getByLabelText('Günlük enerji hedefi (kcal, isteğe bağlı)')).toHaveValue('')
    expect(request.mock.calls.every(([, options]) => !options?.method || options.method === 'GET')).toBe(true)
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Hedef program' } }); fireEvent.change(screen.getByLabelText('Başlangıç tarihi'), { target: { value: '2026-11-21' } })
    await user.click(screen.getByRole('button', { name: 'Taslak oluştur' })); await screen.findByText('Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')
    const writes = request.mock.calls.filter(([, options]) => options?.method === 'POST' || options?.method === 'PATCH')
    expect(writes).toHaveLength(1); expect(writes[0]![0]).toBe('/api/v1/nutrition-plans')
    const body = JSON.parse(writes[0]![1]!.body as string)
    expect(body.clientId).toBe(client); expect(body.startDate).toBe('2026-11-21'); expect(body.endDate).toBeNull(); expect(body.dailyCaloriesTargetKcal).toBeNull(); expect(body.dailyWaterTargetMl).toBeNull()
    expect(body.items[0].alternativeGroupId).not.toBe(group); expect(body.items[0].alternativeGroupId).toBe(body.items[1].alternativeGroupId)
    expect(body.items[0]).not.toHaveProperty('id'); expect(body.items[0]).not.toHaveProperty('nutritionPlanId')
    expect(request.mock.calls.filter(([path]) => String(path) === `/api/v1/nutrition-plans/${planId}`)).toHaveLength(2)
  })
  it.each(['revoked', 'foreign', 'personal'])('does not open a %s source even when the list was previously readable', async scenario => {
    const { user, request } = copySetup({ denied: scenario === 'revoked', foreign: scenario === 'foreign', personal: scenario === 'personal' }); await choose(user)
    expect(await screen.findByRole('alert')).toBeVisible(); expect(screen.queryByRole('form', { name: 'Beslenme programı formu' })).not.toBeInTheDocument()
    expect(request.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false)
  })
  it('discards a copied draft if source permission is revoked before saving and never POSTs it', async () => {
    const { user, request, deny } = copySetup(); await choose(user); deny()
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Hedef' } }); fireEvent.change(screen.getByLabelText('Başlangıç tarihi'), { target: { value: '2026-11-21' } })
    await user.click(screen.getByRole('button', { name: 'Taslak oluştur' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Kopyalanan taslak kaldırıldı')
    expect(screen.queryByRole('form', { name: 'Beslenme programı formu' })).not.toBeInTheDocument()
    expect(request.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false)
  })
  it('removes copied private content on source denial at focus without closing independent target access', async () => {
    const { user, request, deny } = copySetup(); await choose(user); deny()
    act(() => window.dispatchEvent(new Event('focus')))
    expect(await screen.findByRole('alert')).toHaveTextContent('Kopyalanan taslak kaldırıldı')
    expect(screen.queryByRole('form', { name: 'Beslenme programı formu' })).not.toBeInTheDocument()
    expect(await screen.findByRole('button', { name: 'Yeni program oluştur' })).toBeVisible()
    expect(request.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false)
  })
  it('aborts a pending source selection when saving the current draft and ignores its late response', async () => {
    const { user, request, source } = copySetup()
    const original = request.getMockImplementation()!
    let finish!: (response: Response) => void
    request.mockImplementation((path, init) => String(path) === `/api/v1/nutrition-plans/${planId}`
      ? new Promise(resolve => { finish = resolve }) : original(path, init))
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' }))
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: 'Mevcut taslak' } })
    fireEvent.change(screen.getByLabelText('Başlangıç tarihi'), { target: { value: '2026-11-21' } })
    fireEvent.change(screen.getByLabelText('Öğün 1 açıklaması'), { target: { value: 'Mevcut öğün' } })
    await choose(user)
    const pending = request.mock.calls.find(([path]) => String(path) === `/api/v1/nutrition-plans/${planId}`)![1]!.signal!
    fireEvent.submit(screen.getByRole('form', { name: 'Beslenme programı formu' }))
    await screen.findByText('Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')
    expect(pending.aborted).toBe(true)
    await act(async () => finish(Response.json(source)))
    expect(screen.queryByRole('form', { name: 'Beslenme programı formu' })).not.toBeInTheDocument()
    expect(request.mock.calls.filter(([, init]) => init?.method === 'POST')).toHaveLength(1)
  })
  it('creates fresh local identities and preserves every-day/specific-day semantics without carrying personal fields', () => {
    const source = plan(); source.items[0]!.dayOfWeek = null; source.items.forEach(row => { row.alternativeGroupId = null })
    const draft = reusablePlanDraft(source), content = draftContent(draft)
    expect(draft.items.map(row => row.day)).toEqual(['', '1']); expect(draft.items.some(row => source.items.some(old => old.id === row.key))).toBe(false)
    expect(content.title).toBe(''); expect(content.startDate).toBe(''); expect(content.endDate).toBeNull(); expect(Object.keys(content)).not.toContain('clientId')
  })
})

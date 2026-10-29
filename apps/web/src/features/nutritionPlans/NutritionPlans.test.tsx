import { act, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { NutritionPlanPanel } from './NutritionPlanPanel'
import type { NutritionPlanResponse } from './nutritionPlanApi'

const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const dietitianId = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const planId = 'c428ae15-f14c-4685-a272-69a81225c9df'
const versionId = '02c808f1-e866-40c4-8b6f-082b66fda190'
const nextVersionId = '7aa0636c-cd80-4845-9f49-3100d8354496'
const itemId = 'e5a0eb64-90f3-495d-a426-f4ff9fa53ca6'
const row = (changes: Partial<NutritionPlanResponse> = {}): NutritionPlanResponse => ({
  id: planId, clientId, dietitianId, title: 'Sentetik program', startDate: '2026-10-29', endDate: null,
  dailyCaloriesTargetKcal: null, dailyWaterTargetMl: null, status: 'draft', versionNumber: 1, versionId,
  createdAt: '2026-10-29T10:00:00Z', items: [{ id: itemId, nutritionPlanId: planId, dayOfWeek: null,
    mealType: 'breakfast', description: 'Sentetik öğün önerisi', recommendedQuantity: null, sortOrder: 0, recipeId: null, alternativeGroupId: null }], ...changes,
})
const list = (items: NutritionPlanResponse[] = []) => Response.json({ items, totalCount: items.length })
const metadata = { id: versionId, nutritionPlanId: planId, versionNumber: 1, createdAt: '2026-10-29T10:00:00Z' }
function setup() {
  const onFailure = vi.fn(() => false)
  const rendered = render(<WorkspaceContext.Provider value={{ token: 'synthetic-csrf', dietitianId, onFailure }}>
    <h2>Sentetik danışan kimliği</h2><NutritionPlanPanel clientId={clientId} />
  </WorkspaceContext.Provider>)
  return { ...rendered, user: userEvent.setup(), onFailure }
}
async function fill() {
  fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: '  Sentetik program  ' } })
  fireEvent.change(screen.getByLabelText('Başlangıç tarihi'), { target: { value: '2026-10-29' } })
  fireEvent.change(screen.getByLabelText('Öğün 1 açıklaması'), { target: { value: ' Sentetik öğün önerisi ' } })
}

describe('nutrition program workspace', () => {
  it('keeps basic identity but hides health content and editing when sharing is closed, and permits rechecking', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(null, { status: 403 })).mockResolvedValueOnce(list())
    const { user, onFailure } = setup()
    expect(await screen.findByRole('alert')).toHaveTextContent('izniniz bulunmuyor')
    expect(screen.getByText('Sentetik danışan kimliği')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Yeni program oluştur' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Programları yeniden kontrol et' }))
    expect(await screen.findByRole('button', { name: 'Yeni program oluştur' })).toBeVisible()
    expect(onFailure).not.toHaveBeenCalled()
    expect(request.mock.calls[0]?.[0]).toBe(`/api/v1/nutrition-plans?clientId=${clientId}&page=1&pageSize=10`)
  })

  it('creates a draft with no guessed clinical targets or item identities, and never activates it implicitly', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list()).mockResolvedValueOnce(Response.json(row(), { status: 201 })).mockResolvedValueOnce(list([row()]))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' }))
    expect(screen.getByLabelText('Günlük enerji hedefi (kcal, isteğe bağlı)')).toHaveValue('')
    await fill(); await user.click(screen.getByRole('button', { name: 'Taslak oluştur' }))
    expect(await screen.findByText('Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')).toBeVisible()
    expect(request.mock.calls[1]?.[1]).toMatchObject({ method: 'POST', credentials: 'same-origin', cache: 'no-store', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf' } })
    expect(JSON.parse(request.mock.calls[1]?.[1]?.body as string)).toEqual({ clientId, title: 'Sentetik program', startDate: '2026-10-29', endDate: null,
      dailyCaloriesTargetKcal: null, dailyWaterTargetMl: null, items: [{ dayOfWeek: null, mealType: 'breakfast', description: 'Sentetik öğün önerisi', recommendedQuantity: null, sortOrder: 0, recipeId: null, alternativeGroupId: null }] })
    expect(request.mock.calls.some(([path]) => String(path).endsWith('/activate'))).toBe(false)
  })

  it('shows activation success only after the explicit bodyless CSRF request is confirmed', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([row()])).mockResolvedValueOnce(Response.json(row({ status: 'active' }))).mockResolvedValueOnce(list([row({ status: 'active' })]))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Programı etkinleştir' }))
    expect(await screen.findByText('Beslenme programı etkinleştirildi ve danışana atandı.')).toBeVisible()
    expect(request.mock.calls[1]?.[0]).toBe(`/api/v1/nutrition-plans/${planId}/activate`)
    expect(request.mock.calls[1]?.[1]).toMatchObject({ method: 'POST', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf' } })
    expect(request.mock.calls[1]?.[1]?.body).toBeUndefined()
  })

  it('preserves the draft and gives no assigned success on a single-active conflict', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([row()])).mockResolvedValueOnce(Response.json({ error: { code: 'active_nutrition_plan_conflict' } }, { status: 409 }))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Programı etkinleştir' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Başka bir aktif program var')
    expect(screen.getByText('Taslak · Sürüm 1')).toBeVisible()
    expect(screen.queryByText('Beslenme programı etkinleştirildi ve danışana atandı.')).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(2)
  })

  it('shows personal and other dietitian programs read-only', async () => {
    const other = row({ id: nextVersionId, dietitianId: versionId, title: 'Başka uzman programı', items: row().items.map(item => ({ ...item, nutritionPlanId: nextVersionId })) })
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([row({ dietitianId: null }), other]))
    setup()
    expect(await screen.findByText('Kişisel program · Salt okunur')).toBeVisible()
    expect(screen.getByText('Başka diyetisyenin programı · Salt okunur')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Programı düzenle' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Programı etkinleştir' })).not.toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Sürüm geçmişini aç' })).toHaveLength(2)
  })

  it('patches only content and displays a newly confirmed version', async () => {
    const next = row({ title: 'Yeni sentetik başlık', versionNumber: 2, versionId: nextVersionId })
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([row()])).mockResolvedValueOnce(Response.json(next)).mockResolvedValueOnce(list([next]))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Programı düzenle' }))
    fireEvent.change(screen.getByLabelText('Program başlığı'), { target: { value: next.title } })
    await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    expect(await screen.findByText('Taslak · Sürüm 2')).toBeVisible()
    expect(request.mock.calls[1]?.[0]).toBe(`/api/v1/nutrition-plans/${planId}`)
    expect(request.mock.calls[1]?.[1]?.method).toBe('PATCH')
    const body = JSON.parse(request.mock.calls[1]?.[1]?.body as string)
    expect(Object.keys(body).sort()).toEqual(['dailyCaloriesTargetKcal', 'dailyWaterTargetMl', 'endDate', 'items', 'startDate', 'title'])
    expect(body.items[0]).not.toHaveProperty('id'); expect(body.items[0]).not.toHaveProperty('nutritionPlanId')
  })

  it('reads snapshots only under their parent program and offers no historical edit', async () => {
    const current = row(); const { title, startDate, endDate, dailyCaloriesTargetKcal, dailyWaterTargetMl, items } = current
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([current]))
      .mockResolvedValueOnce(Response.json({ items: [metadata], totalCount: 1 }))
      .mockResolvedValueOnce(Response.json({ ...metadata, snapshot: { title: 'Eski sentetik başlık', startDate, endDate, dailyCaloriesTargetKcal, dailyWaterTargetMl, items } }))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Sürüm geçmişini aç' }))
    await user.click(await screen.findByRole('button', { name: 'Sürüm 1' }))
    const history = screen.getByRole('region', { name: 'Program sürüm geçmişi' })
    expect(await within(history).findByText('Sürüm 1: Eski sentetik başlık')).toBeVisible()
    expect(within(history).queryByRole('button', { name: /düzenle|kaydet/i })).not.toBeInTheDocument()
    expect(request.mock.calls[2]?.[0]).toBe(`/api/v1/nutrition-plans/${planId}/versions/${versionId}`)
    expect(screen.getByRole('heading', { name: title })).toBeVisible()
  })

  it('removes all program content and an open editor after sharing is revoked during a write', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([row()])).mockResolvedValueOnce(new Response(null, { status: 403 }))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Programı düzenle' }))
    await user.click(screen.getByRole('button', { name: 'Yeni sürüm kaydet' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('izniniz bulunmuyor')
    expect(screen.queryByText('Sentetik öğün önerisi')).not.toBeInTheDocument()
    expect(screen.queryByRole('form', { name: 'Beslenme programı formu' })).not.toBeInTheDocument()
    expect(screen.getByText('Sentetik danışan kimliği')).toBeVisible()
  })

  it('validates alternative groups in the same day and meal before sending them', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list()).mockResolvedValueOnce(Response.json(row(), { status: 201 })).mockResolvedValueOnce(list([row()]))
    const { user } = setup()
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' })); await fill()
    await user.selectOptions(screen.getByLabelText('Öğün 1 alternatif grubu'), 'new')
    await user.click(screen.getByRole('button', { name: 'Taslak oluştur' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('en az iki öneri')
    expect(request).toHaveBeenCalledTimes(1)
    await user.click(screen.getByRole('button', { name: 'Öğün önerisi ekle' }))
    fireEvent.change(screen.getByLabelText('Öğün 2 açıklaması'), { target: { value: 'Sentetik alternatif' } })
    await user.selectOptions(screen.getByLabelText('Öğün 2 alternatif grubu'), screen.getByLabelText<HTMLSelectElement>('Öğün 1 alternatif grubu').value)
    await user.selectOptions(screen.getByLabelText('Öğün 2 günü'), '1')
    await user.click(screen.getByRole('button', { name: 'Taslak oluştur' }))
    expect(request).toHaveBeenCalledTimes(1)
    await user.selectOptions(screen.getByLabelText('Öğün 2 günü'), '')
    await user.click(screen.getByRole('button', { name: 'Taslak oluştur' }))
    await screen.findByText('Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')
    const body = JSON.parse(request.mock.calls[1]?.[1]?.body as string)
    expect(body.items[0].alternativeGroupId).toBe(body.items[1].alternativeGroupId)
    expect(body.items.map((item: { sortOrder: number }) => item.sortOrder)).toEqual([0, 1])
  })

  it.each([
    { ...row(), clientId: versionId },
    { ...row(), startDate: '2026-02-30' },
    { ...row(), items: [{ ...row().items[0]!, nutritionPlanId: versionId }] },
  ])('rejects mismatched ownership and malformed server content before rendering health data', async invalid => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list([invalid]))
    setup()
    expect(await screen.findByRole('alert')).toHaveTextContent('Program yanıtı doğrulanamadı')
    expect(screen.queryByText('Sentetik öğün önerisi')).not.toBeInTheDocument()
  })

  it('blocks duplicate submissions, aborts a pending write on unmount and never automatically retries', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(list()).mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const { user, unmount } = setup()
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' })); await fill()
    const form = screen.getByRole('form', { name: 'Beslenme programı formu' })
    fireEvent.submit(form); fireEvent.submit(form)
    expect(request).toHaveBeenCalledTimes(2)
    expect(screen.getByRole('button', { name: 'Kaydediliyor…' })).toBeDisabled()
    const signal = request.mock.calls[1]?.[1]?.signal
    unmount(); expect(signal?.aborted).toBe(true)
    await act(async () => finish(Response.json(row(), { status: 201 })))
    expect(request).toHaveBeenCalledTimes(2)
  })
})

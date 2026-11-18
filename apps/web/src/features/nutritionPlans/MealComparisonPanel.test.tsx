import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { NutritionPlanPanel } from './NutritionPlanPanel'
import { MealComparisonPanel } from './MealComparisonPanel'
import { getMealComparison, localDayRange } from './mealComparisonApi'
import type { MealLogNutritionSummary, NutritionPlanMealComparisonResponse } from './mealComparisonApi'
import type { NutritionPlanResponse } from './nutritionPlanApi'

const clientId = '17514097-4a19-4376-819e-045fe3180aae'
const dietitianId = '5b74318b-678d-4bf2-9b82-6a0b3d381376'
const planId = 'c428ae15-f14c-4685-a272-69a81225c9df'
const versionId = '02c808f1-e866-40c4-8b6f-082b66fda190'
const oldVersionId = '7aa0636c-cd80-4845-9f49-3100d8354496'
const groupId = '52cd82ab-7894-43f6-8b9b-b4d6a5e37266'
const ids = ['e5a0eb64-90f3-495d-a426-f4ff9fa53ca6', 'abd76aa5-c7da-4bf1-bf1b-a4df337417ce']
const plan = (): NutritionPlanResponse => ({ id: planId, clientId, dietitianId, title: 'Sentetik program', startDate: '2026-01-01', endDate: '2026-11-18',
  dailyCaloriesTargetKcal: 1000, dailyWaterTargetMl: null, status: 'draft', createdAt: '2026-01-01T00:00:00Z', versionNumber: 2, versionId,
  items: ids.map((id, i) => ({ id, nutritionPlanId: planId, dayOfWeek: null, mealType: 'breakfast', description: `Sentetik alternatif ${i + 1}`,
    recommendedQuantity: 'Bir porsiyon', sortOrder: i, recipeId: null, alternativeGroupId: groupId })),
})
const empty = (): MealLogNutritionSummary => ({ mealLogCount: 0, itemCount: 0, estimatedItemCount: 0, caloriesKcal: { knownTotal: 0, missingItemCount: 0 },
  proteinGrams: { knownTotal: 0, missingItemCount: 0 }, carbsGrams: { knownTotal: 0, missingItemCount: 0 }, fatGrams: { knownTotal: 0, missingItemCount: 0 } })
function body(date = '2026-11-18', selected = versionId): NutritionPlanMealComparisonResponse {
  const { id: _id, clientId: _client, dietitianId: _expert, status: _status, createdAt, versionNumber: _number, versionId: _version, ...snapshot } = plan()
  const actual = { ...empty(), mealLogCount: 2, itemCount: 2, estimatedItemCount: 1, caloriesKcal: { knownTotal: 125.125, missingItemCount: 1 },
    proteinGrams: { knownTotal: 0, missingItemCount: 2 } }
  const range = localDayRange(date)
  return { clientId, nutritionPlanVersion: { id: selected, nutritionPlanId: planId, versionNumber: selected === versionId ? 2 : 1, createdAt,
    snapshot: { ...snapshot, endDate: null } }, date, from: new Date(range.from).toISOString(), to: new Date(range.to).toISOString(), actual, caloriesDifferenceKcal: null,
    meals: ['breakfast', 'lunch', 'dinner', 'snack', 'other'].map(type => ({ mealType: type as 'breakfast', plannedItems: type === 'breakfast' ? snapshot.items : [], actual: type === 'lunch' ? actual : empty() })) }
}
const versionList = () => Response.json({ items: [versionId, oldVersionId].map((id, i) => ({ id, nutritionPlanId: planId, versionNumber: 2 - i, createdAt: '2026-01-01T00:00:00Z' })), totalCount: 2 })
function comparisonFor(path: string) {
  const url = new URL(path, 'https://localhost')
  return body(url.searchParams.get('from')!.slice(0, 10), url.pathname.includes(oldVersionId) ? oldVersionId : versionId)
}
const context = () => ({ token: 'synthetic-csrf', dietitianId, onFailure: vi.fn(() => false) })
function ui(value = plan(), session = context()) {
  return <WorkspaceContext.Provider value={session}><MealComparisonPanel plan={value} onClose={vi.fn()} /></WorkspaceContext.Provider>
}
afterEach(() => vi.restoreAllMocks())

describe('canonical program comparison API', () => {
  it('requests one explicit version and local day with cookie context and validates the existing snapshot', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json(body()))
    const signal = new AbortController().signal
    const result = await getMealComparison(clientId, planId, versionId, '2026-11-18', signal)
    expect(result.actual.caloriesKcal).toEqual({ knownTotal: 125.125, missingItemCount: 1 })
    const [path, options] = request.mock.calls[0]!
    const url = new URL(String(path), 'https://localhost')
    expect(url.pathname).toBe(`/api/v1/nutrition-plans/${planId}/versions/${versionId}/meal-comparison`)
    expect(Object.fromEntries(url.searchParams)).toEqual(localDayRange('2026-11-18'))
    expect(options).toMatchObject({ credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal, headers: { 'X-Profile-Context': 'dietitian' } })
    expect(options?.body).toBeUndefined()
  })
  it.each([401, 403, 404, 422, 500])('preserves status %s without retry or synthetic fallback', async status => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(new Response(null, { status }))
    await expect(getMealComparison(clientId, planId, versionId, '2026-11-18', new AbortController().signal)).rejects.toMatchObject({ status })
    expect(request).toHaveBeenCalledTimes(1)
  })
  it.each(['client', 'version', 'date', 'bounds', 'negative', 'missingCount', 'allUnknownTotal', 'missingKey', 'extraKey', 'groups', 'planItem', 'count', 'unsafeCount', 'falseDifference', 'invalidJson'])('rejects malformed or foreign %s results', async scenario => {
    const value = body()
    if (scenario === 'client') value.clientId = dietitianId
    if (scenario === 'version') value.nutritionPlanVersion.id = oldVersionId
    if (scenario === 'date') value.date = '2026-11-17'
    if (scenario === 'bounds') value.to = value.from
    if (scenario === 'negative') value.actual.caloriesKcal.knownTotal = -1
    if (scenario === 'missingCount') value.actual.caloriesKcal.missingItemCount = 3
    if (scenario === 'allUnknownTotal') value.actual.proteinGrams.knownTotal = 12
    if (scenario === 'missingKey') Reflect.deleteProperty(value.actual, 'caloriesKcal')
    if (scenario === 'extraKey') Reflect.set(value.actual, 'adherencePercent', 100)
    if (scenario === 'groups') value.meals.pop()
    if (scenario === 'planItem') value.meals[0]!.plannedItems = [{ ...value.meals[0]!.plannedItems[0]!, description: 'Wrong snapshot' }, value.meals[0]!.plannedItems[1]!]
    if (scenario === 'count') value.actual.mealLogCount++
    if (scenario === 'unsafeCount') value.actual.itemCount = Number.MAX_SAFE_INTEGER + 1
    if (scenario === 'falseDifference') value.caloriesDifferenceKcal = -874.875
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(scenario === 'invalidJson' ? new Response('{') : Response.json(value))
    await expect(getMealComparison(clientId, planId, versionId, '2026-11-18', new AbortController().signal)).rejects.toMatchObject({ status: 500 })
  })
  it('rejects impossible dates before making a request', async () => {
    const request = vi.spyOn(globalThis, 'fetch')
    for (const date of ['', '2026-02-30', '0000-01-01', '9999-12-31', 'invalid']) {
      await expect(getMealComparison(clientId, planId, versionId, date, new AbortController().signal)).rejects.toMatchObject({ status: 400 })
    }
    expect(request).not.toHaveBeenCalled()
  })
})

describe('daily program comparison view', () => {
  it('distinguishes unknown, known partial, zero and no records and labels alternatives without a compliance score', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => String(path).includes('/meal-comparison?') ? Response.json(comparisonFor(String(path))) : versionList())
    render(ui())
    const daily = await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' })
    expect(within(daily).getByText('125,125 kcal (bilinen kısım)')).toBeVisible()
    expect(within(daily).getByText('Değer bilinmiyor')).toBeVisible()
    expect(within(daily).getAllByText('0 g')).toHaveLength(2)
    expect(within(daily).getByText('1 kalemde değer eksik')).toBeVisible()
    expect(within(daily).getByText('2 kalemde değer eksik')).toBeVisible()
    expect(within(daily).getByText(/Hesaplanamadı/)).toBeVisible()
    const breakfast = screen.getByRole('region', { name: 'Kahvaltı karşılaştırması' })
    expect(within(breakfast).getAllByText('Alternatif 1')).toHaveLength(2)
    expect(within(breakfast).getAllByText('Kayıt yok')).toHaveLength(4)
    expect(screen.getByText(/Gün sınırları:/)).toHaveTextContent('UTC')
    expect(screen.queryByText(/%/)).not.toBeInTheDocument()
  })
  it('uses the signed server difference when all calorie values are recorded', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => {
      if (!String(path).includes('/meal-comparison?')) return versionList()
      const value = comparisonFor(String(path)); value.actual.caloriesKcal = { knownTotal: 125.125, missingItemCount: 0 }; value.caloriesDifferenceKcal = -874.875
      value.meals[1]!.actual = value.actual; return Response.json(value)
    })
    render(ui()); expect(await screen.findByText('Kaydedilen enerji − program hedefi: -874,875 kcal')).toBeVisible()
  })
  it('changes explicit versions and clears results while a new date is loading, ignoring a late old response', async () => {
    let finish: ((value: Response) => void) | undefined
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => {
      const route = String(path)
      if (!route.includes('/meal-comparison?')) return versionList()
      if (new URL(route, 'https://localhost').searchParams.get('from')!.startsWith('2026-11-17')) return new Promise<Response>(resolve => { finish = resolve })
      return Response.json(comparisonFor(route))
    })
    render(ui()); await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' })
    fireEvent.change(screen.getByLabelText('Karşılaştırma günü'), { target: { value: '2026-11-17' } })
    await waitFor(() => expect(finish).toBeDefined())
    expect(screen.queryByRole('region', { name: 'Günlük kaydedilen tüketim' })).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Karşılaştırılacak sürüm'), { target: { value: oldVersionId } })
    fireEvent.change(screen.getByLabelText('Karşılaştırma günü'), { target: { value: '2026-11-18' } })
    expect(await screen.findByText('2026-11-18 · Sürüm 1')).toBeVisible()
    await act(async () => finish!(Response.json(body('2026-11-17'))))
    expect(screen.queryByText('2026-11-17 · Sürüm 2')).not.toBeInTheDocument()
    expect(screen.getByText('2026-11-18 · Sürüm 1')).toBeVisible()
  })
  it.each([403, 404])('clears health data after refresh denial %s while keeping the denial local', async status => {
    let denied = false; const session = context()
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => String(path).includes('/meal-comparison?')
      ? denied ? new Response(null, { status }) : Response.json(comparisonFor(String(path))) : versionList())
    render(ui(plan(), session)); await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' }); denied = true
    await userEvent.click(screen.getByRole('button', { name: 'Karşılaştırmayı yenile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 403 ? 'ikisi de gerekli' : 'bağlantısı sona erdi')
    expect(screen.queryByRole('region', { name: 'Günlük kaydedilen tüketim' })).not.toBeInTheDocument()
    expect(session.onFailure).not.toHaveBeenCalled()
  })
  it('rechecks permissions on focus and visibility and sends 401 to the workspace session', async () => {
    let expired = false; const session = context()
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async path => String(path).includes('/meal-comparison?')
      ? expired ? new Response(null, { status: 401 }) : Response.json(comparisonFor(String(path))) : versionList())
    render(ui(plan(), session)); await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' })
    fireEvent(window, new Event('focus')); await waitFor(() => expect(request).toHaveBeenCalledTimes(4))
    await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' }); expired = true
    fireEvent(document, new Event('visibilitychange'))
    await waitFor(() => expect(session.onFailure).toHaveBeenCalledWith(expect.objectContaining({ status: 401 })))
    expect(screen.queryByRole('region', { name: 'Günlük kaydedilen tüketim' })).not.toBeInTheDocument()
  })
  it('clears results on client and session changes even if the new request stalls', async () => {
    let pending = false
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => pending ? new Promise<Response>(() => {})
      : String(path).includes('/meal-comparison?') ? Response.json(comparisonFor(String(path))) : versionList())
    const session = context(); const view = render(ui(plan(), session)); await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' }); pending = true
    view.rerender(ui({ ...plan(), clientId: dietitianId }, session))
    expect(screen.queryByRole('region', { name: 'Günlük kaydedilen tüketim' })).not.toBeInTheDocument()
    view.rerender(ui(plan(), { ...session, token: 'new-synthetic-session' }))
    expect(screen.queryByText('125,125 kcal (bilinen kısım)')).not.toBeInTheDocument()
  })
  it('opens the comparison from the real program card without automatically reading it beforehand', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async path => String(path).includes('/meal-comparison?') ? Response.json(comparisonFor(String(path)))
      : String(path).includes('/versions?') ? versionList() : Response.json({ items: [plan()], totalCount: 1 }))
    render(<WorkspaceContext.Provider value={context()}><NutritionPlanPanel clientId={clientId} /></WorkspaceContext.Provider>)
    await screen.findByRole('button', { name: 'Program ve tüketimi karşılaştır' }); expect(request).toHaveBeenCalledTimes(1)
    await userEvent.click(screen.getByRole('button', { name: 'Program ve tüketimi karşılaştır' }))
    expect(await screen.findByRole('region', { name: 'Günlük kaydedilen tüketim' })).toBeVisible()
    await userEvent.click(screen.getByRole('button', { name: 'Karşılaştırmayı kapat' }))
    expect(screen.queryByRole('region', { name: 'Program ve tüketim karşılaştırması' })).not.toBeInTheDocument()
  })
})

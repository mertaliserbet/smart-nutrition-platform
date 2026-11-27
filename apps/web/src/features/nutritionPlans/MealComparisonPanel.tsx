import { DateField } from '../../core/components/DateField'
import { Select } from '../../core/components/Select'
import { useCallback, useEffect, useState } from 'react'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { getNutritionPlanVersions, mealLabels } from './nutritionPlanApi'
import type { NutritionPlanResponse } from './nutritionPlanApi'
import { getMealComparison, localDayRange } from './mealComparisonApi'
import type { MealLogNutritionSummary, NutritionValueSummary } from './mealComparisonApi'

const number = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 3 })
async function readable<T>(load: () => Promise<T>) {
  try { return { kind: 'ready' as const, value: await load() } }
  catch (error) {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) return { kind: 'denied' as const, message: error.message }
    throw error
  }
}
function Nutrient({ label, value, itemCount, unit }: { label: string; value: NutritionValueSummary; itemCount: number; unit: string }) {
  return <div><dt>{label}</dt><dd>{itemCount === 0 ? 'Kayıt yok' : value.missingItemCount === itemCount ? 'Değer bilinmiyor'
    : `${number.format(value.knownTotal)} ${unit}${value.missingItemCount > 0 ? ' (bilinen kısım)' : ''}`}
    {value.missingItemCount > 0 && <small>{value.missingItemCount} kalemde değer eksik</small>}</dd></div>
}
function ActualSummary({ value }: { value: MealLogNutritionSummary }) {
  return <><p>{value.mealLogCount === 0 ? 'Bu aralıkta öğün kaydı yok.' : `${value.mealLogCount} öğün kaydı · ${value.itemCount} besin kalemi`}</p>
    {value.estimatedItemCount > 0 && <p className="neutral-badge">{value.estimatedItemCount} kalem tahmini değer içeriyor</p>}
    <dl className="comparison-nutrients">
      <Nutrient label="Enerji" value={value.caloriesKcal} itemCount={value.itemCount} unit="kcal" />
      <Nutrient label="Protein" value={value.proteinGrams} itemCount={value.itemCount} unit="g" />
      <Nutrient label="Karbonhidrat" value={value.carbsGrams} itemCount={value.itemCount} unit="g" />
      <Nutrient label="Yağ" value={value.fatGrams} itemCount={value.itemCount} unit="g" />
    </dl></>
}
export function MealComparisonPanel({ plan, onClose }: { plan: NutritionPlanResponse; onClose: () => void }) {
  const session = useWorkspaceSession()
  return <ComparisonContent key={`${session.dietitianId}:${session.token}:${plan.clientId}:${plan.id}:${plan.versionId}`} plan={plan} onClose={onClose} />
}
function ComparisonContent({ plan, onClose }: { plan: NutritionPlanResponse; onClose: () => void }) {
  const [date, setDate] = useState(() => {
    const now = new Date(); const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
    return today < plan.startDate ? plan.startDate : plan.endDate && today > plan.endDate ? plan.endDate : today
  })
  const [versionId, setVersionId] = useState(plan.versionId)
  const [page, setPage] = useState(1)
  const loadVersions = useCallback((signal: AbortSignal) => readable(() => getNutritionPlanVersions(plan.id, page, signal)), [plan.id, page])
  const versions = useWorkspaceRead(loadVersions)
  const load = useCallback((signal: AbortSignal) => readable(() => getMealComparison(plan.clientId, plan.id, versionId, date, signal)), [plan.clientId, plan.id, versionId, date])
  const result = useWorkspaceRead(load)
  const refresh = result.refresh; const refreshVersions = versions.refresh
  useEffect(() => {
    const recheck = () => { if (document.visibilityState === 'visible') { refresh(); refreshVersions() } }
    window.addEventListener('focus', recheck); document.addEventListener('visibilitychange', recheck)
    return () => { window.removeEventListener('focus', recheck); document.removeEventListener('visibilitychange', recheck) }
  }, [refresh, refreshVersions])
  let boundary = ''
  try { const range = localDayRange(date); boundary = `UTC${range.from.slice(-6)} → UTC${range.to.slice(-6)}` } catch { /* The read displays the date error. */ }
  const data = result.data?.kind === 'ready' ? result.data.value : undefined
  return <section className="meal-comparison" aria-label="Program ve tüketim karşılaştırması">
    <h4>Seçilen sürümle günlük karşılaştırma</h4>
    <p>Program önerileri ve kaydedilen tüketim öğün türüne göre gösterilir. Seçilen sürümün geçmişte o gün aktif olduğu anlamına gelmez.</p>
    <div className="comparison-controls">
      <label>Karşılaştırma günü<DateField type="date" value={date} onChange={event => setDate(event.target.value)} /></label>
      <label>Karşılaştırılacak sürüm<Select value={versionId} onChange={event => setVersionId(event.target.value)}>
        <option value={plan.versionId}>Güncel sürüm {plan.versionNumber}</option>
        {versions.data?.kind === 'ready' && versions.data.value.items.filter(row => row.id !== plan.versionId).map(row => <option key={row.id} value={row.id}>Sürüm {row.versionNumber} · {new Date(row.createdAt).toLocaleString('tr-TR')}</option>)}
      </Select></label>
    </div>
    <p className="comparison-zone">Gün sınırları: {Intl.DateTimeFormat().resolvedOptions().timeZone} · {boundary || 'Geçerli gün seçin'}. Bitiş sınırı hariçtir.</p>
    {versions.pending && <p role="status">Sürüm seçenekleri okunuyor…</p>}{versions.message && <p role="alert">{versions.message}</p>}
    {versions.data?.kind === 'denied' && <p role="alert">{versions.data.message}</p>}
    {versions.data?.kind === 'ready' && versions.data.value.totalCount > 10 && <div className="expert-pagination">
      <button className="button button-secondary" disabled={page <= 1} onClick={() => { setPage(x => x - 1); setVersionId(plan.versionId) }}>Önceki karşılaştırma sürümleri</button>
      <span>Sürüm sayfası {page}</span><button className="button button-secondary" disabled={page * 10 >= versions.data.value.totalCount} onClick={() => { setPage(x => x + 1); setVersionId(plan.versionId) }}>Sonraki karşılaştırma sürümleri</button>
    </div>}
    {result.pending && <p role="status">Karşılaştırma hesaplanıyor…</p>}{result.message && <p role="alert">{result.message}</p>}
    {result.data?.kind === 'denied' && <p role="alert">{result.data.message}</p>}
    {data && <>
      <p><strong>{data.date} · Sürüm {data.nutritionPlanVersion.versionNumber}</strong> · Kaydedilme: <time dateTime={data.nutritionPlanVersion.createdAt}>{new Date(data.nutritionPlanVersion.createdAt).toLocaleString('tr-TR')}</time></p>
      <p>Seçilen sürümün tarihleri: {data.nutritionPlanVersion.snapshot.startDate} – {data.nutritionPlanVersion.snapshot.endDate ?? 'Bitiş belirtilmemiş'}</p>
      <section aria-label="Günlük kaydedilen tüketim"><h5>Günlük kaydedilen tüketim</h5><ActualSummary value={data.actual} />
        <p>Programın günlük enerji hedefi: {data.nutritionPlanVersion.snapshot.dailyCaloriesTargetKcal === null ? 'Belirtilmemiş' : `${number.format(data.nutritionPlanVersion.snapshot.dailyCaloriesTargetKcal)} kcal`}</p>
        <p>Kaydedilen enerji − program hedefi: {data.caloriesDifferenceKcal === null ? 'Hesaplanamadı; tam kalori kaydı ve program hedefi gerekir.' : `${number.format(data.caloriesDifferenceKcal)} kcal`}</p>
      </section>
      <div className="comparison-meals">{data.meals.map(meal => <section key={meal.mealType} aria-label={`${mealLabels[meal.mealType]} karşılaştırması`}>
        <h5>{mealLabels[meal.mealType]}</h5><div className="comparison-columns"><div><h6>Planlanan</h6>
          {meal.plannedItems.length === 0 ? <p>Bu öğün için öneri yok.</p> : <ul>{meal.plannedItems.map(item => {
            const groups = [...new Set(meal.plannedItems.flatMap(row => row.alternativeGroupId ? [row.alternativeGroupId] : []))]
            return <li key={item.id}><p className="plan-description">{item.description}</p><p>Miktar: {item.recommendedQuantity ?? 'Belirtilmemiş'}</p>
              {item.alternativeGroupId && <span className="neutral-badge">Alternatif {groups.indexOf(item.alternativeGroupId) + 1}</span>}</li>
          })}</ul>}
          {meal.plannedItems.some(item => item.alternativeGroupId) && <p>Aynı gruptaki öneriler birbirinin seçeneğidir; birlikte tüketim zorunluluğu oluşturmaz.</p>}
        </div><div><h6>Kaydedilen</h6><ActualSummary value={meal.actual} /></div></div>
      </section>)}</div>
      <p>Özetler seçilen gündeki tüm silinmemiş kayıtlardan hesaplanır. Besin ayrıntıları öğün günlüğündedir. Kayıt olmaması tüketim yapılmadığını göstermez.</p>
    </>}
    <div className="expert-pagination"><button className="button button-secondary" disabled={result.pending} onClick={() => { refresh(); refreshVersions() }}>Karşılaştırmayı yenile</button>
      <button className="button button-secondary" onClick={onClose}>Karşılaştırmayı kapat</button></div>
  </section>
}

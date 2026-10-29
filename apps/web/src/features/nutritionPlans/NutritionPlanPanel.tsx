import { useCallback, useEffect, useRef, useState } from 'react'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { NutritionPlanEditor } from './NutritionPlanEditor'
import { changeNutritionPlan, getNutritionPlans, getNutritionPlanVersion, getNutritionPlanVersions, mealLabels, saveNutritionPlan } from './nutritionPlanApi'
import type { NutritionPlanResponse, NutritionPlanSnapshot, PlanContentRequest } from './nutritionPlanApi'
import './nutritionPlans.css'

const statusLabels = { draft: 'Taslak', active: 'Aktif', archived: 'Arşiv' }
const dayLabels = ['Her gün', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
function ProgramContent({ value }: { value: NutritionPlanSnapshot }) {
  const groups = [...new Set(value.items.flatMap(row => row.alternativeGroupId ? [row.alternativeGroupId] : []))]
  return <div className="nutrition-content">
    <p>Başlangıç: <time dateTime={value.startDate}>{value.startDate}</time>{value.endDate && <> · Bitiş: <time dateTime={value.endDate}>{value.endDate}</time></>}</p>
    <dl className="plan-targets"><dt>Günlük enerji hedefi</dt><dd>{value.dailyCaloriesTargetKcal === null ? 'Belirtilmemiş' : `${value.dailyCaloriesTargetKcal} kcal`}</dd>
      <dt>Günlük su hedefi</dt><dd>{value.dailyWaterTargetMl === null ? 'Belirtilmemiş' : `${value.dailyWaterTargetMl} mL`}</dd></dl>
    <ol className="plan-meals">{value.items.map(item => <li key={item.id}><h4>{dayLabels[item.dayOfWeek ?? 0]} · {mealLabels[item.mealType]}</h4>
      <p className="plan-description">{item.description}</p><p>Miktar önerisi: {item.recommendedQuantity ?? 'Belirtilmemiş'}</p>
      {item.alternativeGroupId && <p className="neutral-badge">Alternatif {groups.indexOf(item.alternativeGroupId) + 1}</p>}
    </li>)}</ol>
    {groups.length > 0 && <p>Aynı gruptaki öneriler birbirinin alternatifidir; birlikte tüketim zorunluluğu oluşturmaz.</p>}
  </div>
}

function ProgramHistory({ planId, handleDenied, onClose }: { planId: string; handleDenied: (error: unknown) => boolean; onClose: () => void }) {
  const [page, setPage] = useState(1); const [selected, setSelected] = useState<string>()
  const load = useCallback((signal: AbortSignal) => getNutritionPlanVersions(planId, page, signal), [planId, page])
  const list = useWorkspaceRead(load, handleDenied)
  const loadVersion = useCallback((signal: AbortSignal) => selected ? getNutritionPlanVersion(planId, selected, signal) : Promise.resolve(undefined), [planId, selected])
  const version = useWorkspaceRead(loadVersion, handleDenied)
  return <section className="card nutrition-history" aria-label="Program sürüm geçmişi"><h3>Sürüm geçmişi</h3>
    {list.pending && <p role="status">Sürümler okunuyor…</p>}{list.message && <p role="alert">{list.message}</p>}
    {list.data && <><ul>{list.data.items.map(row => <li key={row.id}><button className="text-link" type="button" onClick={() => setSelected(row.id)}>Sürüm {row.versionNumber}</button> · <time dateTime={row.createdAt}>{new Date(row.createdAt).toLocaleString('tr-TR')}</time></li>)}</ul>
      <div className="expert-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki sürümler sayfası</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={page * 10 >= list.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki sürümler sayfası</button></div></>}
    {selected && version.pending && <p role="status">Geçmiş içerik okunuyor…</p>}{version.message && <p role="alert">{version.message}</p>}
    {version.data && <article><h4>Sürüm {version.data.versionNumber}: {version.data.snapshot.title}</h4><p>Geçmiş içerik · Salt okunur</p><ProgramContent value={version.data.snapshot} /></article>}
    <button className="button button-secondary" type="button" onClick={onClose}>Geçmişi kapat</button>
  </section>
}

export function NutritionPlanPanel({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  const [page, setPage] = useState(1); const [editorId, setEditorId] = useState<string>(); const [historyId, setHistoryId] = useState<string>()
  const [busy, setBusy] = useState(false); const [message, setMessage] = useState(''); const [notice, setNotice] = useState(''); const [denied, setDenied] = useState('')
  const operation = useRef<AbortController | null>(null)
  const handleDenied = useCallback((error: unknown) => {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) {
      setDenied(error.message); setEditorId(undefined); setHistoryId(undefined); setNotice(''); return true
    }
    return false
  }, [])
  const load = useCallback((signal: AbortSignal) => getNutritionPlans(clientId, page, signal), [clientId, page])
  const state = useWorkspaceRead(load, handleDenied)
  useEffect(() => () => operation.current?.abort(), [])

  async function mutate(action: 'save' | 'activate' | 'archive', plan?: NutritionPlanResponse, content?: PlanContentRequest) {
    if (operation.current || state.pending || denied) return
    const controller = new AbortController(); operation.current = controller; setBusy(true); setMessage(''); setNotice('')
    try {
      const result = action === 'save' ? await saveNutritionPlan(clientId, content!, session.token, controller.signal, plan)
        : await changeNutritionPlan(clientId, plan!.id, action, session.token, controller.signal)
      if (result.dietitianId !== session.dietitianId) throw new WebSessionError(500, 'Program sahipliği doğrulanamadı.')
      if (!controller.signal.aborted) {
        setEditorId(undefined); setHistoryId(undefined)
        setNotice(action === 'save' ? (plan ? 'Yeni program sürümü kaydedildi.' : 'Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')
          : action === 'activate' ? 'Beslenme programı etkinleştirildi ve danışana atandı.' : 'Beslenme programı arşivlendi.')
        state.refresh()
      }
    } catch (error) {
      if (!controller.signal.aborted && !handleDenied(error) && !session.onFailure(error)) setMessage(error instanceof WebSessionError ? error.message : 'Program işlemi doğrulanamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setBusy(false) } }
  }
  function refresh() { setDenied(''); setMessage(''); setEditorId(undefined); setHistoryId(undefined); state.refresh() }
  const editing = state.data?.items.find(plan => plan.id === editorId && plan.dietitianId === session.dietitianId)
  return <section className="nutrition-panel" aria-label="Beslenme programları"><div className="page-heading"><h2>Beslenme programları</h2><p>Program önerileri ve gerçek tüketim kayıtları ayrı tutulur.</p></div>
    {denied ? <p className="form-message" role="alert">{denied}</p> : <>
      {state.pending && <p role="status">Programlar okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}{message && <p role="alert">{message}</p>}{notice && <p role="status">{notice}</p>}
      {state.data && <><button className="button button-primary" disabled={busy || state.pending} onClick={() => { setEditorId('new'); setHistoryId(undefined); setMessage(''); setNotice('') }}>Yeni program oluştur</button>
        {(editorId === 'new' || editing) && <NutritionPlanEditor key={editorId} initial={editing} busy={busy} onCancel={() => setEditorId(undefined)} onSave={content => mutate('save', editing, content)} />}
        {state.data.totalCount === 0 && <p>Bu danışanın kayıtlı beslenme programı bulunmuyor.</p>}
        {state.data.items.map(plan => <article className="card nutrition-card" key={plan.id} aria-labelledby={`plan-heading-${plan.id}`}><header className="card-header"><div><h3 id={`plan-heading-${plan.id}`}>{plan.title}</h3><p>{statusLabels[plan.status]} · Sürüm {plan.versionNumber}</p></div><span className="neutral-badge">{plan.dietitianId === null ? 'Kişisel program · Salt okunur' : plan.dietitianId === session.dietitianId ? 'Atadığınız program' : 'Başka diyetisyenin programı · Salt okunur'}</span></header>
          <ProgramContent value={plan} /><div className="expert-pagination">
            {plan.dietitianId === session.dietitianId && <><button className="button button-secondary" disabled={busy} onClick={() => { setEditorId(plan.id); setHistoryId(undefined); setMessage(''); setNotice('') }}>Programı düzenle</button>
              {plan.status !== 'active' && <button className="button button-primary" disabled={busy} onClick={() => { void mutate('activate', plan) }}>Programı etkinleştir</button>}
              {plan.status !== 'archived' && <button className="button button-secondary" disabled={busy} onClick={() => { void mutate('archive', plan) }}>Programı arşivle</button>}</>}
            <button className="button button-secondary" disabled={busy} onClick={() => { setHistoryId(plan.id); setEditorId(undefined) }}>Sürüm geçmişini aç</button>
          </div>
        </article>)}
        <div className="expert-pagination"><button className="button button-secondary" disabled={busy || page <= 1} onClick={() => { setPage(value => value - 1); setEditorId(undefined); setHistoryId(undefined) }}>Önceki programlar sayfası</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={busy || page * 10 >= state.data.totalCount} onClick={() => { setPage(value => value + 1); setEditorId(undefined); setHistoryId(undefined) }}>Sonraki programlar sayfası</button></div>
        {historyId && <ProgramHistory key={historyId} planId={historyId} handleDenied={handleDenied} onClose={() => setHistoryId(undefined)} />}
      </>}
    </>}
    <button className="button button-secondary" disabled={busy || state.pending} onClick={refresh}>Programları yeniden kontrol et</button>
  </section>
}

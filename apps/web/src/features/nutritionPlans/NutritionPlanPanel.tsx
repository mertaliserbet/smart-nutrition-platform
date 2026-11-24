import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { NutritionPlanEditor } from './NutritionPlanEditor'
import { MealComparisonPanel } from './MealComparisonPanel'
import { changeNutritionPlan, getNutritionPlans, getNutritionPlanVersion, getNutritionPlanVersions, mealLabels, saveNutritionPlan } from './nutritionPlanApi'
import type { NutritionPlanResponse, NutritionPlanSnapshot, PlanContentRequest } from './nutritionPlanApi'
import { PlanCopyPicker } from './PlanCopyPicker'
import { PlanConfirmation } from './PlanConfirmation'
import { reusablePlanDraft } from './planDraft'
import type { PlanDraft } from './planDraft'
import { usePlanNavigation } from './usePlanNavigation'
import { getNutritionPlan } from './nutritionPlanApi'
import './nutritionPlans.css'
import { Icon } from '../../core/components/Icon'

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

type PanelProps = { clientId: string; clientName?: string; active?: boolean; onReturnToEditor?: () => void; compact?: boolean; onDirtyChange?: (dirty: boolean) => void; onBusyChange?: (busy: boolean) => void }
export function NutritionPlanPanel({ clientId, clientName, active = true, onReturnToEditor, compact = false, onDirtyChange, onBusyChange }: PanelProps) {
  const session = useWorkspaceSession()
  return <PlanPanel key={`${session.dietitianId}:${session.token}:${clientId}`} clientId={clientId} clientName={clientName} active={active} onReturnToEditor={onReturnToEditor} compact={compact} onDirtyChange={onDirtyChange} onBusyChange={onBusyChange} />
}
function PlanPanel({ clientId, clientName, active, onReturnToEditor, compact, onDirtyChange, onBusyChange }: PanelProps & { active: boolean }) {
  const session = useWorkspaceSession()
  const [page, setPage] = useState(1); const [historyId, setHistoryId] = useState<string>()
  const [editor, setEditor] = useState<{ key: string; initial?: NutritionPlanResponse; seed?: PlanDraft; source?: { id: string; clientId: string } }>()
  const [dirty, setDirty] = useState(false), [picker, setPicker] = useState(false)
  useEffect(() => { onDirtyChange?.(dirty); return () => onDirtyChange?.(false) }, [dirty, onDirtyChange])
  const editorTrigger = useRef<HTMLElement | null>(null)
  const createButton = useRef<HTMLButtonElement>(null)
  const restoreEditorFocus = useRef(false)
  const [confirmation, setConfirmation] = useState<{ title: string; body: string; label: string; run: () => void }>()
  const guard = useCallback((run: () => void) => {
    setConfirmation({ title: 'Kaydedilmemiş değişiklikler', body: 'Bu taslaktaki değişiklikler silinecek. Düzenlemeye dönebilir veya değişiklikleri silebilirsiniz.', label: 'Değişiklikleri sil', run })
  }, [])
  usePlanNavigation(dirty, guard)
  function replaceEditor(run: () => void) { if (dirty) guard(run); else run() }
  function closeEditor() { setEditor(undefined); setDirty(false) }
  function cancelEditor() {
    restoreEditorFocus.current = true
    closeEditor()
  }
  function openEditor(initial?: NutritionPlanResponse, source?: NutritionPlanResponse, trigger?: HTMLButtonElement) {
    editorTrigger.current = trigger ?? createButton.current
    setEditor({ key: crypto.randomUUID(), initial, ...(source ? { seed: reusablePlanDraft(source), source: { id: source.id, clientId: source.clientId } } : {}) }); setDirty(!!source); setPicker(false); setMessage(''); setNotice('')
  }
  const [comparisonId, setComparisonId] = useState<string>()
  const [busy, setBusy] = useState(false); const [message, setMessage] = useState(''); const [notice, setNotice] = useState(''); const [denied, setDenied] = useState('')
  useEffect(() => { onBusyChange?.(busy); return () => onBusyChange?.(false) }, [busy, onBusyChange])
  const operation = useRef<AbortController | null>(null)
  const handleDenied = useCallback((error: unknown) => {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) {
      setDenied(error.message); setEditor(undefined); setDirty(false); setPicker(false); setConfirmation(undefined); setHistoryId(undefined); setNotice(''); return true
    }
    return false
  }, [setDenied, setEditor, setDirty, setPicker, setConfirmation, setHistoryId, setNotice])
  const load = useCallback((signal: AbortSignal) => getNutritionPlans(clientId, page, signal), [clientId, page])
  const state = useWorkspaceRead(load, handleDenied)
  useLayoutEffect(() => {
    if (editor || confirmation || !restoreEditorFocus.current || state.pending) return
    restoreEditorFocus.current = false
    const target = editorTrigger.current?.isConnected ? editorTrigger.current : createButton.current
    target?.focus()
  }, [editor, confirmation, state.pending])
  useEffect(() => () => operation.current?.abort(), [])
  const sourceId = editor?.source?.id, sourceClientId = editor?.source?.clientId
  useEffect(() => {
    if (!sourceId || !sourceClientId || !active) return
    let check: AbortController | undefined
    const recheck = async () => {
      if (document.visibilityState !== 'visible' || check) return
      const controller = new AbortController(); check = controller
      try {
        const source = await getNutritionPlan(sourceClientId, sourceId, controller.signal)
        if (source.dietitianId !== session.dietitianId) throw new WebSessionError(403, 'Kaynak sahipliği değişti.')
      } catch (error) {
        if (controller.signal.aborted) return
        if (error instanceof WebSessionError && [403, 404].includes(error.status)) {
          operation.current?.abort(); operation.current = null; setBusy(false)
          setEditor(undefined); setDirty(false); setConfirmation(undefined)
          setMessage('Kaynak erişimi sona erdi. Kopyalanan taslak kaldırıldı; kayıt yapılmadı.')
        } else session.onFailure(error)
      } finally { if (check === controller) check = undefined }
    }
    const visible = () => { void recheck() }
    const timer = window.setInterval(visible, 30_000)
    window.addEventListener('focus', visible); document.addEventListener('visibilitychange', visible)
    return () => { check?.abort(); window.clearInterval(timer); window.removeEventListener('focus', visible); document.removeEventListener('visibilitychange', visible) }
  }, [sourceId, sourceClientId, active, session])
  const { revalidate } = state
  useEffect(() => {
    if (!active) return
    const visible = () => { if (document.visibilityState === 'visible' && !operation.current) revalidate() }
    visible()
    window.addEventListener('focus', visible)
    return () => window.removeEventListener('focus', visible)
  }, [active, revalidate])

  async function mutate(action: 'save' | 'activate' | 'archive', plan?: NutritionPlanResponse, content?: PlanContentRequest) {
    if (operation.current || state.pending || denied) return
    const controller = new AbortController(); operation.current = controller; setBusy(true); setPicker(false); setMessage(''); setNotice('')
    try {
      if (action === 'save' && editor?.source) {
        try {
          const source = await getNutritionPlan(editor.source.clientId, editor.source.id, controller.signal)
          if (source.dietitianId !== session.dietitianId) throw new WebSessionError(403, 'Kaynak program artık size ait değil.')
        } catch (error) {
          if (!controller.signal.aborted && error instanceof WebSessionError && [403, 404].includes(error.status)) { closeEditor(); setMessage('Kaynak erişimi sona erdi. Kopyalanan taslak kaldırıldı; kayıt yapılmadı.'); return }
          throw error
        }
      }
      if (controller.signal.aborted) return
      const result = action === 'save' ? await saveNutritionPlan(clientId, content!, session.token, controller.signal, plan)
        : await changeNutritionPlan(clientId, plan!.id, action, session.token, controller.signal)
      if (result.dietitianId !== session.dietitianId) throw new WebSessionError(500, 'Program sahipliği doğrulanamadı.')
      if (!controller.signal.aborted) {
        if (action === 'save') closeEditor()
        setHistoryId(undefined)
        setNotice(action === 'save' ? (plan ? 'Yeni program sürümü kaydedildi.' : 'Taslak kaydedildi. Danışana atamak için programı etkinleştirin.')
          : action === 'activate' ? 'Beslenme programı etkinleştirildi ve danışana atandı.' : 'Beslenme programı arşivlendi.')
        state.refresh()
      }
    } catch (error) {
      if (!controller.signal.aborted && !handleDenied(error) && !session.onFailure(error)) setMessage(error instanceof WebSessionError ? error.message : 'Program işlemi doğrulanamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setBusy(false) } }
  }
  function refresh() { setDenied(''); setMessage(''); state.refresh() }
  function confirmStatus(action: 'activate' | 'archive', plan: NutritionPlanResponse) {
    setConfirmation({ title: action === 'activate' ? 'Programı etkinleştir ve ata' : 'Programı arşivle',
      body: `“${plan.title}” ${action === 'activate' ? 'etkinleştirilecek ve bu danışana atanacak. Başka bir aktif program varsa işlem yapılmaz; mevcut program otomatik arşivlenmez.' : 'arşivlenecek. Başka bir program otomatik etkinleştirilmeyecek.'}`,
      label: action === 'activate' ? 'Onayla ve etkinleştir' : 'Onayla ve arşivle', run: () => { void mutate(action, plan) } })
  }
  return <section className={`nutrition-panel${compact ? ' compact-program-panel' : ''}`} aria-label="Beslenme programları"><div className="page-heading"><h2>Beslenme programları</h2><p>Program önerileri ve gerçek tüketim kayıtları ayrı tutulur.</p></div>
    {denied ? <p className="form-message" role="alert">{denied}</p> : <>
      {state.pending && <p role="status">Programlar okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}{message && <p role="alert">{message}</p>}{notice && <p role="status">{notice}</p>}
      {state.data && <div className="expert-pagination program-page-actions">{compact && <span className="program-page-label">Danışanın programları</span>}<button ref={createButton} className="button button-primary" disabled={busy || state.pending} onClick={event => { const trigger = event.currentTarget; replaceEditor(() => openEditor(undefined, undefined, trigger)) }}>Yeni program oluştur</button>
        <button className="button button-secondary" disabled={busy || state.pending} onClick={() => setPicker(true)}>Kendi programımdan kopyala</button></div>}
      {picker && <PlanCopyPicker onCopy={source => replaceEditor(() => openEditor(undefined, source))} onCancel={() => setPicker(false)} />}
      {editor && <NutritionPlanEditor key={editor.key} initial={editor.initial} seed={editor.seed} clientName={clientName} compact={compact} busy={busy} onDirtyChange={setDirty} onCancel={() => replaceEditor(cancelEditor)} onSave={content => mutate('save', editor.initial, content)} />}
      {state.data && <>
        {state.data.totalCount === 0 && <p>Bu danışanın kayıtlı beslenme programı bulunmuyor.</p>}
        <div className="nutrition-programs-grid">{state.data.items.map(plan => <article className="card nutrition-card" key={plan.id} aria-labelledby={`plan-heading-${plan.id}`}><header className="card-header">{compact && <span className="program-card-icon"><Icon name="plan" /></span>}<div><h3 id={`plan-heading-${plan.id}`}>{plan.title}</h3><p>{statusLabels[plan.status]} · Sürüm {plan.versionNumber}</p></div><span className="neutral-badge">{plan.dietitianId === null ? 'Kişisel program · Salt okunur' : plan.dietitianId === session.dietitianId ? 'Atadığınız program' : 'Başka diyetisyenin programı · Salt okunur'}</span></header>
          {compact ? <><div className="program-card-summary"><p><Icon name="chart" />Günlük hedef: <strong>{plan.dailyCaloriesTargetKcal === null ? 'Belirtilmemiş' : `${plan.dailyCaloriesTargetKcal} kcal`}</strong></p><small><Icon name="meal" />{plan.items.length} öğün önerisi · {plan.startDate}</small></div></> : <ProgramContent value={plan} />}<div className="expert-pagination">
            {plan.dietitianId === session.dietitianId && <><button className="button button-secondary" disabled={busy} onClick={event => { const trigger = event.currentTarget; replaceEditor(() => openEditor(plan, undefined, trigger)) }} aria-label="Programı düzenle">{compact ? 'Düzenle' : 'Programı düzenle'}</button>
              {plan.status !== 'active' && <button className="button button-primary" disabled={busy} onClick={() => { confirmStatus('activate', plan) }} aria-label="Programı etkinleştir">{compact ? 'Danışana ata' : 'Programı etkinleştir'}</button>}
              </>}
          </div><details className="program-content-disclosure"><summary aria-label={`${plan.title} ayrıntıları ve diğer işlemler`}>Ayrıntılar ve diğer işlemler</summary><div className="program-more-content"><ProgramContent value={plan} /><div className="expert-pagination">
            {plan.dietitianId === session.dietitianId && plan.status !== 'archived' && <button className="button button-secondary" disabled={busy} onClick={() => { confirmStatus('archive', plan) }}>Programı arşivle</button>}
            <button className="button button-secondary" disabled={busy} onClick={() => { setHistoryId(plan.id) }}>Sürüm geçmişini aç</button><button className="button button-secondary" disabled={busy} onClick={() => setComparisonId(plan.id)}>Program ve tüketimi karşılaştır</button></div></div></details>
          {comparisonId === plan.id && <MealComparisonPanel plan={plan} onClose={() => setComparisonId(undefined)} />}
        </article>)}</div>
        <nav className="expert-pagination nutrition-pagination" aria-label="Beslenme programı sayfaları"><button className="button button-secondary" disabled={busy || page <= 1} onClick={() => { setPage(value => value - 1); setHistoryId(undefined) }}>Önceki programlar sayfası</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={busy || page * 10 >= state.data.totalCount} onClick={() => { setPage(value => value + 1); setHistoryId(undefined) }}>Sonraki programlar sayfası</button></nav>
        {historyId && <ProgramHistory key={historyId} planId={historyId} handleDenied={handleDenied} onClose={() => setHistoryId(undefined)} />}
      </>}
    </>}
    {confirmation && <PlanConfirmation title={confirmation.title} confirmLabel={confirmation.label} onCancel={() => { setConfirmation(undefined); if (confirmation.label === 'Değişiklikleri sil') { onReturnToEditor?.(); requestAnimationFrame(() => document.getElementById('plan-title')?.focus({ preventScroll: true })) } }} onConfirm={() => { const run = confirmation.run; setConfirmation(undefined); run() }}><p>{confirmation.body}</p></PlanConfirmation>}
    <div className="nutrition-refresh-actions"><button className="button button-secondary" disabled={busy || state.pending} onClick={refresh}>Programları yeniden kontrol et</button></div>
  </section>
}

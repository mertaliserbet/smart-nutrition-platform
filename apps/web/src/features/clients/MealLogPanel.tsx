import { useCallback, useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { MealLogList } from './ClientRecordViews'
import { getMealLogs } from './mealLogApi'
import { MealLogComments } from './MealLogComments'
import { mealDateRange, mealPeriodRange } from './mealDateRange'
import type { MealPeriod } from './mealDateRange'
import './clientTracking.css'

export function MealLogPanel({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  return <MealLogContent key={`${session.dietitianId}:${session.token}:${clientId}`} clientId={clientId} />
}

function MealLogContent({ clientId }: { clientId: string }) {
  const [range, setRange] = useState<{ from?: string; to?: string }>({})
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const [preset, setPreset] = useState<MealPeriod | 'custom' | ''>('')
  const [first, setFirst] = useState(''), [last, setLast] = useState('')
  const [accessError, setAccessError] = useState('')
  const denied = useCallback((error: WebSessionError) => setAccessError(error.message), [])
  const load = useCallback(async (signal: AbortSignal) => {
    try { return { kind: 'ready' as const, ...await getMealLogs(clientId, page, range, signal) } }
    catch (error) {
      // Sharing denial is local to meals; nutrition-plan permission is independent.
      if (error instanceof WebSessionError && (error.status === 403 || error.status === 404))
        return { kind: 'denied' as const, message: error.message }
      throw error
    }
  }, [clientId, page, range])
  const state = useWorkspaceRead(load)
  const refresh = state.refresh
  useEffect(() => {
    const recheck = () => { if (document.visibilityState === 'visible') refresh() }
    window.addEventListener('focus', recheck)
    document.addEventListener('visibilitychange', recheck)
    return () => { window.removeEventListener('focus', recheck); document.removeEventListener('visibilitychange', recheck) }
  }, [refresh])

  function applyFilter(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    try { setRange(mealDateRange(first, last)); setPage(1); setError(''); setAccessError('') }
    catch (error) { setError(error instanceof Error ? error.message : 'Tarihleri kontrol edin.') }
  }
  function selectPeriod(period: MealPeriod) {
    try { setRange(mealPeriodRange(period)); setPreset(period); setPage(1); setError(''); setAccessError('') }
    catch (error) { setError(error instanceof Error ? error.message : 'Tarihleri kontrol edin.') }
  }

  return <section className="card" aria-label="Öğün günlüğü">
    <header className="card-header"><div><h2>Öğün günlüğü</h2><p>Danışanın açık paylaşım izniyle görüntülenen tüketim kayıtları.</p></div><span className="neutral-badge">Salt okunur</span></header>
    <div className="meal-date-controls">
    <div className="meal-date-presets" role="group" aria-label="Öğün tarih aralığı">
      {([['today', 'Bugün'], ['yesterday', 'Dün'], ['week', 'Son 7 gün']] as const).map(([value, label]) => <button key={value} className="button button-secondary" aria-pressed={preset === value} onClick={() => selectPeriod(value)}>{label}</button>)}
      <button className="button button-secondary" aria-pressed={preset === 'custom'} onClick={() => setPreset('custom')}>Özel aralık</button>
    </div>
    <p id="meal-log-time-zone">Tarihler ve kayıt saatleri cihazınızın saat dilimindedir: {Intl.DateTimeFormat().resolvedOptions().timeZone}. Seçilen ilk ve son gün dahil; ertesi günün başlangıcı hariçtir.</p>
    {preset === 'custom' && <form className="meal-preview-filters" aria-label="Öğün tarihi filtresi" onSubmit={applyFilter} noValidate>
      <label>Başlangıç<input name="from" type="date" value={first} onChange={event => setFirst(event.target.value)} aria-describedby="meal-log-time-zone" /></label>
      <label>Bitiş<input name="to" type="date" value={last} onChange={event => setLast(event.target.value)} aria-describedby="meal-log-time-zone" /></label>
      <button className="button button-primary" type="submit">Filtrele</button>
    </form>}
    <button className="button button-secondary" onClick={() => { setError(''); setAccessError(''); setPage(1); setRange({}); setFirst(''); setLast(''); setPreset('') }}>Filtreyi temizle</button>
    {error && <p role="alert">{error}</p>}
    </div>
    {state.pending && <p className="panel-feedback" role="status">Öğünler okunuyor…</p>}
    {state.message && <p className="panel-feedback error-message" role="alert">{state.message}</p>}
    {accessError && <p className="panel-feedback error-message" role="alert">{accessError}</p>}
    {state.data?.kind === 'denied' && <p className="panel-feedback" role="alert">{state.data.message}</p>}
    {state.data?.kind === 'ready' && !accessError && <>
      {state.data.items.length === 0
        ? <EmptyState icon="leaf" title={range.from || range.to ? 'Bu aralıkta öğün kaydı yok' : 'Henüz öğün kaydı yok'}>Başka bir tarih aralığı seçebilir veya öğünleri yenileyebilirsiniz.</EmptyState>
        : <MealLogList clientId={clientId} records={state.data.items} renderComments={meal => <MealLogComments mealLogId={meal.id} onAccessDenied={denied} />} />}
      <div className="meal-preview-pagination">
        <button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki öğün sayfası</button>
        <p role="status">{state.data.totalCount} öğün · Sayfa {page}</p>
        <button className="button button-secondary" disabled={page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki öğün sayfası</button>
      </div>
    </>}
    <div className="panel-actions"><button className="button button-secondary" disabled={state.pending} onClick={() => { setAccessError(''); refresh() }}>Öğünleri yenile</button></div>
  </section>
}

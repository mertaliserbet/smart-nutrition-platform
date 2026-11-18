import { useCallback, useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { MealLogList } from './ClientRecordViews'
import { getMealLogs } from './mealLogApi'
import './clientTracking.css'

export function MealLogPanel({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  return <MealLogContent key={`${session.dietitianId}:${session.token}:${clientId}`} clientId={clientId} />
}

function MealLogContent({ clientId }: { clientId: string }) {
  const [range, setRange] = useState<{ from?: string; to?: string }>({})
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
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
    const data = new FormData(event.currentTarget)
    const from = data.get('from') ? new Date(`${data.get('from')}Z`) : undefined
    const to = data.get('to') ? new Date(`${data.get('to')}Z`) : undefined
    if ((from && !Number.isFinite(from.getTime())) || (to && !Number.isFinite(to.getTime())) || (from && to && from >= to)) {
      setError('Bitiş tarihi ve saati başlangıçtan sonra olmalı.'); return
    }
    setError(''); setPage(1); setRange({ from: from?.toISOString(), to: to?.toISOString() })
  }

  return <section className="card" aria-label="Öğün günlüğü">
    <header className="card-header"><div><h2>Öğün günlüğü</h2><p>Danışanın açık paylaşım izniyle görüntülenen tüketim kayıtları.</p></div><span className="neutral-badge">Salt okunur</span></header>
    <form className="meal-preview-filters" aria-label="Öğün tarihi filtresi" onSubmit={applyFilter}
      onReset={() => { setError(''); setPage(1); setRange({}) }}>
      <p id="meal-log-time-zone">Filtre saatleri UTC (UTC+00:00). Kayıt saatleri cihazın saat diliminde gösterilir.</p>
      <label>Başlangıç<input name="from" type="datetime-local" step="1" aria-describedby="meal-log-time-zone" /></label>
      <label>Bitiş<input name="to" type="datetime-local" step="1" aria-describedby="meal-log-time-zone" /></label>
      <div className="meal-preview-actions"><button className="button button-primary" type="submit">Filtrele</button>
        <button className="button button-secondary" type="reset">Filtreyi temizle</button></div>
      {error && <p role="alert">{error}</p>}
    </form>
    {state.pending && <p className="panel-feedback" role="status">Öğünler okunuyor…</p>}
    {state.message && <p className="panel-feedback error-message" role="alert">{state.message}</p>}
    {state.data?.kind === 'denied' && <p className="panel-feedback" role="alert">{state.data.message}</p>}
    {state.data?.kind === 'ready' && <>
      {state.data.items.length === 0
        ? <EmptyState icon="leaf" title={range.from || range.to ? 'Bu aralıkta öğün kaydı yok' : 'Henüz öğün kaydı yok'}>Başka bir tarih aralığı seçebilir veya öğünleri yenileyebilirsiniz.</EmptyState>
        : <MealLogList clientId={clientId} records={state.data.items} />}
      <div className="meal-preview-pagination">
        <button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki öğün sayfası</button>
        <p role="status">{state.data.totalCount} öğün · Sayfa {page}</p>
        <button className="button button-secondary" disabled={page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki öğün sayfası</button>
      </div>
    </>}
    <div className="panel-actions"><button className="button button-secondary" disabled={state.pending} onClick={refresh}>Öğünleri yenile</button></div>
  </section>
}

import { useCallback, useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { BodyMeasurementList } from './ClientRecordViews'
import { getBodyMeasurementHistory, getBodyMeasurements } from './bodyMeasurementApi'
import { BodyMeasurementCharts } from './BodyMeasurementCharts'
import './clientTracking.css'

export function BodyMeasurementPanel({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  return <BodyMeasurementContent key={`${session.dietitianId}:${session.token}:${clientId}`} clientId={clientId} />
}

function BodyMeasurementContent({ clientId }: { clientId: string }) {
  const [range, setRange] = useState<{ from?: string; to?: string }>({})
  const [fromInput, setFromInput] = useState('')
  const [toInput, setToInput] = useState('')
  const [page, setPage] = useState(1)
  const [error, setError] = useState('')
  const load = useCallback(async (signal: AbortSignal) => {
    if (document.visibilityState !== 'visible') return { kind: 'hidden' as const }
    try {
      const result = await getBodyMeasurements(clientId, page, range, signal)
      const history = page === 1 && result.items.length === result.totalCount
        ? result.items
        : await getBodyMeasurementHistory(clientId, range, signal, result.totalCount)
      return { kind: 'ready' as const, ...result, history }
    }
    catch (error) {
      if (error instanceof WebSessionError && [403, 404].includes(error.status)) return { kind: 'denied' as const, message: error.message }
      throw error
    }
  }, [clientId, page, range])
  const state = useWorkspaceRead(load)
  const refresh = state.refresh
  const refreshRef = useRef(refresh)
  useEffect(() => { refreshRef.current = refresh }, [refresh])
  useEffect(() => {
    const invalidate = () => refreshRef.current()
    const recheck = () => { if (document.visibilityState === 'visible') invalidate() }
    // No push contract exists: revalidate visible data periodically and on return.
    const timer = window.setInterval(recheck, 30_000)
    window.addEventListener('focus', recheck)
    document.addEventListener('visibilitychange', invalidate)
    return () => { window.clearInterval(timer); window.removeEventListener('focus', recheck); document.removeEventListener('visibilitychange', invalidate) }
  }, [])

  function applyFilter(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const from = fromInput ? new Date(`${fromInput}Z`) : undefined
    const to = toInput ? new Date(`${toInput}Z`) : undefined
    if ((from && !Number.isFinite(from.getTime())) || (to && !Number.isFinite(to.getTime())) || (from && to && from >= to)) {
      setError('Ölçüm bitişi başlangıçtan sonra olmalı.'); return
    }
    setError(''); setPage(1); setRange({ from: from?.toISOString(), to: to?.toISOString() })
  }

  return <section className="card" aria-label="Vücut ölçümleri">
    <header className="card-header"><div><h2>Vücut ölçümleri</h2><p>Danışanın açık paylaşım izniyle görüntülenen ölçüm kayıtları.</p></div><span className="neutral-badge">Salt okunur</span></header>
    <form className="meal-preview-filters" aria-label="Ölçüm tarihi filtresi" onSubmit={applyFilter}
      onReset={() => { setError(''); setFromInput(''); setToInput(''); setPage(1); setRange({}) }}>
      <p id="measurement-time-zone">Filtre saatleri UTC (UTC+00:00); başlangıç dahil, bitiş hariçtir. Kayıt saatleri cihazın saat diliminde gösterilir.</p>
      <label>Ölçüm başlangıcı<input name="from" type="datetime-local" step="1" value={fromInput} onChange={event => setFromInput(event.target.value)} aria-describedby="measurement-time-zone" /></label>
      <label>Ölçüm bitişi<input name="to" type="datetime-local" step="1" value={toInput} onChange={event => setToInput(event.target.value)} aria-describedby="measurement-time-zone" /></label>
      <div className="meal-preview-actions"><button className="button button-primary" type="submit">Ölçümleri filtrele</button><button className="button button-secondary" type="reset">Ölçüm filtresini temizle</button></div>
      {error && <p role="alert">{error}</p>}
    </form>
    {state.pending && <p className="panel-feedback" role="status">Ölçümler okunuyor…</p>}
    {state.message && <p className="panel-feedback error-message" role="alert">{state.message}</p>}
    {state.data?.kind === 'denied' && <p className="panel-feedback" role="alert">{state.data.message}</p>}
    {state.data?.kind === 'ready' && <>
      {state.data.history.length > 0 && <BodyMeasurementCharts records={state.data.history} />}
      {state.data.items.length === 0
        ? <EmptyState icon="chart" title={state.data.totalCount > 0 ? 'Bu sayfada ölçüm kaydı kalmadı' : range.from || range.to ? 'Bu aralıkta ölçüm kaydı yok' : 'Henüz ölçüm kaydı yok'}>Tarih aralığını değiştirebilir, önceki sayfaya dönebilir veya ölçümleri yenileyebilirsiniz.</EmptyState>
        : <BodyMeasurementList clientId={clientId} records={state.data.items} />}
      <div className="meal-preview-pagination">
        <button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki ölçüm sayfası</button>
        <p role="status">{state.data.totalCount} ölçüm · Sayfa {page}</p>
        <button className="button button-secondary" disabled={page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki ölçüm sayfası</button>
      </div>
    </>}
    <div className="panel-actions"><button className="button button-secondary" disabled={state.pending} onClick={refresh}>Ölçümleri yenile</button></div>
  </section>
}

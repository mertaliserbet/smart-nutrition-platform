import { useCallback, useEffect, useRef, useState } from 'react'
import { EmptyState } from '../../core/components/EmptyState'
import { WebSessionError } from '../auth/webSessionApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { WaterLogList } from './ClientRecordViews'
import { getWaterDailyTotal, getWaterHistory, getWaterLogs, localDateInput, localDayRange, waterHistoryRange } from './waterLogApi'
import type { WaterLogDailyTotal } from './waterLogApi'
import './clientTracking.css'

const number = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 20 })
const date = new Intl.DateTimeFormat('tr-TR', { day: '2-digit', month: '2-digit', year: 'numeric' })
function WaterHistory({ days }: { days: WaterLogDailyTotal[] }) {
  const maximum = Math.max(...days.map(day => day.totalAmountMl), 1)
  const width = 400 / days.length
  return <div className="water-history">
    <figure className="measurement-chart"><figcaption>Günlük su toplamı (mL)</figcaption>
      <svg viewBox="0 0 500 210" role="img" aria-label={`Günlük su toplamı grafiği: ${days.length} gün`}>
        <line className="measurement-axis" x1="70" x2="470" y1="160" y2="160" />
        <text x="64" y="164" textAnchor="end">0</text><text x="64" y="24" textAnchor="end">{number.format(maximum)}</text>
        {days.map((day, i) => <rect className="water-history-bar" key={day.from} x={70 + i * width + 2}
          y={160 - day.totalAmountMl / maximum * 136} width={Math.max(width - 4, 2)} height={day.totalAmountMl / maximum * 136}>
          <title>{date.format(new Date(day.from))}: {number.format(day.totalAmountMl)} mL</title>
        </rect>)}
        <text x="70" y="190">{date.format(new Date(days[0]!.from))}</text>
        {days.length > 1 && <text x="470" y="190" textAnchor="end">{date.format(new Date(days[days.length - 1]!.from))}</text>}
      </svg>
    </figure>
    <table className="water-history-table"><caption>Su tüketiminin günlük geçmişi</caption><thead><tr><th scope="col">Gün</th><th scope="col">Toplam (mL)</th></tr></thead>
      <tbody>{days.map(day => <tr key={day.from}><th scope="row"><time dateTime={day.from}>{date.format(new Date(day.from))}</time></th><td>{number.format(day.totalAmountMl)} mL</td></tr>)}</tbody>
    </table>
  </div>
}
export function WaterLogPanel({ clientId }: { clientId: string }) {
  const session = useWorkspaceSession()
  return <WaterLogContent key={`${session.dietitianId}:${session.token}:${clientId}`} clientId={clientId} />
}
function WaterLogContent({ clientId }: { clientId: string }) {
  const [day, setDay] = useState(() => localDateInput(new Date()))
  const [from, setFrom] = useState(() => { const date = new Date(); date.setDate(date.getDate() - 6); return localDateInput(date) })
  const [to, setTo] = useState(() => localDateInput(new Date()))
  const [page, setPage] = useState(1)
  const load = useCallback(async (signal: AbortSignal) => {
    if (document.visibilityState !== 'visible') return { kind: 'hidden' as const }
    try {
      const range = localDayRange(day), historyRange = waterHistoryRange(from, to)
      const [records, total, history] = await Promise.all([
        getWaterLogs(clientId, page, range, signal), getWaterDailyTotal(clientId, range, signal), getWaterHistory(clientId, historyRange, signal),
      ])
      return { kind: 'ready' as const, records, total, history }
    } catch (error) {
      if (error instanceof WebSessionError && [403, 404].includes(error.status)) return { kind: 'denied' as const, message: error.message }
      if (error instanceof WebSessionError && error.status === 400) return { kind: 'invalid' as const, message: error.message }
      throw error
    }
  }, [clientId, day, from, to, page])
  const state = useWorkspaceRead(load)
  const refreshRef = useRef(state.refresh)
  useEffect(() => { refreshRef.current = state.refresh }, [state.refresh])
  useEffect(() => {
    const invalidate = () => refreshRef.current()
    const visible = () => { if (document.visibilityState === 'visible') invalidate() }
    const timer = window.setInterval(visible, 30_000)
    window.addEventListener('focus', visible); document.addEventListener('visibilitychange', invalidate)
    return () => { window.clearInterval(timer); window.removeEventListener('focus', visible); document.removeEventListener('visibilitychange', invalidate) }
  }, [])
  return <section className="card" aria-label="Su takibi">
    <header className="card-header"><div><h2>Su takibi</h2><p>Danışanın paylaştığı tüketim kayıtları ve günlük toplamları.</p></div><span className="neutral-badge">Salt okunur</span></header>
    <div className="meal-preview-filters water-date-filters">
      <p>Tarihler ve kayıt saatleri cihazınızın saat dilimindedir: {Intl.DateTimeFormat().resolvedOptions().timeZone}. Geçmiş aralığı başlangıç ve bitiş dahil en fazla 31 gündür.</p>
      <label>Su günü<input type="date" value={day} onChange={event => { setDay(event.target.value); setPage(1) }} /></label>
      <label>Su geçmişi başlangıcı<input type="date" value={from} onChange={event => setFrom(event.target.value)} /></label>
      <label>Su geçmişi bitişi<input type="date" value={to} onChange={event => setTo(event.target.value)} /></label>
    </div>
    {state.pending && <p className="panel-feedback" role="status">Su takibi okunuyor…</p>}
    {state.message && <p className="panel-feedback error-message" role="alert">{state.message}</p>}
    {(state.data?.kind === 'denied' || state.data?.kind === 'invalid') && <p className="panel-feedback" role="alert">{state.data.message}</p>}
    {state.data?.kind === 'ready' && <>
      <div className="water-day-total" role="status" aria-label="Seçilen günün su toplamı"><h3>{day} · Günlük toplam</h3><strong>{number.format(state.data.total.totalAmountMl)} mL</strong></div>
      {state.data.records.items.length > 0 ? <WaterLogList clientId={clientId} records={state.data.records.items} />
        : <EmptyState icon="water" title={state.data.records.totalCount > 0 ? 'Bu sayfada su kaydı kalmadı' : 'Seçilen günde su kaydı yok'}>Başka bir gün seçebilir veya kayıtları yenileyebilirsiniz.</EmptyState>}
      <div className="meal-preview-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>Önceki su sayfası</button>
        <p role="status">{state.data.records.totalCount} su kaydı · Sayfa {page}</p>
        <button className="button button-secondary" disabled={page * 10 >= state.data.records.totalCount} onClick={() => setPage(p => p + 1)}>Sonraki su sayfası</button>
      </div>
      <WaterHistory days={state.data.history} />
    </>}
    <div className="panel-actions"><button className="button button-secondary" disabled={state.pending} onClick={state.refresh}>Su takibini yenile</button></div>
  </section>
}

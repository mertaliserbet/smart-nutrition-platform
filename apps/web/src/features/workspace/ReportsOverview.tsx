import { DateField } from '../../core/components/DateField'
import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import type { IconName } from '../../core/components/Icon'
import { WebSessionError } from '../auth/webSessionApi'
import { getMealLogs } from '../clients/mealLogApi'
import { getBodyMeasurements } from '../clients/bodyMeasurementApi'
import { getNutritionPlans } from '../nutritionPlans/nutritionPlanApi'
import { useWorkspaceRead } from './workspaceSession'

function dateValue(value: Date) { return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}` }
async function permitted<T>(read: () => Promise<T>) {
  try { return { kind: 'ready' as const, value: await read() } }
  catch (error) {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) return { kind: 'denied' as const, message: error.message }
    throw error
  }
}

export function ReportsOverview({ clientId, clientName, totalClients }: { clientId: string; clientName: string; totalClients: number }) {
  const [start, setStart] = useState(() => { const date = new Date(); date.setDate(date.getDate() - 27); return dateValue(date) })
  const valid = /^\d{4}-\d{2}-\d{2}$/.test(start) && Number.isFinite(Date.parse(`${start}T00:00:00`))
  const loadMeals = useCallback((signal: AbortSignal) => permitted(async () => {
    const from = new Date(`${start}T00:00:00`)
    if (!valid) return undefined
    return Promise.all(Array.from({ length: 4 }, async (_, index) => {
      const a = new Date(from.getFullYear(), from.getMonth(), from.getDate() + index * 7)
      const b = new Date(from.getFullYear(), from.getMonth(), from.getDate() + (index + 1) * 7)
      const data = await getMealLogs(clientId, 1, { from: a.toISOString(), to: b.toISOString() }, signal)
      return { from: a, to: b, count: data.totalCount }
    }))
  }), [clientId, start, valid])
  const loadPlans = useCallback((signal: AbortSignal) => permitted(() => getNutritionPlans(clientId, 1, signal)), [clientId])
  const loadMeasurements = useCallback((signal: AbortSignal) => permitted(() => getBodyMeasurements(clientId, 1, {}, signal)), [clientId])
  const meals = useWorkspaceRead(loadMeals), plans = useWorkspaceRead(loadPlans), measurements = useWorkspaceRead(loadMeasurements)
  const weeks = meals.data?.kind === 'ready' ? meals.data.value : undefined
  const programs = plans.data?.kind === 'ready' ? plans.data.value : undefined
  const measures = measurements.data?.kind === 'ready' ? measurements.data.value : undefined
  const mealCount = weeks?.reduce((sum, week) => sum + week.count, 0)
  const maximum = Math.max(8, Math.ceil(Math.max(0, ...weeks?.map(week => week.count) ?? []) / 8) * 8)
  const states = [['active', 'Aktif'], ['draft', 'Taslak'], ['archived', 'Arşiv']] as const
  const end = new Date(`${start}T12:00:00`); end.setDate(end.getDate() + 27)
  const { refresh: refreshMeals } = meals, { refresh: refreshPlans } = plans, { refresh: refreshMeasurements } = measurements
  useEffect(() => {
    const refresh = () => { if (document.visibilityState === 'visible') { refreshMeals(); refreshPlans(); refreshMeasurements() } }
    window.addEventListener('focus', refresh)
    return () => window.removeEventListener('focus', refresh)
  }, [refreshMeals, refreshPlans, refreshMeasurements])
  function csv() {
    if (!weeks || !programs || !measures) return
    const quote = (value: string | number) => `"${String(value).replace(/^[=+@\-\t\r]/, "'$&").replaceAll('"', '""')}"`
    const rows = [['Danışan', 'Başlangıç', 'Bitiş', 'Öğün kaydı', 'Kayıtlı program', 'Kayıtlı ölçüm'], [clientName, start, dateValue(end), mealCount!, programs.totalCount, measures.totalCount]]
    const url = URL.createObjectURL(new Blob(['\uFEFF', rows.map(row => row.map(quote).join(';')).join('\r\n')], { type: 'text/csv;charset=utf-8' }))
    const link = document.createElement('a'); link.href = url; link.download = 'limely-danisan-ozeti.csv'; link.click()
    window.setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  const metrics: { icon: IconName; label: string; value: number | undefined }[] = [
    { icon: 'users', label: 'Listelenen danışan', value: totalClients }, { icon: 'meal', label: 'Dönemdeki öğün', value: mealCount },
    { icon: 'plan', label: 'Kayıtlı program', value: programs?.totalCount }, { icon: 'chart', label: 'Kayıtlı ölçüm', value: measures?.totalCount },
  ]
  return <div className="reports-overview">
    <div className="reports-controls"><label className="report-period"><Icon name="calendar" /><span className="sr-only">28 günlük dönem başlangıcı</span><span className="report-date-caption">{valid ? new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' }).formatRange(new Date(`${start}T12:00:00`), end) : 'Dönem seçin'}</span><DateField type="date" value={start} onChange={event => setStart(event.target.value)} /></label><div><button className="button button-secondary" onClick={csv} disabled={!weeks || !programs || !measures}><Icon name="download" />CSV indir</button><button className="button button-primary" disabled aria-describedby="pdf-unavailable"><Icon name="plan" />PDF raporu</button></div></div>
    {!valid && <p role="alert" className="form-message error-message">Geçerli bir dönem başlangıcı seçin.</p>}
    <section className="metrics-grid report-metrics" aria-label="Danışan rapor göstergeleri">{metrics.map(metric => <article className="metric-card" key={metric.label}><span className="metric-icon green"><Icon name={metric.icon} /></span><div><h2>{metric.label}</h2><strong className="metric-value">{metric.value ?? '—'}</strong></div></article>)}</section>
    <div className="report-chart-grid"><section className="card report-chart-card"><header><h2>Haftalık kayıt hareketi</h2><span className="neutral-badge">{clientName}</span></header>
      {meals.pending && <p role="status">Öğün sayıları okunuyor…</p>}{meals.message && <p role="alert">{meals.message}</p>}{meals.data?.kind === 'denied' && <p role="alert">{meals.data.message}</p>}
      {weeks && <figure className="weekly-record-chart"><svg viewBox="0 0 680 220" role="img" aria-label="Seçilen danışanın haftalara göre öğün sayıları">{[0, 1, 2, 3, 4, 5, 6, 7, 8].map(tick => <g key={tick}><line x1="40" x2="678" y1={194 - tick * 21} y2={194 - tick * 21} className="report-grid-line" /><text x="30" y={199 - tick * 21} textAnchor="end">{Math.round(maximum * tick / 8)}</text></g>)}{weeks.map((week, index) => <g key={week.from.toISOString()}><rect x={70 + index * 155} y={194 - week.count / maximum * 163} width="115" height={week.count / maximum * 163} rx="8" className="report-week-bar" /><text x={127.5 + index * 155} y={182 - week.count / maximum * 163} textAnchor="middle" className="report-week-value">{week.count}</text><text x={127.5 + index * 155} y="218" textAnchor="middle">{index + 1}. Hafta</text></g>)}</svg><figcaption>{start} – {dateValue(end)} · Öğün kaydı adedi</figcaption></figure>}
      {meals.message && <button className="button button-secondary" onClick={meals.refresh}>Öğün sayılarını yeniden dene</button>}
    </section><section className="card report-chart-card"><header><h2>Program durumu</h2><span className="neutral-badge">{programs ? `Gösterilen: ${programs.items.length}` : '—'}</span></header>
      {plans.pending && <p role="status">Programlar okunuyor…</p>}{plans.message && <p role="alert">{plans.message}</p>}{plans.data?.kind === 'denied' && <p role="alert">{plans.data.message}</p>}
      {programs && <><div className="program-status-bars">{states.map(([status, label]) => { const count = programs.items.filter(plan => plan.status === status).length; return <div key={status}><span>{label}</span><span className="program-status-track"><span style={{ width: `${count / Math.max(programs.items.length, 1) * 100}%` }} /></span><strong>{count}</strong></div> })}</div><p className="program-status-caption">İlk {programs.items.length} programın durumu. Toplam {programs.totalCount} kayıtlı program.</p></>}
      {plans.message && <button className="button button-secondary" onClick={plans.refresh}>Programları yeniden dene</button>}
    </section></div>
    <div className="report-summary-grid"><section className="card report-chart-card"><header><h2>Danışan bazında takip özeti</h2></header><div className="client-table-scroll" tabIndex={0} role="region" aria-label="Seçilen danışanın rapor özeti"><table className="client-table"><thead><tr><th scope="col">Danışan</th><th scope="col">Öğün kaydı</th><th scope="col">Son ölçüm</th><th scope="col">Program</th></tr></thead><tbody><tr><td><div className="table-client"><span className="client-avatar" aria-hidden="true">{clientName.slice(0, 1)}</span><strong>{clientName}</strong></div></td><td>{mealCount ?? '—'}</td><td>{measures?.items[0] ? new Date(measures.items[0].measuredAt).toLocaleDateString('tr-TR') : measures ? 'Kayıt yok' : '—'}</td><td>{programs?.totalCount ?? '—'}</td></tr></tbody></table></div>{measurements.pending && <p role="status">Ölçümler okunuyor…</p>}{measurements.message && <p role="alert">{measurements.message}</p>}{measurements.data?.kind === 'denied' && <p role="alert">{measurements.data.message}</p>}</section>
    <section className="card report-chart-card"><header><h2>Bu dönem öne çıkanlar</h2></header><div className="report-highlights"><p><Icon name="meal" /><strong>{mealCount ?? '—'}</strong> seçili dönemde öğün kaydı</p><p><Icon name="plan" /><strong>{programs?.items.filter(plan => plan.status === 'draft').length ?? '—'}</strong> taslak program</p></div><div className="expert-pagination"><Link className="button button-primary" to={`/calisma-alani/danisanlar/${clientId}?bolum=program`}>Programlara git</Link><Link className="button button-secondary" to={`/calisma-alani/danisanlar/${clientId}`}>Danışanı aç</Link></div></section></div>
    <div className="inline-note"><Icon name="info" /><p>Öğün sayıları seçili 28 günlük dönemden; program ve ölçüm adetleri kayıtlı toplamdan gelir. Kayıt sayısı genel uyum veya sağlık değerlendirmesi değildir. <span id="pdf-unavailable">PDF dışa aktarma bu sürümde sunulmuyor.</span></p></div>
  </div>
}

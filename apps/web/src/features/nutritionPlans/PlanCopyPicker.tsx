import { useCallback, useEffect, useRef, useState } from 'react'
import { getClients } from '../relationships/relationshipApi'
import type { ClientListItem } from '../relationships/relationshipApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { WebSessionError } from '../auth/webSessionApi'
import { getNutritionPlan, getNutritionPlans } from './nutritionPlanApi'
import type { NutritionPlanResponse } from './nutritionPlanApi'
import { Icon } from '../../core/components/Icon'

export function PlanCopyPicker({ onCopy, onCancel }: { onCopy: (source: NutritionPlanResponse) => void; onCancel: () => void }) {
  const [input, setInput] = useState(''), [query, setQuery] = useState(''), [page, setPage] = useState(1)
  const [client, setClient] = useState<ClientListItem>()
  const load = useCallback((signal: AbortSignal) => getClients(page, query, 'asc', signal), [page, query])
  const clients = useWorkspaceRead(load)
  return <section className="card plan-copy-picker" aria-label="Kaynak program seçimi"><h3>Kendi programımdan kopyala</h3>
    <p>Önce kaynak danışanı, sonra hâlâ okuma izniniz olan kendi programınızı seçin. Kopyalama kayıt veya atama yapmaz.</p>
    <form className="plan-copy-search" onSubmit={event => { event.preventDefault(); setQuery(input.trim()); setPage(1); setClient(undefined) }}>
      <label>Kaynak danışan ara<input type="search" value={input} onChange={event => setInput(event.target.value)} /></label><button className="button button-secondary"><Icon name="search" />Kaynak ara</button>
    </form>
    {clients.pending && <p role="status">Kaynak danışanlar okunuyor…</p>}{clients.message && <p role="alert">{clients.message}</p>}
    {clients.data && <><ul className="plan-copy-options">{clients.data.items.map(row => <li key={row.id}><button className="button button-secondary plan-source-option" aria-pressed={client?.id === row.id} onClick={() => setClient(row)}><span>{row.displayName}</span><Icon name={client?.id === row.id ? 'check' : 'arrow'} /></button></li>)}</ul>
      {clients.data.totalCount === 0 && <p>Kaynak danışan bulunamadı.</p>}
      <div className="expert-pagination plan-copy-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => { setPage(p => p - 1); setClient(undefined) }}>Önceki kaynak danışanlar</button><span>Sayfa {page}</span>
        <button className="button button-secondary" disabled={page * 10 >= clients.data.totalCount} onClick={() => { setPage(p => p + 1); setClient(undefined) }}>Sonraki kaynak danışanlar</button></div></>}
    {client && clients.data && <SourcePrograms key={client.id} client={client} onCopy={onCopy} />}
    <div className="plan-copy-actions"><button className="button button-secondary" disabled={clients.pending} onClick={() => { setClient(undefined); clients.refresh() }}><Icon name="clock" />Kaynakları yeniden kontrol et</button>
    <button className="button button-secondary" onClick={onCancel}>Kaynak seçimini kapat<Icon name="close" /></button></div>
  </section>
}
function SourcePrograms({ client, onCopy }: { client: ClientListItem; onCopy: (source: NutritionPlanResponse) => void }) {
  const session = useWorkspaceSession()
  const [page, setPage] = useState(1), [message, setMessage] = useState(''), [busy, setBusy] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const load = useCallback(async (signal: AbortSignal) => {
    try { return { kind: 'ready' as const, ...await getNutritionPlans(client.id, page, signal) } }
    catch (error) {
      if (error instanceof WebSessionError && [403, 404].includes(error.status)) return { kind: 'denied' as const, message: error.message }
      throw error
    }
  }, [client.id, page])
  const state = useWorkspaceRead(load)
  const data = state.data?.kind === 'ready' ? state.data : undefined
  useEffect(() => () => operation.current?.abort(), [])
  const refresh = state.refresh
  useEffect(() => {
    const check = () => { operation.current?.abort(); operation.current = null; setBusy(false); setMessage(''); refresh() }
    window.addEventListener('focus', check)
    return () => window.removeEventListener('focus', check)
  }, [refresh])
  async function select(id: string) {
    if (operation.current || state.pending) return
    const controller = new AbortController(); operation.current = controller; setBusy(true); setMessage('')
    try {
      const source = await getNutritionPlan(client.id, id, controller.signal)
      if (source.dietitianId !== session.dietitianId) throw new WebSessionError(403, 'Yalnız kendi programınızı kopyalayabilirsiniz.')
      if (!controller.signal.aborted) onCopy(source)
    } catch (error) {
      if (!controller.signal.aborted) {
        const local = error instanceof WebSessionError && [403, 404].includes(error.status)
        if (local || !session.onFailure(error)) setMessage(error instanceof WebSessionError ? error.message : 'Kaynak doğrulanamadı.')
        refresh()
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setBusy(false) } }
  }
  return <div><h4>{client.displayName} · Kaynak programlar</h4>
    {state.pending && <p role="status">Kaynak programlar okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}
    {state.data?.kind === 'denied' ? <p role="alert">{state.data.message}</p> : message && <p role="alert">{message}</p>}
    {data && <><ul className="plan-copy-options">{data.items.filter(plan => plan.dietitianId === session.dietitianId).map(plan => <li key={plan.id}><button className="button button-secondary plan-source-option" aria-label={`${plan.title} programını kopyala`} disabled={busy} onClick={() => { void select(plan.id) }}><span><strong>{plan.title}</strong><small>Öğün yapısını taslağa kopyala</small></span><Icon name="arrow" /></button></li>)}</ul>
      {!data.items.some(plan => plan.dietitianId === session.dietitianId) && <p>Bu sayfada size ait kopyalanabilir program yok.</p>}
      <div className="expert-pagination plan-copy-pagination"><button className="button button-secondary" disabled={busy || page <= 1} onClick={() => { setMessage(''); setPage(p => p - 1) }}>Önceki kaynak programlar</button><span>Program sayfası {page}</span>
        <button className="button button-secondary" disabled={busy || page * 10 >= data.totalCount} onClick={() => { setMessage(''); setPage(p => p + 1) }}>Sonraki kaynak programlar</button></div></>}
  </div>
}

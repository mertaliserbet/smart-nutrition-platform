import { useCallback, useEffect, useRef, useState } from 'react'
import { getClients } from '../relationships/relationshipApi'
import type { ClientListItem } from '../relationships/relationshipApi'
import { useWorkspaceRead, useWorkspaceSession } from '../workspace/workspaceSession'
import { WebSessionError } from '../auth/webSessionApi'
import { getNutritionPlan, getNutritionPlans } from './nutritionPlanApi'
import type { NutritionPlanResponse } from './nutritionPlanApi'

export function PlanCopyPicker({ onCopy, onCancel }: { onCopy: (source: NutritionPlanResponse) => void; onCancel: () => void }) {
  const [input, setInput] = useState(''), [query, setQuery] = useState(''), [page, setPage] = useState(1)
  const [client, setClient] = useState<ClientListItem>()
  const load = useCallback((signal: AbortSignal) => getClients(page, query, 'asc', signal), [page, query])
  const clients = useWorkspaceRead(load)
  return <section className="card plan-copy-picker" aria-label="Kaynak program seçimi"><h3>Kendi programımdan kopyala</h3>
    <p>Önce kaynak danışanı, sonra hâlâ okuma izniniz olan kendi programınızı seçin. Kopyalama kayıt veya atama yapmaz.</p>
    <form onSubmit={event => { event.preventDefault(); setQuery(input.trim()); setPage(1); setClient(undefined) }}>
      <label>Kaynak danışan ara<input type="search" value={input} onChange={event => setInput(event.target.value)} /></label><button className="button button-secondary">Kaynak ara</button>
    </form>
    {clients.pending && <p role="status">Kaynak danışanlar okunuyor…</p>}{clients.message && <p role="alert">{clients.message}</p>}
    {clients.data && <><ul>{clients.data.items.map(row => <li key={row.id}><button className="text-link" aria-pressed={client?.id === row.id} onClick={() => setClient(row)}>{row.displayName}</button></li>)}</ul>
      {clients.data.totalCount === 0 && <p>Kaynak danışan bulunamadı.</p>}
      <div className="expert-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => { setPage(p => p - 1); setClient(undefined) }}>Önceki kaynak danışanlar</button><span>Sayfa {page}</span>
        <button className="button button-secondary" disabled={page * 10 >= clients.data.totalCount} onClick={() => { setPage(p => p + 1); setClient(undefined) }}>Sonraki kaynak danışanlar</button></div></>}
    {client && <SourcePrograms key={client.id} client={client} onCopy={onCopy} />}
    <button className="button button-secondary" onClick={clients.refresh}>Kaynakları yeniden kontrol et</button>
    <button className="button button-secondary" onClick={onCancel}>Kaynak seçimini kapat</button>
  </section>
}
function SourcePrograms({ client, onCopy }: { client: ClientListItem; onCopy: (source: NutritionPlanResponse) => void }) {
  const session = useWorkspaceSession()
  const [page, setPage] = useState(1), [message, setMessage] = useState(''), [busy, setBusy] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const load = useCallback((signal: AbortSignal) => getNutritionPlans(client.id, page, signal), [client.id, page])
  const handleDenied = useCallback((error: unknown) => {
    if (error instanceof WebSessionError && [403, 404].includes(error.status)) { setMessage(error.message); return true }
    return false
  }, [])
  const state = useWorkspaceRead(load, handleDenied)
  useEffect(() => () => operation.current?.abort(), [])
  const refresh = state.refresh
  useEffect(() => {
    const check = () => { operation.current?.abort(); operation.current = null; setBusy(false); refresh() }
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
        if (!handleDenied(error) && !session.onFailure(error)) setMessage(error instanceof WebSessionError ? error.message : 'Kaynak doğrulanamadı.')
        refresh()
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setBusy(false) } }
  }
  return <div><h4>{client.displayName} · Kaynak programlar</h4>
    {state.pending && <p role="status">Kaynak programlar okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}{message && <p role="alert">{message}</p>}
    {state.data && <><ul>{state.data.items.filter(plan => plan.dietitianId === session.dietitianId).map(plan => <li key={plan.id}><button className="button button-secondary" disabled={busy} onClick={() => { void select(plan.id) }}>{plan.title} programını kopyala</button></li>)}</ul>
      {!state.data.items.some(plan => plan.dietitianId === session.dietitianId) && <p>Bu sayfada size ait kopyalanabilir program yok.</p>}
      <div className="expert-pagination"><button className="button button-secondary" disabled={busy || page <= 1} onClick={() => setPage(p => p - 1)}>Önceki kaynak programlar</button><span>Program sayfası {page}</span>
        <button className="button button-secondary" disabled={busy || page * 10 >= state.data.totalCount} onClick={() => setPage(p => p + 1)}>Sonraki kaynak programlar</button></div></>}
  </div>
}

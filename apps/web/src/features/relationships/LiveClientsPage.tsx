import { useCallback, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useWorkspaceRead } from '../workspace/workspaceSession'
import { getClientDashboard, getClients } from './relationshipApi'
import type { ClientDashboardResponse, ClientListItem, PagedResponse } from './relationshipApi'
import { NutritionPlanPanel } from '../nutritionPlans/NutritionPlanPanel'

export function LiveClientsPage() {
  const [input, setInput] = useState(''); const [query, setQuery] = useState(''); const [sort, setSort] = useState('asc'); const [page, setPage] = useState(1)
  const load = useCallback((signal: AbortSignal) => getClients(page, query, sort, signal), [page, query, sort])
  const state = useWorkspaceRead<PagedResponse<ClientListItem>>(load)
  return <><div className="page-heading"><h1 tabIndex={-1}>Danışanlarım</h1><p>Aktif bağlantı kurduğunuz danışanlar.</p></div>
    <section className="card"><form className="list-toolbar" onSubmit={event => { event.preventDefault(); setQuery(input.trim()); setPage(1) }}>
      <label className="search-field">Danışan adı<input type="search" value={input} onChange={event => setInput(event.target.value)} /></label>
      <button className="button button-secondary" type="submit" disabled={state.pending}>Ara</button>
      <label>Sıralama<select value={sort} disabled={state.pending} onChange={event => { setSort(event.target.value); setPage(1) }}><option value="asc">Ad: A → Z</option><option value="desc">Ad: Z → A</option></select></label>
    </form>
      {state.pending && <p role="status">Danışanlar okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}
      {state.data && <><p role="status">{state.data.totalCount} danışan</p>
        {state.data.totalCount === 0 && <p>Aktif bağlantı veya aramanıza uygun danışan bulunmuyor.</p>}
        <ul className="client-list" aria-label="Aktif danışanlar">{state.data.items.map(client => <li key={client.id}><Link className="client-row" aria-label={`${client.displayName} için danışan detayını aç`} to={`/calisma-alani/danisanlar/${client.id}`}><strong>{client.displayName}</strong><span>Danışan detayını aç</span></Link></li>)}</ul>
        <div className="expert-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki sayfa</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki sayfa</button></div>
      </>}
      <button className="button button-secondary" disabled={state.pending} onClick={state.refresh}>Listeyi yenile</button>
    </section><Link className="text-link" to="/calisma-alani/baglantilar">Bağlantıları ve davet kodunu yönet</Link>
  </>
}
export function LiveClientDetailsPage() {
  const { clientId = '' } = useParams()
  const load = useCallback((signal: AbortSignal) => getClientDashboard(clientId, signal), [clientId])
  const state = useWorkspaceRead<ClientDashboardResponse>(load)
  return <><div className="page-heading"><h1 tabIndex={-1}>Danışan detayı</h1></div>
    {state.pending && <p role="status">Danışan okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}
    {state.data && <section className="card"><h2>{state.data.displayName}</h2><p>Aktif danışan bağlantınız bulunuyor.</p></section>}
    {state.data && <NutritionPlanPanel key={state.data.clientId} clientId={state.data.clientId} />}
    <Link className="text-link" to="/calisma-alani/danisanlar">Danışan listesine dön</Link>
  </>
}

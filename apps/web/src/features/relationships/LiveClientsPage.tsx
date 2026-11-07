import { useCallback, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useWorkspaceRead } from '../workspace/workspaceSession'
import { getClientDashboard, getClients } from './relationshipApi'
import type { ClientDashboardResponse, ClientListItem, PagedResponse } from './relationshipApi'
import { NutritionPlanPanel } from '../nutritionPlans/NutritionPlanPanel'
import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'

export function LiveClientsPage() {
  const [input, setInput] = useState(''); const [query, setQuery] = useState(''); const [sort, setSort] = useState('asc'); const [page, setPage] = useState(1)
  const load = useCallback((signal: AbortSignal) => getClients(page, query, sort, signal), [page, query, sort])
  const state = useWorkspaceRead<PagedResponse<ClientListItem>>(load)
  return <><div className="dashboard-heading"><div className="page-heading"><p className="eyebrow">BİRLİKTE İLERLEYİN</p><h1 tabIndex={-1}>Danışanlarım</h1><p>Aktif bağlantı kurduğunuz danışanlar ve beslenme programları.</p></div>
    <Link className="button button-primary" to="/calisma-alani/baglantilar"><Icon name="link" />Bağlantıları ve daveti yönet</Link></div>
    <section className="card"><header className="card-header"><div><h2>Danışan listesi</h2><p>Detaylara geçmek için bir danışan seçin.</p></div><span className="neutral-badge">{state.data ? `${state.data.totalCount} danışan` : 'Aktif bağlantılar'}</span></header>
    <form className="list-toolbar live-list-toolbar" aria-label="Danışan arama" onSubmit={event => { event.preventDefault(); setQuery(input.trim()); setPage(1) }}>
      <label className="search-field"><Icon name="search" /><span className="sr-only">Danışan adı</span><input type="search" placeholder="Danışan adıyla ara" value={input} onChange={event => setInput(event.target.value)} /></label>
      <button className="button button-secondary" type="submit" disabled={state.pending}>Ara</button>
      <label>Sıralama<select value={sort} disabled={state.pending} onChange={event => { setSort(event.target.value); setPage(1) }}><option value="asc">Ad: A → Z</option><option value="desc">Ad: Z → A</option></select></label>
    </form>
      {state.pending && <p className="panel-feedback" role="status">Danışanlar okunuyor…</p>}{state.message && <p className="panel-feedback error-message" role="alert">{state.message}</p>}
      {state.data && <>
        {state.data.totalCount === 0 && <EmptyState icon="users" title="Aktif bağlantı veya aramanıza uygun danışan bulunmuyor.">Aramanızı değiştirebilir veya bağlantılar bölümünden yeni bir davet kodu oluşturabilirsiniz.</EmptyState>}
        <ul className="live-client-list" aria-label="Aktif danışanlar">{state.data.items.map(client => <li key={client.id}><Link className="live-client-row" aria-label={`${client.displayName} için danışan detayını aç`} to={`/calisma-alani/danisanlar/${client.id}`}>
          <span className="client-avatar" aria-hidden="true">{client.displayName.slice(0, 1).toLocaleUpperCase('tr-TR')}</span><span className="client-identity"><strong>{client.displayName}</strong><small>Danışan detayını aç</small></span><span className="access-badge">Aktif bağlantı</span><Icon name="arrow" />
        </Link></li>)}</ul>
        <div className="panel-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki sayfa</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki sayfa</button></div>
      </>}
      <div className="panel-actions"><button className="button button-secondary" disabled={state.pending} onClick={state.refresh}>Listeyi yenile</button></div>
    </section><div className="inline-note"><Icon name="shield" /><p>Danışan detaylarında yalnızca paylaşım izni verilen programlar görüntülenir.</p></div>
  </>
}
export function LiveClientDetailsPage() {
  const { clientId = '' } = useParams()
  const load = useCallback((signal: AbortSignal) => getClientDashboard(clientId, signal), [clientId])
  const state = useWorkspaceRead<ClientDashboardResponse>(load)
  return <><Link className="text-link back-link" to="/calisma-alani/danisanlar"><Icon name="back" />Danışan listesine dön</Link>
    <div className="page-heading"><p className="eyebrow">DANIŞAN TAKİBİ</p><h1 tabIndex={-1}>Danışan detayı</h1><p>Beslenme programlarını ve sürüm geçmişini bu alandan yönetin.</p></div>
    {state.pending && <p role="status">Danışan okunuyor…</p>}{state.message && <p role="alert">{state.message}</p>}
    {state.data && <section className="card client-profile-card"><span className="client-avatar large-avatar" aria-hidden="true">{state.data.displayName.slice(0, 1).toLocaleUpperCase('tr-TR')}</span><div><h2>{state.data.displayName}</h2><p>Aktif danışan bağlantınız bulunuyor.</p></div><span className="access-badge">Aktif bağlantı</span></section>}
    {state.data && <NutritionPlanPanel key={state.data.clientId} clientId={state.data.clientId} />}
  </>
}

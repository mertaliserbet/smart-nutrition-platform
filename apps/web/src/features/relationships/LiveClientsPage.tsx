import { useCallback, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { useWorkspaceRead } from '../workspace/workspaceSession'
import { getClients } from './relationshipApi'
import type { ClientListItem, PagedResponse } from './relationshipApi'
export { LiveClientDetailsPage } from './LiveClientDetailsPage'
import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import { useClientListState } from './clientListState'

export function LiveClientsPage() {
  const [{ input, query, sort, page }, setFilters] = useClientListState()
  const setInput = (input: string) => setFilters(value => ({ ...value, input }))
  const setQuery = (query: string) => setFilters(value => ({ ...value, query, page: 1 }))
  const setSort = (sort: string) => setFilters(value => ({ ...value, sort, page: 1 }))
  const setPage = (next: number | ((value: number) => number)) => setFilters(value => ({ ...value, page: typeof next === 'function' ? next(value.page) : next }))
  const load = useCallback((signal: AbortSignal) => getClients(page, query, sort, signal), [page, query, sort])
  const state = useWorkspaceRead<PagedResponse<ClientListItem>>(load)
  useEffect(() => {
    if (state.data && page > Math.max(1, Math.ceil(state.data.totalCount / 10)))
      setFilters(value => ({ ...value, page: Math.max(1, Math.ceil(state.data!.totalCount / 10)) }))
  }, [state.data, page, setFilters])
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
        {state.data.totalCount === 0 && (query ? <EmptyState icon="search" title="Aramanıza uygun danışan bulunamadı"><button className="button button-secondary" onClick={() => { setInput(''); setQuery('') }}>Filtreyi temizle</button></EmptyState>
          : <EmptyState icon="users" title="Henüz aktif danışanınız yok">Bağlantılar bölümünden bir davet kodu oluşturabilirsiniz.</EmptyState>)}
        <ul className="live-client-list" aria-label="Aktif danışanlar">{state.data.items.map(client => <li key={client.id}><Link className="live-client-row" aria-label={`${client.displayName} için danışan detayını aç`} to={`/calisma-alani/danisanlar/${client.id}`}>
          <span className="client-avatar" aria-hidden="true">{client.displayName.slice(0, 1).toLocaleUpperCase('tr-TR')}</span><span className="client-identity"><strong>{client.displayName}</strong><small>Danışan detayını aç</small></span><span className="access-badge">Aktif bağlantı</span><Icon name="arrow" />
        </Link></li>)}</ul>
        <div className="panel-pagination"><button className="button button-secondary" disabled={page <= 1} onClick={() => setPage(value => value - 1)}>Önceki sayfa</button><span>Sayfa {page}</span><button className="button button-secondary" disabled={page * 10 >= state.data.totalCount} onClick={() => setPage(value => value + 1)}>Sonraki sayfa</button></div>
      </>}
      <div className="panel-actions"><button className="button button-secondary" disabled={state.pending} onClick={state.refresh}>Listeyi yenile</button></div>
    </section><div className="inline-note"><Icon name="shield" /><p>Danışan detaylarında her kayıt türü kendi paylaşım izniyle görüntülenir.</p></div>
  </>
}

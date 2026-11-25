import { Select } from '../../core/components/Select'
import { useCallback, useEffect } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useWorkspaceRead } from '../workspace/workspaceSession'
import { getClients } from './relationshipApi'
import type { ClientListItem, PagedResponse } from './relationshipApi'
export { LiveClientDetailsPage } from './LiveClientDetailsPage'
import { Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import { useClientListState } from './clientListState'

export function LiveClientsPage() {
  const [params] = useSearchParams()
  const requested = params.get('bolum') ?? ''
  const section = ['ogunler', 'program', 'gorevler', 'olcum-su'].includes(requested) ? requested : ''
  const sectionLabels: Record<string, string> = { ogunler: 'Öğün incelemeleri', program: 'Programlar', gorevler: 'Görevler', 'olcum-su': 'Ölçüm ve su' }
  const [{ input, query, sort, page }, setFilters] = useClientListState()
  const setInput = (input: string) => setFilters(value => ({ ...value, input }))
  const setQuery = (query: string) => setFilters(value => ({ ...value, query, page: 1 }))
  const setSort = (sort: string) => setFilters(value => ({ ...value, sort, page: 1 }))
  const setPage = (next: number | ((value: number) => number)) => setFilters(value => ({ ...value, page: typeof next === 'function' ? next(value.page) : next }))
  const load = useCallback((signal: AbortSignal) => getClients(page, query, sort, signal), [page, query, sort])
  const state = useWorkspaceRead<PagedResponse<ClientListItem>>(load)
  const pageCount = Math.max(1, Math.ceil((state.data?.totalCount ?? 0) / 10))
  const firstPage = Math.min(Math.max(1, page - 2), Math.max(1, pageCount - 4))
  useEffect(() => {
    if (state.data && page > Math.max(1, Math.ceil(state.data.totalCount / 10)))
      setFilters(value => ({ ...value, page: Math.max(1, Math.ceil(state.data!.totalCount / 10)) }))
  }, [state.data, page, setFilters])
  return <><div className="dashboard-heading clients-heading"><div className="page-heading"><h1 tabIndex={-1}>{sectionLabels[section] ?? 'Danışanlar'}</h1><p>{section ? 'İzinli kayıtlarını açmak için bir danışan seçin.' : 'Danışanlarınızı ve takip süreçlerini tek yerden yönetin.'}</p></div>
    <div className="client-page-actions"><form id="client-search" aria-label="Danışan arama" onSubmit={event => { event.preventDefault(); setQuery(input.trim()); setPage(1) }}><label className="search-field"><Icon name="search" /><span className="sr-only">Danışan adı</span><input type="search" placeholder="Danışan adıyla ara" value={input} onChange={event => setInput(event.target.value)} /></label><button className="icon-button" type="submit" disabled={state.pending} aria-label="Ara"><Icon name="search" /></button></form><Link className="button button-primary" to="/calisma-alani/baglantilar"><Icon name="plus" />Danışan ekle</Link></div></div>
    <div className="client-summary-strip"><Icon name="users" /><span><strong>{state.data?.totalCount ?? '—'}</strong> {query ? 'arama sonucu' : 'aktif danışan'}</span><span className="summary-divider" /><Icon name="clock" /><span>Takip bekleyen: <strong title="Toplu takip özeti sunulmuyor">—</strong></span><span className="summary-divider" /><Icon name="users" /><span>Yeni danışan: <strong title="Dönemsel özet sunulmuyor">—</strong></span></div>
    <div className="clients-layout"><div>
    <div className="client-list-status"><span className="selected">Tümü <strong>{state.data?.totalCount ?? '—'}</strong></span><span title="Liste yalnız aktif bağlantıları içerir">Aktif <strong>{state.data?.totalCount ?? '—'}</strong></span><span aria-disabled="true" title="Arşivlenmiş bağlantı listesi sunulmuyor">Arşiv</span></div>
    <div className="client-filter-row"><label><Icon name="target" /><span className="sr-only">Hedef</span><Select disabled title="Danışan listesi hedef bilgisi sunmuyor"><option>Hedef</option></Select></label><label><Icon name="layers" /><span className="sr-only">Program durumu</span><Select disabled title="Danışan listesi program özeti sunmuyor"><option>Program durumu</option></Select></label><label><Icon name="users" /><span className="sr-only">Sıralama</span><Select aria-label="Sıralama" value={sort} disabled={state.pending} onChange={event => { setSort(event.target.value); setPage(1) }}><option value="asc">Ad: A → Z</option><option value="desc">Ad: Z → A</option></Select></label></div>
    <section className="card client-list-card">
      {state.pending && <p className="panel-feedback" role="status">Danışanlar okunuyor…</p>}{state.message && <p className="panel-feedback error-message" role="alert">{state.message}</p>}
      {state.data && <>
        {state.data.totalCount === 0 && (query ? <EmptyState icon="search" title="Aramanıza uygun danışan bulunamadı"><button className="button button-secondary" onClick={() => { setInput(''); setQuery('') }}>Filtreyi temizle</button></EmptyState>
          : <EmptyState icon="users" title="Henüz aktif danışanınız yok">Bağlantılar bölümünden bir davet kodu oluşturabilirsiniz.</EmptyState>)}
        {state.data.items.length > 0 && <div className="client-table-scroll" tabIndex={0} role="region" aria-label="Aktif danışanlar tablosu"><table className="client-table"><thead><tr><th scope="col">Danışan</th><th scope="col">Hedef</th><th scope="col">Son ölçüm</th><th scope="col">Program</th><th scope="col">Durum</th><th scope="col">İşlem</th></tr></thead><tbody>{state.data.items.map(client => <tr key={client.id}>
          <td data-label="Danışan"><div className="table-client"><span className="client-avatar" aria-hidden="true">{client.displayName.trim().split(/\s+/).slice(0, 2).map(part => Array.from(part)[0]).join('').toLocaleUpperCase('tr-TR')}</span><strong>{client.displayName}</strong></div></td>
          <td data-label="Hedef"><span className="table-unavailable" title="Hedef bilgisi danışan listesi yanıtında yer almıyor">—<span className="sr-only">Hedef özeti alınmadı</span></span></td>
          <td data-label="Son ölçüm"><Link className="table-detail-link" aria-label={`${client.displayName} ölçümlerini aç`} to={`/calisma-alani/danisanlar/${client.id}?bolum=olcum-su`}>Ölçümleri aç</Link></td>
          <td data-label="Program"><Link className="table-detail-link" aria-label={`${client.displayName} programlarını aç`} to={`/calisma-alani/danisanlar/${client.id}?bolum=program`}>Programları aç</Link></td>
          <td data-label="Durum"><span className="access-badge"><Icon name="check" />Aktif bağlantı</span></td>
          <td data-label="İşlem"><Link className="button button-secondary table-profile-link" aria-label={`${client.displayName} için danışan detayını aç`} to={`/calisma-alani/danisanlar/${client.id}${section ? `?bolum=${section}` : ''}`}>{section ? 'Kayıtları aç' : 'Profili aç'}<Icon name="arrow" /></Link></td>
        </tr>)}</tbody></table></div>}
        <nav className="client-pagination" aria-label="Danışan sayfaları"><span>{state.data.items.length ? `${(page - 1) * 10 + 1}–${(page - 1) * 10 + state.data.items.length}` : '0'} / {state.data.totalCount} danışan</span><div><button className="icon-button pagination-previous" disabled={page <= 1 || state.pending} onClick={() => setPage(value => value - 1)} aria-label="Önceki sayfa"><Icon name="chevron" /></button>{Array.from({ length: Math.min(5, pageCount) }, (_, index) => firstPage + index).map(number => <button className="icon-button" key={number} aria-label={`${number}. sayfayı aç`} aria-current={page === number ? 'page' : undefined} disabled={state.pending} onClick={() => setPage(number)}>{number}</button>)}<span className="sr-only" aria-live="polite">Sayfa {page}</span><button className="icon-button pagination-next" disabled={page >= pageCount || state.pending} onClick={() => setPage(value => value + 1)} aria-label="Sonraki sayfa"><Icon name="chevron" /></button><button className="icon-button" aria-label="Listeyi yenile" disabled={state.pending} onClick={state.refresh}><Icon name="refresh" /></button></div></nav>
      </>}

    </section></div><aside className="card client-guide"><h2>Takip bekleyenler</h2><div><span className="strip-icon"><Icon name="plan" /></span><h3>Danışana özel program</h3><p>Bir danışan seçerek mevcut programını açın veya yeni bir taslak hazırlayın.</p></div><div><span className="strip-icon"><Icon name="link" /></span><h3>Yeni bir bağlantı</h3><p>Davet kodu oluşturun ve size ulaşan bağlantı taleplerini yanıtlayın.</p><Link className="text-link" to="/calisma-alani/baglantilar">Bağlantıları aç<Icon name="arrow" /></Link></div></aside></div><div className="inline-note"><Icon name="shield" /><p>Danışan detaylarında her kayıt türü kendi paylaşım izniyle görüntülenir.</p></div>
  </>
}

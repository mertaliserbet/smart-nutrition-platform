import { useState } from 'react'
import { Link, useLocation, useSearchParams } from 'react-router-dom'
import { EmptyState } from '../../core/components/EmptyState'
import { Icon } from '../../core/components/Icon'
import { previewClients } from './clientTracking.preview'
import { TrackingPreviewControl, TrackingPreviewState } from './TrackingPreviewState'
import type { TrackingPreviewScenario } from './TrackingPreviewState'
import './clientTracking.css'

export function ClientsPage() {
  const [scenario, setScenario] = useState<TrackingPreviewScenario>('sample')
  const [searchParams, setSearchParams] = useSearchParams()
  const location = useLocation()
  const query = searchParams.get('arama') ?? ''
  const direction = searchParams.get('sirala') === 'za' ? 'za' : 'az'
  const normalizedQuery = query.trim().normalize('NFC').toLocaleLowerCase('tr-TR')
  const clients = previewClients.filter((client) => client.displayName.normalize('NFC').toLocaleLowerCase('tr-TR').includes(normalizedQuery))
    .sort((first, second) => first.displayName.localeCompare(second.displayName, 'tr-TR') * (direction === 'az' ? 1 : -1))

  function changeQuery(key: 'arama' | 'sirala', value: string) {
    setSearchParams((current) => {
      const next = new URLSearchParams(current)
      if (value) next.set(key, value)
      else next.delete(key)
      return next
    }, { replace: true })
  }

  return (
    <>
      <div className="page-heading"><p className="eyebrow">DANIŞAN TAKİBİ</p><h1 tabIndex={-1}>Danışanlarım</h1><p>Birlikte ilerlediğiniz danışanlar, tek bir yerde.</p></div>
      <TrackingPreviewControl scenario={scenario} onChange={setScenario} />
      <section className="card" aria-labelledby="clients-title">
        <header className="card-header"><div><h2 id="clients-title">Danışan listesi</h2><p>Yalnızca ad bilgisi içeren sentetik liste.</p></div><Link className="text-link" to="/onizleme/baglanti-istekleri">Bağlantı isteklerini incele<Icon name="arrow" /></Link></header>
        <TrackingPreviewState scenario={scenario} scope="list" onShowSample={() => setScenario('sample')}>
          <div className="list-toolbar client-toolbar">
            <label className="search-field"><Icon name="search" /><input type="search" aria-label="Danışan ara" placeholder="Danışan adıyla ara" value={query} onChange={(event) => changeQuery('arama', event.target.value)} /></label>
            <label className="sort-control">Sıralama<select value={direction} onChange={(event) => changeQuery('sirala', event.target.value)}><option value="az">Ad: A → Z</option><option value="za">Ad: Z → A</option></select></label>
          </div>
          <p className="client-result-count" role="status">{clients.length} örnek danışan gösteriliyor</p>
          {clients.length === 0 ? <EmptyState icon="search" title="Aramanızla eşleşen danışan yok" action={<button className="button button-secondary" onClick={() => changeQuery('arama', '')}>Aramayı temizle</button>}>Başka bir adla arayın veya arama alanını temizleyin.</EmptyState> : <ul className="client-list" aria-label="Örnek danışanlar">
            {clients.map((client) => <li key={client.id}><Link className="client-row" to={`/onizleme/danisanlar/${client.id}`} state={{ listSearch: location.search }}>
              <span className="client-avatar" aria-hidden="true">{client.displayName.split(' ').at(-1)?.slice(0, 2).toLocaleUpperCase('tr-TR')}</span>
              <span className="client-row-name"><strong>{client.displayName}</strong><small>Sentetik danışan profili</small></span>
              <span className="client-row-action">Kayıtları görüntüle<Icon name="arrow" /></span>
            </Link></li>)}
          </ul>}
        </TrackingPreviewState>
      </section>
      <div className="inline-note"><Icon name="shield" /><p>Danışan bağlantısı, tüm sağlık kayıtlarına erişim anlamına gelmez. Paylaşılan her kategori için danışanın izni gerekir.</p></div>
    </>
  )
}

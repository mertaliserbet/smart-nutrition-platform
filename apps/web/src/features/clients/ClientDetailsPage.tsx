import { useState } from 'react'
import { Link, useLocation, useParams, useSearchParams } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import { getPreviewRecords, previewClients } from './clientTracking.preview'
import type { ClientProfileListItem } from './clientTracking.types'
import { BodyMeasurementList, MealLogList, WaterLogList } from './ClientRecordViews'
import { TrackingPreviewControl, TrackingPreviewState } from './TrackingPreviewState'
import type { TrackingPreviewScenario } from './TrackingPreviewState'
import './clientTracking.css'

function ClientDetailsContent({ client }: { client: ClientProfileListItem }) {
  const [scenario, setScenario] = useState<TrackingPreviewScenario>('sample')
  const [searchParams] = useSearchParams()
  const location = useLocation()
  const listSearch = typeof location.state?.listSearch === 'string' ? location.state.listSearch : ''
  const selectedView = searchParams.get('kayit')
  const view = selectedView === 'su' || selectedView === 'olcumler' ? selectedView : 'ogunler'
  const records = scenario === 'sample' ? getPreviewRecords(client.id) : undefined
  return (
    <>
      <Link className="text-link client-back" to={{ pathname: '/onizleme/danisanlar', search: listSearch }}><Icon name="back" />Danışan listesine dön</Link>
      <div className="client-detail-heading"><div className="page-heading"><p className="eyebrow">DANIŞAN KAYITLARI</p><h1 tabIndex={-1}>{client.displayName}</h1><p>Sentetik danışan profili · Günlük kayıtların salt okunur önizlemesi.</p></div><span className="readonly-badge"><Icon name="eye" />Salt okunur</span></div>
      <TrackingPreviewControl scenario={scenario} onChange={setScenario} />
      <section className="card" aria-labelledby="records-title">
        <nav className="record-navigation" aria-label="Kayıt türü">
          <Link to="?kayit=ogunler" state={{ listSearch }} aria-current={view === 'ogunler' ? 'page' : undefined}><Icon name="leaf" />Öğün günlüğü</Link>
          <Link to="?kayit=su" state={{ listSearch }} aria-current={view === 'su' ? 'page' : undefined}><Icon name="water" />Su kayıtları</Link>
          <Link to="?kayit=olcumler" state={{ listSearch }} aria-current={view === 'olcumler' ? 'page' : undefined}><Icon name="chart" />Ölçümler</Link>
        </nav>
        <header className="card-header"><div><h2 id="records-title">{view === 'su' ? 'Su kayıtları' : view === 'olcumler' ? 'Ölçüm geçmişi' : 'Öğün günlüğü'}</h2><p>Kaynak, zaman ve birim bilgileriyle örnek kayıtlar.</p></div><span className="neutral-badge">Örnek veri</span></header>
        <TrackingPreviewState scenario={scenario} scope="records" onShowSample={() => setScenario('sample')}>
          {records && (view === 'su' ? <WaterLogList clientId={client.id} records={records.waterLogs} /> : view === 'olcumler' ? <BodyMeasurementList clientId={client.id} records={records.bodyMeasurements} /> : <MealLogList clientId={client.id} records={records.mealLogs} />)}
        </TrackingPreviewState>
      </section>
      <div className="inline-note"><Icon name="shield" /><p>Gerçek kayıtlarda doğrulanmış uzman, aktif ilişki ve ilgili paylaşım izni sunucuda denetlenmelidir. Bu önizleme erişim yetkisi vermez; tahliller için ayrıca açık onay gerekir.</p></div>
    </>
  )
}

export function ClientDetailsPage() {
  const { clientId } = useParams()
  const client = previewClients.find((entry) => entry.id === clientId)
  if (!client) return <div className="page-heading"><p className="eyebrow">DANIŞAN TAKİBİ</p><h1 tabIndex={-1}>Danışan bulunamadı.</h1><p>Bu kimlik için görüntülenebilecek bir örnek profil yok.</p><Link className="text-link" to="/onizleme/danisanlar"><Icon name="back" />Danışan listesine dön</Link></div>
  return <ClientDetailsContent key={client.id} client={client} />
}

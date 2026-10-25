import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Icon } from '../../core/components/Icon'
import type { IconName } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'

// Presentation labels, not domain objects or API response mocks.
const metrics: { title: string; icon: IconName; tone: string }[] = [
  { title: 'Aktif danışanlar', icon: 'users', tone: 'green' },
  { title: 'Bekleyen istekler', icon: 'link', tone: 'amber' },
  { title: 'Aktif programlar', icon: 'plan', tone: 'blue' },
  { title: 'Yeni öğün kayıtları', icon: 'leaf', tone: 'rose' },
]

export function DashboardPage() {
  const [today] = useState(() => new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long', year: 'numeric', weekday: 'long' }).format(new Date()))
  return (
    <>
      <div className="dashboard-heading"><div className="page-heading"><p className="eyebrow">ÇALIŞMA ALANINIZA HOŞ GELDİNİZ</p><h1 tabIndex={-1}>Genel bakış</h1><p>Danışan takibinizin bütünü, tek bir bakışta.</p></div><span className="date-label"><Icon name="clock" />{today}</span></div>
      <section className="welcome-panel" aria-labelledby="welcome-title">
        <div><span className="welcome-kicker"><span />DAHA ANLAMLI BİR TAKİP</span><h2 id="welcome-title">İyi bir takip,<br />küçük ayrıntılarla başlar.</h2><p>Danışanlarınızın yolculuğunu birlikte şekillendirin.</p><Link className="button button-welcome" to="/onizleme/danisanlar">Danışanlarımı görüntüle<Icon name="arrow" /></Link></div>
        <div className="welcome-art" aria-hidden="true"><div className="welcome-ring ring-one" /><div className="welcome-ring ring-two" /><span className="welcome-leaf"><Icon name="leaf" /></span><span className="art-caption">birlikte, adım adım.</span></div>
      </section>
      <section className="metrics-grid" aria-label="Takip göstergeleri">
        {metrics.map((metric) => <article className="metric-card" key={metric.title}><div className="metric-top"><h2>{metric.title}</h2><span className={`metric-icon ${metric.tone}`}><Icon name={metric.icon} /></span></div><strong className="metric-value" aria-label="Veri henüz alınmadı">—</strong><p>Veri bağlantısı bekleniyor</p></article>)}
      </section>
      <div className="dashboard-columns">
        <div className="dashboard-primary">
          <section className="card" aria-labelledby="recent-clients-title">
            <header className="card-header"><div><h2 id="recent-clients-title">Danışanlarım</h2><p>Günlük takibin başladığı yer.</p></div><Link className="text-link" to="/onizleme/danisanlar">Listeyi aç<Icon name="arrow" /></Link></header>
            <EmptyState icon="users" title="İlk bağlantıyla başlayacak">
              Danışan listeniz ve izinli kayıtlarınız burada yer alacak. Önizlemede gerçek veya örnek sağlık verisi gösterilmiyor.
            </EmptyState>
          </section>
          <section className="request-strip"><span className="strip-icon"><Icon name="link" /></span><div><h2>Yeni bir yolculuğun ilk adımı</h2><p>Danışanlarınızın bağlantı taleplerini bu alandan takip edin.</p></div><Link to="/onizleme/baglanti-istekleri" className="icon-button" aria-label="Bağlantı isteklerini aç"><Icon name="arrow" /></Link></section>
        </div>
        <aside className="dashboard-secondary" aria-label="Takip rehberi">
          <section className="card journey-card"><p className="eyebrow">BİRLİKTE İLERLEYİN</p><h2>Takibin üç adımı</h2><ol className="journey-list"><li><span>01</span><div><h3>Bağlantıyı kurun</h3><p>Danışanınızla karşılıklı onayla eşleşin.</p></div></li><li><span>02</span><div><h3>Paylaşılanı görün</h3><p>Yalnızca izin verilen kayıtları inceleyin.</p></div></li><li><span>03</span><div><h3>Birlikte planlayın</h3><p>Beslenme programıyla takibi sürdürün.</p></div></li></ol></section>
          <section className="privacy-card"><Icon name="shield" /><h2>Güven, iyi takibin temeli.</h2><p>Paylaşım danışanın kontrolündedir. Tahliller için ayrıca açık onay gerekir.</p><span>İZNE DAYALI TAKİP</span></section>
        </aside>
      </div>
    </>
  )
}

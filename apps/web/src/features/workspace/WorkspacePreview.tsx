import { useRef, useState } from 'react'
import { Link, NavLink, Route, Routes } from 'react-router-dom'
import { Brand, Icon } from '../../core/components/Icon'
import { EmptyState } from '../../core/components/EmptyState'
import { ThemeControl } from '../../core/theme/ThemeProvider'
import { DashboardPage } from './DashboardPage'

function ClientsPage() {
  return (
    <>
      <div className="page-heading"><p className="eyebrow">DANIŞAN TAKİBİ</p><h1 tabIndex={-1}>Danışanlarım</h1><p>Birlikte ilerlediğiniz danışanlar, tek bir yerde.</p></div>
      <section className="card" aria-labelledby="clients-title">
        <header className="card-header"><div><h2 id="clients-title">Danışan listesi</h2><p>Aktif bağlantılarınız burada görüntülenecek.</p></div><span className="neutral-badge">Önizleme</span></header>
        <div className="list-toolbar"><label className="search-field"><Icon name="search" /><input aria-label="Danışan ara" placeholder="Danışan adıyla ara" disabled /></label><p>Arama, danışanlar yüklendiğinde kullanılabilir.</p></div>
        <EmptyState icon="users" title="Danışan listeniz burada yer alacak" action={<Link className="button button-secondary" to="/onizleme/baglanti-istekleri">Bağlantı isteklerini incele<Icon name="arrow" /></Link>}>
          Önizlemede danışan verisi gösterilmiyor. Gerçek listeniz, karşılıklı onaylanan aktif bağlantılarınızı içerecek.
        </EmptyState>
      </section>
      <div className="inline-note"><Icon name="shield" /><p>Danışan bağlantısı, tüm sağlık kayıtlarına erişim anlamına gelmez. Paylaşılan her kategori için danışanın izni gerekir.</p></div>
    </>
  )
}

function RequestsPage() {
  return (
    <>
      <div className="page-heading"><p className="eyebrow">BİRLİKTE BAŞLAYIN</p><h1 tabIndex={-1}>Bağlantı istekleri</h1><p>Danışanlarınızla kuracağınız bağın ilk adımı.</p></div>
      <section className="card" aria-labelledby="requests-title">
        <header className="card-header"><div><h2 id="requests-title">Gelen istekler</h2><p>Bağlantı kurmak isteyen danışanların talepleri.</p></div><span className="neutral-badge">Önizleme</span></header>
        <EmptyState icon="link" title="Bağlantı istekleriniz burada yer alacak">
          Önizlemede istek verisi gösterilmiyor. Bir bağlantı ancak karşılıklı onayla aktif olur; danışanın en fazla bir aktif diyetisyeni olabilir.
        </EmptyState>
      </section>
      <div className="inline-note"><Icon name="info" /><p>Davet koduyla başlatılan bağlantılar da karşılıklı onay gerektirir. Bu önizleme bir bağlantı oluşturmaz veya onaylamaz.</p></div>
    </>
  )
}

export function WorkspacePreview() {
  const [menuOpen, setMenuOpen] = useState(false)
  const menuButton = useRef<HTMLButtonElement>(null)
  function closeMenu() { setMenuOpen(false) }
  return (
    <div className="workspace">
      <aside className="sidebar" onKeyDown={(event) => {
        if (event.key === 'Escape' && menuOpen) { setMenuOpen(false); menuButton.current?.focus() }
      }}>
        <div className="sidebar-brand"><Brand /><button className="icon-button mobile-menu" type="button" ref={menuButton}
          onClick={() => setMenuOpen(!menuOpen)} aria-expanded={menuOpen} aria-controls="workspace-navigation" aria-label={menuOpen ? 'Menüyü kapat' : 'Menüyü aç'}>
          <Icon name={menuOpen ? 'close' : 'menu'} /></button></div>
        <div id="workspace-navigation" className={`sidebar-content ${menuOpen ? 'is-open' : ''}`}>
          <p className="nav-heading">ÇALIŞMA ALANI</p>
          <nav aria-label="Diyetisyen paneli">
            <NavLink to="/onizleme" end onClick={closeMenu}><Icon name="grid" />Genel bakış</NavLink>
            <NavLink to="/onizleme/danisanlar" onClick={closeMenu}><Icon name="users" />Danışanlarım</NavLink>
            <NavLink to="/onizleme/baglanti-istekleri" onClick={closeMenu}><Icon name="link" />Bağlantı istekleri</NavLink>
          </nav>
          <p className="nav-heading upcoming-heading">SONRAKİ ADIMLAR</p>
          <ul className="upcoming-nav" aria-label="Henüz kullanılamayan bölümler">
            <li><Icon name="plan" />Beslenme programları</li><li><Icon name="check" />Görevler</li><li><Icon name="chart" />Analiz ve raporlar</li>
          </ul>
          <div className="sidebar-note"><span className="small-leaf"><Icon name="leaf" /></span><h2>Her danışan, ayrı bir yolculuk.</h2><p>Daha görünür bir takip, daha anlamlı görüşmeler.</p></div>
          <div className="sidebar-footer"><span className="status-dot" /><span>Tasarım önizlemesi<small>Gerçek hesap bağlı değil</small></span></div>
        </div>
      </aside>
      <div className="workspace-body">
        <header className="workspace-header"><div className="workspace-context"><span>Diyetisyen paneli</span><span className="header-divider">/</span><strong>Çalışma alanı</strong></div><div className="header-actions"><ThemeControl /><Link to="/giris" className="header-login">Giriş ekranı<Icon name="arrow" /></Link></div></header>
        <div className="workspace-notice"><span className="preview-badge">Önizleme</span><p>Hesap ve danışan verisi bağlı değil. Gösterilen alanlar yalnızca tasarımı incelemek içindir.</p></div>
        <main id="main-content" className="workspace-main">
          <Routes>
            <Route index element={<DashboardPage />} />
            <Route path="danisanlar" element={<ClientsPage />} />
            <Route path="baglanti-istekleri" element={<RequestsPage />} />
            <Route path="*" element={<div className="page-heading"><h1 tabIndex={-1}>Bu bölüm bulunamadı.</h1><Link className="text-link" to="/onizleme">Genel bakışa dön</Link></div>} />
          </Routes>
          <footer className="workspace-footer"><span>Smart Nutrition Platform</span><span>Takibin merkezinde, danışanınız.</span></footer>
        </main>
      </div>
    </div>
  )
}

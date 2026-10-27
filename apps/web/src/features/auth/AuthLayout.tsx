import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Brand, Icon } from '../../core/components/Icon'
import { ThemeControl } from '../../core/theme/ThemeProvider'

export function AuthLayout({ title, description, children, isLogin = false, badge = 'Arayüz önizlemesi' }: {
  title: string; description: string; children: ReactNode; isLogin?: boolean; badge?: string
}) {
  return (
    <div className="auth-layout">
      <aside className="auth-story">
        <Brand inverse />
        <div className="story-copy">
          <p className="eyebrow">BİRLİKTE, DAHA İYİ BİR TAKİP.</p>
          <h2>Danışanınıza odaklanın.<br /><span>Bütünü bir arada görün.</span></h2>
          <p>Beslenme kayıtları, programlar ve gelişim.<br />Diyetisyenlik pratiğiniz için sakin bir çalışma alanı.</p>
          <div className="story-art" aria-hidden="true"><div className="art-orbit" /><Icon name="leaf" /><span className="art-dot" /></div>
          <div className="story-note"><Icon name="shield" /><span>Paylaşım danışanın kontrolünde.<br /><strong>Her adımda, izinli erişim.</strong></span></div>
        </div>
        <p className="story-footer">SMART NUTRITION PLATFORM</p>
      </aside>
      <div className="auth-main">
        <header className="auth-header"><span className="preview-badge">{badge}</span><ThemeControl /></header>
        <main id="main-content" className="auth-content">
          {!isLogin && <Link to="/giris" className="text-link back-link"><Icon name="back" />Giriş ekranına dön</Link>}
          <span className="auth-icon"><Icon name={isLogin ? 'leaf' : 'link'} /></span>
          <p className="eyebrow">SMART NUTRITION</p>
          <h1 tabIndex={-1}>{title}</h1>
          <p className="auth-description">{description}</p>
          {children}
        </main>
        <footer className="auth-footer">Diyetisyen ve danışan arasında, daha güçlü bir bağ.</footer>
      </div>
    </div>
  )
}

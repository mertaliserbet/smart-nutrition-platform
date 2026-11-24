import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Brand, Icon } from '../../core/components/Icon'
import { LegalLinks } from '../../core/components/LegalLinks'
import './login.css'

export function AuthLayout({ title, description, children, isLogin = false, registration = false, badge = 'Hesap', backTo = '/giris', secondary }: {
  title: string; description: string; children: ReactNode; isLogin?: boolean; registration?: boolean; badge?: string; backTo?: string; secondary?: ReactNode
}) {
  return <div className={`auth-layout${isLogin ? ' auth-layout-login' : ''}${registration ? ' auth-layout-registration' : ''}`}>
    <div className="auth-shell">
      <header className="auth-header">
        <Link to="/giris" aria-label="Limely giriş ekranı"><Brand subtitle="" /></Link>
        <div className="auth-header-actions">{registration ? <><span>Zaten hesabın var mı?</span><Link className="text-link" to="/giris">Giriş yap</Link></> : <Link className="text-link" to="/">Ana sayfaya dön<Icon name="arrow" /></Link>}</div>
      </header>
      <main id="main-content" className="auth-content">
        {!isLogin && !registration && <Link to={backTo} className="text-link back-link"><Icon name="back" />Giriş ekranına dön</Link>}
        <p className="auth-badge">{badge}</p>
        <h1 tabIndex={-1}>{title}{isLogin && <span className="heading-rays" aria-hidden="true" />}</h1>
        <p className="auth-description">{description}</p>
        <div className="auth-form-surface">{children}</div>
      </main>
      {isLogin && <div className="auth-encouragement" aria-hidden="true"><img src="/images/limely-mascot-lime.png" width="1536" height="1024" alt="" /><p>Küçük adımlar,<br />düzenli takip.</p></div>}
      <footer className="auth-footer">{isLogin ? <LegalLinks /> : <><Icon name="shield" /><span>Paylaşım danışanın kontrolünde. Her adımda izinli erişim.</span><span className="auth-footer-brand">Limely</span></>}</footer>
      {secondary}
      {isLogin && <p className="auth-mobile-note">Danışan kaydı ve danışan işlemleri mobil uygulamada yapılır.</p>}
    </div>
  </div>
}

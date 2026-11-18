import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Link, NavLink, useLocation, useNavigate } from 'react-router-dom'
import { Brand, Icon } from '../../core/components/Icon'
import type { IconName } from '../../core/components/Icon'
import { ThemeControl } from '../../core/theme/ThemeProvider'
import { logout } from '../auth/webSessionApi'
import { WorkspaceProfileMenu } from './WorkspaceProfileMenu'
import './workspace.css'

type WorkspaceProfile = { displayName: string; email: string; token: string }

export function WorkspaceLayout({ audience, profile, children }: {
  audience: 'dietitian' | 'admin'; profile?: WorkspaceProfile; children: ReactNode
}) {
  const [menuOpen, setMenuOpen] = useState(false)
  const [signingOut, setSigningOut] = useState(false)
  const menuButton = useRef<HTMLButtonElement>(null)
  const operation = useRef<AbortController | null>(null)
  const { pathname } = useLocation()
  const navigate = useNavigate()
  const admin = audience === 'admin'
  const navigation: { to: string; label: string; icon: IconName; end?: boolean }[] = admin
    ? [{ to: '/yonetim/uzmanlar', label: 'Uzman başvuruları', icon: 'shield' }]
    : [
      { to: '/calisma-alani', label: 'Genel bakış', icon: 'grid', end: true },
      { to: '/calisma-alani/danisanlar', label: 'Danışanlarım', icon: 'users' },
      { to: '/calisma-alani/baglantilar', label: 'Bağlantılar ve davet', icon: 'link' },
    ]
  const title = [...navigation].reverse().find(item => pathname.startsWith(item.to))?.label ?? 'Çalışma alanı'
  const returnTo = admin ? '/yonetici-giris' : '/giris'
  useEffect(() => () => operation.current?.abort(), [])

  async function signOut() {
    if (!profile || operation.current) return
    const controller = new AbortController()
    operation.current = controller
    setSigningOut(true)
    try {
      await logout(profile.token, controller.signal)
      if (!controller.signal.aborted) navigate(returnTo, { replace: true })
    } catch {
      if (!controller.signal.aborted) navigate('/hesabim', { replace: true, state: { returnTo, logoutRecovery: true } })
    }
  }

  if (signingOut) return <main id="main-content" className="not-found" aria-busy="true"><h1 tabIndex={-1}>Çıkış yapılıyor</h1><p role="status">Oturum kapatılıyor…</p></main>

  return <div className="workspace live-workspace">
    <aside className="sidebar" onKeyDown={event => {
      if (event.key === 'Escape' && menuOpen) { setMenuOpen(false); menuButton.current?.focus() }
    }}>
      <div className="sidebar-brand"><Brand subtitle={admin ? 'YÖNETİM ÇALIŞMA ALANI' : 'DİYETİSYEN ÇALIŞMA ALANI'} /><button ref={menuButton} className="icon-button mobile-menu" type="button"
        onClick={() => setMenuOpen(value => !value)} aria-expanded={menuOpen} aria-controls="live-navigation" aria-label={menuOpen ? 'Menüyü kapat' : 'Menüyü aç'}>
        <Icon name={menuOpen ? 'close' : 'menu'} /></button></div>
      <div id="live-navigation" className={`sidebar-content ${menuOpen ? 'is-open' : ''}`}>
        <p className="nav-heading">{admin ? 'YÖNETİM' : 'ÇALIŞMA ALANI'}</p>
        <nav aria-label={admin ? 'Yönetici paneli' : 'Diyetisyen çalışma alanı'}>
          {navigation.map(item => <NavLink key={item.to} to={item.to} end={item.end} onClick={() => setMenuOpen(false)}><Icon name={item.icon} />{item.label}</NavLink>)}
        </nav>
        <div className="sidebar-note"><span className="small-leaf"><Icon name={admin ? 'shield' : 'leaf'} /></span>
          <h2>{admin ? 'Güvenli bir başlangıç.' : 'Her danışan, ayrı bir yolculuk.'}</h2>
          <p>{admin ? 'Uzman başvurularını inceleyin, mesleki doğrulamayı tamamlayın.' : 'Bağlantıyı kurun, paylaşılanı görün, birlikte planlayın.'}</p>
        </div>
      </div>
    </aside>
    <div className="workspace-body">
      <header className="workspace-header"><div className="workspace-context"><span>{admin ? 'Yönetici paneli' : 'Diyetisyen paneli'}</span><span className="header-divider">/</span><strong>{title}</strong></div>
        <div className="header-actions">
          <ThemeControl />
          {profile && <WorkspaceProfileMenu key={pathname} displayName={profile.displayName} email={profile.email}>
            <Link to="/hesabim" state={{ returnTo }}>Hesabım<Icon name="arrow" /></Link>
            <button type="button" onClick={() => { void signOut() }}>Çıkış yap</button>
          </WorkspaceProfileMenu>}
        </div>
      </header>
      <main id="main-content" className="workspace-main">{children}
        <footer className="workspace-footer"><span>Smart Nutrition Platform</span><span>{admin ? 'Uzman doğrulama ve başvuru yönetimi.' : 'Takibin merkezinde, danışanınız.'}</span></footer>
      </main>
    </div>
  </div>
}

import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { Brand, Icon } from '../../core/components/Icon'
import type { IconName } from '../../core/components/Icon'
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
  const { pathname, search } = useLocation()
  const navigate = useNavigate()
  const admin = audience === 'admin'
  const navigation: { to: string; label: string; icon: IconName; end?: boolean }[] = admin
    ? [{ to: '/yonetim/uzmanlar', label: 'Uzman başvuruları', icon: 'shield' }]
    : [
      { to: '/calisma-alani', label: 'Genel bakış', icon: 'grid', end: true },
      { to: '/calisma-alani/danisanlar', label: 'Danışanlar', icon: 'users' },
      { to: '/calisma-alani/ogun-incelemeleri', label: 'Öğün incelemeleri', icon: 'meal' },
      { to: '/calisma-alani/programlar', label: 'Programlar', icon: 'plan' },
      { to: '/calisma-alani/randevular', label: 'Randevular', icon: 'calendar' },
      { to: '/calisma-alani/mesajlar', label: 'Mesajlar', icon: 'message' },
      { to: '/calisma-alani/raporlar', label: 'Raporlar', icon: 'chart' },
    ]
  const selectedSection = new URLSearchParams(search).get('bolum')
  function isCurrent(to: string) {
    if (pathname.startsWith('/calisma-alani/danisanlar/')) {
      const sectionRoutes: Record<string, string> = { program: '/calisma-alani/programlar', ogunler: '/calisma-alani/ogun-incelemeleri', 'olcum-su': '/calisma-alani/raporlar' }
      return to === (sectionRoutes[selectedSection ?? ''] ?? '/calisma-alani/danisanlar')
    }
    return to === '/calisma-alani' ? pathname === to : pathname.startsWith(to)
  }
  const title = navigation.find(item => isCurrent(item.to))?.label ?? (pathname === '/hesabim' ? 'Hesabım' : 'Çalışma alanı')
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
      <div className="sidebar-brand"><Link to={admin ? '/yonetim/uzmanlar' : '/calisma-alani'} aria-label="Limely ana panel"><Brand subtitle={admin ? 'YÖNETİCİ' : 'DİYETİSYEN'} /></Link><button ref={menuButton} className="icon-button mobile-menu" type="button"
        onClick={() => setMenuOpen(value => !value)} aria-expanded={menuOpen} aria-controls="live-navigation" aria-label={menuOpen ? 'Menüyü kapat' : 'Menüyü aç'}>
        <Icon name={menuOpen ? 'close' : 'menu'} /></button></div>
      <div id="live-navigation" className={`sidebar-content ${menuOpen ? 'is-open' : ''}`}>
        <nav aria-label={admin ? 'Yönetici paneli' : 'Diyetisyen çalışma alanı'}>
          {navigation.map(item => <Link key={item.to} to={item.to} className={isCurrent(item.to) ? 'active' : undefined} aria-current={isCurrent(item.to) ? 'page' : undefined} onClick={() => setMenuOpen(false)}><Icon name={item.icon} />{item.label}</Link>)}
        </nav>
        <div className="sidebar-account"><Link className={pathname === '/hesabim' ? 'active' : ''} to="/hesabim" onClick={() => setMenuOpen(false)}><Icon name="settings" />Ayarlar</Link></div>
        {profile && <WorkspaceProfileMenu key={pathname} displayName={profile.displayName} email={profile.email} showName>
          <Link to="/hesabim" state={{ returnTo }}>Hesabım<Icon name="arrow" /></Link>
          {!admin && <Link to="/calisma-alani/baglantilar">Bağlantılar ve davet<Icon name="link" /></Link>}
          <button type="button" onClick={() => { void signOut() }}>Çıkış yap</button>
        </WorkspaceProfileMenu>}
      </div>
    </aside>
    <div className="workspace-body">
      <span className="sr-only">{title}</span>
      <main id="main-content" className="workspace-main">{children}
      </main>
    </div>
  </div>
}

import { useEffect } from 'react'
import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { AuthPage } from './features/auth/AuthPage'
import { EmailVerificationPage } from './features/auth/EmailVerificationPage'
import { AccountPage } from './features/auth/AccountPage'
import { RegistrationPage } from './features/auth/RegistrationPage'
import { WorkspacePreview } from './features/workspace/WorkspacePreview'
import { ThemeProvider } from './core/theme/ThemeProvider'

function RouteFocus() {
  const { pathname } = useLocation()
  useEffect(() => {
    const heading = document.querySelector<HTMLHeadingElement>('h1')
    heading?.focus()
    document.title = `${heading?.textContent ?? 'Sayfa bulunamadı'} · Smart Nutrition`
  }, [pathname])
  return null
}

export default function App() {
  return (
    <ThemeProvider>
      <a className="skip-link" href="#main-content">İçeriğe geç</a>
      <Routes>
        <Route path="/" element={<Navigate to="/giris" replace />} />
        <Route path="/giris" element={<AuthPage key="login" mode="login" />} />
        <Route path="/kayit" element={<RegistrationPage />} />
        <Route path="/sifremi-unuttum" element={<AuthPage key="reset" mode="reset" />} />
        <Route path="/eposta-dogrulama" element={<EmailVerificationPage />} />
        <Route path="/hesabim" element={<AccountPage />} />
        {import.meta.env.DEV && <Route path="/onizleme/*" element={<WorkspacePreview />} />}
        <Route path="*" element={
          <main id="main-content" className="not-found">
            <p className="eyebrow">SMART NUTRITION</p>
            <h1 tabIndex={-1}>Bu sayfa bulunamadı.</h1>
            <p>Devam etmek için giriş ekranına dönebilirsiniz.</p>
            <a className="button button-primary" href="/giris">Giriş ekranına dön</a>
          </main>
        } />
      </Routes>
      <RouteFocus />
    </ThemeProvider>
  )
}

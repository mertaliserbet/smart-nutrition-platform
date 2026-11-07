import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, Route, Routes, useNavigate } from 'react-router-dom'
import { getAccount, getCsrf, WebSessionError } from '../auth/webSessionApi'
import { getDietitianStatus } from '../dietitians/dietitianApi'
import { ConnectionsPage } from '../relationships/ConnectionsPage'
import { LiveClientsPage, LiveClientDetailsPage } from '../relationships/LiveClientsPage'
import { WorkspaceContext } from './workspaceSession'
import type { WorkspaceSession } from './workspaceSession'
import { WorkspaceLayout } from './WorkspaceLayout'
import { LiveDashboardPage } from './LiveDashboardPage'
export function DietitianWorkspace() {
  const [session, setSession] = useState<WorkspaceSession>()
  const [displayName, setDisplayName] = useState<string>()
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState('')
  const operation = useRef<AbortController | null>(null)
  const navigate = useNavigate()
  const onFailure = useCallback((error: unknown) => {
    if (error instanceof WebSessionError && [400, 401, 403].includes(error.status)) {
      setSession(undefined); setDisplayName(undefined); setMessage(error.message)
      if (error.status === 401) navigate('/giris', { replace: true })
      return true
    }
    return false
  }, [navigate])
  async function load() {
    if (operation.current) return
    const controller = new AbortController(); operation.current = controller
    setSession(undefined); setDisplayName(undefined); setMessage(''); setPending(true)
    try {
      const token = await getCsrf(controller.signal)
      const user = await getAccount(controller.signal)
      if (user.role !== 'dietitian' && user.role !== 'client') throw new WebSessionError(403, 'Bu çalışma alanı doğrulanmış diyetisyenler içindir.')
      const profile = await getDietitianStatus(controller.signal)
      if (!controller.signal.aborted) {
        if (!profile.isVerified) navigate('/uzman/basvuru-durumu', { replace: true })
        else { setSession({ token, dietitianId: profile.id, onFailure }); setDisplayName(profile.displayName) }
      }
    } catch (error) {
      if (!controller.signal.aborted && !onFailure(error)) setMessage(error instanceof WebSessionError ? error.message : 'Çalışma alanı açılamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }
  useEffect(() => {
    void load()
    return () => { operation.current?.abort(); operation.current = null }
    // Restore once on entry; never poll to keep a session alive.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return <WorkspaceLayout audience="dietitian" displayName={displayName}>
        {pending && <><h1 tabIndex={-1}>Çalışma alanı</h1><p role="status">Hesap ve uzman doğrulaması kontrol ediliyor…</p></>}
        {message && <><h1 tabIndex={-1}>Çalışma alanı</h1><p className="form-message error-message" role="alert">{message}</p>
          <Link className="text-link" to="/uzman-basvurusu">Diyetisyen başvuru seçeneklerini aç</Link></>}
        {!session && !pending && <button className="button button-secondary" onClick={() => { void load() }}>Erişimi yeniden kontrol et</button>}
        {session && <WorkspaceContext.Provider value={session}><Routes>
          <Route index element={<LiveDashboardPage />} />
          <Route path="danisanlar" element={<LiveClientsPage />} />
          <Route path="danisanlar/:clientId" element={<LiveClientDetailsPage />} />
          <Route path="baglantilar" element={<ConnectionsPage />} />
          <Route path="*" element={<><h1 tabIndex={-1}>Bölüm bulunamadı</h1><Link to="/calisma-alani/danisanlar">Danışanlarıma dön</Link></>} />
        </Routes></WorkspaceContext.Provider>}
  </WorkspaceLayout>
}

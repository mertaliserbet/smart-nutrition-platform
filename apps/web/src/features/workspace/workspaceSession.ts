import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react'
import { WebSessionError } from '../auth/webSessionApi'

export type WorkspaceSession = { token: string; dietitianId: string; onFailure: (error: unknown) => boolean }
export const WorkspaceContext = createContext<WorkspaceSession | null>(null)
export function useWorkspaceSession() {
  const value = useContext(WorkspaceContext)
  if (!value) throw new Error('A workspace session is required.')
  return value
}

// The request key changes synchronously with filters/routes, hiding old private data.
export function useWorkspaceRead<T>(load: (signal: AbortSignal) => Promise<T>, handleLocally?: (error: unknown) => boolean) {
  const [request, setRequest] = useState({ revision: 0, background: false })
  const [snapshot, setSnapshot] = useState<{ load: typeof load; revision: number; token: string; dietitianId: string; data?: T; message: string }>()
  const { onFailure, token, dietitianId } = useWorkspaceSession()
  const operation = useRef<AbortController | null>(null)
  const checking = useRef(false)
  const refresh = useCallback(() => {
    operation.current?.abort()
    operation.current = null
    setSnapshot(undefined)
    checking.current = true
    setRequest(value => ({ revision: value.revision + 1, background: false }))
  }, [])
  const revalidate = useCallback(() => {
    if (checking.current) return
    checking.current = true
    setRequest(value => ({ revision: value.revision + 1, background: true }))
  }, [])
  useEffect(() => {
    const controller = new AbortController()
    operation.current = controller; checking.current = true
    const identity = { load, revision: request.revision, token, dietitianId }
    void load(controller.signal).then(data => {
      if (!controller.signal.aborted) setSnapshot({ ...identity, data, message: '' })
    }).catch((error: unknown) => {
      if (controller.signal.aborted) return
      const handled = handleLocally?.(error) || onFailure(error)
      setSnapshot({ ...identity, message: handled ? '' : error instanceof WebSessionError ? error.message : 'Kayıtlar okunamadı.' })
    }).finally(() => {
      if (operation.current === controller) checking.current = false
    })
    return () => controller.abort()
  }, [load, request.revision, onFailure, handleLocally, token, dietitianId])
  const sameSource = snapshot?.load === load && snapshot?.token === token && snapshot?.dietitianId === dietitianId
  const current = sameSource && snapshot?.revision === request.revision
  return { data: sameSource && (current || request.background) ? snapshot?.data : undefined,
    message: current ? snapshot?.message : '', pending: !current, refresh, revalidate }
}

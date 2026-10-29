import { createContext, useContext, useEffect, useState } from 'react'
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
  const [revision, setRevision] = useState(0)
  const [snapshot, setSnapshot] = useState<{ load: typeof load; revision: number; data?: T; message: string }>()
  const { onFailure } = useWorkspaceSession()
  useEffect(() => {
    const controller = new AbortController()
    void load(controller.signal).then(data => {
      if (!controller.signal.aborted) setSnapshot({ load, revision, data, message: '' })
    }).catch((error: unknown) => {
      if (controller.signal.aborted) return
      if (handleLocally?.(error)) setSnapshot({ load, revision, message: '' })
      else if (!onFailure(error)) setSnapshot({ load, revision, message: error instanceof WebSessionError ? error.message : 'Kayıtlar okunamadı.' })
    })
    return () => controller.abort()
  }, [load, revision, onFailure, handleLocally])
  const current = snapshot?.load === load && snapshot?.revision === revision
  return { data: current ? snapshot?.data : undefined, message: current ? snapshot?.message : '', pending: !current,
    refresh: () => setRevision(value => value + 1) }
}

import { useContext, useEffect } from 'react'
import { UNSAFE_LocationContext } from 'react-router-dom'

// Register before BrowserRouter mounts: its POP listener can synchronously
// unmount the editor before a later listener gets to restore the history entry.
let interceptPop: ((event: PopStateEvent) => void) | undefined
const dispatchPop = (event: PopStateEvent) => interceptPop?.(event)
window.addEventListener('popstate', dispatchPop, true)
if (import.meta.hot) import.meta.hot.dispose(() => window.removeEventListener('popstate', dispatchPop, true))

// Section/query links keep the mounted editor. Browser POP is restored before
// asking and replayed only on confirmation. No draft data enters history.
export function usePlanNavigation(dirty: boolean, confirm: (proceed: () => void) => void) {
  const location = useContext(UNSAFE_LocationContext)
  const pathname = location?.location.pathname ?? window.location.pathname
  useEffect(() => {
    if (!dirty) return
    const unload = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = '' }
    let index = window.history.state?.idx as number | undefined
    let restoring = false, allowed = false, followingLink = false
    const click = (event: MouseEvent) => {
      if (followingLink || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      const anchor = event.target instanceof Element ? event.target.closest('a') : null
      if (!anchor || anchor.target === '_blank' || anchor.hasAttribute('download')) return
      const url = new URL(anchor.href, window.location.href)
      if (url.origin === window.location.origin && (url.pathname === pathname || url.pathname === '/giris')) return
      event.preventDefault(); event.stopPropagation()
      confirm(() => { followingLink = true; anchor.click(); followingLink = false })
    }
    const pop = (event: PopStateEvent) => {
      const next = event.state?.idx as number | undefined
      if (restoring) { restoring = false; event.stopImmediatePropagation(); return }
      if (allowed || window.location.pathname === pathname || index === undefined || next === undefined) { allowed = false; index = next; return }
      const delta = next - index
      if (!delta) return
      event.stopImmediatePropagation(); restoring = true
      window.history.go(-delta)
      confirm(() => { allowed = true; window.history.go(delta) })
    }
    // Observe successful section links after Router has advanced its index.
    const updateIndex = () => { index = window.history.state?.idx }
    document.addEventListener('click', click, true)
    document.addEventListener('click', updateIndex)
    window.addEventListener('beforeunload', unload)
    interceptPop = pop
    return () => {
      document.removeEventListener('click', click, true); document.removeEventListener('click', updateIndex)
      window.removeEventListener('beforeunload', unload); if (interceptPop === pop) interceptPop = undefined
    }
  }, [dirty, confirm, pathname])
}

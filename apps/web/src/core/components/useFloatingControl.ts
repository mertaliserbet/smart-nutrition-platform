import { useLayoutEffect, useRef } from 'react'
import type { RefObject } from 'react'

// The top layer keeps controls visible inside cards, scroll panels and dialogs.
export function useFloatingControl(open: boolean, anchor: RefObject<HTMLElement | null>, close: () => void) {
  const popup = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    if (!open || !popup.current || !anchor.current) return
    const panel = popup.current
    if (typeof panel.showPopover === 'function') panel.showPopover()
    else panel.removeAttribute('popover')
    function position() {
      const element = anchor.current
      if (!element) return
      const box = element.getBoundingClientRect(), margin = 12, gap = 8
      if (box.bottom < 0 || box.top > innerHeight) { close(); return }
      panel.style.width = `${Math.min(Math.max(box.width, panel.classList.contains('date-popup') ? 330 : 240), innerWidth - margin * 2)}px`
      panel.style.maxHeight = `${innerHeight - margin * 2}px`
      const desired = Math.min(panel.scrollHeight, panel.classList.contains('date-popup') ? 470 : 320)
      const below = innerHeight - box.bottom - margin - gap, above = box.top - margin - gap
      const up = below < desired && above > below
      panel.style.maxHeight = `${Math.min(Math.max(72, up ? above : below), panel.classList.contains('date-popup') ? 470 : 320)}px`
      const height = panel.getBoundingClientRect().height, width = panel.getBoundingClientRect().width
      panel.style.left = `${Math.max(margin, Math.min(box.left, innerWidth - width - margin))}px`
      panel.style.top = `${Math.max(margin, Math.min(up ? box.top - height - gap : box.bottom + gap, innerHeight - height - margin))}px`
    }
    function outside(event: Event) {
      if (event.target instanceof Node && !panel.contains(event.target) && !anchor.current?.contains(event.target)) close()
    }
    function scroll(event: Event) { if (event.target instanceof Node && !panel.contains(event.target)) position() }
    position()
    document.addEventListener('pointerdown', outside)
    document.addEventListener('focusin', outside)
    document.addEventListener('scroll', scroll, true)
    window.addEventListener('resize', close)
    return () => {
      document.removeEventListener('pointerdown', outside)
      document.removeEventListener('focusin', outside)
      document.removeEventListener('scroll', scroll, true)
      window.removeEventListener('resize', close)
      if (typeof panel.hidePopover === 'function') panel.hidePopover()
    }
  }, [open, anchor, close])
  return popup
}

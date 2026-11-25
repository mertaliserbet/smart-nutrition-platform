import { createPortal } from 'react-dom'
import { forwardRef, useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import type { SelectHTMLAttributes } from 'react'
import { Icon } from './Icon'
import { useFloatingControl } from './useFloatingControl'
import './formControls.css'

type Option = { value: string; label: string; disabled: boolean }

// Keep the native value, labels, validation and onChange contract intact.
export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Select({ children, onChange, onMouseDown, onClick, onKeyDown, value, disabled, ...props }, forwardedRef) {
  const input = useRef<HTMLSelectElement>(null)
  const restoreFocus = useRef(false)
  const [open, setOpen] = useState(false)
  const [options, setOptions] = useState<Option[]>([])
  const [selectedValue, setSelectedValue] = useState('')
  const [context, setContext] = useState({ value, disabled })
  if (context.value !== value || context.disabled !== disabled) { setContext({ value, disabled }); if (open) setOpen(false) }
  const [active, setActive] = useState(0)
  const id = useId()
  const search = useRef({ text: '', time: 0 })
  const close = useCallback(() => setOpen(false), [])
  const popup = useFloatingControl(open, input, close)
  useLayoutEffect(() => {
    const element = input.current
    if (!restoreFocus.current || !element || element.matches(':disabled')) return
    // A pending filter read temporarily disables the native control. Restore only
    // if the user has not deliberately moved to another element in the meantime.
    if (document.activeElement === document.body || document.activeElement === element) element.focus({ preventScroll: true })
    restoreFocus.current = false
  }, [disabled, open])
  useEffect(() => {
    if (!open) return
    popup.current?.querySelector<HTMLElement>(`[data-index="${active}"]`)?.scrollIntoView?.({ block: 'nearest' })
  }, [active, open, popup])

  function available(index: number, direction: number, choices = options) {
    while (index >= 0 && index < choices.length && choices[index]?.disabled) index += direction
    return index >= 0 && index < choices.length ? index : -1
  }
  function show(last = false) {
    const element = input.current
    if (!element || element.matches(':disabled')) return
    const choices = Array.from(element.options, option => ({ value: option.value, label: option.label, disabled: option.disabled || option.parentElement?.matches('optgroup:disabled') === true }))
    setOptions(choices)
    setSelectedValue(element.value)
    setActive(last ? available(choices.length - 1, -1, choices) : Math.max(0, element.selectedIndex))
    search.current = { text: '', time: 0 }
    setOpen(true)
    return choices
  }
  function choose(index: number) {
    const element = input.current, option = options[index]
    if (!element || element.matches(':disabled') || !option || option.disabled) return
    element.value = option.value
    restoreFocus.current = true
    close()
    element.focus({ preventScroll: true })
    element.dispatchEvent(new Event('change', { bubbles: true }))
  }
  return <span className="select-control">
    <select {...props} value={value} disabled={disabled} data-limely-select ref={element => {
      input.current = element
      if (typeof forwardedRef === 'function') forwardedRef(element)
      else if (forwardedRef) forwardedRef.current = element
    }} aria-expanded={open} aria-haspopup="listbox" aria-controls={open ? id : undefined} aria-activedescendant={open ? `${id}-${active}` : undefined}
      onChange={event => { close(); onChange?.(event) }}
      onMouseDown={event => { onMouseDown?.(event); if (event.defaultPrevented || event.button !== 0 || event.currentTarget.matches(':disabled')) return; event.preventDefault(); event.currentTarget.focus(); if (open) close(); else show() }}
      onClick={event => { onClick?.(event); if (!event.defaultPrevented && event.detail === 0 && !event.currentTarget.matches(':disabled')) { event.preventDefault(); if (open) close(); else show() } }}
      onKeyDown={event => {
        onKeyDown?.(event)
        if (event.defaultPrevented || event.currentTarget.matches(':disabled')) return
        const key = event.key
        if (key === 'Escape' && open) { event.preventDefault(); event.stopPropagation(); close(); return }
        if (key === 'Tab') { close(); return }
        const printable = key.length === 1 && key !== ' ' && !event.ctrlKey && !event.metaKey && !event.altKey
        if (!['ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter', ' '].includes(key) && !printable) return
        event.preventDefault()
        if (!open) {
          const choices = show(key === 'End' || key === 'ArrowUp') ?? []
          if (key === 'Home') setActive(available(0, 1, choices))
          if (printable) {
            search.current = { text: key, time: Date.now() }
            const found = choices.findIndex(option => !option.disabled && option.label.toLocaleLowerCase('tr-TR').startsWith(key.toLocaleLowerCase('tr-TR')))
            if (found >= 0) setActive(found)
          }
          return
        }
        if (key === 'Enter' || key === ' ') { choose(active); return }
        if (key === 'ArrowDown' || key === 'ArrowUp') { const next = available(active + (key === 'ArrowDown' ? 1 : -1), key === 'ArrowDown' ? 1 : -1); if (next >= 0) setActive(next) }
        if (key === 'Home') setActive(available(0, 1))
        if (key === 'End') setActive(available(options.length - 1, -1))
        if (printable) {
          const now = Date.now(), text = now - search.current.time > 700 ? key : search.current.text + key
          search.current = { text, time: now }
          const found = options.findIndex(option => !option.disabled && option.label.toLocaleLowerCase('tr-TR').startsWith(text.toLocaleLowerCase('tr-TR')))
          if (found >= 0) setActive(found)
        }
      }}>{children}</select>
    <span className={`select-caret${open ? ' is-open' : ''}`}><Icon name="chevron" /></span>
    {open && createPortal(<div ref={popup} id={id} popover="manual" className="control-popup select-popup" role="listbox" aria-label={props['aria-label'] ? `${props['aria-label']} seçenekleri` : 'Seçenekler'}>
      {options.map((option, index) => <div key={`${index}-${option.value}`} id={`${id}-${index}`} role="option" aria-selected={String(value ?? selectedValue) === option.value} aria-disabled={option.disabled || undefined} data-index={index} className={`control-option${active === index ? ' is-active' : ''}`} onPointerDown={event => event.preventDefault()} onPointerMove={() => { if (!option.disabled) setActive(index) }} onClick={() => choose(index)}>
        <span>{option.label}</span><span className="option-check"><Icon name="check" /></span>
      </div>)}
    </div>, document.body)}
  </span>
})

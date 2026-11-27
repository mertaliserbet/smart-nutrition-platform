import { fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { Select } from './Select'
import { DateField } from './DateField'

function Choice({ change }: { change?: (value: string) => void }) {
  const [value, setValue] = useState('')
  return <label>Danışan<Select value={value} required onChange={event => { change?.(event.target.value); setValue(event.target.value) }}><option value="">Seçin</option><option value="elif">Elif</option><option value="kerem">Kerem</option><option disabled value="kapali">Kapalı</option></Select></label>
}

describe('shared approved form controls', () => {
  it('commits a visual option through the existing native change and validation flow', async () => {
    const change = vi.fn(), user = userEvent.setup()
    render(<Choice change={change} />)
    const select = screen.getByRole<HTMLSelectElement>('combobox', { name: 'Danışan' })
    expect(select.checkValidity()).toBe(false)
    await user.click(select)
    await user.click(within(screen.getByRole('listbox')).getByRole('option', { name: 'Elif' }))
    expect(select).toHaveValue('elif'); expect(select.checkValidity()).toBe(true)
    expect(change).toHaveBeenCalledExactlyOnceWith('elif')
    expect(select).toHaveFocus(); expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
  })

  it('keeps native disabled fieldsets authoritative', async () => {
    const user = userEvent.setup()
    render(<fieldset disabled><label>Durum<Select><option>Aktif</option></Select></label></fieldset>)
    await user.click(screen.getByRole('combobox'))
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
  })

  it('supports typeahead from the first character and discards Escape navigation', async () => {
    const user = userEvent.setup(); render(<Choice />)
    const select = screen.getByRole('combobox')
    select.focus(); await user.keyboard('ker{Enter}')
    expect(select).toHaveValue('kerem')
    await user.keyboard('{Home}{ArrowDown}{Escape}')
    expect(select).toHaveValue('kerem')
    expect(select).toHaveFocus()
  })

  it('skips disabled choices and closes on Tab', async () => {
    const user = userEvent.setup(); render(<><Choice /><button>Devam</button></>)
    const select = screen.getByRole('combobox'); select.focus()
    await user.keyboard('{End}{Enter}')
    expect(select).toHaveValue('kerem')
    await user.click(select); await user.tab()
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Devam' })).toHaveFocus()
  })

  it('preserves manually entered native dates and validation attributes', () => {
    const change = vi.fn()
    render(<><label htmlFor="day">Tarih</label><DateField id="day" type="date" min="2026-11-24" required onChange={event => change(event.target.value)} /></>)
    const input = screen.getByLabelText<HTMLInputElement>('Tarih')
    fireEvent.change(input, { target: { value: '2026-11-27' } })
    expect(change).toHaveBeenCalledExactlyOnceWith('2026-11-27')
    expect(input).toHaveAttribute('required'); expect(input).toHaveAttribute('min', '2026-11-24')
  })

  it('selects a calendar date without changing its local date semantics', async () => {
    const change = vi.fn(), user = userEvent.setup()
    render(<DateField type="date" defaultValue="2026-11-25" onChange={event => change(event.target.value)} />)
    await user.click(screen.getByRole('button', { name: 'Takvimi aç' }))
    await user.click(screen.getByRole('gridcell', { name: '27 Kasım 2026' }))
    expect(change).toHaveBeenCalledExactlyOnceWith('2026-11-27')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('does not invent a time for an empty datetime-local value', async () => {
    const change = vi.fn(), user = userEvent.setup()
    render(<DateField type="datetime-local" defaultValue="2026-11-25T10:00" onChange={event => change(event.target.value)} />)
    await user.click(screen.getByRole('button', { name: 'Takvimi aç' }))
    fireEvent.change(screen.getByLabelText('Saat'), { target: { value: '' } })
    await user.click(screen.getByRole('gridcell', { name: '27 Kasım 2026' }))
    expect(screen.getByRole('button', { name: 'Uygula' })).toBeDisabled()
    expect(change).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('Saat'), { target: { value: '14:30' } })
    await user.click(screen.getByRole('button', { name: 'Uygula' }))
    expect(change).toHaveBeenCalledExactlyOnceWith('2026-11-27T14:30')
  })

  it('honors calendar bounds and keeps Escape from submitting the form', async () => {
    const change = vi.fn(), submit = vi.fn(), user = userEvent.setup()
    render(<form onSubmit={submit}><DateField type="date" defaultValue="2026-11-25" min="2026-11-24" max="2026-11-30" onChange={change} /></form>)
    await user.click(screen.getByRole('button', { name: 'Takvimi aç' }))
    expect(screen.getByRole('gridcell', { name: '23 Kasım 2026' })).toBeDisabled()
    await user.keyboard('{Escape}')
    expect(change).not.toHaveBeenCalled(); expect(submit).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

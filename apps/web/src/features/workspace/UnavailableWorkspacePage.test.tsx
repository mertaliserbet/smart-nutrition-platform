import { fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { AppointmentsPage } from './UnavailableWorkspacePage'

describe('appointment calendar navigation', () => {
  it.each([
    ['2027-01-31', 'Sonraki dönem', '2027-02-28'],
    ['2028-01-31', 'Sonraki dönem', '2028-02-29'],
    ['2027-03-31', 'Önceki dönem', '2027-02-28'],
    ['2028-03-31', 'Önceki dönem', '2028-02-29'],
    ['2027-05-31', 'Önceki dönem', '2027-04-30'],
    ['2027-12-31', 'Sonraki dönem', '2028-01-31'],
    ['2028-01-31', 'Önceki dönem', '2027-12-31'],
  ])('moves from %s using %s to %s without skipping a month', async (date, direction, expected) => {
    const user = userEvent.setup()
    render(<MemoryRouter><AppointmentsPage /></MemoryRouter>)
    const input = screen.getByLabelText(/Takvim tarihi/, { selector: 'input' })
    fireEvent.change(input, { target: { value: date } })
    await user.click(screen.getByRole('button', { name: 'Ay' }))
    await user.click(screen.getByRole('button', { name: direction }))
    expect(input).toHaveValue(expected)
  })

  it.each([
    ['Gün', '2027-02-01'],
    ['Hafta', '2027-02-07'],
  ])('preserves %s navigation across a month boundary', async (view, expected) => {
    const user = userEvent.setup()
    render(<MemoryRouter><AppointmentsPage /></MemoryRouter>)
    const input = screen.getByLabelText(/Takvim tarihi/, { selector: 'input' })
    fireEvent.change(input, { target: { value: '2027-01-31' } })
    await user.click(screen.getByRole('button', { name: view }))
    await user.click(screen.getByRole('button', { name: 'Sonraki dönem' }))
    expect(input).toHaveValue(expected)
  })
})

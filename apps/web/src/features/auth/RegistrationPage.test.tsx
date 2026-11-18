import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { expect, it, vi } from 'vitest'
import App from '../../App'

it('redirects the former client registration URL to the mobile registration guidance', async () => {
  const request = vi.spyOn(globalThis, 'fetch')
  render(<MemoryRouter initialEntries={['/kayit']}><App /></MemoryRouter>)
  expect(await screen.findByRole('heading', { name: 'Tekrar hoş geldiniz.' })).toBeVisible()
  expect(screen.getByText('Danışan kaydı ve danışan işlemleri mobil uygulamada yapılır.')).toBeVisible()
  expect(screen.queryByRole('form', { name: /kayıt/i })).not.toBeInTheDocument()
  expect(request).not.toHaveBeenCalled()
})

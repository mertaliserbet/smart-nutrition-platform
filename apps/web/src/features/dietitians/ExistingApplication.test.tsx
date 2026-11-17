import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { expect, it, vi } from 'vitest'
import App from '../../App'

it('directs existing clients to the mobile app and offers the public expert application', () => {
  const request = vi.spyOn(globalThis, 'fetch')
  render(<MemoryRouter initialEntries={['/uzman-basvurusu']}><App /></MemoryRouter>)
  expect(screen.getByText(/mobil uygulamada Profil bölümünden/)).toBeVisible()
  expect(screen.queryByRole('form', { name: 'Mevcut hesap başvuru formu' })).not.toBeInTheDocument()
  expect(screen.getByRole('form', { name: 'Diyetisyen başvuru formu' })).toBeVisible()
  expect(request).not.toHaveBeenCalled()
})

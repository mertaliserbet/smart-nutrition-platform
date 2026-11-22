import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Link, MemoryRouter, Route, Routes, useNavigate } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { LiveClientsPage } from './LiveClientsPage'
import { ClientListProvider } from './clientListState'
import { LiveDashboardPage } from '../workspace/LiveDashboardPage'

const id = '11111111-1111-4111-8111-111111111111'
const session = { token: 'synthetic', dietitianId: '22222222-2222-4222-8222-222222222222', onFailure: () => false }
function Detail() {
  const navigate = useNavigate()
  return <><h1>Sentetik detay</h1><Link to="/calisma-alani/danisanlar">Danışan listesine dön</Link><button onClick={() => navigate(-1)}>Tarayıcı Geri</button></>
}
function setup(start = '/calisma-alani/danisanlar') {
  let total = 21
  const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
    const url = new URL(String(input), 'https://localhost')
    if (url.pathname.includes('relationships')) return Response.json({ items: [], totalCount: 0 })
    const page = Number(url.searchParams.get('page'))
    return Response.json({ items: total === 0 || (page - 1) * 10 >= total ? [] : [{ id, displayName: 'Sentetik Ada' }], totalCount: total })
  })
  const tree = (token: string) => <MemoryRouter initialEntries={[start]}><WorkspaceContext.Provider value={{ ...session, token }}><ClientListProvider key={token}><Link to="/calisma-alani">Genel Bakış</Link><Routes>
    <Route path="/calisma-alani" element={<LiveDashboardPage />} /><Route path="/calisma-alani/danisanlar" element={<LiveClientsPage />} /><Route path="/calisma-alani/danisanlar/:id" element={<Detail />} />
  </Routes></ClientListProvider></WorkspaceContext.Provider></MemoryRouter>
  return { ...render(tree('synthetic')), tree, request, user: userEvent.setup(), count: (value: number) => { total = value } }
}
describe('client list return position', () => {
  it.each(['Tarayıcı Geri', 'Danışan listesine dön'])('retains search, sorting and page after %s without putting names in route/history storage', async back => {
    const { user, request } = setup(); await screen.findByText('Sentetik Ada')
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: ' Ada ' } }); await user.click(screen.getByRole('button', { name: 'Ara' }))
    await screen.findByText('Sentetik Ada'); await user.selectOptions(screen.getByLabelText('Sıralama'), 'desc'); await screen.findByText('Sentetik Ada')
    await user.click(screen.getByRole('button', { name: 'Sonraki sayfa' })); await screen.findByText('Sayfa 2')
    await user.click(screen.getByRole('link', { name: 'Sentetik Ada için danışan detayını aç' })); await user.click(screen.getByText(back))
    await screen.findByText('Sentetik Ada'); expect(screen.getByRole('searchbox')).toHaveValue(' Ada '); expect(screen.getByLabelText('Sıralama')).toHaveValue('desc'); expect(screen.getByText('Sayfa 2')).toBeVisible()
    const url = new URL(String(request.mock.calls.at(-1)![0]), 'https://localhost'); expect(url.searchParams.get('query')).toBe('Ada'); expect(url.searchParams.get('page')).toBe('2'); expect(url.searchParams.get('sortOrder')).toBe('desc')
    expect(window.location.search).toBe(''); expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0)
  })
  it('distinguishes setup empty from filtered empty, clears filters, resets search page and repairs removed last pages', async () => {
    const { user, count, request } = setup(); await screen.findByText('Sentetik Ada')
    await user.click(screen.getByRole('button', { name: 'Sonraki sayfa' })); await screen.findByText('Sayfa 2')
    count(0); fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'Bulunmayan' } }); await user.click(screen.getByRole('button', { name: 'Ara' }))
    expect(await screen.findByText('Aramanıza uygun danışan bulunamadı')).toBeVisible(); expect(String(request.mock.calls.at(-1)![0])).toContain('page=1')
    await user.click(screen.getByRole('button', { name: 'Filtreyi temizle' })); expect(await screen.findByText('Henüz aktif danışanınız yok')).toBeVisible()
    count(21); await user.click(screen.getByRole('button', { name: 'Listeyi yenile' })); await screen.findByText('Sentetik Ada')
    await user.click(screen.getByRole('button', { name: 'Sonraki sayfa' })); await screen.findByText('Sayfa 2')
    count(1); await user.click(screen.getByRole('button', { name: 'Listeyi yenile' })); await waitFor(() => expect(screen.getByText('Sayfa 1')).toBeVisible()); await screen.findByText('Sentetik Ada')
  })
  it('starts a fresh list from overview and clears memory on a session change', async () => {
    const { user, rerender, tree } = setup(); await screen.findByText('Sentetik Ada')
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'Ada' } }); await user.click(screen.getByRole('button', { name: 'Ara' })); await screen.findByText('Sentetik Ada')
    await user.click(screen.getByRole('link', { name: 'Genel Bakış' })); await user.click(screen.getByRole('link', { name: 'Danışan ara ve görüntüle' }))
    expect(screen.getByRole('searchbox')).toHaveValue('')
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'Önceki kişi' } }); rerender(tree('new-session'))
    expect(screen.getByRole('searchbox')).toHaveValue('')
  })
})

import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { LiveClientDetailsPage } from './LiveClientDetailsPage'

const first = '11111111-1111-4111-8111-111111111111', second = '33333333-3333-4333-8333-333333333333'
const expert = '22222222-2222-4222-8222-222222222222'
const path = `/calisma-alani/danisanlar/${first}`
function HistoryControls() {
  const navigate = useNavigate(), location = useLocation()
  return <><output aria-label="Test URL">{location.pathname + location.search}</output><button onClick={() => navigate(-1)}>Geri</button><button onClick={() => navigate(1)}>İleri</button><button onClick={() => navigate(`/calisma-alani/danisanlar/${second}`)}>Diğer danışan</button></>
}
function setup(url = path) {
  const request = vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
    const url = String(input)
    if (url.endsWith('/dashboard')) {
      const clientId = url.includes(second) ? second : first
      return Response.json({ clientId, displayName: clientId === first ? 'Sentetik Ada' : 'Sentetik Deniz' })
    }
    if (url.includes('/nutrition-plans?') || url.includes('/client-tasks?')) return Response.json({ items: [], totalCount: 0 })
    return new Response(null, { status: 403 })
  })
  const view = render(<MemoryRouter initialEntries={[url]}><WorkspaceContext.Provider value={{ token: 'synthetic', dietitianId: expert, onFailure: () => false }}>
    <HistoryControls /><Routes><Route path="/calisma-alani/danisanlar/:clientId" element={<LiveClientDetailsPage />} /></Routes>
  </WorkspaceContext.Provider></MemoryRouter>)
  return { ...view, request, user: userEvent.setup() }
}
describe('navigable live client details', () => {
  it('defaults to a minimal summary and loads no health panels', async () => {
    const { request } = setup()
    expect(await screen.findByRole('heading', { level: 1, name: 'Sentetik Ada' })).toBeVisible()
    expect(screen.getByRole('region', { name: 'Danışan özeti' })).toBeVisible()
    expect(screen.getByRole('link', { name: 'Özet' })).toHaveAttribute('aria-current', 'page')
    expect(request).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('button', { name: 'Yeni görev ata' })).not.toBeInTheDocument()
  })
  it.each([
    ['program', 'Beslenme programları', 'nutrition-plans'], ['gorevler', 'Danışan görevleri', 'client-tasks'],
    ['ogunler', 'Öğün günlüğü', 'meal-logs'], ['olcum-su', 'Su takibi', 'water-logs'],
  ])('opens %s directly and restores it on reload without loading unrelated panels', async (section, name, endpoint) => {
    const view = setup(`${path}?bolum=${section}`)
    expect(await screen.findByRole('heading', { level: 1, name: 'Sentetik Ada' })).toBeVisible()
    expect(await screen.findByRole('region', { name })).toBeVisible()
    await waitFor(() => expect(view.request.mock.calls.some(([url]) => String(url).includes(endpoint))).toBe(true))
    expect(view.request.mock.calls.some(([url]) => String(url).includes(section === 'gorevler' ? 'nutrition-plans' : 'client-tasks'))).toBe(false)
    view.unmount()
    const reload = setup(`${path}?bolum=${section}`)
    expect(await screen.findByRole('region', { name })).toBeVisible()
    reload.unmount()
  })
  it('preserves task and program drafts across section links and back/forward with usable focus', async () => {
    const { user } = setup(`${path}?bolum=gorevler`)
    await user.click(await screen.findByRole('button', { name: 'Yeni görev ata' }))
    await user.type(screen.getByLabelText('Görev açıklaması'), 'Kaydedilmemiş görev')
    await user.click(screen.getByRole('link', { name: 'Program' }))
    await user.click(await screen.findByRole('button', { name: 'Yeni program oluştur' }))
    await user.type(screen.getByLabelText('Program başlığı'), 'Kaydedilmemiş program')
    await user.click(screen.getByRole('link', { name: 'Özet' }))
    expect(screen.getByRole('heading', { name: 'Özet' })).toHaveFocus()
    await user.click(screen.getByRole('button', { name: 'Geri' }))
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Kaydedilmemiş program')
    expect(screen.getByLabelText('Program başlığı')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'Geri' }))
    expect(screen.getByLabelText('Görev açıklaması')).toHaveValue('Kaydedilmemiş görev')
    expect(screen.getByLabelText('Görev açıklaması')).toBeVisible()
    await user.click(screen.getByRole('button', { name: 'İleri' }))
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Kaydedilmemiş program')
    expect(screen.getByLabelText('Program başlığı')).toBeVisible()
  })
  it('returns to the hidden program editor with field focus when cancelling a leave action', async () => {
    const { user } = setup(`${path}?bolum=program`)
    await user.click(await screen.findByRole('button', { name: 'Boş taslak' }))
    await user.type(screen.getByLabelText('Program başlığı'), 'Korunan program')
    await user.click(screen.getByRole('link', { name: 'Özet' }))
    await user.click(screen.getByRole('link', { name: 'Danışan listesine dön' }))
    expect(screen.getByRole('alertdialog')).toHaveTextContent('Kaydedilmemiş değişiklikler')
    await user.click(screen.getByRole('button', { name: 'Düzenlemeye dön' }))
    await waitFor(() => expect(screen.getByLabelText('Program başlığı')).toHaveFocus())
    expect(screen.getByLabelText('Program başlığı')).toBeVisible()
    expect(screen.getByLabelText('Program başlığı')).toHaveValue('Korunan program')
    expect(screen.getByRole('link', { name: 'Program' })).toHaveAttribute('aria-current', 'page')
  })
  it('clears drafts and discards delayed reads when switching client', async () => {
    const { user, request } = setup(`${path}?bolum=gorevler`)
    await user.click(await screen.findByRole('button', { name: 'Yeni görev ata' }))
    await user.type(screen.getByLabelText('Görev açıklaması'), 'Eski danışanın taslağı')
    let finish!: (response: Response) => void
    request.mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    fireEvent(window, new Event('focus'))
    await waitFor(() => expect(request.mock.calls.some(([, options]) => options?.signal && !options.signal.aborted)).toBe(true))
    await user.click(screen.getByRole('button', { name: 'Diğer danışan' }))
    expect(screen.queryByDisplayValue('Eski danışanın taslağı')).not.toBeInTheDocument()
    expect(await screen.findByRole('heading', { level: 1, name: 'Sentetik Deniz' })).toBeVisible()
    await act(async () => finish(Response.json({ clientId: first, displayName: 'Sentetik Ada' })))
    expect(screen.queryByRole('heading', { level: 1, name: 'Sentetik Ada' })).not.toBeInTheDocument()
  })
  it('removes all visited panels and drafts after confirmed relation loss', async () => {
    const { user, request } = setup(`${path}?bolum=gorevler`)
    await user.click(await screen.findByRole('button', { name: 'Yeni görev ata' }))
    await user.type(screen.getByLabelText('Görev açıklaması'), 'Özel taslak')
    request.mockResolvedValue(new Response(null, { status: 404 }))
    act(() => window.dispatchEvent(new Event('focus')))
    await waitFor(() => expect(screen.queryByRole('navigation', { name: 'Danışan bölümleri' })).not.toBeInTheDocument())
    expect(screen.queryByDisplayValue('Özel taslak')).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Sentetik Ada' })).not.toBeInTheDocument()
  })
  it('hides each independent denied category without inventing summary values', async () => {
    setup(`${path}?bolum=olcum-su`)
    expect(await screen.findByRole('heading', { name: 'Sentetik Ada' })).toBeVisible()
    const water = await screen.findByRole('region', { name: 'Su takibi' })
    expect(await within(water).findByRole('alert')).toHaveTextContent('Su paylaşımı kapalı')
    expect(within(water).queryByRole('table')).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Danışan görevleri' })).not.toBeInTheDocument()
  })
})

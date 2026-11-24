import { act, fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { WorkspaceContext } from './workspaceSession'
import { LiveDashboardPage } from './LiveDashboardPage'
import App from '../../App'

const expert = '22222222-2222-4222-8222-222222222222'
const client = '11111111-1111-4111-8111-111111111111'
const clients = () => Response.json({ items: [{ id: client, displayName: 'Sentetik danışan' }], totalCount: 7 })
const requests = () => Response.json({ items: [], totalCount: 3 })
const session = { token: 'synthetic-csrf', dietitianId: expert, onFailure: vi.fn(() => false) }

describe('independent dashboard sections', () => {
  it.each(['clients', 'requests'])('keeps the other section intact while %s fails and retries', async failed => {
    let failing = true
    let finish!: (response: Response) => void
    const fetcher = vi.spyOn(globalThis, 'fetch').mockImplementation(async path => {
      const isClients = String(path).includes('dietitian/clients')
      if (isClients === (failed === 'clients')) {
        if (failing) return new Response(null, { status: 500 })
        return new Promise(resolve => { finish = resolve })
      }
      return isClients ? clients() : requests()
    })
    render(<MemoryRouter><WorkspaceContext.Provider value={session}><LiveDashboardPage /></WorkspaceContext.Provider></MemoryRouter>)
    await screen.findByRole('alert')
    const active = screen.getByRole('heading', { name: 'Aktif danışanlar' }).closest('article')!
    const pending = screen.getByRole('article', { name: 'Bekleyen istekler' })
    expect(failed === 'clients' ? active : pending).toHaveTextContent('—')
    expect(failed === 'clients' ? pending : active).toHaveTextContent(failed === 'clients' ? '3' : '7')
    if (failed === 'requests') expect(screen.getByText('Sentetik danışan')).toBeVisible()
    failing = false
    fireEvent.click(screen.getByRole('button', { name: failed === 'clients' ? 'Danışanları yeniden dene' : 'İstekleri yeniden dene' }))
    expect(screen.getByRole('status')).toHaveTextContent(failed === 'clients' ? 'Aktif danışanlar' : 'Bekleyen istekler')
    expect(failed === 'clients' ? pending : active).toHaveTextContent(failed === 'clients' ? '3' : '7')
    expect(fetcher).toHaveBeenCalledTimes(3)
    await act(async () => finish(failed === 'clients' ? clients() : requests()))
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(active).toHaveTextContent('7'); expect(pending).toHaveTextContent('3')
    expect(screen.getByText('Sentetik danışan')).toBeVisible()
  })
  it('keeps each empty state and discards an aborted late response', async () => {
    let finish!: (response: Response) => void
    const fetcher = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({ items: [], totalCount: 0 }))
      .mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const view = render(<MemoryRouter><WorkspaceContext.Provider value={session}><LiveDashboardPage /></WorkspaceContext.Provider></MemoryRouter>)
    await screen.findByText('İlk danışanınızla bağlantı kurun')
    const signal = fetcher.mock.calls[1]![1]!.signal!
    view.unmount(); expect(signal.aborted).toBe(true)
    await act(async () => finish(requests()))
    expect(screen.queryByText('3')).not.toBeInTheDocument()
  })
  it('routes session loss through workspace authentication and removes the healthy section', async () => {
    let finish!: (response: Response) => void
    vi.spyOn(globalThis, 'fetch').mockImplementation(async path => {
      const url = String(path)
      if (url.endsWith('/csrf')) return Response.json({ requestToken: 'synthetic' })
      if (url.endsWith('/auth/me')) return Response.json({ id: client, displayName: 'Uzman', email: 'synthetic@example.test', role: 'dietitian', isEmailVerified: true })
      if (url.endsWith('/dietitians/me')) return Response.json({ id: expert, displayName: 'Uzman', isVerified: true })
      if (url.includes('dietitian/clients')) return clients()
      return new Promise(resolve => { finish = resolve })
    })
    render(<MemoryRouter initialEntries={['/calisma-alani']}><App /></MemoryRouter>)
    await screen.findByText('Sentetik danışan')
    await act(async () => finish(new Response(null, { status: 401 })))
    expect(await screen.findByRole('heading', { name: 'Tekrar hoş geldin' })).toBeVisible()
    expect(screen.queryByText('Sentetik danışan')).not.toBeInTheDocument()
  })
})

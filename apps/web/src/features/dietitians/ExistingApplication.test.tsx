import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const id = '139fb109-43b8-4b6d-9461-710596ca15ca'
const profileId = '792081c4-62b4-49a6-b54a-b6ecdd633cba'
const csrf = () => Response.json({ requestToken: 'synthetic-csrf' })
const account = (role = 'client') => Response.json({ id, displayName: 'Synthetic client', email: 'synthetic@example.test', role, isEmailVerified: true })
const profile = (approved = false, status = 200) => Response.json({ id: profileId, displayName: 'Synthetic professional', isVerified: approved }, { status })
async function open() {
  const user = userEvent.setup()
  const result = render(<MemoryRouter initialEntries={['/uzman-basvurusu']}><App /></MemoryRouter>)
  await user.click(screen.getByRole('button', { name: 'Mevcut hesabımla başvur' }))
  return { user, ...result }
}
function ready() {
  return vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account()).mockResolvedValueOnce(new Response(null, { status: 404 }))
}

describe('existing client dietitian application', () => {
  it('uses the verified session and CSRF without sending identity or password', async () => {
    const request = ready().mockResolvedValueOnce(profile(false, 201))
    const { user } = await open()
    await screen.findByRole('form', { name: 'Mevcut hesap başvuru formu' })
    expect(screen.queryByLabelText('Şifre')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('E-posta adresi')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Mesleki kayıt açıklamanız'), { target: { value: ' Synthetic license ' } })
    await user.click(screen.getByRole('button', { name: 'Mevcut hesabımla başvuruyu gönder' }))
    expect(await screen.findByText(/Başvurunuz Admin incelemesini bekliyor/)).toBeVisible()
    const [path, options] = request.mock.calls[3]!
    expect(path).toBe('/api/v1/dietitians/me/application')
    expect(options).toMatchObject({ method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf' } })
    expect(JSON.parse(options?.body as string)).toEqual({ displayName: 'Synthetic client', licenseInfo: 'Synthetic license' })
    expect(screen.queryByRole('button', { name: 'Mevcut hesabımla başvuruyu gönder' })).not.toBeInTheDocument()
  })
  it.each([false, true])('shows existing application without a second submit (approved=%s)', async approved => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account()).mockResolvedValueOnce(profile(approved))
    await open()
    expect(await screen.findByText(approved ? /Diyetisyen başvurunuz onaylanmış/ : /Başvurunuz Admin incelemesini bekliyor/)).toBeVisible()
    expect(screen.queryByRole('form')).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(3)
    expect(screen.queryByRole('link', { name: 'Diyetisyen çalışma alanımı aç' }) !== null).toBe(approved)
  })
  it('does not allow anonymous submissions', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(new Response(null, { status: 401 }))
    const { user } = await open()
    expect(await screen.findByRole('alert')).toHaveTextContent('Giriş bilgileri doğrulanamadı')
    expect(screen.queryByRole('form')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Yeni hesapla başvur' }))
    expect(screen.getByRole('form', { name: 'Diyetisyen başvuru formu' })).toBeVisible()
  })
  it('does not allow Admin account submissions', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account('admin'))
    await open()
    expect(await screen.findByRole('alert')).toHaveTextContent('Yönetici hesabıyla diyetisyen başvurusu yapılamaz')
    expect(screen.queryByRole('form')).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(2)
  })
  it('invalidates an expired CSRF or duplicate conflict without automatic retry', async () => {
    const request = ready().mockResolvedValueOnce(new Response(null, { status: 409 }))
    const { user } = await open(); await screen.findByRole('form')
    fireEvent.change(screen.getByLabelText('Mesleki kayıt açıklamanız'), { target: { value: 'Synthetic' } })
    await user.click(screen.getByRole('button', { name: 'Mevcut hesabımla başvuruyu gönder' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('zaten bir başvurusu var')
    expect(request).toHaveBeenCalledTimes(4); expect(screen.queryByRole('form')).not.toBeInTheDocument()
  })
  it('aborts pending submission on leaving and ignores late approval data', async () => {
    let finish!: (response: Response) => void
    const request = ready().mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const { user, unmount } = await open(); await screen.findByRole('form')
    fireEvent.change(screen.getByLabelText('Mesleki kayıt açıklamanız'), { target: { value: 'Synthetic' } })
    await user.click(screen.getByRole('button', { name: 'Mevcut hesabımla başvuruyu gönder' }))
    await waitFor(() => expect(request).toHaveBeenCalledTimes(4))
    const signal = request.mock.calls[3]?.[1]?.signal
    unmount(); expect(signal?.aborted).toBe(true)
    await act(async () => finish(profile(false, 201)))
    expect(screen.queryByText(/Başvurunuz Admin incelemesini bekliyor/)).not.toBeInTheDocument()
  })
})

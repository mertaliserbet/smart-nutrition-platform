import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import App from '../../App'

const userId = '139fb109-43b8-4b6d-9461-710596ca15ca'
const expertId = '792081c4-62b4-49a6-b54a-b6ecdd633cba'
const account = (role = 'admin') => Response.json({ id: userId, displayName: null, email: 'synthetic@example.test', role, isEmailVerified: true })
const csrf = () => Response.json({ requestToken: 'synthetic-csrf' })
const review = () => Response.json({ items: [{ id: expertId, displayName: 'Sentetik Uzman', licenseInfo: 'Sentetik mesleki kayıt', isVerified: false }], totalCount: 1 })
function page(path: string) {
  const result = render(<MemoryRouter initialEntries={[path]}><App /></MemoryRouter>)
  return { ...result, user: userEvent.setup() }
}
function fillApplication() {
  fireEvent.change(screen.getByLabelText('Ad ve soyad'), { target: { value: ' Sentetik Uzman ' } })
  fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: ' expert@example.test ' } })
  fireEvent.change(screen.getByLabelText('Şifre'), { target: { value: ' synthetic password ' } })
  fireEvent.change(screen.getByLabelText('Mesleki kayıt / belge açıklaması'), { target: { value: ' Sentetik mesleki kayıt ' } })
}

describe('dietitian application and administrator verification', () => {
  it('submits a separate anonymous application with exact fields and only claims success after 201', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(Response.json({ id: userId }, { status: 201 }))
    const { user } = page('/uzman-basvurusu'); fillApplication()
    await user.click(screen.getByRole('button', { name: 'Başvuruyu gönder' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Başvurunuz kaydedildi')
    expect(request).toHaveBeenCalledOnce()
    expect(request.mock.calls[0]?.[0]).toBe('/api/v1/dietitians/apply')
    const options = request.mock.calls[0]?.[1]
    expect(options).toMatchObject({ credentials: 'omit', redirect: 'error', cache: 'no-store', method: 'POST' })
    expect(JSON.parse(options?.body as string)).toEqual({ email: 'expert@example.test', password: ' synthetic password ', displayName: 'Sentetik Uzman', licenseInfo: 'Sentetik mesleki kayıt' })
    expect(screen.queryByRole('form')).not.toBeInTheDocument()
    expect(screen.queryByText('Uzman doğrulamanız tamamlandı.')).not.toBeInTheDocument()
  })

  it('blocks invalid text without sending and preserves the server rejection rather than simulating approval', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 409 }))
    const { user } = page('/uzman-basvurusu')
    await user.click(screen.getByRole('button', { name: 'Başvuruyu gönder' }))
    expect(request).not.toHaveBeenCalled()
    fillApplication()
    await user.click(screen.getByRole('button', { name: 'Başvuruyu gönder' }))
    expect(await screen.findByText('Bu e-posta adresiyle başvuru tamamlanamadı.')).toBeVisible()
    expect(screen.getByLabelText('Şifre')).toHaveValue('')
    expect(screen.getByRole('form')).toBeVisible()
  })

  it('rejects malformed application success and clears secrets while a request is pending', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockImplementation(() => new Promise(resolve => { finish = resolve }))
    const { user } = page('/uzman-basvurusu'); fillApplication()
    await user.click(screen.getByRole('button', { name: 'Başvuruyu gönder' }))
    expect(screen.getByLabelText('Şifre')).toHaveValue('')
    fireEvent.submit(screen.getByRole('form')); expect(request).toHaveBeenCalledOnce()
    await act(async () => finish(Response.json({ id: userId, accessToken: 'forbidden' }, { status: 201 })))
    expect(await screen.findByRole('alert')).toHaveTextContent('Başvuru sonucu doğrulanamadı')
  })

  it('uses CSRF and the separate administrator endpoint, then loads the protected review list', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account()).mockResolvedValueOnce(review())
    const { user } = page('/yonetici-giris')
    fireEvent.change(screen.getByLabelText('E-posta adresi'), { target: { value: 'admin@example.test' } })
    fireEvent.change(screen.getByLabelText('Şifre'), { target: { value: ' synthetic admin password ' } })
    fireEvent.change(screen.getByLabelText('Doğrulama veya kurtarma kodu'), { target: { value: '123456' } })
    await user.click(screen.getByRole('button', { name: 'Güvenli giriş yap' }))
    expect(await screen.findByRole('button', { name: 'Sentetik Uzman için uzman onayı ver' })).toBeVisible()
    expect(request.mock.calls[1]?.[0]).toBe('/api/v1/auth/admin-web-session')
    expect(JSON.parse(request.mock.calls[1]?.[1]?.body as string)).toEqual({ email: 'admin@example.test', password: ' synthetic admin password ', mfaCode: '123456' })
    expect(request.mock.calls[1]?.[1]?.headers).toMatchObject({ 'X-CSRF-TOKEN': 'synthetic-csrf' })
    expect(request.mock.calls.some(([path]) => path === '/api/v1/auth/login')).toBe(false)
  })

  it('does not allow an ordinary account to fetch the admin list', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account('dietitian'))
    page('/yonetim/uzmanlar')
    expect(await screen.findByRole('alert')).toHaveTextContent('yalnız MFA')
    expect(request).toHaveBeenCalledTimes(2)
    expect(screen.queryByText('Sentetik mesleki kayıt')).not.toBeInTheDocument()
  })

  it('confirms an approval only after an exact response and does not resend it automatically', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account()).mockResolvedValueOnce(review())
      .mockResolvedValueOnce(Response.json({ id: expertId, displayName: 'Sentetik Uzman', isVerified: true }))
    const { user } = page('/yonetim/uzmanlar')
    await user.click(await screen.findByRole('button', { name: 'Sentetik Uzman için uzman onayı ver' }))
    expect(await screen.findByText('Sentetik Uzman için uzman onayı kaydedildi.')).toBeVisible()
    expect(screen.queryByText('Sentetik mesleki kayıt')).not.toBeInTheDocument()
    expect(request.mock.calls[3]?.[0]).toBe(`/api/v1/admin/dietitians/${expertId}/verify`)
    expect(request.mock.calls[3]?.[1]).toMatchObject({ method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-TOKEN': 'synthetic-csrf' } })
    expect(request.mock.calls[3]?.[1]?.body).toBeUndefined()
    expect(request).toHaveBeenCalledTimes(4)
  })

  it('clears private application content and old CSRF on a context failure', async () => {
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account()).mockResolvedValueOnce(review())
      .mockResolvedValueOnce(new Response(null, { status: 400 }))
    const { user } = page('/yonetim/uzmanlar')
    await user.click(await screen.findByRole('button', { name: 'Sentetik Uzman için uzman onayı ver' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('oturum bağlamı')
    expect(screen.queryByText('Sentetik mesleki kayıt')).not.toBeInTheDocument()
    expect(request).toHaveBeenCalledTimes(4)
  })

  it('aborts reads on unmount and prevents late application data from becoming visible', async () => {
    let finish!: (response: Response) => void
    const request = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(csrf()).mockResolvedValueOnce(account())
      .mockImplementationOnce(() => new Promise(resolve => { finish = resolve }))
    const { unmount } = page('/yonetim/uzmanlar')
    await screen.findByText('İşlem sürüyor…')
    await act(async () => {})
    const signal = request.mock.calls[2]?.[1]?.signal
    unmount(); expect(signal?.aborted).toBe(true)
    await act(async () => finish(review()))
    expect(screen.queryByText('Sentetik mesleki kayıt')).not.toBeInTheDocument()
  })

  it.each([false, true])('shows the server application status isVerified=%s without claiming health access', async isVerified => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(account('dietitian'))
      .mockResolvedValueOnce(Response.json({ id: expertId, displayName: 'Sentetik Uzman', isVerified }))
    page('/uzman/basvuru-durumu')
    expect(await screen.findByText(isVerified ? 'Uzman doğrulamanız tamamlandı.' : 'Başvurunuz Admin incelemesini bekliyor.')).toBeVisible()
    expect(screen.getByText(/aktif bağlantı ve danışanın ilgili paylaşım izni/)).toBeVisible()
  })
})

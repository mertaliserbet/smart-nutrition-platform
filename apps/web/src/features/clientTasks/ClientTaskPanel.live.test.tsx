/// <reference types="node" />
// Opt-in real React DOM + HTTPS/cookie API + disposable PostgreSQL integration.
// This is not a Flutter or a browser rendering test.
import { request as httpsRequest } from 'node:https'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, it, vi } from 'vitest'
import { getCsrf, login, logout } from '../auth/webSessionApi'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { ClientTaskPanel } from './ClientTaskPanel'
import { localTaskTime } from './clientTaskForm'
import type { ClientTaskResponse } from './clientTaskApi'

it.skipIf(process.env.SNP_TASK_WEB_LIVE !== '1')('real PostgreSQL/HTTPS: web assignment, client completion, 409, history, edit/cancel, revocation and relationship end', async () => {
  expect(process.env.SNP_TASK_WEB_ORIGIN).toBe('https://localhost:7443')
  const origin = process.env.SNP_TASK_WEB_ORIGIN!
  const ca = readFileSync(process.env.SNP_TASK_WEB_CA!)
  const psql = process.env.SNP_TASK_WEB_PSQL!
  expect(psql.replaceAll('\\', '/')).toMatch(/\/pgsql\/bin\/psql\.exe$/)
  const cookies = new Map<string, string>()
  const signal = new AbortController().signal
  function wire(path: string, options: RequestInit = {}, jar?: Map<string, string>): Promise<Response> {
    const headers = new Headers(options.headers)
    if (jar) { headers.set('Origin', origin); if (jar.size) headers.set('Cookie', [...jar].map(([name, value]) => `${name}=${value}`).join('; ')) }
    return new Promise((resolve, reject) => {
      const request = httpsRequest(new URL(path, origin), { method: options.method ?? 'GET', headers: Object.fromEntries(headers), ca,
        ...(options.signal ? { signal: options.signal } : {}) }, response => {
        for (const cookie of response.headers['set-cookie'] ?? []) { const pair = cookie.split(';')[0]!; const index = pair.indexOf('='); jar?.set(pair.slice(0, index), pair.slice(index + 1)) }
        const chunks: Buffer[] = []
        response.on('data', (chunk: Buffer) => chunks.push(chunk)); response.on('error', reject)
        response.on('end', () => resolve(new Response(response.statusCode === 204 ? null : Buffer.concat(chunks).toString('utf8'), { status: response.statusCode })))
      })
      request.on('error', reject); request.end(options.body ?? undefined)
    })
  }
  async function json(path: string, method: string, expected: number, body?: object, bearer?: string, csrf?: string) {
    const response = await wire(path, { method, headers: { ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(bearer ? { Authorization: `Bearer ${bearer}`, 'X-Profile-Context': 'client' } : {}),
      ...(csrf ? { 'X-CSRF-TOKEN': csrf, 'X-Profile-Context': 'dietitian' } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) }, bearer ? undefined : csrf ? cookies : undefined)
    expect(response.status, `${method} ${path}`).toBe(expected)
    return response.status === 204 ? undefined : response.json()
  }
  const suffix = Date.now(); const password = 'Synthetic U2 integration password'
  const clientEmail = `synthetic-u2-client-${suffix}@example.test`; const expertEmail = `synthetic-u2-expert-${suffix}@example.test`
  const client = await json('/api/v1/auth/register', 'POST', 201, { email: clientEmail, password, displayName: 'Sentetik U2 danışan', role: 'client' })
  const expert = await json('/api/v1/dietitians/apply', 'POST', 201, { email: expertEmail, password, displayName: 'Sentetik U2 uzman', licenseInfo: 'Synthetic U2 test license' })
  for (const id of [client.id, expert.id]) expect(id).toMatch(/^[a-f0-9-]{36}$/)
  // Fixed loopback endpoint + explicitly named disposable database; only these new synthetic users.
  execFileSync(psql, ['-h', '127.0.0.1', '-p', '55582', '-U', 'nutrition_test', '-d', 'nutrition_u2_test', '-v', 'ON_ERROR_STOP=1', '-c',
    `UPDATE users SET is_email_verified=true WHERE id IN ('${client.id}','${expert.id}'); UPDATE dietitian_profiles SET is_verified=true WHERE user_id='${expert.id}';`], { stdio: 'pipe' })
  const mobile = await json('/api/v1/auth/login', 'POST', 200, { email: clientEmail, password })
  const request = vi.spyOn(globalThis, 'fetch').mockImplementation((input, options) => wire(String(input), options, cookies))
  let token: string | undefined
  try {
    await login({ email: expertEmail, password }, signal); token = await getCsrf(signal)
    const profile = await json('/api/v1/dietitians/me', 'GET', 200, undefined, undefined, token)
    const relation = await json('/api/v1/dietitian-relationships', 'POST', 201, { dietitianId: profile.id }, mobile.accessToken)
    await json(`/api/v1/dietitian-relationships/${relation.id}/accept`, 'POST', 200, undefined, undefined, token)
    await json('/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'nutrition_plans', isGranted: true }, mobile.accessToken)
    const user = userEvent.setup()
    render(<WorkspaceContext.Provider value={{ token, dietitianId: profile.id, onFailure: () => false }}><p>Diğer izinli bölüm korunur</p><ClientTaskPanel clientId={relation.clientId} /></WorkspaceContext.Provider>)
    expect(await screen.findByRole('alert')).toHaveTextContent('Görev paylaşımı kapalı')
    const grant = await json('/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'client_tasks', isGranted: true }, mobile.accessToken)
    await user.click(screen.getByRole('button', { name: 'Görevleri yenile' })); await screen.findByText('Henüz atanmış görev yok')
    await user.click(screen.getByRole('button', { name: 'Yeni görev ata' })); await user.type(screen.getByLabelText('Görev açıklaması'), 'Sentetik canlı görev')
    const dueInput = localTaskTime(new Date(Date.now() + 86_400_000).toISOString())
    fireEvent.change(screen.getByLabelText('Son tarih ve saat (isteğe bağlı)'), { target: { value: dueInput } })
    await user.click(screen.getByRole('button', { name: 'Görevi oluştur ve ata' })); await screen.findByText('Görev oluşturuldu ve danışana atandı.')
    const ownList = await json('/api/v1/client-tasks?page=1&pageSize=10', 'GET', 200, undefined, mobile.accessToken)
    const assigned = ownList.items[0] as ClientTaskResponse; expect(assigned.description).toBe('Sentetik canlı görev'); expect(assigned.dueAt && new Date(assigned.dueAt).toISOString()).toBe(new Date(dueInput).toISOString())
    await user.click(await screen.findByRole('button', { name: 'Görevi düzenle' })); await user.clear(screen.getByLabelText('Görev açıklaması')); await user.type(screen.getByLabelText('Görev açıklaması'), 'Kaydedilmemiş canlı taslak')
    const completed = await json(`/api/v1/client-tasks/${assigned.id}`, 'PATCH', 200, { expectedVersionNumber: assigned.versionNumber, status: 'completed' }, mobile.accessToken)
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' }))
    expect(await screen.findByDisplayValue('Kaydedilmemiş canlı taslak')).toBeVisible(); expect(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })).toBeDisabled()
    expect(await screen.findByText('Danışanın tamamlama zamanı')).toBeVisible()
    expect(within(screen.getByRole('region', { name: 'Görev değişiklik geçmişi' })).getByText('Sürüm 2 · Tamamlandı')).toBeVisible()
    expect(completed.description).toBe('Sentetik canlı görev')
    await user.click(screen.getByRole('button', { name: 'Taslağı silip güncel sürüme dön' }))
    expect(screen.queryByLabelText('Görev açıklaması')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Yeni görev ata' })); await user.type(screen.getByLabelText('Görev açıklaması'), 'İkinci canlı görev')
    await user.click(screen.getByRole('button', { name: 'Görevi oluştur ve ata' })); await screen.findByText('Görev oluşturuldu ve danışana atandı.')
    await user.click(await screen.findByRole('button', { name: 'Görevi düzenle' })); await user.type(screen.getByLabelText('Görev açıklaması'), ' düzenlendi')
    await user.click(screen.getByRole('button', { name: 'Değişiklikleri kaydet' })); await screen.findByText('Görev değişiklikleri kaydedildi.')
    await user.click(await screen.findByRole('button', { name: 'Görevi iptal et' })); await user.click(screen.getByRole('button', { name: 'İptali onayla' })); await screen.findByText('Görev iptal edildi.')
    expect(within(screen.getByRole('region', { name: 'Görev değişiklik geçmişi' })).getByText('Sürüm 3 · İptal edildi')).toBeVisible()

    await json(`/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
    act(() => window.dispatchEvent(new Event('focus'))); expect(await screen.findByRole('alert')).toHaveTextContent('Görev paylaşımı kapalı')
    expect(screen.queryByRole('region', { name: 'Görev detayı' })).not.toBeInTheDocument(); expect(screen.queryByText('Sentetik canlı görev')).not.toBeInTheDocument()
    expect(screen.getByText('Diğer izinli bölüm korunur')).toBeVisible()
    const permissions = await json(`/api/v1/data-sharing-permissions?relationshipId=${relation.id}&page=1&pageSize=10`, 'GET', 200, undefined, mobile.accessToken)
    expect(Object.fromEntries(permissions.items.map((row: { category: string; isGranted: boolean }) => [row.category, row.isGranted]))).toEqual({ nutrition_plans: true, client_tasks: false })
    await json(`/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: true }, mobile.accessToken)
    await user.click(screen.getByRole('button', { name: 'Görevleri yenile' })); await screen.findByText('2 görev · Sayfa 1')
    await json(`/api/v1/dietitian-relationships/${relation.id}/end`, 'POST', 200, undefined, mobile.accessToken)
    act(() => window.dispatchEvent(new Event('focus'))); expect(await screen.findByRole('alert')).toHaveTextContent('bağlantınız sona erdi')
    expect(screen.queryByRole('list', { name: 'Atanan görevler' })).not.toBeInTheDocument()
    const history = await json(`/api/v1/client-tasks/${assigned.id}/versions?page=1&pageSize=10`, 'GET', 200, undefined, mobile.accessToken)
    expect(history.items[0].snapshot.status).toBe('completed')
    expect(request.mock.calls.every(([, options]) => !new Headers(options?.headers).has('Authorization'))).toBe(true)
  } finally { if (token) await logout(token, signal) }
}, 90_000)

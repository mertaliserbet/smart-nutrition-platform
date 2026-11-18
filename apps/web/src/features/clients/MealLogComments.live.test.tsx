/// <reference types="node" />
// Opt-in: real React DOM and HTTPS cookie/CSRF API on disposable PostgreSQL.
// This verifies integration, not browser rendering. No application DB fixtures.
import { request as httpsRequest } from 'node:https'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, it, vi } from 'vitest'
import { getCsrf, login, logout } from '../auth/webSessionApi'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { MealLogPanel } from './MealLogPanel'
import { createMealLogComment } from './mealLogCommentApi'

it.skipIf(process.env.SNP_COMMENT_WEB_LIVE !== '1')('real HTTPS: expert root, client reply, comment paging and revoked sharing', async () => {
  const container = process.env.SNP_SHARING_CONTAINER!
  expect(container).toMatch(/^smart-nutrition-sharing-test-\d+$/)
  const origin = 'https://localhost:7101'
  const ca = readFileSync(process.env.SNP_COMMENT_WEB_CA!)
  const cookies = new Map<string, string>()
  const signal = new AbortController().signal
  function wire(path: string, options: RequestInit = {}, jar?: Map<string, string>): Promise<Response> {
    const headers = new Headers(options.headers)
    if (jar) {
      headers.set('Origin', origin)
      if (jar.size) headers.set('Cookie', [...jar].map(([name, value]) => `${name}=${value}`).join('; '))
    }
    return new Promise((resolve, reject) => {
      const request = httpsRequest(new URL(path, origin), { method: options.method ?? 'GET', headers: Object.fromEntries(headers), ca,
        ...(options.signal ? { signal: options.signal } : {}),
      }, response => {
        for (const cookie of response.headers['set-cookie'] ?? []) {
          const pair = cookie.split(';')[0]!, separator = pair.indexOf('=')
          jar?.set(pair.slice(0, separator), pair.slice(separator + 1))
        }
        const chunks: Buffer[] = []
        response.on('data', (chunk: Buffer) => chunks.push(chunk)); response.on('error', reject)
        response.on('end', () => resolve(new Response(response.statusCode === 204 ? null : Buffer.concat(chunks).toString('utf8'), { status: response.statusCode })))
      })
      request.on('error', reject); request.end(options.body ?? undefined)
    })
  }
  async function json(path: string, method: string, expected: number, body?: object, bearer?: string, jar?: Map<string, string>, csrf?: string) {
    const response = await wire(path, { method, headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(bearer ? { Authorization: `Bearer ${bearer}`, 'X-Profile-Context': 'client' } : {}),
      ...(csrf ? { 'X-CSRF-TOKEN': csrf, 'X-Profile-Context': 'dietitian' } : {}),
    }, ...(body ? { body: JSON.stringify(body) } : {}) }, jar)
    expect(response.status, `${method} ${path}`).toBe(expected)
    return response.status === 204 ? undefined : response.json()
  }
  const suffix = Date.now(), password = 'Synthetic comment integration password'
  const clientEmail = `synthetic-sharing-client-${suffix}@example.test`, expertEmail = `synthetic-sharing-expert-${suffix}@example.test`
  const client = await json('/api/v1/auth/register', 'POST', 201, { email: clientEmail, password, displayName: 'Synthetic comment client', role: 'client' })
  const expert = await json('/api/v1/dietitians/apply', 'POST', 201, { email: expertEmail, password, displayName: 'Synthetic comment expert', licenseInfo: 'Synthetic license' })
  expect(client.id).toMatch(/^[a-f0-9-]{36}$/); expect(expert.id).toMatch(/^[a-f0-9-]{36}$/)
  execFileSync('docker', ['exec', container, 'psql', '-U', 'sharing_test', '-d', 'sharing_test', '-v', 'ON_ERROR_STOP=1', '-c',
    `UPDATE users SET is_email_verified=true WHERE id IN ('${client.id}','${expert.id}'); UPDATE dietitian_profiles SET is_verified=true WHERE user_id='${expert.id}';`], { stdio: 'pipe' })
  const mobile = await json('/api/v1/auth/login', 'POST', 200, { email: clientEmail, password })
  const fetch = vi.spyOn(globalThis, 'fetch').mockImplementation((input, options) => wire(String(input), options, cookies))
  let token: string | undefined
  try {
    await login({ email: expertEmail, password }, signal); token = await getCsrf(signal)
    const profile = await json('/api/v1/dietitians/me', 'GET', 200, undefined, undefined, cookies)
    const relationship = await json('/api/v1/dietitian-relationships', 'POST', 201, { dietitianId: profile.id }, mobile.accessToken)
    await json(`/api/v1/dietitian-relationships/${relationship.id}/accept`, 'POST', 200, undefined, undefined, cookies, token)
    const grant = await json('/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relationship.id, category: 'meal_logs', isGranted: true }, mobile.accessToken)
    const meal = await json('/api/v1/meal-logs', 'POST', 201, { mealType: 'lunch', consumedAt: '2026-11-18T12:00:00Z', source: 'manual',
      items: [{ displayName: 'Synthetic HTTPS meal', isEstimated: false, caloriesKcal: 125.5 }],
    }, mobile.accessToken)
    render(<WorkspaceContext.Provider value={{ token, dietitianId: profile.id, onFailure: () => false }}><MealLogPanel clientId={relationship.clientId} /></WorkspaceContext.Provider>)
    const user = userEvent.setup()
    await screen.findByText('Synthetic HTTPS meal')
    await user.click(screen.getByRole('button', { name: 'Yorumlar ve yanıtlar' }))
    expect(await screen.findByText('Henüz yorum veya yanıt yok.')).toBeVisible()
    const text = 'Sentetik HTTPS diyetisyen yorumu'
    await user.type(screen.getByLabelText('Öğüne yorumunuz'), text)
    await user.click(screen.getByRole('button', { name: 'Yorum gönder' }))
    expect(await screen.findByText('Diyetisyen yorumu')).toBeVisible()
    expect(screen.getByText('Yorum kaydedildi.')).toBeVisible()
    const posts = fetch.mock.calls.filter(([url, options]) => String(url).includes('/comments') && options?.method === 'POST')
    expect(posts).toHaveLength(1); expect(JSON.parse(posts[0]![1]!.body as string)).toEqual({ text })
    const page = await json(`/api/v1/meal-logs/${meal.id}/comments?page=1&pageSize=10`, 'GET', 200, undefined, undefined, cookies)
    expect(page.totalCount).toBe(1)
    await json(`/api/v1/meal-logs/${meal.id}/comments`, 'POST', 201, { text: 'Sentetik HTTPS danışan yanıtı', parentCommentId: page.items[0].id }, mobile.accessToken)
    await user.click(screen.getByRole('button', { name: 'Yorumları yenile' }))
    expect(await screen.findByText('Danışan yanıtı')).toBeVisible()
    expect(screen.getByText('Sentetik HTTPS danışan yanıtı')).toBeVisible()
    for (let i = 0; i < 9; i++) await createMealLogComment(meal.id, `Sentetik sayfalama yorumu ${i}`, token, signal)
    await user.click(screen.getByRole('button', { name: 'Yorumları yenile' }))
    await screen.findByText('11 yorum/yanıt · Sayfa 1')
    await user.click(screen.getByRole('button', { name: 'Sonraki yorum sayfası' }))
    expect(await screen.findByText('11 yorum/yanıt · Sayfa 2')).toBeVisible()
    expect(within(screen.getByRole('list', { name: 'Yorum geçmişi' })).getAllByRole('listitem')).toHaveLength(1)
    await user.type(screen.getByLabelText('Öğüne yorumunuz'), 'Sentetik geçici taslak')
    await json(`/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
    await user.click(screen.getByRole('button', { name: 'Yorumları yenile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Öğün paylaşımı kapalı')
    expect(screen.queryByRole('article')).not.toBeInTheDocument(); expect(screen.queryByDisplayValue('Sentetik geçici taslak')).not.toBeInTheDocument()
    expect((await json(`/api/v1/meal-logs/${meal.id}/comments?page=1&pageSize=10`, 'GET', 200, undefined, mobile.accessToken)).totalCount).toBe(11)
    expect(fetch.mock.calls.every(([, options]) => !new Headers(options?.headers).has('Authorization'))).toBe(true)
  } finally { if (token) await logout(token, signal) }
}, 30_000)

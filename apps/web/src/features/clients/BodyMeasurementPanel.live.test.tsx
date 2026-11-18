/// <reference types="node" />
// Opt-in integration: real React DOM + HTTPS cookie/CSRF API on a disposable PostgreSQL.
// This is not a browser rendering test. No application database fixtures are created.
import { request as httpsRequest } from 'node:https'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, it, vi } from 'vitest'
import { getCsrf, login, logout } from '../auth/webSessionApi'
import { WorkspaceContext } from '../workspace/workspaceSession'
import { BodyMeasurementPanel } from './BodyMeasurementPanel'

it.skipIf(process.env.SNP_MEASUREMENT_WEB_LIVE !== '1')('real PostgreSQL/HTTPS: permitted measurement diary, full charts, filter, paging and revocation', async () => {
  const container = process.env.SNP_SHARING_CONTAINER!
  expect(container).toMatch(/^smart-nutrition-sharing-test-\d+$/)
  const origin = 'https://localhost:7101'
  const ca = readFileSync(process.env.SNP_MEASUREMENT_WEB_CA!)
  const cookies = new Map<string, string>()
  const signal = new AbortController().signal
  function wire(path: string, options: RequestInit = {}, jar?: Map<string, string>): Promise<Response> {
    const headers = new Headers(options.headers)
    if (jar) {
      headers.set('Origin', origin)
      if (jar.size) headers.set('Cookie', [...jar].map(([name, value]) => `${name}=${value}`).join('; '))
    }
    return new Promise((resolve, reject) => {
      const request = httpsRequest(new URL(path, origin), {
        method: options.method ?? 'GET', headers: Object.fromEntries(headers), ca,
        ...(options.signal ? { signal: options.signal } : {}),
      }, response => {
        for (const cookie of response.headers['set-cookie'] ?? []) {
          const pair = cookie.split(';')[0]!
          const index = pair.indexOf('=')
          jar?.set(pair.slice(0, index), pair.slice(index + 1))
        }
        const chunks: Buffer[] = []
        response.on('data', (chunk: Buffer) => chunks.push(chunk))
        response.on('error', reject)
        response.on('end', () => resolve(new Response(response.statusCode === 204 ? null : Buffer.concat(chunks).toString('utf8'), { status: response.statusCode })))
      })
      request.on('error', reject)
      request.end(options.body ?? undefined)
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
  const suffix = Date.now()
  const clientEmail = `synthetic-sharing-client-${suffix}@example.test`
  const expertEmail = `synthetic-sharing-expert-${suffix}@example.test`
  const password = 'Synthetic measurement integration password'
  const client = await json('/api/v1/auth/register', 'POST', 201, { email: clientEmail, password, displayName: 'Sentetik danışan', role: 'client' })
  const expert = await json('/api/v1/dietitians/apply', 'POST', 201, { email: expertEmail, password, displayName: 'Sentetik uzman', licenseInfo: 'Synthetic test license' })
  expect(client.id).toMatch(/^[a-f0-9-]{36}$/)
  expect(expert.id).toMatch(/^[a-f0-9-]{36}$/)
  // Only these new synthetic accounts in the explicitly named disposable DB are approved.
  execFileSync('docker', ['exec', container, 'psql', '-U', 'sharing_test', '-d', 'sharing_test', '-v', 'ON_ERROR_STOP=1', '-c',
    `UPDATE users SET is_email_verified=true WHERE id IN ('${client.id}','${expert.id}'); UPDATE dietitian_profiles SET is_verified=true WHERE user_id='${expert.id}';`], { stdio: 'pipe' })
  const mobile = await json('/api/v1/auth/login', 'POST', 200, { email: clientEmail, password })
  const fetch = vi.spyOn(globalThis, 'fetch').mockImplementation((input, options) => wire(String(input), options, cookies))
  let token: string | undefined
  try {
    await login({ email: expertEmail, password }, signal)
    token = await getCsrf(signal)
    const profile = await json('/api/v1/dietitians/me', 'GET', 200, undefined, undefined, cookies)
    const relation = await json('/api/v1/dietitian-relationships', 'POST', 201, { dietitianId: profile.id }, mobile.accessToken)
    await json(`/api/v1/dietitian-relationships/${relation.id}/accept`, 'POST', 200, undefined, undefined, cookies, token)
    for (const category of ['nutrition_plans', 'meal_logs']) {
      await json('/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category, isGranted: true }, mobile.accessToken)
    }
    for (let index = 1; index <= 11; index++) {
      await json('/api/v1/body-measurements', 'POST', 201, {
        measuredAt: `2026-11-${String(index).padStart(2, '0')}T09:00:00Z`, source: 'manual',
        weightKg: 80 - index, waistCm: index % 2 === 0 ? null : 85 - index,
        hipCm: 100 - index, chestCm: 95 - index, bodyFatPercent: 22 - index,
        note: 'Sentetik canlı ölçüm',
      }, mobile.accessToken)
    }
    const user = userEvent.setup()
    render(<WorkspaceContext.Provider value={{ token, dietitianId: profile.id, onFailure: () => false }}><BodyMeasurementPanel clientId={relation.clientId} /></WorkspaceContext.Provider>)
    expect(await screen.findByRole('alert')).toHaveTextContent('Ölçüm paylaşımı kapalı')
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    const grant = await json('/api/v1/data-sharing-permissions', 'POST', 201, { relationshipId: relation.id, category: 'body_measurements', isGranted: true }, mobile.accessToken)
    await user.click(screen.getByRole('button', { name: 'Ölçümleri yenile' }))
    expect(await screen.findByRole('img', { name: 'Kilo gelişimi (kg): 11 kayıt' })).toBeVisible()
    expect(screen.getAllByRole('article')).toHaveLength(10)
    await user.click(screen.getByRole('button', { name: 'Sonraki ölçüm sayfası' }))
    expect(await screen.findByText('11 ölçüm · Sayfa 2')).toBeVisible()
    expect(screen.getAllByRole('article')).toHaveLength(1)
    expect(screen.getByRole('img', { name: 'Kilo gelişimi (kg): 11 kayıt' }).querySelectorAll('circle')).toHaveLength(11)
    fireEvent.change(screen.getByLabelText('Ölçüm başlangıcı'), { target: { value: '2026-11-03T00:00' } })
    fireEvent.change(screen.getByLabelText('Ölçüm bitişi'), { target: { value: '2026-11-05T00:00' } })
    await user.click(screen.getByRole('button', { name: 'Ölçümleri filtrele' }))
    expect(await screen.findByRole('img', { name: 'Kilo gelişimi (kg): 2 kayıt' })).toBeVisible()
    expect(screen.getAllByRole('article')).toHaveLength(2)
    await json(`/api/v1/data-sharing-permissions/${grant.id}`, 'PATCH', 200, { isGranted: false }, mobile.accessToken)
    act(() => window.dispatchEvent(new Event('focus')))
    expect(await screen.findByRole('alert')).toHaveTextContent('Ölçüm paylaşımı kapalı')
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    const permissions = await json(`/api/v1/data-sharing-permissions?relationshipId=${relation.id}&page=1&pageSize=10`, 'GET', 200, undefined, mobile.accessToken)
    expect(Object.fromEntries(permissions.items.map((item: { category: string; isGranted: boolean }) => [item.category, item.isGranted])))
      .toEqual({ nutrition_plans: true, meal_logs: true, body_measurements: false })
    expect(fetch.mock.calls.every(([, options]) => !new Headers(options?.headers).has('Authorization'))).toBe(true)
  } finally {
    if (token) await logout(token, signal)
  }
}, 30_000)

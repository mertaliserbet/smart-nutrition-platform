import { defineConfig } from '@playwright/test'
import { isAbsolute, resolve, sep } from 'node:path'

if (process.env.SNP_E2E_TEST_ENV !== 'nutrition_u6_test') throw new Error('Start the isolated U6 test environment first.')
const results = process.env.SNP_E2E_RESULTS
const repository = resolve(import.meta.dirname, '../..')
if (!results || !isAbsolute(results) || resolve(results).startsWith(repository + sep)) throw new Error('Use an absolute test results directory outside the repository.')
export default defineConfig({
  testDir: './e2e', testMatch: '**/*.e2e.ts', workers: 1, retries: 0, timeout: 90_000,
  outputDir: results,
  reporter: [['list']],
  use: {
    baseURL: 'https://localhost:5446', channel: 'msedge', headless: true,
    ignoreHTTPSErrors: false, locale: 'tr-TR', timezoneId: 'Europe/Istanbul',
    viewport: { width: 1366, height: 900 }, trace: 'off', screenshot: 'off', video: 'off',
  },
})

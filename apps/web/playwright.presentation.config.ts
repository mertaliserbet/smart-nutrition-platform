import { defineConfig } from '@playwright/test'

// Presentation QA uses synthetic intercepted API responses, never the application DB.
export default defineConfig({
  testDir: './e2e', testMatch: '**/*.ui.ts', workers: 1, retries: 0, timeout: 90_000,
  outputDir: './node_modules/.cache/nutrition-visual-qa/results', reporter: [['list']],
  use: { baseURL: process.env.SMART_NUTRITION_PRESENTATION_URL ?? 'http://127.0.0.1:5173', channel: 'msedge', headless: true, locale: 'tr-TR', timezoneId: 'Europe/Istanbul', colorScheme: 'light', trace: 'off', video: 'off', screenshot: 'only-on-failure' },
})

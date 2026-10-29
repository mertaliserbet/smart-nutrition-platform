import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'
import { readFileSync } from 'node:fs'

const certificate = process.env.SMART_NUTRITION_HTTPS_CERT
const key = process.env.SMART_NUTRITION_HTTPS_KEY
if (Boolean(certificate) !== Boolean(key)) throw new Error('Both development HTTPS certificate paths are required.')
// Anonymous auth also stays on HTTPS when the API HTTPS profile redirects HTTP.
const anonymousAuthTarget = certificate ? 'https://localhost:7099' : 'http://127.0.0.1:5052'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: certificate ? 'localhost' : '127.0.0.1', strictPort: true,
    ...(certificate && key ? { https: { cert: readFileSync(certificate), key: readFileSync(key) } } : {}),
    proxy: {
      '/api/v1/auth/register': { target: anonymousAuthTarget, secure: true },
      '/api/v1/auth/verify-email': { target: anonymousAuthTarget, secure: true },
      '/api/v1/auth/resend-verification': { target: anonymousAuthTarget, secure: true },
      '/api/v1/auth/csrf': { target: 'https://localhost:7099', secure: true },
      '/api/v1/auth/web-session': { target: 'https://localhost:7099', secure: true },
      '/api/v1/auth/me': { target: 'https://localhost:7099', secure: true },
      '/api/v1/auth/admin-web-session': { target: 'https://localhost:7099', secure: true },
      '/api/v1/dietitians/apply': { target: anonymousAuthTarget, secure: true },
      '/api/v1/dietitians': { target: 'https://localhost:7099', secure: true },
      '/api/v1/admin/dietitians': { target: 'https://localhost:7099', secure: true },
      '/api/v1/dietitian-relationships': { target: 'https://localhost:7099', secure: true },
      '/api/v1/data-sharing-permissions': { target: 'https://localhost:7099', secure: true },
      '/api/v1/dietitian/clients': { target: 'https://localhost:7099', secure: true },
      '/api/v1/nutrition-plans': { target: 'https://localhost:7099', secure: true },
    },
  },
  preview: { host: '127.0.0.1', strictPort: true },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    restoreMocks: true,
  },
})

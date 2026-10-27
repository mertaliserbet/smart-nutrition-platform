import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1', strictPort: true,
    proxy: {
      '/api/v1/auth/verify-email': { target: 'http://127.0.0.1:5052' },
      '/api/v1/auth/resend-verification': { target: 'http://127.0.0.1:5052' },
    },
  },
  preview: { host: '127.0.0.1', strictPort: true },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    restoreMocks: true,
  },
})

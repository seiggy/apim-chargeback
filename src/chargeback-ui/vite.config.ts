import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/logs': 'http://localhost:5000',
      '/chargeback': 'http://localhost:5000',
      '/api': 'http://localhost:5000',
    }
  }
})

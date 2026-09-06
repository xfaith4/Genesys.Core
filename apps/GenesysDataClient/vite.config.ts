/// <reference types="node" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// The demo server holds the fixtures. In dev we proxy to it so the app runs same-origin
// and needs no CORS; in a build the app is served by that same server from dist/.
const MOCK_SERVER = process.env.GDC_MOCK_SERVER ?? 'http://localhost:7777';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': { target: MOCK_SERVER, changeOrigin: true },
      '/__meta': { target: MOCK_SERVER, changeOrigin: true },
      '/oauth': { target: MOCK_SERVER, changeOrigin: true },
      '/health': { target: MOCK_SERVER, changeOrigin: true },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});

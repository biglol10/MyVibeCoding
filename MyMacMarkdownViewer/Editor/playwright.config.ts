import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: 'tests/browser', timeout: 30000, fullyParallel: false,
  use: { baseURL: 'http://127.0.0.1:4173', viewport: { width: 1100, height: 800 }, colorScheme: 'light' },
  projects: [{ name: 'webkit', use: { browserName: 'webkit' } }],
  webServer: { command: 'npx vite preview --host 127.0.0.1 --port 4173', url: 'http://127.0.0.1:4173', reuseExistingServer: false },
});

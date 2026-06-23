import { configDefaults, defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  test: {
    environment: "jsdom",
    exclude: [...configDefaults.exclude, "tests/e2e/**", "browser-extension/**", ".worktrees/**", "scripts/**"],
    globals: true,
    setupFiles: "./src/setupTests.ts",
  },
});

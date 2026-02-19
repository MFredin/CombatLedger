import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],

  // Prevent Vite from obscuring Rust errors in the terminal.
  clearScreen: false,

  server: {
    port: 1420,
    strictPort: true,
    // Tauri expects a fixed port in development mode.
    watch: {
      // Tell Vite's FSWatcher to ignore the Rust source tree.
      ignored: ["**/src-tauri/**"],
    },
  },

  envPrefix: ["VITE_", "TAURI_"],

  build: {
    // Tauri WebView supports ES2021 on all platforms.
    target: ["es2021", "chrome100", "safari13"],
    // Don't minify for debug builds.
    minify: !process.env.TAURI_DEBUG ? "esbuild" : false,
    sourcemap: !!process.env.TAURI_DEBUG,
  },
});

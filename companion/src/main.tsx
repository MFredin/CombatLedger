/**
 * main.tsx — React entry point + Tauri log-line listener
 *
 * Detects which Tauri window is active and renders the appropriate UI.
 * The log-line pipeline (watcher → parser → writer) is initialised here
 * for the main window so it runs for the full lifetime of the app.
 */

import React from "react";
import ReactDOM from "react-dom/client";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { orchestrator } from "./orchestrator.js";
import App from "./ui/App.js";
import "./ui/styles/global.css";

// ---------------------------------------------------------------------------
// Log-line pipeline (only active in the main window)
// ---------------------------------------------------------------------------

async function initLogListener(): Promise<void> {
  // Load historical snapshots from SQLite so subsequent fights include them.
  await orchestrator.initialize();

  // Write GeneratedData.lua with current history.  Can't do this inline
  // because wow_paths is set by an async Rust background task — if we call
  // write_session before it finishes we get "WoW paths not configured".
  // Strategy: try immediately (works if auto-resolve was fast), then retry
  // once the status-update event confirms WoW paths are ready.
  let startupWriteDone = false;

  async function tryStartupWrite(): Promise<void> {
    if (startupWriteDone) return;
    const lua = orchestrator.generateStartupLua();
    if (!lua) return; // nothing in history yet
    try {
      await invoke("write_session", { luaContent: lua });
      startupWriteDone = true;
      await invoke("log_activity", {
        level: "info",
        message: "Startup: historical session data written to GeneratedData.lua.",
      });
    } catch {
      // wow_paths not ready yet; the status-update listener will retry.
    }
  }

  // Best-effort immediate attempt.
  await tryStartupWrite();

  // Definitive retry once the Rust auto-resolve task confirms WoW is found.
  await listen<string>("status-update", async (e) => {
    if (!startupWriteDone) {
      const s = e.payload.toLowerCase();
      if (s.includes("watching") || s.includes("log found")) {
        await tryStartupWrite();
      }
    }
  });

  await listen<string[]>("log-lines", async (event) => {
    const outputs = await orchestrator.processLines(event.payload);
    for (const output of outputs) {
      try {
        await invoke("write_session", { luaContent: output.luaContent });
        const name = output.session.encounterName;
        const result = output.session.success ? "Kill" : "Wipe";
        await invoke("log_activity", {
          level: output.session.success ? "info" : "warn",
          message: `${name} — ${result} (pull #${output.session.pullNumber})`,
        });
      } catch (err) {
        await invoke("log_activity", {
          level: "error",
          message: `Session write failed: ${String(err)}`,
        });
      }
    }
  });
}

// ---------------------------------------------------------------------------
// React mount
// ---------------------------------------------------------------------------

const rootEl = document.getElementById("root");
if (!rootEl) throw new Error("Root element not found");

// Start log pipeline alongside the UI.
initLogListener().catch((err) =>
  console.error("[CombatLedger] Log listener failed:", err)
);

ReactDOM.createRoot(rootEl).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

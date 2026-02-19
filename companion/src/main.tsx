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
import { getCurrentWindow } from "@tauri-apps/api/window";
import { ParserOrchestrator } from "./parser/index.js";
import App from "./ui/App.js";
import SettingsWindow from "./ui/windows/SettingsWindow.js";
import "./ui/styles/global.css";

// ---------------------------------------------------------------------------
// Log-line pipeline (only active in the main window)
// ---------------------------------------------------------------------------

const orchestrator = new ParserOrchestrator();

async function initLogListener(): Promise<void> {
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

const windowLabel = getCurrentWindow().label;

if (windowLabel === "settings") {
  ReactDOM.createRoot(rootEl).render(
    <React.StrictMode>
      <SettingsWindow />
    </React.StrictMode>
  );
} else {
  // Start log pipeline alongside the UI.
  initLogListener().catch((err) =>
    console.error("[CombatLedger] Log listener failed:", err)
  );

  ReactDOM.createRoot(rootEl).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
}

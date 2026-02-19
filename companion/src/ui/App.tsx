import React, { useState, useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import ActivityTab from "./tabs/ActivityTab.js";
import HistoryTab from "./tabs/HistoryTab.js";
import TrendsTab from "./tabs/TrendsTab.js";
import { importLogFile } from "../parser/importer.js";
import type { ImportProgress, ImportSummary } from "../parser/importer.js";

type Tab = "activity" | "history" | "trends";
type UpdateStatus = "idle" | "available" | "downloading" | "error";
type UpdateInfo = { version: string; notes: string };
type ImportStatus = "idle" | "running" | "done";

function statusToDotClass(status: string): string {
  const s = status.toLowerCase();
  if (s.includes("watching") || s.includes("log found")) return "watching";
  if (s.includes("error") || s.includes("failed")) return "error";
  if (s.includes("setup") || s.includes("not found") || s.includes("not yet")) return "warn";
  return "idle";
}

export default function App(): React.ReactElement {
  const [activeTab, setActiveTab] = useState<Tab>("activity");
  const [status, setStatus] = useState<string>("Connecting…");
  const [updateStatus, setUpdateStatus] = useState<UpdateStatus>("idle");
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [importStatus, setImportStatus] = useState<ImportStatus>("idle");
  const [importProgress, setImportProgress] = useState<ImportProgress | null>(null);
  const [importSummary, setImportSummary] = useState<ImportSummary | null>(null);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen<string>("status-update", (e) => {
      setStatus(e.payload);
    })
      .then((fn) => {
        unlisten = fn;
      })
      .catch(console.error);

    return () => {
      unlisten?.();
    };
  }, []);

  // Check for a new release once, a few seconds after the UI settles.
  useEffect(() => {
    const timer = setTimeout(async () => {
      try {
        const info = await invoke<UpdateInfo | null>("check_update");
        if (info) {
          setUpdateInfo(info);
          setUpdateStatus("available");
        }
      } catch {
        // Silent fail — no network or update server unreachable.
      }
    }, 4000);
    return () => clearTimeout(timer);
  }, []);

  async function handleInstall() {
    setUpdateStatus("downloading");
    try {
      await invoke("install_update");
      // On Windows the NSIS installer launches and the process exits here.
      // On macOS the app restarts. Either way we won't reach this line normally.
    } catch (err) {
      console.error("[updater]", err);
      setUpdateStatus("error");
    }
  }

  async function handleImport() {
    setImportStatus("running");
    setImportProgress(null);
    setImportSummary(null);
    try {
      const result = await importLogFile((p) => setImportProgress(p));
      if (result === null) {
        // User cancelled the file picker.
        setImportStatus("idle");
      } else {
        setImportSummary(result);
        setImportStatus("done");
      }
    } catch (err) {
      console.error("[import] Failed:", err);
      setImportStatus("idle");
    }
  }

  const dotClass = `tab-bar__logo-dot tab-bar__logo-dot--${statusToDotClass(status)}`;

  return (
    <div className="app-root">
      {/* ── Tab bar ─────────────────────────────────────────────────── */}
      <div className="tab-bar">
        <div className="tab-bar__logo">
          <span className={dotClass} title={status} />
          CombatLedger
        </div>

        {(
          [
            ["activity", "Activity"],
            ["history",  "History"],
            ["trends",   "Trends"],
          ] as [Tab, string][]
        ).map(([id, label]) => (
          <button
            key={id}
            className={`tab-btn${activeTab === id ? " tab-btn--active" : ""}`}
            onClick={() => setActiveTab(id)}
          >
            {label}
          </button>
        ))}

        <button
          className="tab-bar__import-btn"
          onClick={handleImport}
          disabled={importStatus === "running"}
          title="Import a WoW combat log file to backfill history"
        >
          {importStatus === "running" ? "Importing…" : "Import Log"}
        </button>
      </div>

      {/* ── Update banner ───────────────────────────────────────────── */}
      {updateStatus === "available" && updateInfo && (
        <div className="update-banner">
          <span className="update-banner__icon">↑</span>
          <span className="update-banner__text">
            Update available:{" "}
            <span className="update-banner__version">v{updateInfo.version}</span>
          </span>
          <button className="update-banner__btn" onClick={handleInstall}>
            Install &amp; Restart
          </button>
          <button
            className="update-banner__dismiss"
            onClick={() => setUpdateStatus("idle")}
            title="Dismiss"
          >
            ✕
          </button>
        </div>
      )}
      {updateStatus === "downloading" && (
        <div className="update-banner update-banner--downloading">
          <span className="update-banner__icon">↓</span>
          <span className="update-banner__text">Downloading update…</span>
        </div>
      )}
      {updateStatus === "error" && (
        <div className="update-banner update-banner--error">
          <span className="update-banner__text">Update failed — check your connection and try again.</span>
          <button
            className="update-banner__dismiss"
            onClick={() => setUpdateStatus("idle")}
            title="Dismiss"
          >
            ✕
          </button>
        </div>
      )}

      {/* ── Import progress / summary banner ────────────────────────── */}
      {importStatus === "running" && (
        <div className="import-banner">
          <span className="import-banner__text">
            {importProgress
              ? `Analysing… ${importProgress.totalBytes > 0
                  ? Math.round((importProgress.bytesRead / importProgress.totalBytes) * 100)
                  : "?"}% — ${importProgress.sessionsFound} session${importProgress.sessionsFound !== 1 ? "s" : ""} found`
              : "Starting import…"}
          </span>
          {importProgress && importProgress.totalBytes > 0 && (
            <div className="import-progress">
              <div
                className="import-progress__bar"
                style={{
                  width: `${Math.round((importProgress.bytesRead / importProgress.totalBytes) * 100)}%`,
                }}
              />
            </div>
          )}
        </div>
      )}
      {importStatus === "done" && importSummary && (
        <div className="import-banner import-banner--done">
          <span className="import-banner__icon">✓</span>
          <span className="import-banner__text">
            Import complete — {importSummary.sessionsImported} session{importSummary.sessionsImported !== 1 ? "s" : ""} imported
            {importSummary.sessionsSkipped > 0 && `, ${importSummary.sessionsSkipped} skipped (already in database)`}.
            {" "}Do a <code>/reload</code> in WoW to see the updated history.
          </span>
          <button
            className="import-banner__dismiss"
            onClick={() => { setImportStatus("idle"); setImportSummary(null); }}
            title="Dismiss"
          >
            ✕
          </button>
        </div>
      )}

      {/* ── Tab content ─────────────────────────────────────────────── */}
      <div className="tab-content">
        {activeTab === "activity" && <ActivityTab status={status} />}
        {activeTab === "history"  && <HistoryTab />}
        {activeTab === "trends"   && <TrendsTab />}
      </div>
    </div>
  );
}

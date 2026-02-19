import React, { useState, useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import ActivityTab from "./tabs/ActivityTab.js";
import HistoryTab from "./tabs/HistoryTab.js";
import TrendsTab from "./tabs/TrendsTab.js";

type Tab = "activity" | "history" | "trends";

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
      </div>

      {/* ── Tab content ─────────────────────────────────────────────── */}
      <div className="tab-content">
        {activeTab === "activity" && <ActivityTab status={status} />}
        {activeTab === "history"  && <HistoryTab />}
        {activeTab === "trends"   && <TrendsTab />}
      </div>
    </div>
  );
}

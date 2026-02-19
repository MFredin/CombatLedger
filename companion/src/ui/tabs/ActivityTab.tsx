import React, { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

interface ActivityEntry {
  id: number;
  timestamp: string;   // e.g. "2026-02-19 14:30:05"
  level: "info" | "warn" | "error";
  message: string;
}

function formatTime(ts: string): string {
  // SQLite returns "YYYY-MM-DD HH:MM:SS" in UTC
  const d = new Date(ts.replace(" ", "T") + "Z");
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false });
}

function levelIcon(level: string): string {
  if (level === "warn")  return "⚠";
  if (level === "error") return "✕";
  return "•";
}

interface Props {
  status: string;
}

function statusToDotClass(status: string): string {
  const s = status.toLowerCase();
  if (s.includes("watching") || s.includes("log found")) return "status-dot--watching";
  if (s.includes("error") || s.includes("failed"))       return "status-dot--error";
  if (s.includes("setup") || s.includes("not found") || s.includes("not yet")) return "status-dot--warn";
  return "status-dot--idle";
}

export default function ActivityTab({ status }: Props): React.ReactElement {
  const [entries, setEntries] = useState<ActivityEntry[]>([]);

  const refresh = useCallback(async () => {
    try {
      const data = await invoke<ActivityEntry[]>("get_activity_log", { limit: 100 });
      setEntries(data);
    } catch {
      // silently ignore — DB may not be ready on first render
    }
  }, []);

  // Initial load + polling
  useEffect(() => {
    void refresh();
    const interval = setInterval(() => void refresh(), 4000);
    return () => clearInterval(interval);
  }, [refresh]);

  // Refresh immediately when a new session is written
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen<void>("activity-update", () => void refresh())
      .then((fn) => { unlisten = fn; })
      .catch(console.error);
    return () => { unlisten?.(); };
  }, [refresh]);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", overflow: "hidden" }}>
      {/* Status row */}
      <div className="status-row">
        <div className={`status-dot ${statusToDotClass(status)}`} />
        <span className="status-text">{status}</span>
      </div>

      {/* Feed */}
      {entries.length === 0 ? (
        <div className="feed-empty">
          <span style={{ fontSize: 28, opacity: 0.3 }}>◉</span>
          <span>No activity yet</span>
          <span style={{ fontSize: 11, opacity: 0.6 }}>
            Entries appear here when CombatLedger processes combat sessions.
          </span>
        </div>
      ) : (
        <div className="feed-wrap">
          {entries.map((e) => (
            <div
              key={e.id}
              className={`feed-entry feed-entry--${e.level}`}
            >
              <span className="feed-entry__time">{formatTime(e.timestamp)}</span>
              <span className="feed-entry__icon">{levelIcon(e.level)}</span>
              <span className="feed-entry__msg">{e.message}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

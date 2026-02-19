import React, { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";

interface EncounterOption {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  pull_count: number;
  last_seen: number;
}

interface SessionSummary {
  id: number;
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  group_size: number;
  start_time: number;
  end_time: number;
  duration_sec: number;
  success: boolean;
  pull_number: number;
  total_deaths: number;
  interrupt_rate_pct: number;
  total_damage_done: number;
  total_healing_done: number;
  cc_avg_coverage_pct: number;
}

const DIFFICULTY: Record<number, string> = {
  1: "Normal", 2: "Heroic", 3: "Mythic", 4: "LFR",
  8: "Mythic+", 14: "Normal", 15: "Heroic", 16: "Mythic", 17: "LFR",
};

function fmtDifficulty(d: number): string {
  return DIFFICULTY[d] ?? `Diff ${d}`;
}

function fmtDuration(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function fmtDps(dmg: number, dur: number): string {
  if (dur <= 0) return "—";
  const dps = dmg / dur;
  return dps >= 1000 ? `${(dps / 1000).toFixed(1)}k` : String(Math.round(dps));
}

function fmtDate(ts: number): string {
  // ts is Unix seconds from SQLite
  return new Date(ts * 1000).toLocaleDateString([], {
    month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false,
  });
}

const PAGE_SIZE = 20;

export default function HistoryTab(): React.ReactElement {
  const [encounters, setEncounters] = useState<EncounterOption[]>([]);
  const [selectedEncounter, setSelectedEncounter] = useState<number | null>(null);
  const [selectedDifficulty, setSelectedDifficulty] = useState<number | null>(null);
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [page, setPage] = useState(0);
  const [hasMore, setHasMore] = useState(false);

  // Load encounter dropdown options once
  useEffect(() => {
    invoke<EncounterOption[]>("get_encounters")
      .then(setEncounters)
      .catch(console.error);
  }, []);

  const loadSessions = useCallback(
    async (enc: number | null, diff: number | null, pg: number) => {
      try {
        const data = await invoke<SessionSummary[]>("get_session_history", {
          encounterId: enc,
          difficulty: diff,
          limit: PAGE_SIZE + 1,
          offset: pg * PAGE_SIZE,
        });
        setHasMore(data.length > PAGE_SIZE);
        setSessions(data.slice(0, PAGE_SIZE));
      } catch (err) {
        console.error(err);
      }
    },
    []
  );

  useEffect(() => {
    void loadSessions(selectedEncounter, selectedDifficulty, page);
  }, [selectedEncounter, selectedDifficulty, page, loadSessions]);

  function handleEncounterChange(e: React.ChangeEvent<HTMLSelectElement>) {
    const val = e.target.value;
    setSelectedEncounter(val === "" ? null : Number(val));
    setSelectedDifficulty(null);
    setPage(0);
  }

  function handleDifficultyChange(e: React.ChangeEvent<HTMLSelectElement>) {
    const val = e.target.value;
    setSelectedDifficulty(val === "" ? null : Number(val));
    setPage(0);
  }

  // Unique difficulties for selected encounter
  const difficulties = selectedEncounter !== null
    ? [...new Set(
        encounters
          .filter((o) => o.encounter_id === selectedEncounter)
          .map((o) => o.difficulty)
      )]
    : [...new Set(encounters.map((o) => o.difficulty))];

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", overflow: "hidden" }}>
      {/* Filter bar */}
      <div className="filter-bar">
        <span className="filter-bar__label">Encounter</span>
        <select value={selectedEncounter ?? ""} onChange={handleEncounterChange} style={{ minWidth: 180 }}>
          <option value="">All encounters</option>
          {[...new Map(encounters.map((o) => [o.encounter_id, o])).values()].map((o) => (
            <option key={o.encounter_id} value={o.encounter_id}>
              {o.encounter_name} ({o.pull_count})
            </option>
          ))}
        </select>

        <span className="filter-bar__label">Difficulty</span>
        <select value={selectedDifficulty ?? ""} onChange={handleDifficultyChange} style={{ minWidth: 120 }}>
          <option value="">All</option>
          {difficulties.map((d) => (
            <option key={d} value={d}>{fmtDifficulty(d)}</option>
          ))}
        </select>
      </div>

      {/* Table */}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Date</th>
              <th>Encounter</th>
              <th>Diff</th>
              <th>Pull</th>
              <th>Duration</th>
              <th>Result</th>
              <th>Deaths</th>
              <th>Int%</th>
              <th>DPS</th>
            </tr>
          </thead>
          <tbody>
            {sessions.length === 0 ? (
              <tr className="data-table--empty">
                <td colSpan={9}>No sessions recorded yet — run a raid or M+ to start tracking.</td>
              </tr>
            ) : (
              sessions.map((s) => (
                <tr key={s.id}>
                  <td style={{ color: "var(--text-secondary)" }}>{fmtDate(s.start_time)}</td>
                  <td>{s.encounter_name}</td>
                  <td style={{ color: "var(--text-secondary)" }}>{fmtDifficulty(s.difficulty)}</td>
                  <td style={{ color: "var(--text-muted)" }}>#{s.pull_number}</td>
                  <td>{fmtDuration(s.duration_sec)}</td>
                  <td>
                    <span className={`badge badge--${s.success ? "kill" : "wipe"}`}>
                      {s.success ? "Kill" : "Wipe"}
                    </span>
                  </td>
                  <td style={{ color: s.total_deaths > 0 ? "var(--red)" : "var(--text-secondary)" }}>
                    {s.total_deaths}
                  </td>
                  <td style={{ color: s.interrupt_rate_pct >= 80 ? "var(--green)" : s.interrupt_rate_pct >= 50 ? "var(--gold)" : "var(--red)" }}>
                    {s.interrupt_rate_pct.toFixed(0)}%
                  </td>
                  <td>{fmtDps(s.total_damage_done, s.duration_sec)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      <div className="pagination">
        <button
          className="page-btn"
          onClick={() => setPage((p) => Math.max(0, p - 1))}
          disabled={page === 0}
        >
          ← Prev
        </button>
        <span className="page-info">Page {page + 1}</span>
        <button
          className="page-btn"
          onClick={() => setPage((p) => p + 1)}
          disabled={!hasMore}
        >
          Next →
        </button>
      </div>
    </div>
  );
}

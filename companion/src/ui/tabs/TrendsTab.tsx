import React, { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
  type ChartOptions,
} from "chart.js";
import { Line } from "react-chartjs-2";

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler);

interface EncounterOption {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  pull_count: number;
  last_seen: number;
}

interface TrendPoint {
  session_id: number;
  pull_number: number;
  start_time: number;
  success: boolean;
  duration_sec: number;
  total_deaths: number;
  interrupt_rate_pct: number;
  total_damage_done: number;
  total_healing_done: number;
  cc_avg_coverage_pct: number;
}

interface TrendSummary {
  total_pulls: number;
  kills: number;
  wipes: number;
  best_time_sec: number;
  avg_deaths: number;
  avg_interrupt_rate: number;
  death_trend: number;
  interrupt_trend: number;
  dps_trend: number;
}

interface TrendReport {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  points: TrendPoint[];
  summary: TrendSummary;
}

const DIFFICULTY: Record<number, string> = {
  1: "Normal", 2: "Heroic", 3: "Mythic", 4: "LFR",
  8: "Mythic+", 14: "Normal", 15: "Heroic", 16: "Mythic", 17: "LFR",
};

function fmtTime(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function trendArrow(val: number): string {
  if (val > 0.01)  return " ↑";
  if (val < -0.01) return " ↓";
  return " —";
}

const CHART_OPTIONS: ChartOptions<"line"> = {
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 300 },
  plugins: {
    legend: {
      labels: {
        color: "#7888a0",
        font: { size: 11 },
        boxWidth: 12,
        padding: 12,
      },
    },
    tooltip: {
      backgroundColor: "#141820",
      borderColor: "#252d40",
      borderWidth: 1,
      titleColor: "#e0e8f0",
      bodyColor: "#7888a0",
    },
  },
  scales: {
    x: {
      ticks: { color: "#4a5870", font: { size: 10 } },
      grid: { color: "#1e2535" },
    },
    y: {
      ticks: { color: "#4a5870", font: { size: 10 } },
      grid: { color: "#1e2535" },
    },
  },
};

export default function TrendsTab(): React.ReactElement {
  const [encounters, setEncounters] = useState<EncounterOption[]>([]);
  const [selectedEncounter, setSelectedEncounter] = useState<number | null>(null);
  const [selectedDifficulty, setSelectedDifficulty] = useState<number | null>(null);
  const [pullRange, setPullRange] = useState(20);
  const [report, setReport] = useState<TrendReport | null>(null);

  useEffect(() => {
    invoke<EncounterOption[]>("get_encounters")
      .then((opts) => {
        setEncounters(opts);
        if (opts[0]) {
          setSelectedEncounter(opts[0].encounter_id);
          setSelectedDifficulty(opts[0].difficulty);
        }
      })
      .catch(console.error);
  }, []);

  const loadTrend = useCallback(async () => {
    if (selectedEncounter === null || selectedDifficulty === null) {
      setReport(null);
      return;
    }
    try {
      const data = await invoke<TrendReport>("get_trend", {
        encounterId: selectedEncounter,
        difficulty: selectedDifficulty,
        lastN: pullRange,
      });
      setReport(data);
    } catch (err) {
      console.error(err);
    }
  }, [selectedEncounter, selectedDifficulty, pullRange]);

  useEffect(() => {
    void loadTrend();
  }, [loadTrend]);

  const difficulties = [...new Set(
    encounters.filter((o) => o.encounter_id === selectedEncounter).map((o) => o.difficulty)
  )];

  // Chart data
  const labels = report?.points.map((p) => `#${p.pull_number}`) ?? [];

  const deathData = {
    labels,
    datasets: [
      {
        label: "Deaths",
        data: report?.points.map((p) => p.total_deaths) ?? [],
        borderColor: "#e84040",
        backgroundColor: "rgba(232,64,64,0.1)",
        fill: true,
        tension: 0.3,
        pointRadius: 4,
        pointBackgroundColor: report?.points.map((p) =>
          p.success ? "#40e87a" : "#e84040"
        ) ?? [],
      },
    ],
  };

  const intData = {
    labels,
    datasets: [
      {
        label: "Interrupt %",
        data: report?.points.map((p) => Number(p.interrupt_rate_pct.toFixed(1))) ?? [],
        borderColor: "#40b8e8",
        backgroundColor: "rgba(64,184,232,0.1)",
        fill: true,
        tension: 0.3,
        pointRadius: 4,
      },
    ],
  };

  const s = report?.summary;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", overflow: "hidden" }}>
      {/* Filter bar */}
      <div className="filter-bar">
        <span className="filter-bar__label">Encounter</span>
        <select
          value={selectedEncounter ?? ""}
          onChange={(e) => {
            const val = Number(e.target.value);
            setSelectedEncounter(val);
            const diff = encounters.find((o) => o.encounter_id === val)?.difficulty ?? null;
            setSelectedDifficulty(diff);
          }}
          style={{ minWidth: 180 }}
        >
          {encounters.length === 0 && <option value="">No data yet</option>}
          {[...new Map(encounters.map((o) => [o.encounter_id, o])).values()].map((o) => (
            <option key={o.encounter_id} value={o.encounter_id}>{o.encounter_name}</option>
          ))}
        </select>

        <span className="filter-bar__label">Difficulty</span>
        <select
          value={selectedDifficulty ?? ""}
          onChange={(e) => setSelectedDifficulty(Number(e.target.value))}
          style={{ minWidth: 110 }}
        >
          {difficulties.map((d) => (
            <option key={d} value={d}>{DIFFICULTY[d] ?? `Diff ${d}`}</option>
          ))}
        </select>

        <span className="filter-bar__label">Last</span>
        <select value={pullRange} onChange={(e) => setPullRange(Number(e.target.value))} style={{ width: 80 }}>
          <option value={10}>10 pulls</option>
          <option value={20}>20 pulls</option>
          <option value={30}>30 pulls</option>
        </select>
      </div>

      {report === null ? (
        <div className="chart-placeholder" style={{ flex: 1 }}>
          {encounters.length === 0
            ? "No sessions yet — complete a raid or M+ pull to start tracking."
            : "Select an encounter above."}
        </div>
      ) : (
        <div className="trends-wrap">
          {/* Summary stats */}
          {s && (
            <div className="summary-grid">
              <div className="summary-card">
                <div className="summary-card__val summary-card__val--white">{s.total_pulls}</div>
                <div className="summary-card__label">Pulls</div>
              </div>
              <div className="summary-card">
                <div className="summary-card__val summary-card__val--green">{s.kills}</div>
                <div className="summary-card__label">Kills</div>
              </div>
              <div className="summary-card">
                <div className="summary-card__val summary-card__val--red">{s.wipes}</div>
                <div className="summary-card__label">Wipes</div>
              </div>
              <div className="summary-card">
                <div className="summary-card__val summary-card__val--blue">
                  {s.best_time_sec > 0 ? fmtTime(s.best_time_sec) : "—"}
                </div>
                <div className="summary-card__label">Best Time</div>
              </div>
              <div className="summary-card">
                <div
                  className={`summary-card__val summary-card__val--${s.avg_deaths < 1 ? "green" : s.avg_deaths < 3 ? "white" : "red"}`}
                >
                  {s.avg_deaths.toFixed(1)}
                  <span style={{ fontSize: 12, color: s.death_trend < 0 ? "var(--green)" : "var(--red)" }}>
                    {trendArrow(-s.death_trend)}
                  </span>
                </div>
                <div className="summary-card__label">Avg Deaths</div>
              </div>
              <div className="summary-card">
                <div
                  className={`summary-card__val summary-card__val--${s.avg_interrupt_rate >= 80 ? "green" : s.avg_interrupt_rate >= 50 ? "white" : "red"}`}
                >
                  {s.avg_interrupt_rate.toFixed(0)}%
                </div>
                <div className="summary-card__label">Avg Int%</div>
              </div>
            </div>
          )}

          {/* Deaths chart */}
          <div className="chart-card" style={{ flex: 1 }}>
            <div className="section-header">Deaths per pull</div>
            <div style={{ height: "calc(100% - 22px)" }}>
              <Line data={deathData} options={CHART_OPTIONS} />
            </div>
          </div>

          {/* Interrupt chart */}
          <div className="chart-card" style={{ flex: 1 }}>
            <div className="section-header">Interrupt rate %</div>
            <div style={{ height: "calc(100% - 22px)" }}>
              <Line data={intData} options={CHART_OPTIONS} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

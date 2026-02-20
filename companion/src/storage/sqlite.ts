/**
 * storage/sqlite.ts — TypeScript wrappers for Phase 3 SQLite Tauri commands
 *
 * Provides typed invoke() wrappers for the Rust database commands. All types
 * here mirror the Rust structs in database.rs exactly (snake_case).
 */

import { invoke } from "@tauri-apps/api/core";

// ---------------------------------------------------------------------------
// Insert types — sent to Rust
// ---------------------------------------------------------------------------

export interface PlayerMetricInsert {
  player_guid: string;
  player_name: string;
  player_class: string;
  player_spec: string;
  damage_done: number;
  healing_done: number;
  overhealing: number;
  dps: number;
  hps: number;
  interrupt_count: number;
  death_count: number;
  cc_applied: number;
}

export interface SessionInsert {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  group_size: number;
  start_time: number;   // unix seconds
  end_time: number;
  duration_sec: number;
  success: boolean;
  pull_number: number;
  companion_version: string;
  total_deaths: number;
  interrupt_total: number;
  interrupt_hit: number;
  interrupt_rate_pct: number;
  total_damage_done: number;
  total_healing_done: number;
  cc_avg_coverage_pct: number;
  players: PlayerMetricInsert[];
  /** JSON-serialised sessionToLuaValue output for this session. */
  session_snapshot: string;
}

// ---------------------------------------------------------------------------
// Query result types — received from Rust
// ---------------------------------------------------------------------------

export interface SessionSummary {
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

export interface TrendPoint {
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

export interface TrendSummary {
  total_pulls: number;
  kills: number;
  wipes: number;
  best_time_sec: number;
  avg_deaths: number;
  avg_interrupt_rate: number;
  death_trend: number;       // negative = improving (fewer deaths)
  interrupt_trend: number;   // positive = improving
  dps_trend: number;         // positive = improving
}

export interface TrendReport {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  points: TrendPoint[];
  summary: TrendSummary;
}

export interface PlayerDistribution {
  player_guid: string;
  player_name: string;
  player_class: string;
  player_spec: string;
  metric: string;         // "dps", "hps", "interrupts"
  current_value: number;
  percentile: number;
  total_samples: number;
  min_value: number;
  max_value: number;
  median_value: number;
}

export interface DistributionReport {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  players: PlayerDistribution[];
}

export interface EncounterOption {
  encounter_id: number;
  encounter_name: string;
  difficulty: number;
  pull_count: number;
  last_seen: number;
}

// ---------------------------------------------------------------------------
// API functions
// ---------------------------------------------------------------------------

export async function storeSession(session: SessionInsert): Promise<number> {
  return invoke<number>("store_session", { session });
}

/** Return the most recent `limit` session_snapshot JSON strings, newest first. */
export async function getSessionSnapshots(limit = 19): Promise<string[]> {
  return invoke<string[]>("get_session_snapshots", { limit });
}

/** Return true if a session with the given encounter + start_time already exists. */
export async function sessionExists(encounterId: number, startTime: number): Promise<boolean> {
  return invoke<boolean>("session_exists", { encounterId, startTime });
}

export async function getSessionHistory(
  encounterId?: number,
  difficulty?: number,
  limit = 50,
  offset = 0,
): Promise<SessionSummary[]> {
  return invoke<SessionSummary[]>("get_session_history", {
    encounterId: encounterId ?? null,
    difficulty: difficulty ?? null,
    limit,
    offset,
  });
}

export async function getTrend(
  encounterId: number,
  difficulty: number,
  lastN = 30,
): Promise<TrendReport> {
  return invoke<TrendReport>("get_trend", { encounterId, difficulty, lastN });
}

export async function getDistribution(
  encounterId: number,
  difficulty: number,
  currentSessionId: number,
): Promise<DistributionReport> {
  return invoke<DistributionReport>("get_distribution", {
    encounterId,
    difficulty,
    currentSessionId,
  });
}

export async function getEncounters(): Promise<EncounterOption[]> {
  return invoke<EncounterOption[]>("get_encounters");
}

/**
 * Wipe all session data from SQLite and reset GeneratedData.lua to empty.
 * This is the Advanced settings "Purge All Data" action.  It cannot be undone.
 */
export async function purgeAllData(): Promise<void> {
  return invoke<void>("purge_all_data");
}

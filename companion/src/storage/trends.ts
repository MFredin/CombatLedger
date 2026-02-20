/**
 * storage/trends.ts — Phase 3 trend builder
 *
 * Converts parsed session data into a SessionInsert payload, persists it to
 * SQLite, then fetches trend + distribution data for the same encounter.
 * The results are returned for inclusion in the SavedVariables Lua payload.
 */

import type { EncounterSession } from "../parser/session.js";
import type { DeathRecap } from "../parser/death.js";
import type { InterruptReport } from "../parser/interrupt.js";
import type { CCCoverage } from "../parser/cc.js";
import type { PerformanceReport } from "../parser/performance.js";
import {
  storeSession,
  getTrend,
  getDistribution,
  type SessionInsert,
  type PlayerMetricInsert,
  type TrendReport,
  type DistributionReport,
} from "./sqlite.js";

const COMPANION_VERSION = "1.3.0";

// ---------------------------------------------------------------------------
// Build SessionInsert from parsed session data
// ---------------------------------------------------------------------------

export function buildSessionInsert(
  session: EncounterSession,
  deaths: DeathRecap[],
  interrupts: InterruptReport,
  ccCoverage: CCCoverage[],
  performance: PerformanceReport,
  sessionSnapshot: string,
): SessionInsert {
  const avgCcCoverage =
    ccCoverage.length > 0
      ? ccCoverage.reduce((sum, cc) => sum + cc.coveragePercent, 0) / ccCoverage.length
      : 0;

  const players: PlayerMetricInsert[] = performance.players.map((p) => ({
    player_guid: p.playerGUID,
    player_name: p.playerName,
    player_class: p.playerClass,
    player_spec: p.playerSpec,
    damage_done: p.damageDone,
    healing_done: p.healingDone,
    overhealing: p.overhealing,
    dps: Math.round(p.dps),
    hps: Math.round(p.hps),
    interrupt_count: p.interruptCount,
    death_count: p.deathCount,
    cc_applied: p.ccApplied,
  }));

  return {
    encounter_id: session.encounterId,
    encounter_name: session.encounterName,
    difficulty: session.difficulty,
    group_size: session.groupSize,
    start_time: Math.floor(session.startTime.getTime() / 1000),
    end_time: Math.floor(session.endTime.getTime() / 1000),
    duration_sec: Math.round((session.endTime.getTime() - session.startTime.getTime()) / 1000),
    success: session.success,
    pull_number: session.pullNumber,
    companion_version: COMPANION_VERSION,
    total_deaths: deaths.length,
    interrupt_total: interrupts.summary.total,
    interrupt_hit: interrupts.summary.intercepted,
    interrupt_rate_pct: interrupts.summary.ratePercent,
    total_damage_done: performance.totalDamageDone,
    total_healing_done: performance.totalHealingDone,
    cc_avg_coverage_pct: Math.round(avgCcCoverage * 10) / 10,
    players,
    session_snapshot: sessionSnapshot,
  };
}

// ---------------------------------------------------------------------------
// Persist + analyse
// ---------------------------------------------------------------------------

export interface TrendAnalysis {
  sessionDbId: number;
  trend: TrendReport;
  distribution: DistributionReport;
}

/**
 * Store the session to SQLite, then fetch trend and distribution data for the
 * same encounter.  Returns all three for inclusion in the Lua SavedVariables.
 */
export async function persistAndAnalyze(
  session: EncounterSession,
  deaths: DeathRecap[],
  interrupts: InterruptReport,
  ccCoverage: CCCoverage[],
  performance: PerformanceReport,
  sessionSnapshot: string,
): Promise<TrendAnalysis> {
  const insert = buildSessionInsert(session, deaths, interrupts, ccCoverage, performance, sessionSnapshot);
  const sessionDbId = await storeSession(insert);

  const [trend, distribution] = await Promise.all([
    getTrend(session.encounterId, session.difficulty, 30),
    getDistribution(session.encounterId, session.difficulty, sessionDbId),
  ]);

  return { sessionDbId, trend, distribution };
}

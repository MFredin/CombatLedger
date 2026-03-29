// parser/performance.ts — Per-player performance aggregation (Task 2.3)
//
// Aggregates damage done, healing done, interrupts, deaths, and CC applied
// for each player in the encounter session.
//
// Output fed into SavedVariables as session.performance[].

import type { EncounterSession } from "./session.js";
import type { InterruptReport } from "./interrupt.js";
import type { DeathRecap } from "./death.js";
import type { CCCoverage } from "./cc.js";
import type { GuidResolver } from "../enrichment/guid.js";
import {
  isPlayer,
  type SpellDamageEvent,
  type SpellHealEvent,
  type SwingDamageEvent,
  type RangeDamageEvent,
} from "./cleu.js";

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

export interface PlayerPerformance {
  playerGUID: string;
  playerName: string;
  playerClass: string;
  playerSpec: string;

  /** Total damage dealt to enemies (absorbs excluded). */
  damageDone: number;
  /** Total effective healing done to allies (overheals excluded). */
  healingDone: number;
  /** Total overhealing. */
  overhealing: number;
  /** Number of interrupts landed. */
  interruptCount: number;
  /** Number of times this player died. */
  deathCount: number;
  /** Number of CC segments this player applied. */
  ccApplied: number;

  /** Encounter duration in seconds for DPS/HPS computation. */
  encounterDurationSec: number;
  /** Damage per second = damageDone / encounterDurationSec. */
  dps: number;
  /** Heals per second = healingDone / encounterDurationSec. */
  hps: number;
}

export interface PerformanceReport {
  players: PlayerPerformance[];
  encounterDurationSec: number;
  totalDamageDone: number;
  totalHealingDone: number;
}

// ---------------------------------------------------------------------------
// Internal accumulator
// ---------------------------------------------------------------------------

interface Accumulator {
  playerGUID: string;
  playerName: string;
  playerClass: string;
  playerSpec: string;
  damageDone: number;
  healingDone: number;
  overhealing: number;
  interruptCount: number;
  deathCount: number;
  ccApplied: number;
}

function emptyAccum(guid: string, name: string, cls: string, spec: string): Accumulator {
  return {
    playerGUID: guid,
    playerName: name,
    playerClass: cls,
    playerSpec: spec,
    damageDone: 0,
    healingDone: 0,
    overhealing: 0,
    interruptCount: 0,
    deathCount: 0,
    ccApplied: 0,
  };
}

// ---------------------------------------------------------------------------
// Main export
// ---------------------------------------------------------------------------

/**
 * Builds a PerformanceReport from a parsed EncounterSession and the
 * already-computed interrupt report, death recaps, and CC coverage.
 */
export function buildPerformanceReport(
  session: EncounterSession,
  resolver: GuidResolver,
  interrupts: InterruptReport,
  deaths: DeathRecap[],
  _ccCoverage: CCCoverage[],
): PerformanceReport {
  const accums = new Map<string, Accumulator>();

  // Seed accumulators from all known players (gives data even for quiet players).
  for (const info of resolver.all()) {
    accums.set(info.guid, emptyAccum(info.guid, info.name, info.class, info.spec));
  }

  const getOrCreate = (guid: string, name: string): Accumulator => {
    if (!accums.has(guid)) {
      const info = resolver.resolve(guid);
      accums.set(
        guid,
        emptyAccum(guid, name, info?.class ?? "Unknown", info?.spec ?? "Unknown")
      );
    }
    return accums.get(guid)!;
  };

  // Build a set of known player GUIDs from COMBATANT_INFO for fallback matching.
  // If sourceFlags is zero or missing (e.g. log-format variance), we still count
  // events from GUIDs we positively identified as players via COMBATANT_INFO.
  const knownPlayerGuids = new Set(resolver.all().map((p) => p.guid));

  // ---------------------------------------------------------------------------
  // Single pass over all events — damage and heals only
  // ---------------------------------------------------------------------------
  for (const ev of session.events) {
    if (!("sourceFlags" in ev)) continue;
    const srcGuid = (ev as { sourceGUID?: string }).sourceGUID ?? "";
    if (!isPlayer(ev.sourceFlags) && !knownPlayerGuids.has(srcGuid)) continue;

    const sub = ev.subevent;

    if (sub === "SPELL_DAMAGE" || sub === "SPELL_PERIODIC_DAMAGE") {
      const e = ev as SpellDamageEvent;
      const acc = getOrCreate(e.sourceGUID, e.sourceName);
      acc.damageDone += Math.max(0, e.amount - (e.absorbed ?? 0));
    } else if (sub === "SWING_DAMAGE") {
      const e = ev as SwingDamageEvent;
      const acc = getOrCreate(e.sourceGUID, e.sourceName);
      acc.damageDone += Math.max(0, e.amount - (e.absorbed ?? 0));
    } else if (sub === "RANGE_DAMAGE") {
      const e = ev as RangeDamageEvent;
      const acc = getOrCreate(e.sourceGUID, e.sourceName);
      acc.damageDone += Math.max(0, e.amount - (e.absorbed ?? 0));
    } else if (sub === "SPELL_HEAL" || sub === "SPELL_PERIODIC_HEAL") {
      const e = ev as SpellHealEvent;
      const acc = getOrCreate(e.sourceGUID, e.sourceName);
      const overh = e.overheal ?? 0;
      acc.healingDone += Math.max(0, e.amount - overh);
      acc.overhealing += overh;
    }
  }

  // ---------------------------------------------------------------------------
  // Merge interrupt counts from already-built InterruptReport
  // byPlayer is now keyed by GUID — O(1) lookup instead of O(n) name scan.
  // ---------------------------------------------------------------------------
  for (const [guid, pdata] of Object.entries(interrupts.byPlayer ?? {})) {
    const acc = accums.get(guid);
    if (acc) acc.interruptCount += pdata.intercepted ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Merge death counts
  // ---------------------------------------------------------------------------
  for (const death of deaths) {
    const acc = accums.get(death.playerGUID);
    if (acc) acc.deathCount += 1;
  }

  // ---------------------------------------------------------------------------
  // Count CC applied per player — CCSegment.sourceGUID allows O(1) lookup.
  // ---------------------------------------------------------------------------
  for (const target of _ccCoverage) {
    for (const seg of target.segments) {
      if (!seg.sourceGUID) continue;
      const acc = accums.get(seg.sourceGUID);
      if (acc && !seg.wasImmune) acc.ccApplied++;
    }
  }

  // ---------------------------------------------------------------------------
  // Compute duration and DPS/HPS
  // ---------------------------------------------------------------------------
  const durationMs =
    session.endTime && session.startTime
      ? session.endTime.getTime() - session.startTime.getTime()
      : 0;
  const durationSec = durationMs / 1000;
  const safeDur = durationSec > 0 ? durationSec : 1;

  const players: PlayerPerformance[] = [];
  let totalDamage = 0;
  let totalHealing = 0;

  for (const [, acc] of accums) {
    totalDamage += acc.damageDone;
    totalHealing += acc.healingDone;

    players.push({
      playerGUID: acc.playerGUID,
      playerName: acc.playerName,
      playerClass: acc.playerClass,
      playerSpec: acc.playerSpec,
      damageDone: acc.damageDone,
      healingDone: acc.healingDone,
      overhealing: acc.overhealing,
      interruptCount: acc.interruptCount,
      deathCount: acc.deathCount,
      ccApplied: acc.ccApplied,
      encounterDurationSec: durationSec,
      dps: acc.damageDone / safeDur,
      hps: acc.healingDone / safeDur,
    });
  }

  // Sort by damage done desc, then healing desc
  players.sort((a, b) => {
    if (b.damageDone !== a.damageDone) return b.damageDone - a.damageDone;
    return b.healingDone - a.healingDone;
  });

  return {
    players,
    encounterDurationSec: durationSec,
    totalDamageDone: totalDamage,
    totalHealingDone: totalHealing,
  };
}

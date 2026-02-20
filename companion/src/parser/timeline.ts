/**
 * timeline.ts — Boss ability timeline builder
 *
 * Builds a chronological list of boss ability casts with pre-computed
 * per-player impact data so the Timeline addon tab can display interval
 * breakdowns (Damage dealt, taken, deaths, CDs used) without needing
 * raw event access in the addon.
 *
 * Importance tiers:
 *   "high"   — cast killed at least one player, OR is in top-damage bracket
 *   "medium" — cast landed significant damage on players
 *   "low"    — cosmetic / untargeted / trivial casts
 */

import type { EncounterSession } from "./session.js";
import type { DeathRecap } from "./death.js";
import type { GuidResolver } from "../enrichment/guid.js";
import type {
  SpellCastSuccessEvent,
  SpellDamageEvent,
} from "./cleu.js";
import { isEnemy, isPlayer } from "./cleu.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** How far after a boss cast we look for damage events from that same spell. */
const IMPACT_WINDOW_MS = 5_000;

/** How far after a boss cast a player death counts as "linked" to that cast. */
const DEATH_LINK_MS = 10_000;

/** Boss-sourced spells that appear constantly and add no analytical value. */
const EXCLUDE_SPELL_IDS = new Set<number>([
  // add known noise spell IDs here as they're discovered
]);

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

export interface TimelinePlayerImpact {
  playerGUID: string;
  playerName: string;
  playerClass: string;
  /** Damage received from this specific boss spell within IMPACT_WINDOW_MS. */
  damageTaken: number;
  /** Whether this player died within DEATH_LINK_MS after this cast. */
  died: boolean;
}

export interface BossAbilityCast {
  /** Seconds into the pull when this cast completed. */
  timeIntoPull: number;
  spellId: number;
  spellName: string;
  casterName: string;
  casterGUID: string;
  /**
   * Importance tier used by the ALL / IMPORTANT / TRIVIAL filter in the addon.
   *   "high"   — killed someone or was a top-damage cast
   *   "medium" — damaged players
   *   "low"    — no measurable player impact
   */
  importance: "high" | "medium" | "low";
  /** Sum of damage across all affected players from this cast. */
  totalDamageTaken: number;
  /** Names of players who died within DEATH_LINK_MS after this cast. */
  deathsLinked: string[];
  /** Per-player breakdown, sorted damage-desc. */
  impacts: TimelinePlayerImpact[];
  /** 1-based index into BossTimeline.phases. 0 if no phases were detected. */
  phaseIndex: number;
}

/** A contiguous segment of the boss encounter, separated by boss-casting gaps. */
export interface BossPhase {
  /** 1-based position in the phase sequence (Phase 1 = 1, Intermission = 2, Phase 2 = 3, …). */
  index: number;
  /** Human-readable label, e.g. "Phase 1", "Intermission", "Phase 2". */
  phaseName: string;
  /** Seconds into the pull where this phase begins. */
  startSec: number;
  /** Seconds into the pull where this phase ends. */
  endSec: number;
  /** True for gap segments (boss stopped casting for >= threshold). */
  isIntermission: boolean;
}

export interface BossTimeline {
  pullDurationSec: number;
  /** Phase segments detected from casting gaps. Empty when the fight has no distinct phases. */
  phases: BossPhase[];
  events: BossAbilityCast[];
}

// ---------------------------------------------------------------------------
// Phase detection
// ---------------------------------------------------------------------------

/** Minimum gap (seconds) in the dominant boss caster's spell stream to be
 *  treated as a phase boundary / intermission. */
const PHASE_GAP_SEC = 20;

/** Minimum events needed from the dominant caster before phase detection runs. */
const PHASE_MIN_EVENTS = 8;

/**
 * Detect boss-encounter phases by looking for sustained gaps in the dominant
 * enemy caster's SPELL_CAST_SUCCESS stream.  Returns an empty array when the
 * fight appears to be a single continuous phase.
 */
function detectPhases(events: BossAbilityCast[], totalDurationSec: number): BossPhase[] {
  if (events.length < PHASE_MIN_EVENTS) return [];

  // ── Find the dominant caster (highest event count). ─────────────────────
  const casterCount = new Map<string, number>();
  for (const ev of events) {
    casterCount.set(ev.casterGUID, (casterCount.get(ev.casterGUID) ?? 0) + 1);
  }
  let dominantGUID = "";
  let maxCount = 0;
  for (const [guid, count] of casterCount) {
    if (count > maxCount) { maxCount = count; dominantGUID = guid; }
  }

  // Only dominant caster's events, already in chronological order.
  const bossEvents = events.filter((e) => e.casterGUID === dominantGUID);
  if (bossEvents.length < PHASE_MIN_EVENTS) return [];

  // ── Scan for gaps ≥ PHASE_GAP_SEC in that caster's stream. ──────────────
  const gaps: { start: number; end: number }[] = [];
  for (let i = 1; i < bossEvents.length; i++) {
    const gap = bossEvents[i]!.timeIntoPull - bossEvents[i - 1]!.timeIntoPull;
    if (gap >= PHASE_GAP_SEC) {
      gaps.push({ start: bossEvents[i - 1]!.timeIntoPull, end: bossEvents[i]!.timeIntoPull });
    }
  }
  if (gaps.length === 0) return [];   // single continuous phase

  // ── Build phase list: active → intermission → active → … ────────────────
  const phases: BossPhase[] = [];
  let phaseNum = 1;
  let prevEnd = 0;
  const multiGap = gaps.length > 1;

  for (let gi = 0; gi < gaps.length; gi++) {
    const gap = gaps[gi]!;
    // Active phase leading up to the gap.
    phases.push({
      index: phases.length + 1,
      phaseName: `Phase ${phaseNum++}`,
      startSec: prevEnd,
      endSec: gap.start,
      isIntermission: false,
    });
    // The gap itself = intermission.
    phases.push({
      index: phases.length + 1,
      phaseName: multiGap ? `Intermission ${gi + 1}` : "Intermission",
      startSec: gap.start,
      endSec: gap.end,
      isIntermission: true,
    });
    prevEnd = gap.end;
  }
  // Final active phase after the last gap.
  phases.push({
    index: phases.length + 1,
    phaseName: `Phase ${phaseNum}`,
    startSec: prevEnd,
    endSec: totalDurationSec,
    isIntermission: false,
  });

  return phases;
}

/** Assign phaseIndex to every event based on detected phases. */
function tagEventPhases(events: BossAbilityCast[], phases: BossPhase[]): void {
  for (const ev of events) {
    if (phases.length === 0) {
      ev.phaseIndex = 0;
      continue;
    }
    let assigned = false;
    for (const phase of phases) {
      if (ev.timeIntoPull >= phase.startSec && ev.timeIntoPull <= phase.endSec) {
        ev.phaseIndex = phase.index;
        assigned = true;
        break;
      }
    }
    if (!assigned) {
      ev.phaseIndex = phases[phases.length - 1]!.index;
    }
  }
}

// ---------------------------------------------------------------------------
// Main export
// ---------------------------------------------------------------------------

export function buildBossTimeline(
  session: EncounterSession,
  deaths: DeathRecap[],
  resolver: GuidResolver,
): BossTimeline {
  const startMs = session.startTime.getTime();
  const durationMs = session.endTime.getTime() - startMs;

  // ------------------------------------------------------------------
  // Pre-index: player-targeting spell damage events for fast windowing
  // ------------------------------------------------------------------
  interface DmgEntry {
    ts: number;
    spellId: number;
    destGUID: string;
    destName: string;
    destClass: string;
    amount: number;
  }
  const dmgEntries: DmgEntry[] = [];
  for (const ev of session.events) {
    if (ev.subevent !== "SPELL_DAMAGE" && ev.subevent !== "SPELL_PERIODIC_DAMAGE") continue;
    if (!isPlayer(ev.destFlags)) continue;
    if (!isEnemy(ev.sourceFlags)) continue;
    const d = ev as SpellDamageEvent;
    const info = resolver.resolve(d.destGUID);
    dmgEntries.push({
      ts: d.timestamp.getTime(),
      spellId: d.spellId,
      destGUID: d.destGUID,
      destName: d.destName,
      destClass: info?.class ?? "UNKNOWN",
      amount: Math.max(0, d.amount - (d.absorbed ?? 0)),
    });
  }
  // Already sorted chronologically as events are.

  // ------------------------------------------------------------------
  // Collect all enemy SPELL_CAST_SUCCESS events
  // ------------------------------------------------------------------
  const results: BossAbilityCast[] = [];

  for (const ev of session.events) {
    if (ev.subevent !== "SPELL_CAST_SUCCESS") continue;
    if (!isEnemy(ev.sourceFlags)) continue;

    const cast = ev as SpellCastSuccessEvent;
    if (EXCLUDE_SPELL_IDS.has(cast.spellId)) continue;

    const castMs = cast.timestamp.getTime();
    const timeIntoPull = Math.max(0, (castMs - startMs) / 1000);

    // Deaths linked: died within DEATH_LINK_MS after this cast
    const deathsLinked: string[] = [];
    for (const d of deaths) {
      const deathMs = d.deathTimestamp.getTime();
      if (deathMs >= castMs && deathMs <= castMs + DEATH_LINK_MS) {
        deathsLinked.push(d.playerName);
      }
    }

    // Damage correlation: same spellId landing on players in the impact window
    const perPlayer = new Map<string, { name: string; cls: string; dmg: number }>();
    for (const dmg of dmgEntries) {
      if (dmg.ts < castMs) continue;
      if (dmg.ts > castMs + IMPACT_WINDOW_MS) break; // entries are sorted
      if (dmg.spellId !== cast.spellId) continue;
      const existing = perPlayer.get(dmg.destGUID);
      if (existing) {
        existing.dmg += dmg.amount;
      } else {
        perPlayer.set(dmg.destGUID, { name: dmg.destName, cls: dmg.destClass, dmg: dmg.amount });
      }
    }

    const impacts: TimelinePlayerImpact[] = [];
    let totalDmg = 0;
    for (const [guid, data] of perPlayer) {
      const died = deaths.some(
        (d) =>
          d.playerGUID === guid &&
          d.deathTimestamp.getTime() >= castMs &&
          d.deathTimestamp.getTime() <= castMs + DEATH_LINK_MS,
      );
      impacts.push({
        playerGUID: guid,
        playerName: data.name,
        playerClass: data.cls,
        damageTaken: data.dmg,
        died,
      });
      totalDmg += data.dmg;
    }
    impacts.sort((a, b) => b.damageTaken - a.damageTaken);

    // Initial importance based on deaths
    const importance: "high" | "medium" | "low" =
      deathsLinked.length > 0 ? "high" : totalDmg > 0 ? "medium" : "low";

    results.push({
      timeIntoPull,
      spellId: cast.spellId,
      spellName: cast.spellName,
      casterName: cast.sourceName,
      casterGUID: cast.sourceGUID,
      importance,
      totalDamageTaken: totalDmg,
      deathsLinked,
      impacts,
      phaseIndex: 0,   // filled in below
    });
  }

  // Sort chronologically
  results.sort((a, b) => a.timeIntoPull - b.timeIntoPull);

  // ------------------------------------------------------------------
  // Post-pass: promote high-damage "medium" events to "high"
  // Events in the top 10% of total damage taken are promoted.
  // ------------------------------------------------------------------
  const damagedEvents = results.filter((e) => e.totalDamageTaken > 0);
  if (damagedEvents.length >= 5) {
    const sorted = [...damagedEvents].sort((a, b) => b.totalDamageTaken - a.totalDamageTaken);
    const topN = Math.max(1, Math.ceil(sorted.length * 0.1));
    const threshold = sorted[topN - 1]!.totalDamageTaken;
    for (const e of results) {
      if (e.importance === "medium" && e.totalDamageTaken >= threshold) {
        e.importance = "high";
      }
    }
  }

  // ------------------------------------------------------------------
  // Phase detection: find sustained casting gaps from the dominant boss
  // ------------------------------------------------------------------
  const pullDurationSec = Math.round(durationMs / 1000);
  const phases = detectPhases(results, pullDurationSec);
  tagEventPhases(results, phases);

  return {
    pullDurationSec,
    phases,
    events: results,
  };
}

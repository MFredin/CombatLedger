/**
 * cc.ts — CC Coverage Engine with DR Tracking (Task 2.1)
 *
 * Architecture designed by Opus 4.6.
 * Processes SPELL_AURA_APPLIED/REFRESH/REMOVED events to build per-target
 * CC coverage timelines with full Diminishing Returns state tracking.
 */

import type { EncounterSession } from "./session.js";
import type {
  ParsedEvent,
  SpellAuraAppliedEvent,
  SpellAuraRemovedEvent,
} from "./cleu.js";
import { isEnemy, UNIT_FLAGS } from "./cleu.js";
import {
  getPlayerSpell,
  getDrCategoryForSpell,
} from "../enrichment/spelldb.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DR_RESET_MS = 18_000;
const EARLY_BREAK_TOLERANCE_SEC = 0.5;
const DAMAGE_BREAK_WINDOW_MS = 200;

/** DR multiplier indexed by application count (index 0 unused, 1=first, 2=second...). */
const DR_MULTIPLIERS: readonly number[] = [1.0, 1.0, 0.5, 0.25, 0.0];

function getDrMultiplier(applicationCount: number): number {
  if (applicationCount <= 0) return 1.0;
  if (applicationCount >= DR_MULTIPLIERS.length) return 0.0;
  return DR_MULTIPLIERS[applicationCount] ?? 0.0;
}

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

export interface CCSegment {
  sourceGUID: string;
  sourceName: string;
  spellId: number;
  spellName: string;
  ccCategory: string;
  startTime: Date;
  endTime: Date;
  theoreticalDuration: number;
  actualDuration: number;
  drMultiplier: number;
  drApplicationNumber: number;
  brokeEarly: boolean;
  brokeReason?: string;
  wasImmune: boolean;
}

export interface DrStateSnapshot {
  timestamp: Date;
  category: string;
  applicationCount: number;
  drMultiplier: number;
  resetTime: Date;
  didReset: boolean;
}

export interface CCCoverage {
  targetGUID: string;
  targetName: string;
  targetType: string;
  segments: CCSegment[];
  totalCombatDuration: number;
  coveredDuration: number;
  coveragePercent: number;
  wastedCasts: number;
  drHistory: DrStateSnapshot[];
  byCategory: Record<string, { coveredDuration: number; segments: number; wastedCasts: number }>;
}

// ---------------------------------------------------------------------------
// Internal state types
// ---------------------------------------------------------------------------

interface DrTracker {
  applicationCount: number;
  lastCcEndTime: Date | null;
}

interface OpenSegment {
  sourceGUID: string;
  sourceName: string;
  spellId: number;
  spellName: string;
  ccCategory: string;
  startTime: Date;
  baseDurationSec: number;
  drMultiplier: number;
  drApplicationNumber: number;
  breakOnDamage: boolean;
}

interface TargetState {
  targetGUID: string;
  targetName: string;
  targetFlags: number;
  drState: Map<string, DrTracker>;
  openSegments: Map<number, OpenSegment>;
  closedSegments: CCSegment[];
  drHistory: DrStateSnapshot[];
  firstEventTime: Date | null;
  lastEventTime: Date | null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getTargetType(flags: number): string {
  if (flags & UNIT_FLAGS.TYPE_PLAYER) return "Player";
  if (flags & UNIT_FLAGS.TYPE_NPC) return "NPC";
  if (flags & UNIT_FLAGS.TYPE_PET) return "Pet";
  if (flags & UNIT_FLAGS.TYPE_GUARDIAN) return "Guardian";
  return "Unknown";
}

/** Merge overlapping time intervals and return total covered seconds. */
function mergeIntervalsSec(intervals: Array<[number, number]>): number {
  if (intervals.length === 0) return 0;
  const sorted = [...intervals].sort((a, b) => a[0] - b[0]);
  let total = 0;
  let curStart = sorted[0]![0];
  let curEnd = sorted[0]![1];
  for (let i = 1; i < sorted.length; i++) {
    const [s, e] = sorted[i]!;
    if (s <= curEnd) {
      curEnd = Math.max(curEnd, e);
    } else {
      total += curEnd - curStart;
      curStart = s;
      curEnd = e;
    }
  }
  total += curEnd - curStart;
  return total / 1000; // ms → seconds
}

/** Determine break reason by scanning damage events near the removal time. */
function detectBreakReason(
  targetGUID: string,
  removeTimeMs: number,
  events: ParsedEvent[]
): string {
  for (const e of events) {
    const ts = e.timestamp.getTime();
    if (ts > removeTimeMs) break;
    if (removeTimeMs - ts > DAMAGE_BREAK_WINDOW_MS) continue;
    if (!("destGUID" in e) || e.destGUID !== targetGUID) continue;
    const sub = e.subevent;
    if (
      sub === "SPELL_DAMAGE" ||
      sub === "SPELL_PERIODIC_DAMAGE" ||
      sub === "SWING_DAMAGE" ||
      sub === "RANGE_DAMAGE"
    ) {
      return "damage";
    }
  }
  return "spell";
}

/** Close an open segment, producing a CCSegment. */
function closeSegment(
  open: OpenSegment,
  targetGUID: string,
  endTime: Date,
  events: ParsedEvent[],
  isOrphan = false
): CCSegment {
  const theoreticalDuration = open.baseDurationSec * open.drMultiplier;
  const actualDuration = (endTime.getTime() - open.startTime.getTime()) / 1000;
  const brokeEarly =
    !isOrphan &&
    open.drMultiplier > 0 &&
    actualDuration < theoreticalDuration - EARLY_BREAK_TOLERANCE_SEC;

  let brokeReason: string | undefined;
  if (brokeEarly) {
    brokeReason = detectBreakReason(targetGUID, endTime.getTime(), events);
  }

  return {
    sourceGUID: open.sourceGUID,
    sourceName: open.sourceName,
    spellId: open.spellId,
    spellName: open.spellName,
    ccCategory: open.ccCategory,
    startTime: open.startTime,
    endTime,
    theoreticalDuration,
    actualDuration,
    drMultiplier: open.drMultiplier,
    drApplicationNumber: open.drApplicationNumber,
    brokeEarly,
    ...(brokeReason !== undefined ? { brokeReason } : {}),
    wasImmune: open.drMultiplier === 0.0,
  };
}

// ---------------------------------------------------------------------------
// Main engine
// ---------------------------------------------------------------------------

export function buildCCCoverage(session: EncounterSession): CCCoverage[] {
  const targetStates = new Map<string, TargetState>();

  function getOrCreateTarget(
    guid: string,
    name: string,
    flags: number
  ): TargetState {
    let state = targetStates.get(guid);
    if (!state) {
      state = {
        targetGUID: guid,
        targetName: name,
        targetFlags: flags,
        drState: new Map(),
        openSegments: new Map(),
        closedSegments: [],
        drHistory: [],
        firstEventTime: null,
        lastEventTime: null,
      };
      targetStates.set(guid, state);
    }
    return state;
  }

  function getOrCreateDrTracker(state: TargetState, category: string): DrTracker {
    let tracker = state.drState.get(category);
    if (!tracker) {
      tracker = { applicationCount: 0, lastCcEndTime: null };
      state.drState.set(category, tracker);
    }
    return tracker;
  }

  // -------------------------------------------------------------------------
  // Phase 1: single-pass event processing
  // -------------------------------------------------------------------------

  for (const event of session.events) {
    const ts = event.timestamp;

    // Track first/last event times for enemy targets (combat duration).
    if ("destGUID" in event && event.destGUID && isEnemy(event.destFlags ?? 0)) {
      const tgt = targetStates.get(event.destGUID);
      if (tgt) {
        if (!tgt.firstEventTime || ts < tgt.firstEventTime) tgt.firstEventTime = ts;
        if (!tgt.lastEventTime || ts > tgt.lastEventTime) tgt.lastEventTime = ts;
      }
    }

    const sub = event.subevent;

    // Only process aura events.
    if (
      sub !== "SPELL_AURA_APPLIED" &&
      sub !== "SPELL_AURA_REFRESH" &&
      sub !== "SPELL_AURA_REMOVED"
    ) {
      continue;
    }

    const auraEv = event as SpellAuraAppliedEvent | SpellAuraRemovedEvent;

    // Only process DEBUFFs on enemy targets.
    if (auraEv.auraType !== "DEBUFF") continue;
    if (!isEnemy(auraEv.destFlags)) continue;

    const spellId = auraEv.spellId;
    const category = getDrCategoryForSpell(spellId);
    if (!category) continue;

    const spellMeta = getPlayerSpell(spellId);
    if (!spellMeta || spellMeta.type !== "cc") continue;

    const targetGUID = auraEv.destGUID;
    const targetName = auraEv.destName;
    const targetFlags = auraEv.destFlags;

    if (sub === "SPELL_AURA_APPLIED" || sub === "SPELL_AURA_REFRESH") {
      const state = getOrCreateTarget(targetGUID, targetName, targetFlags);

      // Update combat duration tracking.
      if (!state.firstEventTime || ts < state.firstEventTime) state.firstEventTime = ts;
      if (!state.lastEventTime || ts > state.lastEventTime) state.lastEventTime = ts;

      const tracker = getOrCreateDrTracker(state, category);

      // Check DR reset.
      let didReset = false;
      if (
        tracker.lastCcEndTime !== null &&
        ts.getTime() - tracker.lastCcEndTime.getTime() >= DR_RESET_MS
      ) {
        tracker.applicationCount = 0;
        didReset = true;
      }

      // For REFRESH, close existing open segment first.
      const existingOpen = state.openSegments.get(spellId);
      if (existingOpen) {
        const closed = closeSegment(existingOpen, targetGUID, ts, session.events);
        state.closedSegments.push(closed);
        state.openSegments.delete(spellId);
        // DR end time updated below via tracker.lastCcEndTime only on REMOVED.
        // For REFRESH the CC is still active — DR resets are not possible (< 18s since last end).
      }

      tracker.applicationCount++;
      const drMultiplier = getDrMultiplier(tracker.applicationCount);

      // Record DR snapshot.
      const resetTime = new Date(ts.getTime() + DR_RESET_MS);
      state.drHistory.push({
        timestamp: ts,
        category,
        applicationCount: tracker.applicationCount,
        drMultiplier,
        resetTime,
        didReset,
      });

      // Open new segment.
      state.openSegments.set(spellId, {
        sourceGUID: auraEv.sourceGUID,
        sourceName: auraEv.sourceName,
        spellId,
        spellName: auraEv.spellName,
        ccCategory: category,
        startTime: ts,
        baseDurationSec: spellMeta.durationSec ?? 0,
        drMultiplier,
        drApplicationNumber: tracker.applicationCount,
        breakOnDamage: spellMeta.breakOnDamage ?? false,
      });
    }

    if (sub === "SPELL_AURA_REMOVED") {
      const state = targetStates.get(targetGUID);
      if (!state) continue;

      const open = state.openSegments.get(spellId);
      if (!open) continue; // orphan REMOVED — skip

      // Update combat duration tracking.
      if (!state.lastEventTime || ts > state.lastEventTime) state.lastEventTime = ts;

      const closed = closeSegment(open, targetGUID, ts, session.events);
      state.closedSegments.push(closed);
      state.openSegments.delete(spellId);

      // Update DR end time.
      const tracker = getOrCreateDrTracker(state, category);
      tracker.lastCcEndTime = ts;
    }
  }

  // -------------------------------------------------------------------------
  // Phase 2: close orphan segments (encounter ended while CC still active)
  // -------------------------------------------------------------------------

  for (const state of targetStates.values()) {
    for (const [spellId, open] of state.openSegments) {
      const closed = closeSegment(open, state.targetGUID, session.endTime, session.events, true);
      state.closedSegments.push(closed);
    }
    state.openSegments.clear();
  }

  // -------------------------------------------------------------------------
  // Phase 3: compute coverage metrics and build output
  // -------------------------------------------------------------------------

  const results: CCCoverage[] = [];

  for (const state of targetStates.values()) {
    if (state.closedSegments.length === 0) continue;

    // Sort segments chronologically.
    state.closedSegments.sort((a, b) => a.startTime.getTime() - b.startTime.getTime());

    // Total combat duration.
    const firstTs = state.firstEventTime ?? session.startTime;
    const lastTs = state.lastEventTime ?? session.endTime;
    const totalCombatDuration = Math.max(
      0.001,
      (lastTs.getTime() - firstTs.getTime()) / 1000
    );

    // Covered duration: merge overlapping non-immune intervals.
    const intervals: Array<[number, number]> = state.closedSegments
      .filter((s) => s.drMultiplier > 0)
      .map((s) => [s.startTime.getTime(), s.endTime.getTime()]);
    const coveredDuration = mergeIntervalsSec(intervals);

    const coveragePercent = Math.min(
      100,
      Math.round((coveredDuration / totalCombatDuration) * 1000) / 10
    );

    const wastedCasts = state.closedSegments.filter((s) => s.wasImmune).length;

    // Per-category breakdown.
    const byCategory: Record<string, { coveredDuration: number; segments: number; wastedCasts: number }> = {};
    for (const seg of state.closedSegments) {
      const cat = seg.ccCategory;
      const entry = byCategory[cat] ?? { coveredDuration: 0, segments: 0, wastedCasts: 0 };
      entry.segments++;
      if (seg.wasImmune) {
        entry.wastedCasts++;
      } else {
        entry.coveredDuration += seg.actualDuration;
      }
      byCategory[cat] = entry;
    }

    results.push({
      targetGUID: state.targetGUID,
      targetName: state.targetName,
      targetType: getTargetType(state.targetFlags),
      segments: state.closedSegments,
      totalCombatDuration,
      coveredDuration,
      coveragePercent,
      wastedCasts,
      drHistory: state.drHistory,
      byCategory,
    });
  }

  return results.sort((a, b) => a.targetName.localeCompare(b.targetName));
}

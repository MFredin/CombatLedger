/**
 * interrupt.ts — Interrupt report engine (Task 1.7)
 *
 * Identifies all interruptible enemy casts, correlates SPELL_INTERRUPT events,
 * and flags missed casts.
 */

import type { EncounterSession } from "./session.js";
import type {
  ParsedEvent,
  SpellCastStartEvent,
  SpellCastSuccessEvent,
  SpellInterruptEvent,
} from "./cleu.js";
import { isEnemy, isPlayer } from "./cleu.js";
import { getEnemySpell } from "../enrichment/spelldb.js";

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

export interface InterruptEvent {
  timestamp: Date;
  pullNumber: number;
  targetName: string;
  targetGUID: string;
  spellId: number;
  spellName: string;
  castDurationMs: number;
  wasInterrupted: boolean;
  interruptedBy?: string;
  interruptSpellId?: number;
  castPercentAtInterrupt?: number; // 0-100
  missedReason?: string;
}

export interface InterruptReport {
  encounterId: number;
  interrupts: InterruptEvent[];
  summary: {
    total: number;
    intercepted: number;
    missed: number;
    ratePercent: number;
  };
  byPlayer: Record<
    string,
    {
      playerName: string;
      intercepted: number;
      opportunities: number;
    }
  >;
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

/** Derive the dungeon key from encounter name (lowercase, hyphens). */
function dungeonKey(encounterName: string): string {
  return encounterName.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
}

export function buildInterruptReport(session: EncounterSession): InterruptReport {
  const dungeon = dungeonKey(session.encounterName);
  const events = session.events;

  // Collect all cast-starts from enemies for interruptible spells.
  interface PendingCast {
    castStart: SpellCastStartEvent;
    startMs: number;
  }
  const pendingCasts: PendingCast[] = [];
  const completedInterrupts: InterruptEvent[] = [];
  const byPlayer: Record<string, { playerName: string; intercepted: number; opportunities: number }> = {};

  for (const e of events) {
    // Track enemy cast starts.
    if (e.subevent === "SPELL_CAST_START" && isEnemy((e as SpellCastStartEvent).sourceFlags)) {
      const cast = e as SpellCastStartEvent;
      const meta = getEnemySpell(dungeon, cast.spellId);
      if (meta?.interruptible) {
        pendingCasts.push({ castStart: cast, startMs: cast.timestamp.getTime() });
      }
    }

    // Match SPELL_INTERRUPT to pending casts.
    if (e.subevent === "SPELL_INTERRUPT") {
      const interrupt = e as SpellInterruptEvent;
      const pendingIdx = pendingCasts.findIndex(
        (p) =>
          p.castStart.sourceGUID === interrupt.destGUID &&
          p.castStart.spellId === interrupt.extraSpellId
      );
      if (pendingIdx !== -1) {
        const pending = pendingCasts.splice(pendingIdx, 1)[0]!;
        const meta = getEnemySpell(dungeon, pending.castStart.spellId);
        const castDurationMs = (meta?.castDurationSec ?? 0) * 1000;
        const elapsedMs = interrupt.timestamp.getTime() - pending.startMs;
        const castPct = castDurationMs > 0 ? Math.min(100, (elapsedMs / castDurationMs) * 100) : 0;

        // Track per-player interrupt.
        const pName = interrupt.sourceName;
        if (!byPlayer[pName]) {
          byPlayer[pName] = { playerName: pName, intercepted: 0, opportunities: 0 };
        }
        byPlayer[pName].intercepted++;

        completedInterrupts.push({
          timestamp: interrupt.timestamp,
          pullNumber: session.pullNumber,
          targetName: pending.castStart.sourceName,
          targetGUID: pending.castStart.sourceGUID,
          spellId: pending.castStart.spellId,
          spellName: pending.castStart.spellName,
          castDurationMs,
          wasInterrupted: true,
          interruptedBy: pName,
          interruptSpellId: interrupt.spellId,
          castPercentAtInterrupt: Math.round(castPct),
        });
      }
    }

    // Mark cast completions (SPELL_CAST_SUCCESS) for pending interruptible casts.
    if (e.subevent === "SPELL_CAST_SUCCESS" && isEnemy((e as SpellCastSuccessEvent).sourceFlags)) {
      const success = e as SpellCastSuccessEvent;
      const pendingIdx = pendingCasts.findIndex(
        (p) =>
          p.castStart.sourceGUID === success.sourceGUID &&
          p.castStart.spellId === success.spellId
      );
      if (pendingIdx !== -1) {
        const pending = pendingCasts.splice(pendingIdx, 1)[0]!;
        const meta = getEnemySpell(dungeon, pending.castStart.spellId);
        const castDurationMs = (meta?.castDurationSec ?? 0) * 1000;

        completedInterrupts.push({
          timestamp: success.timestamp,
          pullNumber: session.pullNumber,
          targetName: pending.castStart.sourceName,
          targetGUID: pending.castStart.sourceGUID,
          spellId: pending.castStart.spellId,
          spellName: pending.castStart.spellName,
          castDurationMs,
          wasInterrupted: false,
          missedReason: "cast completed",
        });
      }
    }
  }

  // Any remaining pending casts were never completed or interrupted (wipe mid-cast).
  for (const pending of pendingCasts) {
    const meta = getEnemySpell(dungeon, pending.castStart.spellId);
    completedInterrupts.push({
      timestamp: pending.castStart.timestamp,
      pullNumber: session.pullNumber,
      targetName: pending.castStart.sourceName,
      targetGUID: pending.castStart.sourceGUID,
      spellId: pending.castStart.spellId,
      spellName: pending.castStart.spellName,
      castDurationMs: (meta?.castDurationSec ?? 0) * 1000,
      wasInterrupted: false,
      missedReason: "no interrupter",
    });
  }

  completedInterrupts.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

  const intercepted = completedInterrupts.filter((i) => i.wasInterrupted).length;
  const total = completedInterrupts.length;

  return {
    encounterId: session.encounterId,
    interrupts: completedInterrupts,
    summary: {
      total,
      intercepted,
      missed: total - intercepted,
      ratePercent: total > 0 ? Math.round((intercepted / total) * 100) : 100,
    },
    byPlayer,
  };
}

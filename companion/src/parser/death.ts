/**
 * death.ts — Death recap engine (Task 1.6)
 *
 * For each UNIT_DIED event targeting a player, builds a DeathRecap:
 *  - Last 10 seconds of damage + heal events
 *  - Fatal event identification
 *  - Running HP estimate
 *  - Defensive availability audit
 */

import type { EncounterSession } from "./session.js";
import type {
  ParsedEvent,
  SpellDamageEvent,
  SwingDamageEvent,
  RangeDamageEvent,
  SpellHealEvent,
  SpellCastSuccessEvent,
  UnitDiedEvent,
} from "./cleu.js";
import { isPlayer } from "./cleu.js";
import { getDefensives } from "../enrichment/spelldb.js";
import type { GuidResolver } from "../enrichment/guid.js";

const DEATH_LOOKBACK_MS = 10_000;
const DEFENSIVE_LOOKBACK_MS = 30_000;

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

export interface DeathEvent {
  timestamp: Date;
  type: "damage" | "heal";
  sourceGUID: string;
  sourceName: string;
  spellId: number;
  spellName: string;
  amount: number;
  isFatal: boolean;
  estimatedHpAfter: number; // percentage 0-100
}

export interface DefensiveStatus {
  spellId: number;
  spellName: string;
  wasUsed: boolean;
  usedAt?: Date;
  available: boolean;
}

export interface DeathRecap {
  playerGUID: string;
  playerName: string;
  playerClass: string;
  playerSpec: string;
  deathTimestamp: Date;
  pullNumber: number;
  timeIntoPull: number; // seconds since ENCOUNTER_START
  fatalSpellId: number;
  fatalSpellName: string;
  fatalSourceName: string;
  overkill: number;
  events: DeathEvent[];
  availableDefensives: DefensiveStatus[];
}

// ---------------------------------------------------------------------------
// Helper: extract damage/heal amount + spell info from various event types
// ---------------------------------------------------------------------------

interface DmgHealInfo {
  type: "damage" | "heal";
  amount: number;
  overkill: number;
  spellId: number;
  spellName: string;
  sourceGUID: string;
  sourceName: string;
}

function extractDmgHeal(e: ParsedEvent): DmgHealInfo | null {
  switch (e.subevent) {
    case "SPELL_DAMAGE":
    case "SPELL_PERIODIC_DAMAGE": {
      const ev = e as SpellDamageEvent;
      return {
        type: "damage",
        amount: ev.amount,
        overkill: ev.overkill,
        spellId: ev.spellId,
        spellName: ev.spellName,
        sourceGUID: ev.sourceGUID,
        sourceName: ev.sourceName,
      };
    }
    case "SWING_DAMAGE": {
      const ev = e as SwingDamageEvent;
      return {
        type: "damage",
        amount: ev.amount,
        overkill: ev.overkill,
        spellId: 0,
        spellName: "Melee",
        sourceGUID: ev.sourceGUID,
        sourceName: ev.sourceName,
      };
    }
    case "RANGE_DAMAGE": {
      const ev = e as RangeDamageEvent;
      return {
        type: "damage",
        amount: ev.amount,
        overkill: ev.overkill,
        spellId: ev.spellId,
        spellName: ev.spellName,
        sourceGUID: ev.sourceGUID,
        sourceName: ev.sourceName,
      };
    }
    case "SPELL_HEAL":
    case "SPELL_PERIODIC_HEAL": {
      const ev = e as SpellHealEvent;
      return {
        type: "heal",
        amount: ev.amount,
        overkill: 0,
        spellId: ev.spellId,
        spellName: ev.spellName,
        sourceGUID: ev.sourceGUID,
        sourceName: ev.sourceName,
      };
    }
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Main engine
// ---------------------------------------------------------------------------

export function buildDeathRecaps(
  session: EncounterSession,
  resolver: GuidResolver
): DeathRecap[] {
  const recaps: DeathRecap[] = [];

  for (const event of session.events) {
    if (event.subevent !== "UNIT_DIED") continue;
    const diedEvent = event as UnitDiedEvent;
    if (!isPlayer(diedEvent.destFlags)) continue;

    const playerGUID = diedEvent.destGUID;
    const deathTs = diedEvent.timestamp.getTime();
    const pullStartTs = session.startTime.getTime();

    const playerInfo = resolver.resolve(playerGUID);
    const playerName = diedEvent.destName || playerInfo?.name || "Unknown";
    const playerClass = playerInfo?.class ?? "UNKNOWN";
    const playerSpec = playerInfo?.spec ?? "UNKNOWN";

    // Collect last 10s of damage/heal events targeting this player.
    const windowEvents: Array<{ event: ParsedEvent; info: DmgHealInfo }> = [];
    for (const e of session.events) {
      if (e.timestamp.getTime() > deathTs) break;
      if (!("destGUID" in e) || e.destGUID !== playerGUID) continue;
      const info = extractDmgHeal(e);
      if (!info) continue;
      if (deathTs - e.timestamp.getTime() <= DEATH_LOOKBACK_MS) {
        windowEvents.push({ event: e, info });
      }
    }

    // Identify the fatal event: last damage event with overkill > 0.
    let fatalIdx = -1;
    for (let i = windowEvents.length - 1; i >= 0; i--) {
      if (windowEvents[i].info.type === "damage" && windowEvents[i].info.overkill > 0) {
        fatalIdx = i;
        break;
      }
    }
    if (fatalIdx === -1) {
      // Fallback: last damage event
      for (let i = windowEvents.length - 1; i >= 0; i--) {
        if (windowEvents[i].info.type === "damage") {
          fatalIdx = i;
          break;
        }
      }
    }

    const fatalInfo = fatalIdx >= 0 ? windowEvents[fatalIdx].info : null;

    // Calculate running HP (we don't have true max HP from COMBATANT_INFO stamina,
    // so we estimate from the last known HP before the death window via cumulative approach).
    // We work backwards: the player had 0 HP at death. Reverse-sum to find max.
    let netDamage = 0;
    for (const { info } of windowEvents) {
      if (info.type === "damage") netDamage += info.amount;
      else netDamage -= info.amount;
    }
    const estimatedMaxHp = Math.max(netDamage, 1);

    let runningHp = estimatedMaxHp;
    const deathEvents: DeathEvent[] = windowEvents.map(({ event, info }, idx) => {
      if (info.type === "damage") runningHp -= info.amount;
      else runningHp += info.amount;
      const hpPct = Math.max(0, Math.min(100, (runningHp / estimatedMaxHp) * 100));
      return {
        timestamp: event.timestamp,
        type: info.type,
        sourceGUID: info.sourceGUID,
        sourceName: info.sourceName,
        spellId: info.spellId,
        spellName: info.spellName,
        amount: info.amount,
        isFatal: idx === fatalIdx,
        estimatedHpAfter: Math.round(hpPct),
      };
    });

    // Defensive audit: check last 30s before death for cast success events.
    const defensives = getDefensives(playerClass, playerSpec);
    const defensiveStatuses: DefensiveStatus[] = defensives.map((def) => {
      let lastUsedAt: Date | undefined;

      for (const e of session.events) {
        if (e.timestamp.getTime() > deathTs) break;
        if (e.subevent !== "SPELL_CAST_SUCCESS") continue;
        const cast = e as SpellCastSuccessEvent;
        if (cast.sourceGUID !== playerGUID) continue;
        if (cast.spellId !== def.spellId) continue;
        lastUsedAt = cast.timestamp;
      }

      let available = false;
      if (!lastUsedAt) {
        // Never used in this encounter — available.
        available = true;
      } else {
        const secSinceUse = (deathTs - lastUsedAt.getTime()) / 1000;
        available = secSinceUse >= def.cooldownSec;
      }

      return {
        spellId: def.spellId,
        spellName: def.name,
        wasUsed: !!lastUsedAt,
        usedAt: lastUsedAt,
        available,
      };
    });

    recaps.push({
      playerGUID,
      playerName,
      playerClass,
      playerSpec,
      deathTimestamp: diedEvent.timestamp,
      pullNumber: session.pullNumber,
      timeIntoPull: (deathTs - pullStartTs) / 1000,
      fatalSpellId: fatalInfo?.spellId ?? 0,
      fatalSpellName: fatalInfo?.spellName ?? "Unknown",
      fatalSourceName: fatalInfo?.sourceName ?? "Unknown",
      overkill: fatalInfo?.overkill ?? 0,
      events: deathEvents,
      availableDefensives: defensiveStatuses,
    });
  }

  return recaps;
}

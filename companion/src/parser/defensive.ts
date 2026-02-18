// parser/defensive.ts — Defensive Usage Audit engine (Task 2.4)
//
// Tracks every player defensive spell usage during the encounter and flags
// missed opportunities: defensives that were available (off-cooldown) at
// the moment a player took their fatal hit.
//
// Output fed into SavedVariables as session.defensiveAudit[].

import type { EncounterSession } from "./session.js";
import type { DeathRecap } from "./death.js";
import type { GuidResolver } from "../enrichment/guid.js";
import { getDefensives } from "../enrichment/spelldb.js";
import type { SpellCastSuccessEvent } from "./cleu.js";
import { isPlayer } from "./cleu.js";

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

export interface DefensiveUse {
  /** Seconds into the encounter when the defensive was cast. */
  timeIntoPull: number;
  playerGUID: string;
  playerName: string;
  playerClass: string;
  playerSpec: string;
  spellId: number;
  spellName: string;
  /** Cooldown of the spell in seconds (from spelldb). */
  cooldownSec: number;
}

export interface MissedDefensive {
  spellId: number;
  spellName: string;
  cooldownSec: number;
  /** Seconds since last use (null = never used this encounter). */
  secSinceLastUse: number | null;
}

export interface PlayerDefensiveAudit {
  playerGUID: string;
  playerName: string;
  playerClass: string;
  playerSpec: string;
  uses: DefensiveUse[];
  missedAtDeath: MissedDefensive[];
  totalUses: number;
}

export interface DefensiveAuditReport {
  players: PlayerDefensiveAudit[];
}

// ---------------------------------------------------------------------------
// Main export
// ---------------------------------------------------------------------------

export function buildDefensiveAudit(
  session: EncounterSession,
  resolver: GuidResolver,
  deaths: DeathRecap[],
): DefensiveAuditReport {
  const sessionStartMs = session.startTime.getTime();

  // Collect all defensive spell IDs across all player classes/specs.
  const defensiveSpellIds = new Set<number>();
  for (const info of resolver.all()) {
    for (const def of getDefensives(info.class, info.spec)) {
      defensiveSpellIds.add(def.spellId);
    }
  }

  // Map: playerGUID → DefensiveUse[]
  const playerUses = new Map<string, DefensiveUse[]>();

  for (const ev of session.events) {
    if (ev.subevent !== "SPELL_CAST_SUCCESS") continue;
    if (!isPlayer(ev.sourceFlags)) continue;

    const cast = ev as SpellCastSuccessEvent;
    const spellId = cast.spellId;
    if (!defensiveSpellIds.has(spellId)) continue;

    const info = resolver.resolve(cast.sourceGUID);
    if (!info) continue;

    // Confirm this spell is actually a defensive for THIS player's class/spec.
    const defs = getDefensives(info.class, info.spec);
    const matchedDef = defs.find((d) => d.spellId === spellId);
    if (!matchedDef) continue;

    const use: DefensiveUse = {
      timeIntoPull: Math.max(0, (cast.timestamp.getTime() - sessionStartMs) / 1000),
      playerGUID: cast.sourceGUID,
      playerName: cast.sourceName,
      playerClass: info.class,
      playerSpec: info.spec,
      spellId,
      spellName: matchedDef.name,
      cooldownSec: matchedDef.cooldownSec,
    };

    if (!playerUses.has(cast.sourceGUID)) playerUses.set(cast.sourceGUID, []);
    playerUses.get(cast.sourceGUID)!.push(use);
  }

  // Build per-player audits, seeded from all known players.
  const audits = new Map<string, PlayerDefensiveAudit>();
  for (const info of resolver.all()) {
    const uses = playerUses.get(info.guid) ?? [];
    audits.set(info.guid, {
      playerGUID: info.guid,
      playerName: info.name,
      playerClass: info.class,
      playerSpec: info.spec,
      uses,
      missedAtDeath: [],
      totalUses: uses.length,
    });
  }

  // ---------------------------------------------------------------------------
  // Missed defensives at death
  // ---------------------------------------------------------------------------
  for (const death of deaths) {
    const audit = audits.get(death.playerGUID);
    if (!audit) continue;

    const deathTimeSec = death.deathTimestamp.getTime() / 1000;
    const usesForPlayer = playerUses.get(death.playerGUID) ?? [];
    const defs = getDefensives(death.playerClass, death.playerSpec ?? "");

    for (const def of defs) {
      const lastUse = usesForPlayer
        .filter((u) => u.spellId === def.spellId)
        .sort((a, b) => b.timeIntoPull - a.timeIntoPull)[0];

      let secSinceLastUse: number | null = null;
      let isAvailable: boolean;

      if (!lastUse) {
        isAvailable = true;
      } else {
        // lastUse.timeIntoPull is seconds from encounter start.
        // deathTimeSec is absolute unix time / 1000.
        // We need the absolute timestamp of the last use.
        const lastUseAbsSec = sessionStartMs / 1000 + lastUse.timeIntoPull;
        secSinceLastUse = deathTimeSec - lastUseAbsSec;
        isAvailable = secSinceLastUse >= def.cooldownSec;
      }

      if (isAvailable) {
        audit.missedAtDeath.push({
          spellId: def.spellId,
          spellName: def.name,
          cooldownSec: def.cooldownSec,
          secSinceLastUse,
        });
      }
    }
  }

  return {
    players: Array.from(audits.values()),
  };
}

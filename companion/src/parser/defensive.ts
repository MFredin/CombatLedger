// parser/defensive.ts — Defensive Usage Audit engine (Task 2.4 + Phase 3.5)
//
// Tracks every player defensive spell usage during the encounter and flags
// missed opportunities: defensives that were available (off-cooldown) at
// the moment a player took their fatal hit.
//
// Phase 3.5 addition: also tracks external defensives (Ironbark, Pain Suppression,
// Blessing of Protection, etc.) applied to another player — surfaced separately
// so raid leaders can see whether external cooldowns were used on deaths.

import type { EncounterSession } from "./session.js";
import type { DeathRecap } from "./death.js";
import type { GuidResolver } from "../enrichment/guid.js";
import { getDefensives, getAllExternalDefensiveIds, getExternalDefensive } from "../enrichment/spelldb.js";
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

/** An external defensive applied by one player to another. */
export interface ExternalDefensiveUse {
  timeIntoPull: number;
  casterGUID: string;
  casterName: string;
  targetGUID: string;
  targetName: string;
  spellId: number;
  spellName: string;
  cooldownSec: number;
}

export interface MissedDefensive {
  spellId: number;
  spellName: string;
  cooldownSec: number;
  /** Seconds since last use (null = never used this encounter). */
  secSinceLastUse: number | null;
}

/** A missed external defensive at time of death — another player had this CD available. */
export interface MissedExternal {
  casterName: string;
  spellId: number;
  spellName: string;
  cooldownSec: number;
  secSinceLastUse: number | null;
}

export interface PlayerDefensiveAudit {
  playerGUID: string;
  playerName: string;
  playerClass: string;
  playerSpec: string;
  uses: DefensiveUse[];
  missedAtDeath: MissedDefensive[];
  missedExternals: MissedExternal[];
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

  // Collect all personal defensive spell IDs across all player classes/specs.
  const defensiveSpellIds = new Set<number>();
  for (const info of resolver.all()) {
    for (const def of getDefensives(info.class, info.spec)) {
      defensiveSpellIds.add(def.spellId);
    }
  }

  // Collect all external defensive spell IDs (from raid data).
  const externalIds = new Set<number>(getAllExternalDefensiveIds());

  // Map: playerGUID → DefensiveUse[]
  const playerUses = new Map<string, DefensiveUse[]>();
  // Map: casterGUID → ExternalDefensiveUse[]
  const externalUses = new Map<string, ExternalDefensiveUse[]>();

  for (const ev of session.events) {
    if (ev.subevent !== "SPELL_CAST_SUCCESS") continue;
    if (!isPlayer(ev.sourceFlags)) continue;

    const cast = ev as SpellCastSuccessEvent;
    const spellId = cast.spellId;

    // ---- Personal defensives -----------------------------------------------
    if (defensiveSpellIds.has(spellId)) {
      const info = resolver.resolve(cast.sourceGUID);
      if (info) {
        const defs = getDefensives(info.class, info.spec);
        const matchedDef = defs.find((d) => d.spellId === spellId);
        if (matchedDef) {
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
      }
    }

    // ---- External defensives (source casts on a different player dest) ------
    if (externalIds.has(spellId) && cast.sourceGUID !== cast.destGUID && isPlayer(cast.destFlags)) {
      const extDef = getExternalDefensive(spellId);
      if (extDef?.isExternal) {
        const use: ExternalDefensiveUse = {
          timeIntoPull: Math.max(0, (cast.timestamp.getTime() - sessionStartMs) / 1000),
          casterGUID: cast.sourceGUID,
          casterName: cast.sourceName,
          targetGUID: cast.destGUID,
          targetName: cast.destName,
          spellId,
          spellName: extDef.name,
          cooldownSec: extDef.cooldownSec,
        };
        if (!externalUses.has(cast.sourceGUID)) externalUses.set(cast.sourceGUID, []);
        externalUses.get(cast.sourceGUID)!.push(use);
      }
    }
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
      missedExternals: [],
      totalUses: uses.length,
    });
  }

  // ---------------------------------------------------------------------------
  // Missed personal + external defensives at death
  // ---------------------------------------------------------------------------
  for (const death of deaths) {
    const audit = audits.get(death.playerGUID);
    if (!audit) continue;

    const deathTimeSec = death.deathTimestamp.getTime() / 1000;
    const usesForPlayer = playerUses.get(death.playerGUID) ?? [];
    const defs = getDefensives(death.playerClass, death.playerSpec ?? "");

    // Personal defensives
    for (const def of defs) {
      const lastUse = usesForPlayer
        .filter((u) => u.spellId === def.spellId)
        .sort((a, b) => b.timeIntoPull - a.timeIntoPull)[0];

      let secSinceLastUse: number | null = null;
      let isAvailable: boolean;

      if (!lastUse) {
        isAvailable = true;
      } else {
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

    // External defensives: for each other player who has external CDs, check
    // whether they could have applied one to the dying player.
    for (const [casterGUID, extUseList] of externalUses) {
      if (casterGUID === death.playerGUID) continue;

      for (const extId of externalIds) {
        const extDef = getExternalDefensive(extId);
        if (!extDef?.isExternal) continue;

        const casterName = extUseList[0]?.casterName ?? "";
        const lastUse = extUseList
          .filter((u) => u.spellId === extId)
          .sort((a, b) => b.timeIntoPull - a.timeIntoPull)[0];

        let secSinceLastUse: number | null = null;
        let isAvailable: boolean;

        if (!lastUse) {
          // Never used this encounter — it was available from the start.
          isAvailable = true;
        } else {
          const lastUseAbsSec = sessionStartMs / 1000 + lastUse.timeIntoPull;
          secSinceLastUse = deathTimeSec - lastUseAbsSec;
          isAvailable = secSinceLastUse >= extDef.cooldownSec;
        }

        if (isAvailable) {
          // Only flag if the caster is a known player in this session.
          const casterInfo = resolver.resolve(casterGUID);
          if (!casterInfo) continue;
          // Only flag if the caster has this spell (class/spec check).
          if (extDef.spec !== "any" && casterInfo.spec !== extDef.spec) continue;
          if (casterInfo.class !== extDef.class) continue;

          audit.missedExternals.push({
            casterName: casterName || casterInfo.name,
            spellId: extId,
            spellName: extDef.name,
            cooldownSec: extDef.cooldownSec,
            secSinceLastUse,
          });
        }
      }
    }
  }

  return {
    players: Array.from(audits.values()),
  };
}

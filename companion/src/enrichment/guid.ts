/**
 * guid.ts — GUID → player name/class resolution
 *
 * Builds a map from COMBATANT_INFO events collected during session segmentation.
 * COMBATANT_INFO does not carry a player name — only a GUID — so names are
 * backfilled separately by scanning regular combat events (which always carry
 * the real player name as sourceName / destName).
 */

import type { CombatantInfo } from "../parser/session.js";
import type { ParsedEvent } from "../parser/cleu.js";

export interface PlayerInfo {
  guid: string;
  name: string;
  class: string;
  spec: string;
  specId: number;
}

/** Spec ID → { class, spec } mapping for WoW 12.0 (Midnight). */
const SPEC_MAP: Record<number, { class: string; spec: string }> = {
  // Death Knight
  250: { class: "DEATHKNIGHT", spec: "BLOOD" },
  251: { class: "DEATHKNIGHT", spec: "FROST" },
  252: { class: "DEATHKNIGHT", spec: "UNHOLY" },
  // Demon Hunter
  577: { class: "DEMONHUNTER", spec: "HAVOC" },
  581: { class: "DEMONHUNTER", spec: "VENGEANCE" },
  // Druid
  102: { class: "DRUID", spec: "BALANCE" },
  103: { class: "DRUID", spec: "FERAL" },
  104: { class: "DRUID", spec: "GUARDIAN" },
  105: { class: "DRUID", spec: "RESTORATION" },
  // Evoker
  1467: { class: "EVOKER", spec: "DEVASTATION" },
  1468: { class: "EVOKER", spec: "PRESERVATION" },
  1473: { class: "EVOKER", spec: "AUGMENTATION" },
  // Hunter
  253: { class: "HUNTER", spec: "BEAST_MASTERY" },
  254: { class: "HUNTER", spec: "MARKSMANSHIP" },
  255: { class: "HUNTER", spec: "SURVIVAL" },
  // Mage
  62: { class: "MAGE", spec: "ARCANE" },
  63: { class: "MAGE", spec: "FIRE" },
  64: { class: "MAGE", spec: "FROST" },
  // Monk
  268: { class: "MONK", spec: "BREWMASTER" },
  269: { class: "MONK", spec: "WINDWALKER" },
  270: { class: "MONK", spec: "MISTWEAVER" },
  // Paladin
  65: { class: "PALADIN", spec: "HOLY" },
  66: { class: "PALADIN", spec: "PROTECTION" },
  70: { class: "PALADIN", spec: "RETRIBUTION" },
  // Priest
  256: { class: "PRIEST", spec: "DISCIPLINE" },
  257: { class: "PRIEST", spec: "HOLY" },
  258: { class: "PRIEST", spec: "SHADOW" },
  // Rogue
  259: { class: "ROGUE", spec: "ASSASSINATION" },
  260: { class: "ROGUE", spec: "OUTLAW" },
  261: { class: "ROGUE", spec: "SUBTLETY" },
  // Shaman
  262: { class: "SHAMAN", spec: "ELEMENTAL" },
  263: { class: "SHAMAN", spec: "ENHANCEMENT" },
  264: { class: "SHAMAN", spec: "RESTORATION" },
  // Warlock
  265: { class: "WARLOCK", spec: "AFFLICTION" },
  266: { class: "WARLOCK", spec: "DEMONOLOGY" },
  267: { class: "WARLOCK", spec: "DESTRUCTION" },
  // Warrior
  71: { class: "WARRIOR", spec: "ARMS" },
  72: { class: "WARRIOR", spec: "FURY" },
  73: { class: "WARRIOR", spec: "PROTECTION" },
};

export class GuidResolver {
  private map: Map<string, PlayerInfo> = new Map();

  /** Populate from combatants extracted during session segmentation. */
  populate(combatants: CombatantInfo[]): void {
    for (const c of combatants) {
      const specInfo = SPEC_MAP[c.specId] ?? { class: "UNKNOWN", spec: "UNKNOWN" };
      this.map.set(c.guid, {
        guid: c.guid,
        name: c.name,
        class: specInfo.class,
        spec: specInfo.spec,
        specId: c.specId,
      });
    }
  }

  /**
   * Back-fill real player names by scanning combat events.
   *
   * COMBATANT_INFO events do not carry a player name, so populate() stores the
   * GUID as a placeholder.  Every regular CLEU event (SPELL_DAMAGE, UNIT_DIED,
   * etc.) does carry the real name as sourceName / destName.  This method scans
   * those events and overwrites any entry whose name is still the placeholder
   * GUID with the real name found in the log.
   *
   * Call this once after populate() and before any analysis engines run, so
   * that all downstream consumers (deaths, defensives, performance) see correct
   * names without each needing its own resolution logic.
   */
  populateNamesFromEvents(events: ParsedEvent[]): void {
    for (const ev of events) {
      // Use optional-property access — non-base events (ENCOUNTER_START etc.)
      // don't have source/dest fields and will simply produce undefined here.
      const b = ev as Partial<{
        sourceGUID: string;
        sourceName: string;
        destGUID: string;
        destName: string;
      }>;

      if (b.sourceGUID && b.sourceName && b.sourceName !== b.sourceGUID) {
        const info = this.map.get(b.sourceGUID);
        if (info && info.name === info.guid) {
          this.map.set(b.sourceGUID, { ...info, name: b.sourceName });
        }
      }

      if (b.destGUID && b.destName && b.destName !== b.destGUID) {
        const info = this.map.get(b.destGUID);
        if (info && info.name === info.guid) {
          this.map.set(b.destGUID, { ...info, name: b.destName });
        }
      }
    }
  }

  resolve(guid: string): PlayerInfo | undefined {
    return this.map.get(guid);
  }

  all(): PlayerInfo[] {
    return Array.from(this.map.values());
  }
}

/**
 * cleu.ts — Raw CLEU line parser → typed events
 *
 * Parses individual lines from WoWCombatLog.txt into strongly-typed
 * discriminated-union event structs.
 *
 * Format:
 *   MM/DD HH:MM:SS.mmm  SUBEVENT,hideCaster,srcGUID,srcName,srcFlags,srcRaidFlags,
 *                        dstGUID,dstName,dstFlags,dstRaidFlags,[event-specific...]
 */

import type { Result } from "../types.js";

// ---------------------------------------------------------------------------
// Unit flag helpers (Section 11 of brief)
// ---------------------------------------------------------------------------
export const UNIT_FLAGS = {
  AFFILIATION_MINE: 0x00000001,
  AFFILIATION_PARTY: 0x00000002,
  AFFILIATION_RAID: 0x00000004,
  AFFILIATION_OUTSIDER: 0x00000008,
  REACTION_FRIENDLY: 0x00000010,
  REACTION_NEUTRAL: 0x00000020,
  REACTION_HOSTILE: 0x00000040,
  CONTROL_PLAYER: 0x00000100,
  CONTROL_NPC: 0x00000200,
  TYPE_PLAYER: 0x00000400,
  TYPE_NPC: 0x00000800,
  TYPE_PET: 0x00001000,
  TYPE_GUARDIAN: 0x00002000,
  TYPE_OBJECT: 0x00004000,
} as const;

export function isPlayer(flags: number): boolean {
  return (flags & UNIT_FLAGS.TYPE_PLAYER) !== 0;
}

export function isEnemy(flags: number): boolean {
  return (flags & UNIT_FLAGS.REACTION_HOSTILE) !== 0;
}

// ---------------------------------------------------------------------------
// Base event interface
// ---------------------------------------------------------------------------
export interface BaseEvent {
  timestamp: Date;
  subevent: string;
  hideCaster: boolean;
  sourceGUID: string;
  sourceName: string;
  sourceFlags: number;
  sourceRaidFlags: number;
  destGUID: string;
  destName: string;
  destFlags: number;
  destRaidFlags: number;
}

// ---------------------------------------------------------------------------
// Typed event interfaces
// ---------------------------------------------------------------------------
export interface SpellDamageEvent extends BaseEvent {
  subevent: "SPELL_DAMAGE" | "SPELL_PERIODIC_DAMAGE";
  spellId: number;
  spellName: string;
  spellSchool: number;
  amount: number;
  overkill: number; // -1 if not a killing blow
  resisted: number;
  blocked: number;
  absorbed: number;
  critical: boolean;
}

export interface SwingDamageEvent extends BaseEvent {
  subevent: "SWING_DAMAGE";
  amount: number;
  overkill: number;
  school: number;
  resisted: number;
  blocked: number;
  absorbed: number;
  critical: boolean;
}

export interface RangeDamageEvent extends BaseEvent {
  subevent: "RANGE_DAMAGE";
  spellId: number;
  spellName: string;
  spellSchool: number;
  amount: number;
  overkill: number;
  resisted: number;
  blocked: number;
  absorbed: number;
  critical: boolean;
}

export interface SpellHealEvent extends BaseEvent {
  subevent: "SPELL_HEAL" | "SPELL_PERIODIC_HEAL";
  spellId: number;
  spellName: string;
  spellSchool: number;
  amount: number;
  overheal: number;
  absorbed: number;
  critical: boolean;
}

export interface UnitDiedEvent extends BaseEvent {
  subevent: "UNIT_DIED";
  unconsciousOnDeath: boolean;
}

export interface SpellInterruptEvent extends BaseEvent {
  subevent: "SPELL_INTERRUPT";
  spellId: number;
  spellName: string;
  spellSchool: number;
  extraSpellId: number;   // the interrupted spell
  extraSpellName: string;
  extraSchool: number;
}

export interface SpellCastStartEvent extends BaseEvent {
  subevent: "SPELL_CAST_START";
  spellId: number;
  spellName: string;
  spellSchool: number;
}

export interface SpellCastSuccessEvent extends BaseEvent {
  subevent: "SPELL_CAST_SUCCESS";
  spellId: number;
  spellName: string;
  spellSchool: number;
}

export interface SpellCastFailedEvent extends BaseEvent {
  subevent: "SPELL_CAST_FAILED";
  spellId: number;
  spellName: string;
  spellSchool: number;
  failedType: string;
}

export interface SpellAuraAppliedEvent extends BaseEvent {
  subevent: "SPELL_AURA_APPLIED" | "SPELL_AURA_REFRESH" | "SPELL_AURA_APPLIED_DOSE";
  spellId: number;
  spellName: string;
  spellSchool: number;
  auraType: "BUFF" | "DEBUFF";
  amount?: number; // stacks for DOSE
}

export interface SpellAuraRemovedEvent extends BaseEvent {
  subevent: "SPELL_AURA_REMOVED";
  spellId: number;
  spellName: string;
  spellSchool: number;
  auraType: "BUFF" | "DEBUFF";
}

export interface EncounterStartEvent {
  subevent: "ENCOUNTER_START";
  timestamp: Date;
  encounterId: number;
  encounterName: string;
  difficulty: number;
  groupSize: number;
}

export interface EncounterEndEvent {
  subevent: "ENCOUNTER_END";
  timestamp: Date;
  encounterId: number;
  encounterName: string;
  difficulty: number;
  groupSize: number;
  success: boolean;
}

export interface CombatantInfoEvent {
  subevent: "COMBATANT_INFO";
  timestamp: Date;
  playerGUID: string;
  faction: number;
  strength: number;
  agility: number;
  stamina: number;
  intellect: number;
  currentSpecId: number;
}

export interface ZoneChangedEvent {
  subevent: "ZONE_CHANGED_NEW_AREA";
  timestamp: Date;
}

// Catch-all for unhandled events
export interface UnknownEvent extends BaseEvent {
  subevent: string;
  rawParams: string[];
}

export type ParsedEvent =
  | SpellDamageEvent
  | SwingDamageEvent
  | RangeDamageEvent
  | SpellHealEvent
  | UnitDiedEvent
  | SpellInterruptEvent
  | SpellCastStartEvent
  | SpellCastSuccessEvent
  | SpellCastFailedEvent
  | SpellAuraAppliedEvent
  | SpellAuraRemovedEvent
  | EncounterStartEvent
  | EncounterEndEvent
  | CombatantInfoEvent
  | ZoneChangedEvent
  | UnknownEvent;

// ---------------------------------------------------------------------------
// Timestamp parsing
// ---------------------------------------------------------------------------

/** Parse "MM/DD HH:MM:SS.mmm" into a Date (uses current year). */
function parseTimestamp(raw: string): Date {
  const [datePart, timePart] = raw.split(" ");
  const [month, day] = datePart.split("/").map(Number);
  const [time, ms] = timePart.split(".");
  const [hh, mm, ss] = time.split(":").map(Number);
  const year = new Date().getFullYear();
  return new Date(year, month - 1, day, hh, mm, ss, Number(ms ?? 0));
}

// ---------------------------------------------------------------------------
// CSV split that respects quoted strings
// ---------------------------------------------------------------------------

function splitCsvLine(line: string): string[] {
  const result: string[] = [];
  let current = "";
  let inQuote = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuote = !inQuote;
    } else if (ch === "," && !inQuote) {
      result.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  result.push(current);
  return result;
}

// ---------------------------------------------------------------------------
// Field helpers
// ---------------------------------------------------------------------------

function num(s: string | undefined): number {
  if (!s) return 0;
  if (s.startsWith("0x") || s.startsWith("0X")) return parseInt(s, 16);
  return parseInt(s, 10) || 0;
}

function bool(s: string | undefined): boolean {
  return s === "1" || s?.toLowerCase() === "true";
}

function str(s: string | undefined): string {
  if (!s) return "";
  if (s.startsWith('"') && s.endsWith('"')) return s.slice(1, -1);
  return s;
}

// ---------------------------------------------------------------------------
// Base params parser (indices 0-9 after the subevent field)
// ---------------------------------------------------------------------------

function parseBase(
  timestamp: Date,
  subevent: string,
  params: string[]
): Omit<BaseEvent, "subevent"> {
  return {
    timestamp,
    hideCaster: bool(params[0]),
    sourceGUID: str(params[1]),
    sourceName: str(params[2]),
    sourceFlags: num(params[3]),
    sourceRaidFlags: num(params[4]),
    destGUID: str(params[5]),
    destName: str(params[6]),
    destFlags: num(params[7]),
    destRaidFlags: num(params[8]),
  };
}

// ---------------------------------------------------------------------------
// Main line parser
// ---------------------------------------------------------------------------

/**
 * Parse a single line from WoWCombatLog.txt.
 * Returns a Result<ParsedEvent, Error> — never throws.
 */
export function parseLine(line: string): Result<ParsedEvent, Error> {
  try {
    // Split on the two-space separator between timestamp and event data.
    const sepIdx = line.indexOf("  ");
    if (sepIdx === -1) {
      return { ok: false, error: new Error("No timestamp separator") };
    }

    const rawTs = line.slice(0, sepIdx);
    const rest = line.slice(sepIdx + 2);
    const timestamp = parseTimestamp(rawTs);

    const parts = splitCsvLine(rest);
    if (parts.length === 0) {
      return { ok: false, error: new Error("Empty event line") };
    }

    const subevent = parts[0];
    const params = parts.slice(1);

    // Handle non-CLEU lines (ENCOUNTER_START etc. don't have base unit fields)
    if (subevent === "ENCOUNTER_START") {
      return {
        ok: true,
        value: {
          subevent: "ENCOUNTER_START",
          timestamp,
          encounterId: num(params[0]),
          encounterName: str(params[1]),
          difficulty: num(params[2]),
          groupSize: num(params[3]),
        } as EncounterStartEvent,
      };
    }

    if (subevent === "ENCOUNTER_END") {
      return {
        ok: true,
        value: {
          subevent: "ENCOUNTER_END",
          timestamp,
          encounterId: num(params[0]),
          encounterName: str(params[1]),
          difficulty: num(params[2]),
          groupSize: num(params[3]),
          success: bool(params[4]),
        } as EncounterEndEvent,
      };
    }

    if (subevent === "COMBATANT_INFO") {
      return {
        ok: true,
        value: {
          subevent: "COMBATANT_INFO",
          timestamp,
          playerGUID: str(params[0]),
          faction: num(params[1]),
          strength: num(params[2]),
          agility: num(params[3]),
          stamina: num(params[4]),
          intellect: num(params[5]),
          // currentSpecID is at index 23 per the COMBATANT_INFO layout
          currentSpecId: num(params[23]),
        } as CombatantInfoEvent,
      };
    }

    if (subevent === "ZONE_CHANGED_NEW_AREA") {
      return {
        ok: true,
        value: { subevent: "ZONE_CHANGED_NEW_AREA", timestamp } as ZoneChangedEvent,
      };
    }

    // All remaining events share the 9-field base (hideCaster + 4 src + 4 dst).
    const base = parseBase(timestamp, subevent, params);
    // Event-specific params start at index 9.
    const ep = params.slice(9);

    switch (subevent) {
      case "SPELL_DAMAGE":
      case "SPELL_PERIODIC_DAMAGE":
        return {
          ok: true,
          value: {
            ...base,
            subevent: subevent as "SPELL_DAMAGE" | "SPELL_PERIODIC_DAMAGE",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            amount: num(ep[3]),
            overkill: num(ep[4]),
            resisted: num(ep[5]),
            blocked: num(ep[6]),
            absorbed: num(ep[7]),
            critical: bool(ep[9]),
          } as SpellDamageEvent,
        };

      case "SWING_DAMAGE":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "SWING_DAMAGE",
            amount: num(ep[0]),
            overkill: num(ep[1]),
            school: num(ep[2]),
            resisted: num(ep[3]),
            blocked: num(ep[4]),
            absorbed: num(ep[5]),
            critical: bool(ep[7]),
          } as SwingDamageEvent,
        };

      case "RANGE_DAMAGE":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "RANGE_DAMAGE",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            amount: num(ep[3]),
            overkill: num(ep[4]),
            resisted: num(ep[5]),
            blocked: num(ep[6]),
            absorbed: num(ep[7]),
            critical: bool(ep[9]),
          } as RangeDamageEvent,
        };

      case "SPELL_HEAL":
      case "SPELL_PERIODIC_HEAL":
        return {
          ok: true,
          value: {
            ...base,
            subevent: subevent as "SPELL_HEAL" | "SPELL_PERIODIC_HEAL",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            amount: num(ep[3]),
            overheal: num(ep[4]),
            absorbed: num(ep[5]),
            critical: bool(ep[6]),
          } as SpellHealEvent,
        };

      case "UNIT_DIED":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "UNIT_DIED",
            unconsciousOnDeath: bool(ep[0]),
          } as UnitDiedEvent,
        };

      case "SPELL_INTERRUPT":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "SPELL_INTERRUPT",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            extraSpellId: num(ep[3]),
            extraSpellName: str(ep[4]),
            extraSchool: num(ep[5]),
          } as SpellInterruptEvent,
        };

      case "SPELL_CAST_START":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "SPELL_CAST_START",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
          } as SpellCastStartEvent,
        };

      case "SPELL_CAST_SUCCESS":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "SPELL_CAST_SUCCESS",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
          } as SpellCastSuccessEvent,
        };

      case "SPELL_CAST_FAILED":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "SPELL_CAST_FAILED",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            failedType: str(ep[3]),
          } as SpellCastFailedEvent,
        };

      case "SPELL_AURA_APPLIED":
      case "SPELL_AURA_REFRESH":
      case "SPELL_AURA_APPLIED_DOSE": {
        const auraType = str(ep[3]) as "BUFF" | "DEBUFF";
        return {
          ok: true,
          value: {
            ...base,
            subevent: subevent as "SPELL_AURA_APPLIED" | "SPELL_AURA_REFRESH" | "SPELL_AURA_APPLIED_DOSE",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            auraType,
            amount: subevent === "SPELL_AURA_APPLIED_DOSE" ? num(ep[4]) : undefined,
          } as SpellAuraAppliedEvent,
        };
      }

      case "SPELL_AURA_REMOVED":
        return {
          ok: true,
          value: {
            ...base,
            subevent: "SPELL_AURA_REMOVED",
            spellId: num(ep[0]),
            spellName: str(ep[1]),
            spellSchool: num(ep[2]),
            auraType: str(ep[3]) as "BUFF" | "DEBUFF",
          } as SpellAuraRemovedEvent,
        };

      default:
        return {
          ok: true,
          value: {
            ...base,
            subevent,
            rawParams: ep,
          } as UnknownEvent,
        };
    }
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err : new Error(String(err)),
    };
  }
}

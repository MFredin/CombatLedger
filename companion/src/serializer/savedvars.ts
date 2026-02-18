/**
 * savedvars.ts — TypeScript → Lua table serialiser (Task 1.8)
 *
 * Converts the parsed session data into a valid CombatLedger.lua file that WoW
 * can load as a SavedVariables global.
 *
 * Output format uses explicit [index] table keys for arrays and ["key"] for
 * string keys to match the WoW SavedVariables convention.
 */

import type { EncounterSession } from "../parser/session.js";
import type { DeathRecap } from "../parser/death.js";
import type { InterruptReport } from "../parser/interrupt.js";
import type { CCCoverage } from "../parser/cc.js";
import type { PerformanceReport } from "../parser/performance.js";
import type { DefensiveAuditReport } from "../parser/defensive.js";

const MAX_SESSION_BYTES = 500_000;

interface SerialiseInput {
  version: number;
  generatedAt: number;
  companionVersion: string;
  sessions: Array<{
    session: EncounterSession;
    deaths: DeathRecap[];
    interrupts: InterruptReport;
    ccCoverage?: CCCoverage[];
    performance?: PerformanceReport;
    defensiveAudit?: DefensiveAuditReport;
  }>;
}

// ---------------------------------------------------------------------------
// Lua value serialisers
// ---------------------------------------------------------------------------

function luaStr(s: string): string {
  // Escape backslashes and double quotes; wrap in double quotes.
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
}

function luaNum(n: number): string {
  return String(n);
}

function luaBool(b: boolean): string {
  return b ? "true" : "false";
}

function luaDate(d: Date): string {
  return String(Math.floor(d.getTime() / 1000));
}

type LuaValue =
  | string
  | number
  | boolean
  | Date
  | null
  | undefined
  | LuaValue[]
  | Record<string, LuaValue>;

function toLuaValue(val: LuaValue, indent = 0): string {
  if (val === null || val === undefined) return "nil";
  if (typeof val === "boolean") return luaBool(val);
  if (typeof val === "number") return luaNum(val);
  if (typeof val === "string") return luaStr(val);
  if (val instanceof Date) return luaDate(val);
  if (Array.isArray(val)) return toLuaArray(val, indent);
  return toLuaTable(val as Record<string, LuaValue>, indent);
}

function toLuaArray(arr: LuaValue[], indent: number): string {
  if (arr.length === 0) return "{}";
  const pad = "  ".repeat(indent + 1);
  const closePad = "  ".repeat(indent);
  const items = arr.map((v, i) => `${pad}[${i + 1}] = ${toLuaValue(v, indent + 1)}`);
  return `{\n${items.join(",\n")}\n${closePad}}`;
}

function toLuaTable(obj: Record<string, LuaValue>, indent: number): string {
  const keys = Object.keys(obj);
  if (keys.length === 0) return "{}";
  const pad = "  ".repeat(indent + 1);
  const closePad = "  ".repeat(indent);
  const entries = keys.map((k) => `${pad}[${luaStr(k)}] = ${toLuaValue(obj[k], indent + 1)}`);
  return `{\n${entries.join(",\n")}\n${closePad}}`;
}

// ---------------------------------------------------------------------------
// Session → Lua-value conversion helpers
// ---------------------------------------------------------------------------

function ccCoverageToLuaValue(cc: CCCoverage[]): LuaValue[] {
  return cc.map((target) => ({
    targetGUID: target.targetGUID,
    targetName: target.targetName,
    targetType: target.targetType,
    totalCombatDuration: Math.round(target.totalCombatDuration),
    coveredDuration: Math.round(target.coveredDuration * 10) / 10,
    coveragePercent: target.coveragePercent,
    wastedCasts: target.wastedCasts,
    segments: target.segments.map((s) => ({
      sourceName: s.sourceName,
      spellId: s.spellId,
      spellName: s.spellName,
      ccCategory: s.ccCategory,
      startTime: Math.floor(s.startTime.getTime() / 1000),
      endTime: Math.floor(s.endTime.getTime() / 1000),
      theoreticalDuration: Math.round(s.theoreticalDuration * 10) / 10,
      actualDuration: Math.round(s.actualDuration * 10) / 10,
      drMultiplier: s.drMultiplier,
      drApplicationNumber: s.drApplicationNumber,
      brokeEarly: s.brokeEarly,
      brokeReason: s.brokeReason ?? null,
      wasImmune: s.wasImmune,
    })) as LuaValue[],
    byCategory: Object.fromEntries(
      Object.entries(target.byCategory).map(([k, v]) => [
        k,
        { coveredDuration: v.coveredDuration, segments: v.segments, wastedCasts: v.wastedCasts },
      ])
    ) as Record<string, LuaValue>,
  })) as LuaValue[];
}

function performanceToLuaValue(perf: PerformanceReport): LuaValue {
  return {
    encounterDurationSec: Math.round(perf.encounterDurationSec),
    totalDamageDone: perf.totalDamageDone,
    totalHealingDone: perf.totalHealingDone,
    players: perf.players.map((p) => ({
      playerGUID: p.playerGUID,
      playerName: p.playerName,
      playerClass: p.playerClass,
      playerSpec: p.playerSpec,
      damageDone: p.damageDone,
      healingDone: p.healingDone,
      overhealing: p.overhealing,
      interruptCount: p.interruptCount,
      deathCount: p.deathCount,
      ccApplied: p.ccApplied,
      dps: Math.round(p.dps),
      hps: Math.round(p.hps),
    })) as LuaValue[],
  };
}

function defensiveAuditToLuaValue(audit: DefensiveAuditReport): LuaValue {
  return {
    players: audit.players.map((p) => ({
      playerGUID: p.playerGUID,
      playerName: p.playerName,
      playerClass: p.playerClass,
      playerSpec: p.playerSpec,
      totalUses: p.totalUses,
      uses: p.uses.map((u) => ({
        timeIntoPull: Math.round(u.timeIntoPull),
        spellId: u.spellId,
        spellName: u.spellName,
        cooldownSec: u.cooldownSec,
      })) as LuaValue[],
      missedAtDeath: p.missedAtDeath.map((m) => ({
        spellId: m.spellId,
        spellName: m.spellName,
        cooldownSec: m.cooldownSec,
        secSinceLastUse: m.secSinceLastUse ?? null,
      })) as LuaValue[],
    })) as LuaValue[],
  };
}

function sessionToLuaValue(
  session: EncounterSession,
  deaths: DeathRecap[],
  interrupts: InterruptReport,
  ccCoverage?: CCCoverage[],
  performance?: PerformanceReport,
  defensiveAudit?: DefensiveAuditReport,
): Record<string, LuaValue> {
  return {
    encounterId: session.encounterId,
    encounterName: session.encounterName,
    difficulty: session.difficulty,
    groupSize: session.groupSize,
    startTime: Math.floor(session.startTime.getTime() / 1000),
    endTime: Math.floor(session.endTime.getTime() / 1000),
    durationSec: Math.round((session.endTime.getTime() - session.startTime.getTime()) / 1000),
    success: session.success,
    pullNumber: session.pullNumber,
    combatants: session.combatants.map((c) => ({
      guid: c.guid,
      name: c.name,
      specId: c.specId,
    })) as LuaValue[],
    deaths: deaths.map((d) => ({
      playerGUID: d.playerGUID,
      playerName: d.playerName,
      playerClass: d.playerClass,
      playerSpec: d.playerSpec,
      deathTimestamp: Math.floor(d.deathTimestamp.getTime() / 1000),
      pullNumber: d.pullNumber,
      timeIntoPull: Math.round(d.timeIntoPull),
      fatalSpellId: d.fatalSpellId,
      fatalSpellName: d.fatalSpellName,
      fatalSourceName: d.fatalSourceName,
      overkill: d.overkill,
      events: d.events.map((e) => ({
        timestamp: Math.floor(e.timestamp.getTime() / 1000),
        type: e.type,
        sourceName: e.sourceName,
        spellId: e.spellId,
        spellName: e.spellName,
        amount: e.amount,
        isFatal: e.isFatal,
        estimatedHpAfter: e.estimatedHpAfter,
      })) as LuaValue[],
      availableDefensives: d.availableDefensives.map((def) => ({
        spellId: def.spellId,
        spellName: def.spellName,
        wasUsed: def.wasUsed,
        usedAt: def.usedAt ? Math.floor(def.usedAt.getTime() / 1000) : null,
        available: def.available,
      })) as LuaValue[],
    })) as LuaValue[],
    ccCoverage: ccCoverage ? ccCoverageToLuaValue(ccCoverage) : [],
    interrupts: {
      encounterId: interrupts.encounterId,
      summary: {
        total: interrupts.summary.total,
        intercepted: interrupts.summary.intercepted,
        missed: interrupts.summary.missed,
        ratePercent: interrupts.summary.ratePercent,
      },
      events: interrupts.interrupts.map((i) => ({
        timestamp: Math.floor(i.timestamp.getTime() / 1000),
        pullNumber: i.pullNumber,
        targetName: i.targetName,
        spellId: i.spellId,
        spellName: i.spellName,
        castDurationMs: i.castDurationMs,
        wasInterrupted: i.wasInterrupted,
        interruptedBy: i.interruptedBy ?? null,
        interruptSpellId: i.interruptSpellId ?? null,
        castPercentAtInterrupt: i.castPercentAtInterrupt ?? null,
        missedReason: i.missedReason ?? null,
      })) as LuaValue[],
      byPlayer: Object.fromEntries(
        Object.entries(interrupts.byPlayer).map(([k, v]) => [
          k,
          { playerName: v.playerName, intercepted: v.intercepted, opportunities: v.opportunities },
        ])
      ) as Record<string, LuaValue>,
    },
    performance: performance ? performanceToLuaValue(performance) : {},
    defensiveAudit: defensiveAudit ? defensiveAuditToLuaValue(defensiveAudit) : {},
  };
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

export function serializeToLua(input: SerialiseInput): string {
  const sessionValues: LuaValue[] = input.sessions.map(
    ({ session, deaths, interrupts, ccCoverage, performance, defensiveAudit }) =>
      sessionToLuaValue(session, deaths, interrupts, ccCoverage, performance, defensiveAudit)
  );

  const db: Record<string, LuaValue> = {
    version: input.version,
    generatedAt: input.generatedAt,
    companionVersion: input.companionVersion,
    sessions: sessionValues,
  };

  const content = `-- CombatLedger.lua (SavedVariables)\n-- Auto-generated by CombatLedger Companion v${input.companionVersion}\n-- Do not edit manually.\nCombatLedgerDB = ${toLuaValue(db)}\n`;

  if (content.length > MAX_SESSION_BYTES * input.sessions.length) {
    console.warn(
      `[serializer] Output size ${content.length} bytes exceeds target. Consider trimming sessions.`
    );
  }

  return content;
}

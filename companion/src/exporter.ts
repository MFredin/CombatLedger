/**
 * exporter.ts — Export functionality (Task 2.6)
 *
 * Provides CSV and JSON export of CombatLedger session data.
 * Called from the Tauri tray menu "Export…" action.
 *
 * Exports available:
 *   - deaths.csv  — per-death row: player, pull, time, fatal spell, overkill
 *   - interrupts.csv — per-cast row: target, spell, interrupted_by, cast%, status
 *   - cc.csv      — per-target row: target, coverage%, wasted, by-category summary
 *   - performance.csv — per-player row: name, class, spec, dps, hps, interrupts, deaths
 *   - session.json — full structured export of the latest session
 */

import { writeFile } from "fs/promises";
import { join } from "path";
import type { EncounterSession } from "./parser/session.js";
import type { DeathRecap } from "./parser/death.js";
import type { InterruptReport } from "./parser/interrupt.js";
import type { CCCoverage } from "./parser/cc.js";
import type { PerformanceReport } from "./parser/performance.js";
import type { DefensiveAuditReport } from "./parser/defensive.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ExportPayload {
  session: EncounterSession;
  deaths: DeathRecap[];
  interrupts: InterruptReport;
  ccCoverage: CCCoverage[];
  performance: PerformanceReport;
  defensiveAudit: DefensiveAuditReport;
}

export type ExportFormat = "csv" | "json";
export type ExportTarget = "deaths" | "interrupts" | "cc" | "performance" | "all";

// ---------------------------------------------------------------------------
// CSV helpers
// ---------------------------------------------------------------------------

function escapeCsvField(val: string | number | boolean | null | undefined): string {
  if (val === null || val === undefined) return "";
  const s = String(val);
  if (s.includes(",") || s.includes('"') || s.includes("\n")) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function csvRow(fields: (string | number | boolean | null | undefined)[]): string {
  return fields.map(escapeCsvField).join(",");
}

// ---------------------------------------------------------------------------
// Individual CSV generators
// ---------------------------------------------------------------------------

function generateDeathsCsv(deaths: DeathRecap[]): string {
  const header = csvRow([
    "pull_number", "player_name", "player_class", "player_spec",
    "time_into_pull_sec", "fatal_spell", "fatal_source", "overkill",
    "unused_defensives",
  ]);
  const rows = deaths.map((d) => {
    const unusedDefs = (d.availableDefensives ?? [])
      .filter((def) => def.available && !def.wasUsed)
      .map((def) => def.spellName)
      .join("; ");
    return csvRow([
      d.pullNumber,
      d.playerName,
      d.playerClass,
      d.playerSpec,
      Math.round(d.timeIntoPull),
      d.fatalSpellName,
      d.fatalSourceName,
      d.overkill,
      unusedDefs || "none",
    ]);
  });
  return [header, ...rows].join("\n");
}

function generateInterruptsCsv(report: InterruptReport): string {
  const header = csvRow([
    "pull_number", "target", "spell", "cast_duration_ms",
    "was_interrupted", "interrupted_by", "cast_pct", "missed_reason",
  ]);
  const rows = report.interrupts.map((i) =>
    csvRow([
      i.pullNumber,
      i.targetName,
      i.spellName,
      i.castDurationMs,
      i.wasInterrupted ? "yes" : "no",
      i.interruptedBy ?? "",
      i.castPercentAtInterrupt != null ? Math.round(i.castPercentAtInterrupt) : "",
      i.missedReason ?? "",
    ])
  );
  return [header, ...rows].join("\n");
}

function generateCcCsv(cc: CCCoverage[]): string {
  const header = csvRow([
    "target_name", "target_type", "combat_duration_sec",
    "covered_sec", "coverage_pct", "wasted_casts",
    "segments_total", "categories",
  ]);
  const rows = cc.map((t) => {
    const cats = Object.keys(t.byCategory).join("; ");
    return csvRow([
      t.targetName,
      t.targetType,
      Math.round(t.totalCombatDuration),
      Math.round(t.coveredDuration * 10) / 10,
      t.coveragePercent,
      t.wastedCasts,
      t.segments.length,
      cats,
    ]);
  });
  return [header, ...rows].join("\n");
}

function generatePerformanceCsv(perf: PerformanceReport): string {
  const header = csvRow([
    "player_name", "class", "spec",
    "damage_done", "dps", "healing_done", "hps", "overhealing",
    "interrupts", "deaths", "cc_applied",
  ]);
  const rows = perf.players.map((p) =>
    csvRow([
      p.playerName,
      p.playerClass,
      p.playerSpec,
      p.damageDone,
      Math.round(p.dps),
      p.healingDone,
      Math.round(p.hps),
      p.overhealing,
      p.interruptCount,
      p.deathCount,
      p.ccApplied,
    ])
  );
  return [header, ...rows].join("\n");
}

// ---------------------------------------------------------------------------
// JSON export
// ---------------------------------------------------------------------------

function generateSessionJson(payload: ExportPayload): string {
  // Produce a clean JSON snapshot (no circular refs, Dates as ISO strings).
  const clone = {
    encounterName: payload.session.encounterName,
    difficulty: payload.session.difficulty,
    groupSize: payload.session.groupSize,
    startTime: payload.session.startTime.toISOString(),
    endTime: payload.session.endTime.toISOString(),
    durationSec: Math.round(
      (payload.session.endTime.getTime() - payload.session.startTime.getTime()) / 1000
    ),
    success: payload.session.success,
    pullNumber: payload.session.pullNumber,
    summary: {
      deaths: payload.deaths.length,
      interrupts: payload.interrupts.summary,
      performance: {
        totalDamageDone: payload.performance.totalDamageDone,
        totalHealingDone: payload.performance.totalHealingDone,
        encounterDurationSec: payload.performance.encounterDurationSec,
      },
    },
    deaths: payload.deaths.map((d) => ({
      playerName: d.playerName,
      playerClass: d.playerClass,
      playerSpec: d.playerSpec,
      pullNumber: d.pullNumber,
      timeIntoPull: Math.round(d.timeIntoPull),
      fatalSpell: d.fatalSpellName,
      overkill: d.overkill,
    })),
    ccCoverage: payload.ccCoverage.map((t) => ({
      targetName: t.targetName,
      coveragePercent: t.coveragePercent,
      wastedCasts: t.wastedCasts,
      combatDurationSec: Math.round(t.totalCombatDuration),
    })),
    players: payload.performance.players.map((p) => ({
      name: p.playerName,
      class: p.playerClass,
      spec: p.playerSpec,
      dps: Math.round(p.dps),
      hps: Math.round(p.hps),
      interrupts: p.interruptCount,
      deaths: p.deathCount,
    })),
  };
  return JSON.stringify(clone, null, 2);
}

// ---------------------------------------------------------------------------
// Main export function
// ---------------------------------------------------------------------------

export interface ExportResult {
  filePath: string;
  bytes: number;
}

/**
 * Write export file(s) to the given directory.
 *
 * @param outputDir  Directory to write files into (must exist).
 * @param payload    Session data to export.
 * @param format     "csv" | "json"
 * @param target     Which data to export ("deaths" | "interrupts" | "cc" | "performance" | "all")
 * @returns          Array of written file results.
 */
export async function exportSession(
  outputDir: string,
  payload: ExportPayload,
  format: ExportFormat = "csv",
  target: ExportTarget = "all",
): Promise<ExportResult[]> {
  const results: ExportResult[] = [];

  if (format === "json") {
    const content = generateSessionJson(payload);
    const filePath = join(outputDir, `combatledger_session_${payload.session.pullNumber}.json`);
    await writeFile(filePath, content, "utf-8");
    results.push({ filePath, bytes: Buffer.byteLength(content, "utf-8") });
    return results;
  }

  // CSV exports
  const writes: Array<{ name: string; content: string }> = [];

  if (target === "deaths" || target === "all") {
    writes.push({ name: "deaths.csv", content: generateDeathsCsv(payload.deaths) });
  }
  if (target === "interrupts" || target === "all") {
    writes.push({ name: "interrupts.csv", content: generateInterruptsCsv(payload.interrupts) });
  }
  if (target === "cc" || target === "all") {
    writes.push({ name: "cc_coverage.csv", content: generateCcCsv(payload.ccCoverage) });
  }
  if (target === "performance" || target === "all") {
    writes.push({
      name: "performance.csv",
      content: generatePerformanceCsv(payload.performance),
    });
  }

  for (const { name, content } of writes) {
    const filePath = join(outputDir, `combatledger_${name}`);
    await writeFile(filePath, content, "utf-8");
    results.push({ filePath, bytes: Buffer.byteLength(content, "utf-8") });
  }

  return results;
}

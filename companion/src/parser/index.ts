/**
 * index.ts — Parser orchestration
 *
 * Ties together: line parsing → session segmentation → analysis engines →
 * SQLite persistence (Phase 3) → serialisation.
 * Called by the Tauri front-end when new log lines arrive.
 */

import { parseLine } from "./cleu.js";
import { SessionSegmenter } from "./session.js";
import { buildDeathRecaps } from "./death.js";
import { buildInterruptReport } from "./interrupt.js";
import { buildCCCoverage } from "./cc.js";
import { buildPerformanceReport } from "./performance.js";
import { buildDefensiveAudit } from "./defensive.js";
import { GuidResolver } from "../enrichment/guid.js";
import { serializeToLua, sessionToLuaValue } from "../serializer/savedvars.js";
import { persistAndAnalyze } from "../storage/trends.js";
import { getSessionSnapshots } from "../storage/sqlite.js";
import type { EncounterSession } from "./session.js";
import type { TrendReport, DistributionReport } from "../storage/sqlite.js";

export interface SessionOutput {
  session: EncounterSession;
  luaContent: string;
  sessionDbId: number;
}

export class ParserOrchestrator {
  private segmenter = new SessionSegmenter();
  /** Pre-converted session snapshots, newest first. Populated from SQLite on
   *  startup and prepended after each new fight. Max 19 entries (the 20th slot
   *  is always the live session being serialised). */
  private historicalSnapshots: Record<string, unknown>[] = [];

  /** Load the most recent sessions from SQLite so the addon immediately has
   *  full history even after a companion restart. Call once before listening. */
  async initialize(): Promise<void> {
    try {
      const raw = await getSessionSnapshots(19);
      this.historicalSnapshots = raw
        .filter((s) => s.length > 0)
        .map((s) => JSON.parse(s) as Record<string, unknown>);
      console.log(`[orchestrator] Loaded ${this.historicalSnapshots.length} historical session(s) from SQLite.`);
    } catch (err) {
      console.warn("[orchestrator] Failed to load historical snapshots:", err);
    }
  }

  /** Generate a Lua file from historical snapshots alone, for writing on startup
   *  before any fight has ended.  Returns null if there is no history yet. */
  generateStartupLua(): string | null {
    if (this.historicalSnapshots.length === 0) return null;
    return serializeToLua({
      version: 4,
      generatedAt: Math.floor(Date.now() / 1000),
      companionVersion: "1.3.5",
      sessions: [],
      historicalSnapshots: this.historicalSnapshots,
    });
  }

  /** Process a batch of new log lines. Returns completed sessions (if any). */
  async processLines(lines: string[]): Promise<SessionOutput[]> {
    const outputs: SessionOutput[] = [];

    for (const line of lines) {
      const result = parseLine(line);
      if (!result.ok) continue;

      const completedSessions = this.segmenter.feed(result.value);
      for (const completed of completedSessions) {
        const output = await this.processSession(completed);
        outputs.push(output);
      }
    }

    return outputs;
  }

  /** Wipe the in-memory snapshot history (called after a data purge). */
  clearHistory(): void {
    this.historicalSnapshots = [];
  }

  /** Force-close any open sessions (e.g. on app shutdown). */
  async flush(): Promise<SessionOutput[]> {
    const completedSessions = this.segmenter.flush();
    const outputs: SessionOutput[] = [];
    for (const completed of completedSessions) {
      outputs.push(await this.processSession(completed));
    }
    return outputs;
  }

  /** Build analysis output, persist to SQLite, and serialise to Lua. */
  private async processSession(session: EncounterSession): Promise<SessionOutput> {
    const resolver = new GuidResolver();
    resolver.populate(session.combatants);
    // COMBATANT_INFO events carry no player name — only a GUID.  Back-fill
    // real names from the combat events that followed (every CLEU event that
    // has a source/dest carries the name as a plain string in the log line).
    resolver.populateNamesFromEvents(session.events);

    // Patch real names back into session.combatants so serialisation emits
    // actual player names rather than the GUID-as-placeholder that
    // COMBATANT_INFO produces.  The resolver map is updated in-place by
    // populateNamesFromEvents() but session.combatants is a separate array.
    for (const c of session.combatants) {
      const info = resolver.resolve(c.guid);
      if (info && info.name !== info.guid) {
        c.name = info.name;
      }
    }

    const deaths = buildDeathRecaps(session, resolver);
    const interrupts = buildInterruptReport(session);
    const ccCoverage = buildCCCoverage(session);
    const performance = buildPerformanceReport(session, resolver, interrupts, deaths, ccCoverage);
    const defensiveAudit = buildDefensiveAudit(session, resolver, deaths);

    // Build a pre-converted snapshot for this session so it can be stored in
    // SQLite and reused as historical data in future companion runs.
    const snapshot = sessionToLuaValue(
      session, deaths, interrupts, ccCoverage, performance, defensiveAudit,
    ) as Record<string, unknown>;

    // Phase 3: persist to SQLite and retrieve trend/distribution data.
    let sessionDbId = 0;
    let trend: TrendReport | undefined;
    let distribution: DistributionReport | undefined;

    try {
      const analysis = await persistAndAnalyze(
        session, deaths, interrupts, ccCoverage, performance,
        JSON.stringify(snapshot),
      );
      sessionDbId = analysis.sessionDbId;
      trend = analysis.trend;
      distribution = analysis.distribution;
    } catch (err) {
      // SQLite unavailable (e.g. test environment) — continue without trends.
      console.warn("[orchestrator] SQLite persist failed, continuing without trends:", err);
    }

    // Serialise: current session via full analysis + up to 19 historical snapshots.
    const luaContent = serializeToLua({
      version: 4,
      generatedAt: Math.floor(Date.now() / 1000),
      companionVersion: "1.3.5",
      sessions: [{ session, deaths, interrupts, ccCoverage, performance, defensiveAudit }],
      historicalSnapshots: this.historicalSnapshots.slice(0, 19),
      ...(trend !== undefined ? { trend } : {}),
      ...(distribution !== undefined ? { distribution } : {}),
    });

    // Prepend this session's snapshot so subsequent fights in the same run
    // also include it as history (capped at 19 to leave room for the live session).
    this.historicalSnapshots = [snapshot, ...this.historicalSnapshots].slice(0, 19);

    return { session, luaContent, sessionDbId };
  }
}

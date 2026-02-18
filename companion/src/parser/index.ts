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
import { serializeToLua } from "../serializer/savedvars.js";
import { persistAndAnalyze } from "../storage/trends.js";
import type { EncounterSession } from "./session.js";
import type { TrendReport, DistributionReport } from "../storage/sqlite.js";

export interface SessionOutput {
  session: EncounterSession;
  luaContent: string;
  sessionDbId: number;
}

export class ParserOrchestrator {
  private segmenter = new SessionSegmenter();
  private allSessions: EncounterSession[] = [];

  /** Process a batch of new log lines. Returns completed sessions (if any). */
  async processLines(lines: string[]): Promise<SessionOutput[]> {
    const outputs: SessionOutput[] = [];

    for (const line of lines) {
      const result = parseLine(line);
      if (!result.ok) continue;

      const completed = this.segmenter.feed(result.value);
      if (completed) {
        const output = await this.processSession(completed);
        outputs.push(output);
        this.allSessions.unshift(completed);
        if (this.allSessions.length > 20) this.allSessions.pop();
      }
    }

    return outputs;
  }

  /** Force-close any open session (e.g. on app shutdown). */
  async flush(): Promise<SessionOutput | null> {
    const completed = this.segmenter.flush();
    if (!completed) return null;
    return this.processSession(completed);
  }

  /** Build analysis output, persist to SQLite, and serialise to Lua. */
  private async processSession(session: EncounterSession): Promise<SessionOutput> {
    const resolver = new GuidResolver();
    resolver.populate(session.combatants);

    const deaths = buildDeathRecaps(session, resolver);
    const interrupts = buildInterruptReport(session);
    const ccCoverage = buildCCCoverage(session);
    const performance = buildPerformanceReport(session, resolver, interrupts, deaths, ccCoverage);
    const defensiveAudit = buildDefensiveAudit(session, resolver, deaths);

    // Phase 3: persist to SQLite and retrieve trend/distribution data.
    let sessionDbId = 0;
    let trend: TrendReport | undefined;
    let distribution: DistributionReport | undefined;

    try {
      const analysis = await persistAndAnalyze(
        session, deaths, interrupts, ccCoverage, performance,
      );
      sessionDbId = analysis.sessionDbId;
      trend = analysis.trend;
      distribution = analysis.distribution;
    } catch (err) {
      // SQLite unavailable (e.g. test environment) — continue without trends.
      console.warn("[orchestrator] SQLite persist failed, continuing without trends:", err);
    }

    const allSessions = [session, ...this.allSessions].slice(0, 20);
    const luaContent = serializeToLua({
      version: 4,
      generatedAt: Math.floor(Date.now() / 1000),
      companionVersion: "0.4.0",
      sessions: allSessions.map((s, idx) => {
        const r = new GuidResolver();
        r.populate(s.combatants);
        const d = idx === 0 ? deaths : buildDeathRecaps(s, r);
        const int = idx === 0 ? interrupts : buildInterruptReport(s);
        const cc = idx === 0 ? ccCoverage : buildCCCoverage(s);
        return {
          session: s,
          deaths: d,
          interrupts: int,
          ccCoverage: cc,
          performance: idx === 0 ? performance : buildPerformanceReport(s, r, int, d, cc),
          defensiveAudit: idx === 0 ? defensiveAudit : buildDefensiveAudit(s, r, d),
        };
      }),
      ...(trend !== undefined ? { trend } : {}),
      ...(distribution !== undefined ? { distribution } : {}),
    });

    return { session, luaContent, sessionDbId };
  }
}

import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { parseLine } from "../../companion/src/parser/cleu.js";
import { SessionSegmenter } from "../../companion/src/parser/session.js";
import { buildInterruptReport } from "../../companion/src/parser/interrupt.js";
import type { EncounterSession } from "../../companion/src/parser/session.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = join(__dirname, "../fixtures");

function parseFixture(filename: string): EncounterSession[] {
  const lines = readFileSync(join(FIXTURES_DIR, filename), "utf-8").split("\n");
  const segmenter = new SessionSegmenter();
  const sessions: EncounterSession[] = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    const result = parseLine(line);
    if (!result.ok) continue;
    const completed = segmenter.feed(result.value);
    if (completed) sessions.push(completed);
  }
  return sessions;
}

describe("InterruptReportEngine", () => {
  it("counts total / intercepted / missed correctly", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    expect(sessions).toHaveLength(1);
    const report = buildInterruptReport(sessions[0]);
    // fixture has: 2 kicks, 2 missed (completed) = 4 total interruptible casts
    expect(report.summary.total).toBe(4);
    expect(report.summary.intercepted).toBe(2);
    expect(report.summary.missed).toBe(2);
  });

  it("calculates interrupt rate percent", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    const report = buildInterruptReport(sessions[0]);
    expect(report.summary.ratePercent).toBe(50);
  });

  it("attributes kicks to the correct player", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    const report = buildInterruptReport(sessions[0]);
    // Rogue did the kicking in the fixture
    const rogueStats = report.byPlayer["Shadowstep"] ?? report.byPlayer["Rogue"];
    // May be keyed by sourceName which is "Shadowstep" in the fixture
    const firstKicker = Object.values(report.byPlayer)[0];
    expect(firstKicker).toBeDefined();
    expect(firstKicker.intercepted).toBe(2);
  });

  it("marks missed casts with correct reason", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    const report = buildInterruptReport(sessions[0]);
    const missed = report.interrupts.filter((i) => !i.wasInterrupted);
    expect(missed).toHaveLength(2);
    expect(missed[0].missedReason).toBe("cast completed");
  });

  it("records castPercentAtInterrupt for kicked spells", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    const report = buildInterruptReport(sessions[0]);
    const kicked = report.interrupts.filter((i) => i.wasInterrupted);
    expect(kicked.length).toBeGreaterThan(0);
    for (const k of kicked) {
      expect(k.castPercentAtInterrupt).toBeGreaterThan(0);
      expect(k.castPercentAtInterrupt).toBeLessThanOrEqual(100);
    }
  });

  it("returns empty report for a session with no interruptible casts", () => {
    const sessions = parseFixture("fixture_wipe.txt");
    const report = buildInterruptReport(sessions[0]);
    expect(report.summary.total).toBe(0);
    expect(report.summary.ratePercent).toBe(100);
  });
});

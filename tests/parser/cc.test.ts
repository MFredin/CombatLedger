import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { parseLine } from "../../companion/src/parser/cleu.js";
import { SessionSegmenter } from "../../companion/src/parser/session.js";
import { buildCCCoverage } from "../../companion/src/parser/cc.js";
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

describe("CCCoverageEngine", () => {
  it("returns empty array for sessions with no CC events", () => {
    // Use an existing fixture that has no aura events (wipe fixture only has death/damage)
    const sessions = parseFixture("fixture_wipe.txt");
    expect(sessions.length).toBeGreaterThan(0);
    const result = buildCCCoverage(sessions[0]!);
    expect(result).toEqual([]);
  });

  it("produces two CCCoverage entries for two targets", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    expect(sessions.length).toBe(1);
    const coverage = buildCCCoverage(sessions[0]!);
    // Boss Alpha (NPC1) and Boss Beta (NPC2)
    expect(coverage).toHaveLength(2);
  });

  it("correctly identifies target names", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const names = coverage.map((c) => c.targetName).sort();
    expect(names).toContain("Boss Alpha");
    expect(names).toContain("Boss Beta");
  });

  it("tracks 3 segments for Boss Alpha (DR sequence)", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha");
    expect(alpha).toBeDefined();
    expect(alpha!.segments).toHaveLength(3);
  });

  it("first Kidney Shot has full DR (multiplier=1.0)", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    const first = alpha.segments[0]!;
    expect(first.drMultiplier).toBe(1.0);
    expect(first.drApplicationNumber).toBe(1);
    expect(first.wasImmune).toBe(false);
  });

  it("second Kidney Shot on same target has 50% DR", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    const second = alpha.segments[1]!;
    expect(second.drMultiplier).toBe(0.5);
    expect(second.drApplicationNumber).toBe(2);
    expect(second.wasImmune).toBe(false);
  });

  it("second Kidney Shot actual duration ≈ theoretical (3s = 6s × 0.5)", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    const second = alpha.segments[1]!;
    // theoretical = 6s * 0.5 = 3s; actual = 18s - 15s = 3s
    expect(second.actualDuration).toBeCloseTo(3.0, 1);
    expect(second.theoreticalDuration).toBeCloseTo(3.0, 1);
    expect(second.brokeEarly).toBe(false);
  });

  it("third Kidney Shot has DR reset (multiplier=1.0 again after >18s)", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    const third = alpha.segments[2]!;
    // t=40s applied, last CC ended at t=18s → 22s gap → DR reset
    expect(third.drMultiplier).toBe(1.0);
    expect(third.drApplicationNumber).toBe(1);
  });

  it("wastedCasts is 0 for Boss Alpha (no immune applications)", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    expect(alpha.wastedCasts).toBe(0);
  });

  it("Boss Alpha coveragePercent reflects 15s covered over ~41s combat", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    // Covered: 6s + 3s + 6s = 15s; combatDuration = t46 - t5 = 41s
    // coverage% = 15/41 * 100 ≈ 36.6
    expect(alpha.coveragePercent).toBeGreaterThan(30);
    expect(alpha.coveragePercent).toBeLessThan(45);
  });

  it("Hex on Boss Beta broke early due to damage", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const beta = coverage.find((c) => c.targetName === "Boss Beta")!;
    expect(beta).toBeDefined();
    expect(beta.segments).toHaveLength(1);
    const seg = beta.segments[0]!;
    // Hex base = 8s, DR1 = 1.0 → theoretical = 8s; actual = 25s - 20s = 5s
    expect(seg.theoreticalDuration).toBeCloseTo(8.0, 1);
    expect(seg.actualDuration).toBeCloseTo(5.0, 1);
    expect(seg.brokeEarly).toBe(true);
    expect(seg.brokeReason).toBe("damage");
  });

  it("Hex segment has full DR (first application)", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const beta = coverage.find((c) => c.targetName === "Boss Beta")!;
    const seg = beta.segments[0]!;
    expect(seg.drMultiplier).toBe(1.0);
    expect(seg.spellId).toBe(51514);
    expect(seg.ccCategory).toBe("incapacitate");
    expect(seg.wasImmune).toBe(false);
  });

  it("byCategory organises segments by DR category", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    expect(alpha.byCategory).toHaveProperty("stun");
    expect(alpha.byCategory["stun"]!.segments).toBe(3);
  });

  it("drHistory records DR applications for Boss Alpha", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    // 3 applications on stun category
    const stunHistory = alpha.drHistory.filter((h) => h.category === "stun");
    expect(stunHistory.length).toBe(3);
  });

  it("DR reset snapshot has didReset=true for third application", () => {
    const sessions = parseFixture("fixture_cc_basic.txt");
    const coverage = buildCCCoverage(sessions[0]!);
    const alpha = coverage.find((c) => c.targetName === "Boss Alpha")!;
    const stunHistory = alpha.drHistory.filter((h) => h.category === "stun");
    // Third entry should have didReset=true
    const third = stunHistory[2]!;
    expect(third.didReset).toBe(true);
    expect(third.drMultiplier).toBe(1.0);
    expect(third.applicationCount).toBe(1);
  });
});

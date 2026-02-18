import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { parseLine } from "../../companion/src/parser/cleu.js";
import { SessionSegmenter } from "../../companion/src/parser/session.js";
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

describe("SessionSegmenter", () => {
  it("produces 3 sessions from fixture_full_key.txt", () => {
    const sessions = parseFixture("fixture_full_key.txt");
    expect(sessions).toHaveLength(3);
  });

  it("correctly identifies success/wipe for each pull", () => {
    const sessions = parseFixture("fixture_full_key.txt");
    // Sessions are returned in order of completion (oldest first from feed)
    expect(sessions[0].success).toBe(false); // pull 1 — wipe
    expect(sessions[1].success).toBe(false); // pull 2 — wipe
    expect(sessions[2].success).toBe(true);  // pull 3 — kill
  });

  it("assigns pull numbers correctly", () => {
    const sessions = parseFixture("fixture_full_key.txt");
    expect(sessions[0].pullNumber).toBe(1);
    expect(sessions[1].pullNumber).toBe(2);
    expect(sessions[2].pullNumber).toBe(3);
  });

  it("populates combatants from COMBATANT_INFO", () => {
    const sessions = parseFixture("fixture_full_key.txt");
    expect(sessions[0].combatants.length).toBeGreaterThanOrEqual(2);
  });

  it("produces 1 session from simple wipe fixture", () => {
    const sessions = parseFixture("fixture_wipe.txt");
    expect(sessions).toHaveLength(1);
    expect(sessions[0].success).toBe(false);
  });

  it("collects events within encounter boundaries", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    expect(sessions).toHaveLength(1);
    // Events should include cast starts, interrupts, successes
    const subevents = sessions[0].events.map((e) => e.subevent);
    expect(subevents).toContain("SPELL_CAST_START");
    expect(subevents).toContain("SPELL_INTERRUPT");
  });
});

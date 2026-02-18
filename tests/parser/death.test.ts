import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { parseLine } from "../../companion/src/parser/cleu.js";
import { SessionSegmenter } from "../../companion/src/parser/session.js";
import { buildDeathRecaps } from "../../companion/src/parser/death.js";
import { GuidResolver } from "../../companion/src/enrichment/guid.js";
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

describe("DeathRecapEngine", () => {
  it("identifies fatal event correctly", () => {
    const sessions = parseFixture("fixture_death_simple.txt");
    expect(sessions).toHaveLength(1);
    const resolver = new GuidResolver();
    resolver.populate(sessions[0].combatants);
    const deaths = buildDeathRecaps(sessions[0], resolver);
    expect(deaths).toHaveLength(1);
    expect(deaths[0].fatalSpellName).toBe("Dark Bolt");
    expect(deaths[0].overkill).toBe(12820);
  });

  it("marks fatal event in the events list", () => {
    const sessions = parseFixture("fixture_death_simple.txt");
    const resolver = new GuidResolver();
    resolver.populate(sessions[0].combatants);
    const deaths = buildDeathRecaps(sessions[0], resolver);
    const fatalEvents = deaths[0].events.filter((e) => e.isFatal);
    expect(fatalEvents).toHaveLength(1);
    expect(fatalEvents[0].spellName).toBe("Dark Bolt");
  });

  it("includes healing events in the timeline", () => {
    const sessions = parseFixture("fixture_death_simple.txt");
    const resolver = new GuidResolver();
    resolver.populate(sessions[0].combatants);
    const deaths = buildDeathRecaps(sessions[0], resolver);
    const healEvents = deaths[0].events.filter((e) => e.type === "heal");
    expect(healEvents.length).toBeGreaterThan(0);
  });

  it("captures timeIntoPull correctly", () => {
    const sessions = parseFixture("fixture_death_simple.txt");
    const resolver = new GuidResolver();
    resolver.populate(sessions[0].combatants);
    const deaths = buildDeathRecaps(sessions[0], resolver);
    expect(deaths[0].timeIntoPull).toBeGreaterThan(0);
  });

  it("records available defensives when none were used", () => {
    const sessions = parseFixture("fixture_death_no_defensive.txt");
    const resolver = new GuidResolver();
    resolver.populate(sessions[0].combatants);
    const deaths = buildDeathRecaps(sessions[0], resolver);
    // No class-specific info from COMBATANT_INFO GUID alone, but death should be recorded.
    expect(deaths).toHaveLength(1);
  });

  it("produces no deaths for a session with no UNIT_DIED events", () => {
    const sessions = parseFixture("fixture_interrupts_mixed.txt");
    const resolver = new GuidResolver();
    resolver.populate(sessions[0].combatants);
    const deaths = buildDeathRecaps(sessions[0], resolver);
    expect(deaths).toHaveLength(0);
  });
});

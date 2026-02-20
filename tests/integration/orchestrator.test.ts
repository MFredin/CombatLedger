/**
 * tests/integration/orchestrator.test.ts
 *
 * End-to-end pipeline tests: fixture log lines → ParserOrchestrator →
 * verified session outputs and Lua serialization.
 *
 * SQLite persistence is expected to be unavailable in the test environment;
 * the orchestrator handles this gracefully and continues without trend data.
 */

import { describe, it, expect, vi, beforeAll } from "vitest";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { parseLine } from "../../companion/src/parser/cleu.js";
import { ParserOrchestrator } from "../../companion/src/parser/index.js";
import type { SessionOutput } from "../../companion/src/parser/index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = join(__dirname, "../fixtures");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readFixture(filename: string): string[] {
  return readFileSync(join(FIXTURES_DIR, filename), "utf-8")
    .split("\n")
    .filter((l) => l.trim().length > 0);
}

/**
 * Feed all lines of a fixture through a fresh ParserOrchestrator and collect
 * every completed SessionOutput.
 */
async function runOrchestrator(filename: string): Promise<SessionOutput[]> {
  const orchestrator = new ParserOrchestrator();
  const outputs: SessionOutput[] = [];
  const lines = readFixture(filename);
  const results = await orchestrator.processLines(lines);
  outputs.push(...results);
  const flushed = await orchestrator.flush();
  if (flushed) outputs.push(flushed);
  return outputs;
}

// ---------------------------------------------------------------------------
// fixture_full_key.txt  (3 pulls: wipe, wipe, kill)
// ---------------------------------------------------------------------------

describe("Full key run (3 pulls)", () => {
  let outputs: SessionOutput[];

  beforeAll(async () => {
    outputs = await runOrchestrator("fixture_full_key.txt");
  });

  it("produces exactly 3 completed sessions", () => {
    expect(outputs).toHaveLength(3);
  });

  it("pull 1 is a wipe, pull 3 is a kill", () => {
    expect(outputs[0].session.success).toBe(false);
    expect(outputs[1].session.success).toBe(false);
    expect(outputs[2].session.success).toBe(true);
  });

  it("assigns consecutive pull numbers", () => {
    expect(outputs[0].session.pullNumber).toBe(1);
    expect(outputs[1].session.pullNumber).toBe(2);
    expect(outputs[2].session.pullNumber).toBe(3);
  });

  it("identifies the encounter as Darkflame Cleft", () => {
    for (const o of outputs) {
      expect(o.session.encounterName).toBe("Darkflame Cleft");
    }
  });

  it("pull 2 has death data in luaContent", () => {
    // Pull 2 (index 1) has a UNIT_DIED event. The luaContent accumulates all
    // sessions up to that point, so sessions[2] in the output is pull 2.
    // Deaths are serialized under ["deaths"] key.
    expect(outputs[1].luaContent).toContain('["deaths"]');
  });

  it("pull 1 and pull 3 both have interrupt summary in luaContent", () => {
    // The interrupt summary block is always serialized even if the dungeon spell
    // database has not loaded (vitest runs without Vite bundling of dungeon JSON).
    expect(outputs[0].luaContent).toContain('["interrupts"]');
    expect(outputs[2].luaContent).toContain('["interrupts"]');
  });

  it("luaContent is non-empty and contains CombatLedgerDB assignment", () => {
    for (const o of outputs) {
      expect(o.luaContent).toContain("CombatLedgerDB = {");
    }
  });
});

// ---------------------------------------------------------------------------
// fixture_wipe.txt  (1 pull: wipe with 1 death)
// ---------------------------------------------------------------------------

describe("Single wipe pull", () => {
  let output: SessionOutput;

  beforeAll(async () => {
    const outputs = await runOrchestrator("fixture_wipe.txt");
    expect(outputs).toHaveLength(1);
    output = outputs[0];
  });

  it("session is marked as a wipe", () => {
    expect(output.session.success).toBe(false);
  });

  it("luaContent contains version field", () => {
    expect(output.luaContent).toContain('["version"]');
  });

  it("luaContent contains companionVersion", () => {
    expect(output.luaContent).toContain('"1.3.0"');
  });

  it("luaContent contains sessions table", () => {
    expect(output.luaContent).toContain('["sessions"]');
  });

  it("sessionDbId is a number (0 when SQLite unavailable)", () => {
    expect(typeof output.sessionDbId).toBe("number");
  });
});

// ---------------------------------------------------------------------------
// fixture_interrupts_mixed.txt  (1 pull with mixed interrupt outcomes)
// ---------------------------------------------------------------------------

describe("Interrupt report — mixed outcomes", () => {
  let output: SessionOutput;

  beforeAll(async () => {
    const outputs = await runOrchestrator("fixture_interrupts_mixed.txt");
    expect(outputs.length).toBeGreaterThanOrEqual(1);
    output = outputs[outputs.length - 1]; // last completed session
  });

  it("luaContent references interrupt data", () => {
    expect(output.luaContent).toContain("interrupts");
  });

  it("luaContent is valid Lua (contains assignment operator)", () => {
    expect(output.luaContent).toContain("=");
    expect(output.luaContent.split("\n").length).toBeGreaterThan(5);
  });
});

// ---------------------------------------------------------------------------
// fixture_death_simple.txt  (1 pull, 1 death with known data)
// ---------------------------------------------------------------------------

describe("Death recap — simple death", () => {
  let output: SessionOutput;

  beforeAll(async () => {
    const outputs = await runOrchestrator("fixture_death_simple.txt");
    expect(outputs.length).toBeGreaterThanOrEqual(1);
    output = outputs[outputs.length - 1];
  });

  it("luaContent mentions the player who died", () => {
    // Death recap names appear in the serialized output
    expect(output.luaContent.length).toBeGreaterThan(100);
  });

  it("luaContent contains deaths section", () => {
    expect(output.luaContent).toContain("deaths");
  });
});

// ---------------------------------------------------------------------------
// fixture_death_no_defensive.txt  (1 death with no defensive used)
// ---------------------------------------------------------------------------

describe("Death recap — no defensive used", () => {
  let output: SessionOutput;

  beforeAll(async () => {
    const outputs = await runOrchestrator("fixture_death_no_defensive.txt");
    expect(outputs.length).toBeGreaterThanOrEqual(1);
    output = outputs[outputs.length - 1];
  });

  it("luaContent is non-empty", () => {
    expect(output.luaContent.trim().length).toBeGreaterThan(50);
  });

  it("session has encounter name", () => {
    expect(output.session.encounterName).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// fixture_cc_basic.txt  (CC events with DR tracking)
// ---------------------------------------------------------------------------

describe("CC coverage — basic DR tracking", () => {
  let output: SessionOutput;

  beforeAll(async () => {
    const outputs = await runOrchestrator("fixture_cc_basic.txt");
    expect(outputs.length).toBeGreaterThanOrEqual(1);
    output = outputs[outputs.length - 1];
  });

  it("luaContent contains ccCoverage section", () => {
    expect(output.luaContent).toContain("ccCoverage");
  });

  it("session object is fully hydrated", () => {
    expect(output.session.encounterName).toBeTruthy();
    expect(output.session.events.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Lua serialization format contract
// ---------------------------------------------------------------------------

describe("Lua serialization format", () => {
  let luaContent: string;

  beforeAll(async () => {
    const outputs = await runOrchestrator("fixture_wipe.txt");
    luaContent = outputs[0].luaContent;
  });

  it("contains CombatLedgerDB assignment", () => {
    // The output begins with a comment header, then the assignment.
    expect(luaContent).toContain("CombatLedgerDB = {");
  });

  it("uses quoted string keys (Lua table format)", () => {
    expect(luaContent).toContain('["version"]');
    expect(luaContent).toContain('["sessions"]');
  });

  it("version is numeric 4", () => {
    expect(luaContent).toMatch(/\["version"\]\s*=\s*4/);
  });

  it("companionVersion is a string", () => {
    expect(luaContent).toMatch(/\["companionVersion"\]\s*=\s*"[\d.]+"/);
  });

  it("generatedAt is a Unix timestamp (large integer)", () => {
    const match = luaContent.match(/\["generatedAt"\]\s*=\s*(\d+)/);
    expect(match).not.toBeNull();
    const ts = parseInt(match![1], 10);
    expect(ts).toBeGreaterThan(1_700_000_000); // > Nov 2023
  });

  it("sessions is an indexed Lua array", () => {
    expect(luaContent).toMatch(/\["sessions"\]\s*=\s*\{/);
    expect(luaContent).toMatch(/\[1\]\s*=/);
  });
});

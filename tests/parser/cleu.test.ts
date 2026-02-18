import { describe, it, expect } from "vitest";
import { parseLine, isPlayer, isEnemy, UNIT_FLAGS } from "../../companion/src/parser/cleu.js";

describe("parseLine", () => {
  it("parses ENCOUNTER_START", () => {
    const line = `8/17 20:10:00.000  ENCOUNTER_START,2660,"Darkflame Cleft",8,5`;
    const result = parseLine(line);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.subevent).toBe("ENCOUNTER_START");
    const ev = result.value as { subevent: string; encounterId: number; encounterName: string; difficulty: number; groupSize: number };
    expect(ev.encounterId).toBe(2660);
    expect(ev.encounterName).toBe("Darkflame Cleft");
    expect(ev.difficulty).toBe(8);
    expect(ev.groupSize).toBe(5);
  });

  it("parses ENCOUNTER_END with success=true", () => {
    const line = `8/17 20:30:45.000  ENCOUNTER_END,2660,"Darkflame Cleft",8,5,1`;
    const result = parseLine(line);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const ev = result.value as { subevent: string; success: boolean };
    expect(ev.subevent).toBe("ENCOUNTER_END");
    expect(ev.success).toBe(true);
  });

  it("parses ENCOUNTER_END with success=false", () => {
    const line = `8/17 20:30:45.000  ENCOUNTER_END,2660,"Darkflame Cleft",8,5,0`;
    const result = parseLine(line);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const ev = result.value as { success: boolean };
    expect(ev.success).toBe(false);
  });

  it("parses SPELL_DAMAGE with overkill", () => {
    const line = `8/17 20:14:44.900  SPELL_DAMAGE,Creature-0-1234-2660-0-12346-0001,"Umbral Tender",0x10a48,0x0,Player-1234-AABBCC01,"Valdris",0x511,0x0,453620,"Dark Bolt",4,31000,12820,0,0,0,nil,1`;
    const result = parseLine(line);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const ev = result.value as { subevent: string; amount: number; overkill: number; critical: boolean };
    expect(ev.subevent).toBe("SPELL_DAMAGE");
    expect(ev.amount).toBe(31000);
    expect(ev.overkill).toBe(12820);
    expect(ev.critical).toBe(true);
  });

  it("parses SPELL_INTERRUPT", () => {
    const line = `8/17 20:30:11.500  SPELL_INTERRUPT,Player-1234-ROGUE001,"Shadowstep",0x511,0x0,Creature-0-1234-2660-0-12346-0000,"Umbral Tender",0x10a48,0x0,1766,"Kick",1,453620,"Dark Bolt",4`;
    const result = parseLine(line);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const ev = result.value as { subevent: string; extraSpellId: number; spellId: number };
    expect(ev.subevent).toBe("SPELL_INTERRUPT");
    expect(ev.spellId).toBe(1766);
    expect(ev.extraSpellId).toBe(453620);
  });

  it("parses UNIT_DIED", () => {
    const line = `8/17 20:14:45.000  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-1234-AABBCC01,"Valdris",0x511,0x0,nil`;
    const result = parseLine(line);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.subevent).toBe("UNIT_DIED");
  });

  it("returns error on malformed line", () => {
    const result = parseLine("not a valid log line");
    expect(result.ok).toBe(false);
  });

  it("does not throw on garbage input", () => {
    expect(() => parseLine("")).not.toThrow();
    expect(() => parseLine("   ")).not.toThrow();
    expect(() => parseLine("garbage,data,here")).not.toThrow();
  });
});

describe("unit flag helpers", () => {
  it("isPlayer returns true for player flag", () => {
    expect(isPlayer(0x511)).toBe(true);
  });

  it("isEnemy returns true for hostile flag", () => {
    expect(isEnemy(0x10a48)).toBe(true);
  });

  it("isPlayer returns false for NPC", () => {
    expect(isPlayer(0x10a48)).toBe(false);
  });
});

/**
 * spelldb.ts — Spell metadata lookup
 *
 * Data is loaded via Vite static imports (import.meta.glob) so this module
 * works in both the Tauri WebView (no Node.js fs available) and in Vitest.
 * All JSON is bundled at build time — no runtime filesystem access needed.
 */

/// <reference types="vite/client" />

export interface PlayerSpell {
  name: string;
  class?: string;
  type: "interrupt" | "cc" | "defensive" | "other";
  interruptible?: boolean;
  cooldownSec?: number;
  ccCategory?: string;
  durationSec?: number;
  breakOnDamage?: boolean;
  notes?: string;
}

export interface EnemySpell {
  name: string;
  casterId?: number;
  casterName?: string;
  interruptible: boolean;
  castDurationSec: number;
  priority?: "high" | "medium" | "low" | "avoid";
  notes?: string;
}

export interface DefensiveSpell {
  spellId: number;
  name: string;
  durationSec: number;
  cooldownSec: number;
  isExternal?: boolean;
  notes?: string;
}

/** An external defensive (e.g. Ironbark, Pain Suppression) applied to another player. */
export interface ExternalDefensive {
  name: string;
  class: string;
  spec: string;        // "any" or specific spec name
  durationSec: number;
  cooldownSec: number;
  isExternal: boolean;
  notes?: string;
}

export interface RaidEncounter {
  name: string;
  difficulty: number[];
  interruptibleSpells: Record<string, EnemySpell>;
}

export interface DrCategory {
  resetTimerSec: number;
  pvpImmunityAfter: number;
  pveImmunityAfter: number;
  spells: number[];
}

interface SpellDatabase {
  spells: Record<string, PlayerSpell>;
  enemySpells: {
    dungeons: Record<string, Record<string, EnemySpell>>;
  };
  defensives: Record<string, Record<string, DefensiveSpell[]>>;
  drCategories: Record<string, DrCategory>;
}

interface RaidDatabase {
  encounters: Record<string, RaidEncounter>;
  externalDefensives: Record<string, ExternalDefensive>;
}

// ---------------------------------------------------------------------------
// Static data loading via Vite bundler (works in WebView + Vitest)
// ---------------------------------------------------------------------------

// Base spell database — bundled at build time.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
import baseDbRaw from "../../../data/spells/base.json" with { type: "json" };

// All raid JSON files discovered and bundled at build time.
// import.meta.glob is a Vite/Vitest feature resolved at build time.
const _raidFileModules = import.meta.glob(
  "../../../data/spells/raids/*.json",
  { eager: true, import: "default" },
);

// Individual dungeon spell files (one per dungeon key, e.g. darkflame-cleft.json).
// Merged over the inline base.json dungeon entries — file data takes precedence.
const _dungeonFileModules = import.meta.glob(
  "../../../data/spells/dungeons/*.json",
  { eager: true, import: "default" },
);

function buildDungeonDb(): Record<string, Record<string, EnemySpell>> {
  const merged: Record<string, Record<string, EnemySpell>> = {};
  for (const [path, mod] of Object.entries(_dungeonFileModules)) {
    // Derive dungeon key from filename: ".../darkflame-cleft.json" → "darkflame-cleft"
    const key = path.split("/").pop()?.replace(".json", "") ?? "";
    const data = mod as { spells?: Record<string, EnemySpell> };
    if (key && data.spells) {
      merged[key] = data.spells;
    }
  }
  return merged;
}

const _dungeonDb = buildDungeonDb();

// Merge individual dungeon files over inline base.json entries.
const _rawDb = baseDbRaw as unknown as SpellDatabase;
const _db: SpellDatabase = {
  ..._rawDb,
  enemySpells: {
    dungeons: {
      ..._rawDb.enemySpells.dungeons,
      ..._dungeonDb,
    },
  },
};

function buildRaidDb(): RaidDatabase {
  const merged: RaidDatabase = { encounters: {}, externalDefensives: {} };
  for (const mod of Object.values(_raidFileModules)) {
    const data = mod as { encounters?: Record<string, RaidEncounter>; externalDefensives?: Record<string, ExternalDefensive> };
    Object.assign(merged.encounters, data.encounters ?? {});
    Object.assign(merged.externalDefensives, data.externalDefensives ?? {});
  }
  return merged;
}

const _raidDb: RaidDatabase = buildRaidDb();

// ---------------------------------------------------------------------------
// Dungeon / base spell lookups
// ---------------------------------------------------------------------------

export function getPlayerSpell(spellId: number): PlayerSpell | undefined {
  return _db.spells[String(spellId)];
}

export function getEnemySpell(
  dungeon: string,
  spellId: number
): EnemySpell | undefined {
  return _db.enemySpells.dungeons[dungeon]?.[String(spellId)];
}

export function getDefensives(
  cls: string,
  spec: string
): DefensiveSpell[] {
  return _db.defensives[cls]?.[spec] ?? [];
}

export function getDrCategories(): Record<string, DrCategory> {
  return _db.drCategories;
}

/** Return the DR category name for a given spell ID, or undefined. */
export function getDrCategoryForSpell(spellId: number): string | undefined {
  const cats = getDrCategories();
  for (const [catName, cat] of Object.entries(cats)) {
    if (cat.spells.includes(spellId)) return catName;
  }
  return undefined;
}

/** Return whether the given spell ID is flagged as interruptible (enemy spell). */
export function isInterruptible(dungeon: string, spellId: number): boolean {
  return getEnemySpell(dungeon, spellId)?.interruptible ?? false;
}

// ---------------------------------------------------------------------------
// Raid lookups (Phase 3.5)
// ---------------------------------------------------------------------------

/** Return raid encounter metadata by encounter ID, or undefined. */
export function getRaidEncounter(encounterId: number): RaidEncounter | undefined {
  return _raidDb.encounters[String(encounterId)];
}

/** Return all interruptible spells for a raid encounter. */
export function getRaidInterruptibleSpells(
  encounterId: number
): Record<string, EnemySpell> {
  return getRaidEncounter(encounterId)?.interruptibleSpells ?? {};
}

/** Return external defensive metadata by spell ID, or undefined. */
export function getExternalDefensive(spellId: number): ExternalDefensive | undefined {
  return _raidDb.externalDefensives[String(spellId)];
}

/** Return all external defensive spell IDs. */
export function getAllExternalDefensiveIds(): number[] {
  return Object.keys(_raidDb.externalDefensives).map(Number);
}

/** True if a spell ID is a known external defensive applied to another player. */
export function isExternalDefensive(spellId: number): boolean {
  return getExternalDefensive(spellId)?.isExternal ?? false;
}

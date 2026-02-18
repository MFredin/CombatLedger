/**
 * spelldb.ts — Spell metadata lookup
 *
 * Loads data/spells/base.json, dungeon-specific JSON files, and Phase 3.5
 * raid spell data from data/spells/raids/*.json.
 * Provides fast O(1) lookups by spell ID.
 */

import { readFileSync, readdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(__dirname, "../../data");

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

let _db: SpellDatabase | null = null;
let _raidDb: RaidDatabase | null = null;

function loadDb(): SpellDatabase {
  if (_db) return _db;
  const raw = readFileSync(join(DATA_DIR, "spells/base.json"), "utf-8");
  _db = JSON.parse(raw) as SpellDatabase;
  return _db;
}

function loadRaidDb(): RaidDatabase {
  if (_raidDb) return _raidDb;

  const merged: RaidDatabase = { encounters: {}, externalDefensives: {} };
  const raidsDir = join(DATA_DIR, "spells/raids");

  try {
    const files = readdirSync(raidsDir).filter((f) => f.endsWith(".json"));
    for (const file of files) {
      const raw = readFileSync(join(raidsDir, file), "utf-8");
      const data = JSON.parse(raw);
      Object.assign(merged.encounters, data.encounters ?? {});
      Object.assign(merged.externalDefensives, data.externalDefensives ?? {});
    }
  } catch {
    // Raids directory absent — silently proceed without raid data.
  }

  _raidDb = merged;
  return _raidDb;
}

// ---------------------------------------------------------------------------
// Dungeon / base spell lookups
// ---------------------------------------------------------------------------

export function getPlayerSpell(spellId: number): PlayerSpell | undefined {
  return loadDb().spells[String(spellId)];
}

export function getEnemySpell(
  dungeon: string,
  spellId: number
): EnemySpell | undefined {
  return loadDb().enemySpells.dungeons[dungeon]?.[String(spellId)];
}

export function getDefensives(
  cls: string,
  spec: string
): DefensiveSpell[] {
  return loadDb().defensives[cls]?.[spec] ?? [];
}

export function getDrCategories(): Record<string, DrCategory> {
  return loadDb().drCategories;
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
  return loadRaidDb().encounters[String(encounterId)];
}

/** Return all interruptible spells for a raid encounter. */
export function getRaidInterruptibleSpells(
  encounterId: number
): Record<string, EnemySpell> {
  return getRaidEncounter(encounterId)?.interruptibleSpells ?? {};
}

/** Return external defensive metadata by spell ID, or undefined. */
export function getExternalDefensive(spellId: number): ExternalDefensive | undefined {
  return loadRaidDb().externalDefensives[String(spellId)];
}

/** Return all external defensive spell IDs. */
export function getAllExternalDefensiveIds(): number[] {
  return Object.keys(loadRaidDb().externalDefensives).map(Number);
}

/** True if a spell ID is a known external defensive applied to another player. */
export function isExternalDefensive(spellId: number): boolean {
  return getExternalDefensive(spellId)?.isExternal ?? false;
}

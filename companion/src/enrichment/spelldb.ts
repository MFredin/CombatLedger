/**
 * spelldb.ts — Spell metadata lookup
 *
 * Loads data/spells/base.json and dungeon-specific JSON files.
 * Provides fast O(1) lookups by spell ID.
 */

import { readFileSync } from "fs";
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

let _db: SpellDatabase | null = null;

function loadDb(): SpellDatabase {
  if (_db) return _db;
  const raw = readFileSync(join(DATA_DIR, "spells/base.json"), "utf-8");
  _db = JSON.parse(raw) as SpellDatabase;
  return _db;
}

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

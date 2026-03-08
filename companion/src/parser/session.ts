/**
 * session.ts — Session/encounter segmentation
 *
 * Groups a stream of ParsedEvents into EncounterSession objects bounded by
 * ENCOUNTER_START / ENCOUNTER_END events (boss pulls) or detected hostile
 * combat activity outside boss encounters (trash pulls).
 *
 * Trash pulls are detected by scanning for hostile CLEU events outside of any
 * boss encounter.  A trash pull ends when there is a gap of >= TRASH_GAP_MS
 * with no new hostile combat, or when an ENCOUNTER_START fires.
 *
 * feed() returns EncounterSession[] to allow emitting a closing trash session
 * and signalling a new boss session in the same tick.
 */

import type {
  ParsedEvent,
  EncounterStartEvent,
  EncounterEndEvent,
  CombatantInfoEvent,
} from "./cleu.js";
import { isEnemy, isPlayer } from "./cleu.js";

export interface CombatantInfo {
  guid: string;
  name: string;
  specId: number;
}

export interface EncounterSession {
  /** Identifies which zone visit (dungeon run / raid lockout) this pull belongs to.
   *  All sessions with the same runId were recorded in the same continuous zone session.
   *  Resets on ZONE_CHANGED_NEW_AREA. */
  runId: string;
  /** Discriminates between tracked boss encounters and detected trash pulls. */
  pullType: "boss" | "trash";
  encounterId: number;
  encounterName: string;
  difficulty: number;
  groupSize: number;
  startTime: Date;
  endTime: Date;
  success: boolean;
  pullNumber: number;       // 1-indexed within the zone session
  events: ParsedEvent[];
  combatants: CombatantInfo[];
}

/** Generate a lightweight unique ID without importing crypto. */
function newRunId(): string {
  const t = Date.now().toString(36);
  const r = Math.random().toString(36).slice(2, 9);
  return `${t}-${r}`;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_SESSIONS = 20;

/** Gap in milliseconds without hostile combat that ends a trash pull. */
const TRASH_GAP_MS = 20_000;

/** Minimum number of hostile combat events to qualify as a real trash pull. */
const TRASH_MIN_EVENTS = 5;

/** CLEU subevents that indicate active hostile combat (enemy attacking players). */
const HOSTILE_SUBEVENTS = new Set([
  "SPELL_DAMAGE",
  "SPELL_PERIODIC_DAMAGE",
  "SWING_DAMAGE",
  "RANGE_DAMAGE",
  "SPELL_CAST_SUCCESS",
  "SPELL_CAST_START",
  "UNIT_DIED",
]);

// ---------------------------------------------------------------------------
// SessionSegmenter — stateful, fed lines one at a time
// ---------------------------------------------------------------------------

export class SessionSegmenter {
  private sessions: EncounterSession[] = [];

  // Boss pull state
  private currentSession: Partial<EncounterSession> | null = null;
  private currentEvents: ParsedEvent[] = [];
  private currentCombatants: CombatantInfo[] = [];

  // Trash pull state
  private trashActive = false;
  private trashEvents: ParsedEvent[] = [];
  private trashStart: Date | null = null;
  private trashLastCombatMs = 0;
  private trashEventCount = 0;

  // Shared state
  private pullNumber = 1;
  private runId = newRunId();

  /** Combatants/difficulty/groupSize from the most recently completed boss pull,
   *  used to annotate trash sessions that don't have COMBATANT_INFO events. */
  private lastKnownCombatants: CombatantInfo[] = [];
  private lastKnownDifficulty = 0;
  private lastKnownGroupSize = 0;

  /** Feed a parsed event. Returns any sessions that just completed. */
  feed(event: ParsedEvent): EncounterSession[] {
    const completed: EncounterSession[] = [];

    switch (event.subevent) {
      case "ZONE_CHANGED_NEW_AREA": {
        // Close any open trash pull (not enough to be "successful").
        const trashSession = this.closeTrashPull(event.timestamp, false);
        if (trashSession) completed.push(trashSession);

        // Close any stale boss session.
        if (this.currentSession) {
          const bossSession = this.closeCurrentSession(event.timestamp, false);
          completed.push(bossSession);
        }

        // Reset zone-specific state.
        this.pullNumber = 1;
        this.runId = newRunId();
        this.lastKnownCombatants = [];
        this.lastKnownDifficulty = 0;
        this.lastKnownGroupSize = 0;
        break;
      }

      case "ENCOUNTER_START": {
        const e = event as EncounterStartEvent;

        // Close any open trash pull — entering a boss fight means the trash
        // pull ended successfully.
        const trashSession = this.closeTrashPull(e.timestamp, true);
        if (trashSession) completed.push(trashSession);

        // Close any stale boss session (prev pull wiped without ENCOUNTER_END).
        if (this.currentSession) {
          const bossSession = this.closeCurrentSession(e.timestamp, false);
          completed.push(bossSession);
        }

        this.currentSession = {
          runId: this.runId,
          pullType: "boss",
          encounterId: e.encounterId,
          encounterName: e.encounterName,
          difficulty: e.difficulty,
          groupSize: e.groupSize,
          startTime: e.timestamp,
          pullNumber: this.pullNumber,
        };
        this.currentEvents = [];
        this.currentCombatants = [];
        break;
      }

      case "COMBATANT_INFO": {
        const c = event as CombatantInfoEvent;
        this.currentCombatants.push({
          guid: c.playerGUID,
          name: c.playerGUID,
          specId: c.currentSpecId,
        });
        break;
      }

      case "ENCOUNTER_END": {
        const e = event as EncounterEndEvent;
        if (!this.currentSession) break;
        const bossSession = this.closeCurrentSession(e.timestamp, e.success);
        completed.push(bossSession);

        // Persist roster/context for annotating subsequent trash pulls.
        this.lastKnownCombatants = [...bossSession.combatants];
        this.lastKnownDifficulty = bossSession.difficulty;
        this.lastKnownGroupSize = bossSession.groupSize;

        this.pullNumber++;
        break;
      }

      default: {
        // Always accumulate into the current boss session when inside one.
        if (this.currentSession) {
          this.currentEvents.push(event);
          break;
        }

        // Outside a boss session: check for hostile combat events to drive
        // trash pull detection.
        if (!HOSTILE_SUBEVENTS.has(event.subevent)) break;

        const ev = event as Partial<{
          sourceFlags: number;
          destFlags: number;
          sourceName: string;
          destName: string;
        }>;

        // We care about events where an enemy is the source (attacking players)
        // OR where a player is the dest being hit by an enemy.
        const enemyIsSource = ev.sourceFlags !== undefined && isEnemy(ev.sourceFlags);
        const playerIsDest = ev.destFlags !== undefined && isPlayer(ev.destFlags);

        if (!enemyIsSource && !playerIsDest) break;

        const eventMs = event.timestamp.getTime();

        // Check if an active trash pull has gone stale (gap exceeded).
        if (this.trashActive && eventMs - this.trashLastCombatMs > TRASH_GAP_MS) {
          const closeTs = new Date(this.trashLastCombatMs);
          const trashSession = this.closeTrashPull(closeTs, false);
          if (trashSession) completed.push(trashSession);
        }

        // Start a new trash pull if none is active.
        if (!this.trashActive) {
          this.trashActive = true;
          this.trashEvents = [];
          this.trashStart = event.timestamp;
          this.trashEventCount = 0;
        }

        this.trashEvents.push(event);
        this.trashLastCombatMs = eventMs;
        this.trashEventCount++;
        break;
      }
    }

    return completed;
  }

  /** Force-close any open sessions (e.g. on process shutdown). */
  flush(): EncounterSession[] {
    const completed: EncounterSession[] = [];
    const now = new Date();

    const trashSession = this.closeTrashPull(now, false);
    if (trashSession) completed.push(trashSession);

    if (this.currentSession) {
      completed.push(this.closeCurrentSession(now, false));
    }

    return completed;
  }

  getSessions(): EncounterSession[] {
    return [...this.sessions];
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /** Close the active trash pull and emit a session if it had enough events. */
  private closeTrashPull(endTime: Date, success: boolean): EncounterSession | null {
    if (!this.trashActive) return null;

    this.trashActive = false;

    if (this.trashEventCount < TRASH_MIN_EVENTS) {
      // Too sparse — discard, don't emit a session.
      this.trashEvents = [];
      this.trashStart = null;
      return null;
    }

    const session: EncounterSession = {
      runId: this.runId,
      pullType: "trash",
      encounterId: 0,
      encounterName: "Trash",
      difficulty: this.lastKnownDifficulty,
      groupSize: this.lastKnownGroupSize,
      startTime: this.trashStart!,
      endTime,
      success,
      pullNumber: this.pullNumber,
      events: [...this.trashEvents],
      combatants: [...this.lastKnownCombatants],
    };

    this.trashEvents = [];
    this.trashStart = null;
    this.pullNumber++;

    this.sessions.unshift(session);
    if (this.sessions.length > MAX_SESSIONS) {
      this.sessions.pop();
    }

    return session;
  }

  private closeCurrentSession(endTime: Date, success: boolean): EncounterSession {
    const partial = this.currentSession!;
    const session: EncounterSession = {
      runId: partial.runId ?? this.runId,
      pullType: "boss",
      encounterId: partial.encounterId ?? 0,
      encounterName: partial.encounterName ?? "Unknown",
      difficulty: partial.difficulty ?? 0,
      groupSize: partial.groupSize ?? 0,
      startTime: partial.startTime ?? endTime,
      endTime,
      success,
      pullNumber: partial.pullNumber ?? this.pullNumber,
      events: [...this.currentEvents],
      combatants: [...this.currentCombatants],
    };

    this.sessions.unshift(session);
    if (this.sessions.length > MAX_SESSIONS) {
      this.sessions.pop();
    }

    this.currentSession = null;
    this.currentEvents = [];
    this.currentCombatants = [];
    return session;
  }
}

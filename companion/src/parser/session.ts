/**
 * session.ts — Session/encounter segmentation
 *
 * Groups a stream of ParsedEvents into EncounterSession objects bounded by
 * ENCOUNTER_START / ENCOUNTER_END events.
 */

import type {
  ParsedEvent,
  EncounterStartEvent,
  EncounterEndEvent,
  CombatantInfoEvent,
} from "./cleu.js";

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
// SessionSegmenter — stateful, fed lines one at a time
// ---------------------------------------------------------------------------

const MAX_SESSIONS = 10;

export class SessionSegmenter {
  private sessions: EncounterSession[] = [];
  private currentSession: Partial<EncounterSession> | null = null;
  private currentEvents: ParsedEvent[] = [];
  private currentCombatants: CombatantInfo[] = [];
  private pullNumber = 1;
  private runId = newRunId();   // reset on every zone change

  /** Feed a parsed event into the segmenter. Returns a completed session if one just closed. */
  feed(event: ParsedEvent): EncounterSession | null {
    switch (event.subevent) {
      case "ZONE_CHANGED_NEW_AREA":
        // Reset pull counter and run ID on zone change.
        this.pullNumber = 1;
        this.runId = newRunId();
        if (this.currentSession) {
          // Close any open session (e.g. mid-boss wipe, then zone out).
          this.closeCurrentSession(new Date(), false);
        }
        return null;

      case "ENCOUNTER_START": {
        const e = event as EncounterStartEvent;
        if (this.currentSession) {
          // Previous pull wiped without ENCOUNTER_END — close it.
          this.closeCurrentSession(e.timestamp, false);
        }
        this.currentSession = {
          runId: this.runId,
          encounterId: e.encounterId,
          encounterName: e.encounterName,
          difficulty: e.difficulty,
          groupSize: e.groupSize,
          startTime: e.timestamp,
          pullNumber: this.pullNumber,
        };
        this.currentEvents = [];
        this.currentCombatants = [];
        return null;
      }

      case "COMBATANT_INFO": {
        const c = event as CombatantInfoEvent;
        // COMBATANT_INFO does not carry a player name — only a GUID.
        // We store the GUID as a placeholder; GuidResolver.populateNamesFromEvents()
        // overwrites it with the real name once the session's combat events are available.
        this.currentCombatants.push({
          guid: c.playerGUID,
          name: c.playerGUID,
          specId: c.currentSpecId,
        });
        return null;
      }

      case "ENCOUNTER_END": {
        const e = event as EncounterEndEvent;
        if (!this.currentSession) return null;
        const session = this.closeCurrentSession(e.timestamp, e.success);
        this.pullNumber++;
        return session;
      }

      default:
        if (this.currentSession) {
          this.currentEvents.push(event);
        }
        return null;
    }
  }

  /** Force-close the in-progress session (e.g. on process shutdown). */
  flush(): EncounterSession | null {
    if (!this.currentSession) return null;
    return this.closeCurrentSession(new Date(), false);
  }

  getSessions(): EncounterSession[] {
    return [...this.sessions];
  }

  private closeCurrentSession(endTime: Date, success: boolean): EncounterSession {
    const partial = this.currentSession!;
    const session: EncounterSession = {
      runId: partial.runId ?? this.runId,
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

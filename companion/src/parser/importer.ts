/**
 * parser/importer.ts — Historical combat-log import
 *
 * Lets the user pick a WoW combat log (.txt) from disk, streams it through
 * the same parsing pipeline used for live logs, and persists each session to
 * SQLite (skipping sessions already in the database).  A single GeneratedData.lua
 * write happens at the end so the addon reflects all imported history on the
 * next /reload.
 */

import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { parseLine } from "./cleu.js";
import { SessionSegmenter } from "./session.js";
import { buildDeathRecaps } from "./death.js";
import { buildInterruptReport } from "./interrupt.js";
import { buildCCCoverage } from "./cc.js";
import { buildPerformanceReport } from "./performance.js";
import { buildDefensiveAudit } from "./defensive.js";
import { GuidResolver } from "../enrichment/guid.js";
import { sessionToLuaValue } from "../serializer/savedvars.js";
import { buildSessionInsert } from "../storage/trends.js";
import { storeSession, sessionExists } from "../storage/sqlite.js";
import { orchestrator } from "../orchestrator.js";
import type { EncounterSession } from "./session.js";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface ImportProgress {
  /** Bytes read from the file so far. */
  bytesRead: number;
  /** Total file size in bytes (0 if unavailable). */
  totalBytes: number;
  sessionsFound: number;
  sessionsImported: number;
  sessionsSkipped: number;
}

export type ImportSummary = Pick<
  ImportProgress,
  "sessionsFound" | "sessionsImported" | "sessionsSkipped"
>;

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/**
 * Open a native file picker, then stream + parse the chosen combat log.
 * `onProgress` is called after each 1000-line batch completes.
 * Returns null if the user cancelled the file picker.
 */
export async function importLogFile(
  onProgress: (p: ImportProgress) => void,
): Promise<ImportSummary | null> {
  // Let the user pick the file via the OS dialog.
  const path = await invoke<string | null>("pick_log_file");
  if (!path) return null;

  const segmenter = new SessionSegmenter();
  const summary: ImportSummary = { sessionsFound: 0, sessionsImported: 0, sessionsSkipped: 0 };
  let bytesRead = 0;
  let totalBytes = 0;

  return new Promise<ImportSummary>((resolve) => {
    // Set up listeners BEFORE triggering the import so no events are missed.
    const unlistenLines = listen<{ lines: string[]; bytesRead: number; totalBytes: number }>(
      "import-lines",
      async (event) => {
        bytesRead = event.payload.bytesRead;
        totalBytes = event.payload.totalBytes;

        for (const line of event.payload.lines) {
          const result = parseLine(line);
          if (!result.ok) continue;

          const completed = segmenter.feed(result.value);
          for (const session of completed) {
            summary.sessionsFound++;
            const imported = await importOneSession(session);
            if (imported) summary.sessionsImported++;
            else summary.sessionsSkipped++;
          }
        }

        onProgress({ bytesRead, totalBytes, ...summary });
      },
    );

    const unlistenDone = listen<void>("import-done", async () => {
      // Unlisten first so no further events fire while we finalise.
      (await unlistenLines)();
      (await unlistenDone)();

      // Flush any sessions that were open at EOF.
      const remaining = segmenter.flush();
      for (const session of remaining) {
        summary.sessionsFound++;
        const imported = await importOneSession(session);
        if (imported) summary.sessionsImported++;
        else summary.sessionsSkipped++;
      }

      // Reload orchestrator history so subsequent fights include imported sessions.
      await orchestrator.initialize();
      const lua = orchestrator.generateStartupLua();
      if (lua) {
        try {
          await invoke("write_session", { luaContent: lua });
          await invoke("log_activity", {
            level: "info",
            message: `Import: ${summary.sessionsImported} session(s) imported — GeneratedData.lua updated. Do a /reload in WoW.`,
          });
        } catch (err) {
          // Write failed — wow_paths may not be configured.  Log it visibly
          // in the Activity tab so the user knows why WoW isn't showing data.
          console.error("[importer] write_session failed:", err);
          await invoke("log_activity", {
            level: "error",
            message: `Import: failed to write GeneratedData.lua — ${String(err)}. Check that WoW path is configured in Settings.`,
          }).catch(() => {});
        }
      } else {
        // No snapshots available — sessions may not have been stored with snapshots.
        await invoke("log_activity", {
          level: "warn",
          message: "Import: no session snapshots available — GeneratedData.lua was not updated.",
        }).catch(() => {});
      }

      // Always resolve so the UI transitions out of "Importing…" regardless
      // of whether the file write succeeded.
      resolve(summary);
    });

    // Start the background file stream (returns immediately).
    invoke("start_log_import", { path }).catch((err) => {
      console.error("[importer] start_log_import failed:", err);
      resolve(summary); // resolve with whatever we have rather than hanging
    });
  });
}

// ---------------------------------------------------------------------------
// Per-session import (analysis + dedup + persist)
// ---------------------------------------------------------------------------

async function importOneSession(session: EncounterSession): Promise<boolean> {
  const startTime = Math.floor(session.startTime.getTime() / 1000);
  try {
    if (await sessionExists(session.encounterId, startTime)) return false;

    const resolver = new GuidResolver();
    resolver.populate(session.combatants);
    resolver.populateNamesFromEvents(session.events);

    // Patch real names back into session.combatants so the serialised snapshot
    // stores actual player names rather than the GUID placeholder from COMBATANT_INFO.
    for (const c of session.combatants) {
      const info = resolver.resolve(c.guid);
      if (info && info.name !== info.guid) {
        c.name = info.name;
      }
    }

    const deaths = buildDeathRecaps(session, resolver);
    const interrupts = buildInterruptReport(session);
    const ccCoverage = buildCCCoverage(session);
    const performance = buildPerformanceReport(session, resolver, interrupts, deaths, ccCoverage);
    const defensiveAudit = buildDefensiveAudit(session, resolver, deaths);

    const snapshot = sessionToLuaValue(
      session, deaths, interrupts, ccCoverage, performance, defensiveAudit,
    ) as Record<string, unknown>;

    const insert = buildSessionInsert(
      session, deaths, interrupts, ccCoverage, performance,
      JSON.stringify(snapshot),
    );
    await storeSession(insert);
    return true;
  } catch (err) {
    console.warn("[importer] Failed to import session:", err);
    return false;
  }
}
